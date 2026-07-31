// ChatHistoryManager.ets
// 命运之轮对话 · 聊天记录持久化服务（本地 + 云端同步）

import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import http from '@ohos.net.http';
import hilog from '@ohos.hilog';
import { AppConfig } from '../common/AppConfig';
import { AuthenticatedHttpClient } from './AuthenticatedHttpClient';

const TAG: string = 'ChatHistoryManager';
const DOMAIN: number = 0xFF01;
const PREF_NAME: string = 'chat_history_store';
const ACCOUNT_PREF_NAME: string = 'echoing_user';
const SESSION_INDEX_KEY: string = 'session_index';
const USER_ID_KEY: string = 'device_user_id';
const CLOUD_BASE: string = AppConfig.CHAT_HISTORY_CLOUD_BASE;

// ====== 数据接口 ======
export interface ChatMsg {
  id: number;
  role: string;
  content: string;
}

export interface ChatSession {
  id: string;
  userId?: string;
  accountKey?: string;
  nickname?: string;
  bio?: string;
  theme: string;
  summary: string;
  systemPrompt: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMsg[];
}

// 云端列表项（不含消息体）
export interface CloudSessionItem {
  id: string;
  theme: string;
  summary: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
}

// 云端记忆上下文
export interface MemoryContextResp {
  context: string;
  count: number;
}

export class ChatHistoryManager {
  private static instance: ChatHistoryManager | null = null;
  private preferences: dataPreferences.Preferences | null = null;
  private isInitialized: boolean = false;
  private userId: string = 'default';
  private accountKey: string = '';
  private nickname: string = '';
  private bio: string = '';

  private constructor() {
  }

  public static getInstance(): ChatHistoryManager {
    if (ChatHistoryManager.instance === null) {
      ChatHistoryManager.instance = new ChatHistoryManager();
    }
    return ChatHistoryManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      if (this.preferences === null) {
        this.preferences = await dataPreferences.getPreferences(context, PREF_NAME);
      }
      await this.refreshAccountIdentity(context);
      this.isInitialized = true;
      hilog.info(DOMAIN, TAG, `ChatHistory initialized, userId: ${this.userId}, accountKey: ${this.accountKey}`);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Init failed: ${error.message}`);
      return Promise.reject(error);
    }
  }

  public getUserId(): string {
    return this.userId;
  }

  public getAccountKey(): string {
    return this.accountKey;
  }

  private async refreshAccountIdentity(context: common.UIAbilityContext): Promise<void> {
    const accountPrefs = await dataPreferences.getPreferences(context, ACCOUNT_PREF_NAME);
    const storedUserId = await accountPrefs.get('userId', '') as string;
    if (storedUserId.length > 0) {
      this.accountKey = storedUserId;
      this.userId = storedUserId;
      const nick = await accountPrefs.get(`profile.${storedUserId}.nickname`, '') as string;
      const bio = await accountPrefs.get(`profile.${storedUserId}.bio`, '') as string;
      const legacyNick = await accountPrefs.get('nickname', '') as string;
      const legacyBio = await accountPrefs.get('bio', '') as string;
      this.nickname = nick.length > 0 ? nick : legacyNick;
      this.bio = bio.length > 0 ? bio : legacyBio;
      return;
    }
    this.accountKey = '';
    this.nickname = '';
    this.bio = '';
    await this.ensureDeviceUserId();
  }

  private async ensureDeviceUserId(): Promise<void> {
    if (this.preferences === null) return;
    const storedId = await this.preferences.get(USER_ID_KEY, '') as string;
    if (storedId) {
      this.userId = storedId;
      return;
    }
    this.userId = `u_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    await this.preferences.put(USER_ID_KEY, this.userId);
    await this.preferences.flush();
  }

  private getSessionIndexKey(): string {
    return `${SESSION_INDEX_KEY}_${this.userId}`;
  }

  private getSessionStorageKey(sessionId: string): string {
    return `chat_${this.userId}_${sessionId}`;
  }

  // ==================== 本地存储 ====================

  public async saveSession(session: ChatSession): Promise<void> {
    if (this.preferences === null) {
      return;
    }
    try {
      session.updatedAt = Date.now();
      session.userId = this.userId;
      session.accountKey = this.accountKey || this.userId;
      session.nickname = this.nickname;
      session.bio = this.bio;
      const key = this.getSessionStorageKey(session.id);
      await this.preferences.put(key, JSON.stringify(session));
      await this.addToIndex(session.id);
      await this.preferences.flush();
      hilog.info(DOMAIN, TAG, `Session saved: ${session.id}`);

      // 异步同步到云端（不阻塞）
      this.syncToCloud(session);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Save failed: ${error.message}`);
    }
  }

  public async getSession(sessionId: string): Promise<ChatSession | null> {
    if (this.preferences === null) {
      return null;
    }
    try {
      const key = this.getSessionStorageKey(sessionId);
      const json = await this.preferences.get(key, '') as string;
      if (!json) return null;
      return JSON.parse(json) as ChatSession;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Get session failed: ${error.message}`);
      return null;
    }
  }

  public async getAllSessions(): Promise<ChatSession[]> {
    if (this.preferences === null) {
      return [];
    }
    try {
      const indexJson = await this.preferences.get(this.getSessionIndexKey(), '[]') as string;
      const ids: string[] = JSON.parse(indexJson) as string[];
      let sessions: ChatSession[] = [];

      for (let i = 0; i < ids.length; i++) {
        const s = await this.getSession(ids[i]);
        if (s !== null) {
          sessions.push(s);
        }
      }

      // 按更新时间倒序
      sessions.sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
      return sessions;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Get all failed: ${error.message}`);
      return [];
    }
  }

  public async deleteSession(sessionId: string): Promise<void> {
    if (this.preferences === null) {
      return;
    }
    try {
      const key = this.getSessionStorageKey(sessionId);
      await this.preferences.delete(key);
      await this.removeFromIndex(sessionId);
      await this.preferences.flush();

      // 异步云端删除
      this.cloudDelete(sessionId);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Delete failed: ${error.message}`);
    }
  }

  private async addToIndex(sessionId: string): Promise<void> {
    if (this.preferences === null) return;
    try {
      const indexJson = await this.preferences.get(this.getSessionIndexKey(), '[]') as string;
      let ids: string[] = JSON.parse(indexJson) as string[];
      if (!ids.includes(sessionId)) {
        ids.push(sessionId);
        await this.preferences.put(this.getSessionIndexKey(), JSON.stringify(ids));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Add to index failed`);
    }
  }

  private async removeFromIndex(sessionId: string): Promise<void> {
    if (this.preferences === null) return;
    try {
      const indexJson = await this.preferences.get(this.getSessionIndexKey(), '[]') as string;
      let ids: string[] = JSON.parse(indexJson) as string[];
      let newIds: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] !== sessionId) {
          newIds.push(ids[i]);
        }
      }
      await this.preferences.put(this.getSessionIndexKey(), JSON.stringify(newIds));
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Remove from index failed`);
    }
  }

  // ==================== 云端同步 ====================

  private syncToCloud(session: ChatSession): void {
    const cloudPayload: ChatSession = {
      id: session.id,
      theme: session.theme,
      summary: session.summary,
      systemPrompt: session.systemPrompt,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      messages: session.messages
    };
    AuthenticatedHttpClient.request(`${CLOUD_BASE}/api/sessions`, {
      method: http.RequestMethod.POST,
      extraData: JSON.stringify(cloudPayload),
      connectTimeout: 5000,
      readTimeout: 10000
    }).then(() => {
      hilog.info(DOMAIN, TAG, 'Cloud sync OK');
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, `Cloud sync failed (offline mode): ${error.message}`);
    });
  }

  private cloudDelete(sessionId: string): void {
    AuthenticatedHttpClient.request(`${CLOUD_BASE}/api/sessions/${sessionId}`, {
      method: http.RequestMethod.DELETE,
      connectTimeout: 5000,
      readTimeout: 5000
    }).catch(() => {});
  }

  // ==================== AI 记忆上下文 ====================

  public getMemoryContext(callback: (context: string) => void): void {
    AuthenticatedHttpClient.request(`${CLOUD_BASE}/api/memory-context`, {
      method: http.RequestMethod.GET,
      connectTimeout: 3000,
      readTimeout: 5000
    }).then((data: http.HttpResponse) => {
      if (data.responseCode !== 200) {
        this.getLocalMemoryContext(callback);
        return;
      }
      try {
        const resp = JSON.parse(data.result as string) as MemoryContextResp;
        callback(resp.context);
      } catch (error) {
        callback('');
      }
    }).catch(() => {
      this.getLocalMemoryContext(callback);
    });
  }

  private async getLocalMemoryContext(callback: (context: string) => void): Promise<void> {
    try {
      const sessions = await this.getAllSessions();
      let lines: string[] = [];
      const count = Math.min(sessions.length, 5);
      for (let i = 0; i < count; i++) {
        const s = sessions[i];
        const summary = s.summary || '无摘要';
        lines.push(`- 「${s.theme}」: ${summary}`);
      }
      if (lines.length > 0) {
        callback('用户的历史占卜记录：\n' + lines.join('\n'));
      } else {
        callback('');
      }
    } catch (e) {
      callback('');
    }
  }

  // 生成 sessionId
  public static generateId(): string {
    const now = Date.now();
    const random = Math.floor(Math.random() * 10000);
    return `s_${now}_${random}`;
  }

  // 导出所有对话为文本
  public async exportAllSessions(): Promise<string> {
    const sessions = await this.getAllSessions();
    if (sessions.length === 0) {
      return '暂无占卜记录';
    }

    let text = '═══ 嵩月塔罗 · 占卜记忆导出 ═══\n';
    const now = new Date();
    text += `导出时间：${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()} ${now.getHours()}:${now.getMinutes() < 10 ? '0' : ''}${now.getMinutes()}\n`;
    text += `共 ${sessions.length} 条记录\n\n`;

    for (let i = 0; i < sessions.length; i++) {
      const s = sessions[i];
      const d = new Date(s.createdAt);
      const dateStr = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()} ${d.getHours()}:${d.getMinutes() < 10 ? '0' : ''}${d.getMinutes()}`;

      text += `────── 第 ${i + 1} 条 ──────\n`;
      text += `主题：${s.theme || '未设主题'}\n`;
      text += `摘要：${s.summary || '无摘要'}\n`;
      text += `时间：${dateStr}\n\n`;

      for (let j = 0; j < s.messages.length; j++) {
        const m = s.messages[j];
        const label = m.role === 'user' ? '我' : 'AI';
        text += `【${label}】${m.content}\n\n`;
      }
      text += '\n';
    }
    return text;
  }
}

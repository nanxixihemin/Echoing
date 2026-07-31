import { authentication } from '@kit.AccountKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import cloud from '@hw-agconnect/cloud';
import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences';
import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { SecureTokenStorage } from './SecureTokenStorage';

const SESSION_PREFS: string = 'echoing_user';
const DEVICE_ID_KEY: string = 'deviceId';

export interface EchoingUser {
  id: string;
  provider: string;
  nickname: string;
  bio: string;
}

interface AuthSessionResponse {
  accessToken: string;
  accessExpiresIn: number;
  refreshToken: string;
  refreshExpiresIn: number;
  user: EchoingUser;
}

interface UserResponse {
  user: EchoingUser;
}

interface ErrorResponse {
  message?: string;
}

interface ProfileUpdateRequest {
  nickname: string;
  bio: string;
}

interface LogoutRequest {}

interface ExchangeRequest {
  provider: string;
  credential: string;
  deviceId: string;
  nonce?: string;
}

interface RefreshRequest {
  refreshToken: string;
  deviceId: string;
}

export class AuthSessionService {
  private static instance: AuthSessionService | null = null;
  private context: common.UIAbilityContext | null = null;
  private secureStorage: SecureTokenStorage | null = null;
  private accessToken: string = '';
  private accessExpiresAt: number = 0;
  private currentUser: EchoingUser | null = null;
  private deviceId: string = '';
  private refreshPromise: Promise<string> | null = null;

  private constructor() {}

  static getInstance(): AuthSessionService {
    if (AuthSessionService.instance === null) {
      AuthSessionService.instance = new AuthSessionService();
    }
    return AuthSessionService.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<boolean> {
    this.context = context;
    this.secureStorage = new SecureTokenStorage(context);
    this.deviceId = await this.loadOrCreateDeviceId();
    try {
      await this.refreshSession();
      return true;
    } catch (error) {
      await this.clearLocalSession();
      return false;
    }
  }

  async signInWithAgc(): Promise<EchoingUser> {
    const user = await cloud.auth().getCurrentUser();
    if (user === null) {
      throw new Error('AGC user is not signed in');
    }
    const tokenResult = await user.getToken(false);
    const credential = tokenResult.getString();
    return this.exchange('agc', credential, '');
  }

  async signInWithHuawei(): Promise<EchoingUser> {
    const state = this.randomUrlSafeValue(32);
    const nonce = this.randomUrlSafeValue(32);
    const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    request.forceLogin = true;
    request.state = state;
    request.nonce = nonce;
    request.idTokenSignAlgorithm = authentication.IdTokenSignAlgorithm.PS256;
    const controller = this.context === null
      ? new authentication.AuthenticationController()
      : new authentication.AuthenticationController(this.context);
    const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
    if (!response.state || response.state !== state) {
      throw new Error('Huawei login state validation failed');
    }
    const credential = response.data?.idToken || '';
    if (!credential) {
      throw new Error('当前华为账号服务端验证尚未配置');
    }
    return this.exchange('huawei', credential, nonce);
  }

  async getAccessToken(): Promise<string> {
    if (this.accessToken && Date.now() + 30000 < this.accessExpiresAt) {
      return this.accessToken;
    }
    return this.refreshSession();
  }

  refreshSession(): Promise<string> {
    if (this.refreshPromise !== null) {
      return this.refreshPromise;
    }
    this.refreshPromise = this.performRefresh().finally(() => {
      this.refreshPromise = null;
    });
    return this.refreshPromise;
  }

  getCurrentUser(): EchoingUser | null {
    return this.currentUser;
  }

  isAuthenticated(): boolean {
    return this.currentUser !== null && this.accessToken.length > 0;
  }

  async updateProfile(nickname: string, bio: string): Promise<EchoingUser> {
    const token = await this.getAccessToken();
    const body: ProfileUpdateRequest = { nickname: nickname, bio: bio };
    const response = await this.requestJson(
      `${AppConfig.API_BASE}/api/app-users/upsert`,
      http.RequestMethod.POST,
      body,
      token
    ) as UserResponse;
    this.currentUser = response.user;
    await this.persistPublicState();
    return response.user;
  }

  async logout(): Promise<void> {
    const provider = this.currentUser?.provider || '';
    try {
      if (this.accessToken) {
        const body: LogoutRequest = {};
        await this.requestJson(
          `${AppConfig.API_BASE}/api/app-auth/logout`, http.RequestMethod.POST, body, this.accessToken);
      }
    } catch (error) {
    } finally {
      await this.clearLocalSession();
      if (provider === 'agc') {
        try {
          await cloud.auth().signOut();
        } catch (error) {
        }
      }
    }
  }

  async clearLocalSession(): Promise<void> {
    this.accessToken = '';
    this.accessExpiresAt = 0;
    this.currentUser = null;
    if (this.secureStorage !== null) {
      await this.secureStorage.clearRefreshToken();
    }
    if (this.context !== null) {
      const prefs = await dataPreferences.getPreferences(this.context, SESSION_PREFS);
      await prefs.put('hasSession', false);
      await prefs.put('isLoggedIn', false);
      await prefs.delete('userId');
      await prefs.delete('accountKey');
      await prefs.delete('provider');
      await prefs.flush();
    }
  }

  private async exchange(provider: string, credential: string, nonce: string): Promise<EchoingUser> {
    const body: ExchangeRequest = {
      provider: provider,
      credential: credential,
      deviceId: this.deviceId
    };
    if (nonce) {
      body.nonce = nonce;
    }
    const response = await this.requestJson(
      `${AppConfig.API_BASE}/api/app-auth/exchange`, http.RequestMethod.POST, body
    ) as AuthSessionResponse;
    await this.acceptSession(response);
    return response.user;
  }

  private async performRefresh(): Promise<string> {
    if (this.secureStorage === null || !this.deviceId) {
      throw new Error('Auth session service is not initialized');
    }
    const refreshToken = await this.secureStorage.loadRefreshToken();
    if (!refreshToken) {
      throw new Error('No refresh session is available');
    }
    const body: RefreshRequest = { refreshToken: refreshToken, deviceId: this.deviceId };
    const response = await this.requestJson(
      `${AppConfig.API_BASE}/api/app-auth/refresh`,
      http.RequestMethod.POST,
      body
    ) as AuthSessionResponse;
    await this.acceptSession(response);
    return response.accessToken;
  }

  private async acceptSession(response: AuthSessionResponse): Promise<void> {
    if (!response.accessToken || !response.refreshToken || !response.user?.id) {
      throw new Error('Server returned an invalid auth session');
    }
    if (this.secureStorage === null) {
      throw new Error('Secure token storage is not initialized');
    }
    await this.secureStorage.saveRefreshToken(response.refreshToken);
    this.accessToken = response.accessToken;
    this.accessExpiresAt = Date.now() + response.accessExpiresIn * 1000;
    this.currentUser = response.user;
    await this.persistPublicState();
  }

  private async persistPublicState(): Promise<void> {
    if (this.context === null || this.currentUser === null) {
      return;
    }
    const prefs = await dataPreferences.getPreferences(this.context, SESSION_PREFS);
    await prefs.put('hasSession', true);
    await prefs.put('isLoggedIn', true);
    await prefs.put('userId', this.currentUser.id);
    await prefs.put('provider', this.currentUser.provider);
    await prefs.flush();
  }

  private async loadOrCreateDeviceId(): Promise<string> {
    if (this.context === null) {
      throw new Error('Auth session service is not initialized');
    }
    const prefs = await dataPreferences.getPreferences(this.context, SESSION_PREFS);
    const stored = await prefs.get(DEVICE_ID_KEY, '') as string;
    if (stored.length >= 16) {
      return stored;
    }
    const deviceId = this.randomUrlSafeValue(32);
    await prefs.put(DEVICE_ID_KEY, deviceId);
    await prefs.flush();
    return deviceId;
  }

  private randomUrlSafeValue(byteLength: number): string {
    const bytes = cryptoFramework.createRandom().generateRandomSync(byteLength).data;
    return new util.Base64Helper().encodeToStringSync(bytes)
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }

  private async requestJson(
    url: string,
    method: http.RequestMethod,
    body: object,
    bearerToken: string = ''
  ): Promise<object> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (bearerToken) {
        headers.Authorization = `Bearer ${bearerToken}`;
      }
      const response = await request.request(url, {
        method: method,
        header: headers,
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 15000
      });
      const raw = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 300) {
        let message = `认证服务返回 ${response.responseCode}`;
        try {
          const parsed = JSON.parse(raw) as ErrorResponse;
          message = parsed.message || message;
        } catch (error) {
        }
        throw new Error(message);
      }
      return JSON.parse(raw) as object;
    } finally {
      request.destroy();
    }
  }
}

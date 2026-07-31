import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences';
import { Seed } from '../models/Seed';
import { EchoTask } from '../models/EchoTask';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'EchoingCore.db',
  securityLevel: relationalStore.SecurityLevel.S1
};
const ACCOUNT_PREF_NAME: string = 'echoing_user';
// 与 AuthSessionService.persistPublicState 写入的键保持一致（历史上误用 'accountKey'，无人写入）
const ACCOUNT_KEY_NAME: string = 'userId';
const GUEST_ACCOUNT_KEY: string = 'guest';

export class DatabaseService {
  private rdbStore: relationalStore.RdbStore | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  // 初始化数据库及建表
  async init(): Promise<void> {
    try {
      this.rdbStore = await relationalStore.getRdbStore(this.context, STORE_CONFIG);

      // 创建心念种子表
      const SQL_CREATE_SEED_TABLE = `
        CREATE TABLE IF NOT EXISTS seed (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_key TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL,
          source TEXT NOT NULL,
          state INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      `;

      // 创建回声待办表
      const SQL_CREATE_TASK_TABLE = `
        CREATE TABLE IF NOT EXISTS echo_task (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          seed_id INTEGER,
          account_key TEXT NOT NULL DEFAULT '',
          action TEXT NOT NULL,
          is_completed INTEGER NOT NULL DEFAULT 0,
          completed_at INTEGER,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(seed_id) REFERENCES seed(id)
        )
      `;

      await this.rdbStore.executeSql(SQL_CREATE_SEED_TABLE);
      await this.rdbStore.executeSql(SQL_CREATE_TASK_TABLE);
      await this.ensureAccountColumns();
      await this.claimLegacyRowsForCurrentAccount();
      console.info('[Echoing] Database initialized successfully.');
    } catch (err) {
      console.error(`[Echoing] Database init failed. Code: ${err.code}, message: ${err.message}`);
    }
  }

  // 本地隐私数据按当前 App 账号隔离。
  private async getCurrentAccountKey(): Promise<string> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, ACCOUNT_PREF_NAME);
      const value = await prefs.get(ACCOUNT_KEY_NAME, '') as string;
      if (value && value.length > 0) {
        return value;
      }
    } catch (err) {
      console.error('[Echoing] Read account key failed.');
    }
    return GUEST_ACCOUNT_KEY;
  }

  private async ensureAccountColumns(): Promise<void> {
    if (!this.rdbStore) return;
    await this.addColumnIfMissing('seed', 'account_key TEXT NOT NULL DEFAULT \'\'');
    await this.addColumnIfMissing('echo_task', 'account_key TEXT NOT NULL DEFAULT \'\'');
  }

  private async addColumnIfMissing(tableName: string, columnSql: string): Promise<void> {
    if (!this.rdbStore) return;
    try {
      await this.rdbStore.executeSql(`ALTER TABLE ${tableName} ADD COLUMN ${columnSql}`);
    } catch (err) {
      // Column already exists on upgraded local databases.
    }
  }

  private async claimLegacyRowsForCurrentAccount(): Promise<void> {
    if (!this.rdbStore) return;
    const accountKey = await this.getCurrentAccountKey();
    if (accountKey === GUEST_ACCOUNT_KEY) return;

    const predicates = new relationalStore.RdbPredicates('echo_task');
    predicates.equalTo('account_key', accountKey);
    const resultSet = await this.rdbStore.query(predicates, ['id']);
    const hasCurrentAccountRows = resultSet.goToNextRow();
    resultSet.close();
    if (hasCurrentAccountRows) {
      return;
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'account_key': accountKey
    };

    // 认领两类历史数据：旧版本留下的空 account_key 行，
    // 以及账号键修复前被统一标记为 'guest' 的行（实为用户登录态写入的私有数据）
    const legacyKeys: string[] = ['', GUEST_ACCOUNT_KEY];
    for (const legacyKey of legacyKeys) {
      const seedPredicates = new relationalStore.RdbPredicates('seed');
      seedPredicates.equalTo('account_key', legacyKey);
      await this.rdbStore.update(valueBucket, seedPredicates);

      const taskPredicates = new relationalStore.RdbPredicates('echo_task');
      taskPredicates.equalTo('account_key', legacyKey);
      await this.rdbStore.update(valueBucket, taskPredicates);
    }
  }

  async insertSeed(seed: Seed): Promise<number> {
    if (!this.rdbStore) return -1;
    const explicitAccountKey = seed.account_key ? seed.account_key : '';
    const accountKey = explicitAccountKey.length > 0 ? explicitAccountKey : await this.getCurrentAccountKey();
    const valueBucket: relationalStore.ValuesBucket = {
      'account_key': accountKey,
      'content': seed.content,
      'source': seed.source,
      'state': seed.state,
      'created_at': seed.created_at
    };
    return await this.rdbStore.insert('seed', valueBucket);
  }

  // 插入一个回声待办 (可关联Seed)
  async insertTask(task: EchoTask): Promise<number> {
    if (!this.rdbStore) return -1;
    const explicitAccountKey = task.account_key ? task.account_key : '';
    const accountKey = explicitAccountKey.length > 0 ? explicitAccountKey : await this.getCurrentAccountKey();
    const valueBucket: relationalStore.ValuesBucket = {
      'seed_id': task.seed_id ? task.seed_id : null,
      'account_key': accountKey,
      'action': task.action,
      'is_completed': task.is_completed ? 1 : 0,
      'completed_at': task.completed_at ? task.completed_at : null,
      'created_at': task.created_at
    };
    return await this.rdbStore.insert('echo_task', valueBucket);
  }

  async markTaskCompleted(taskId: number, completedAt: number): Promise<boolean> {
    if (!this.rdbStore) return false;
    const accountKey = await this.getCurrentAccountKey();
    const valueBucket: relationalStore.ValuesBucket = {
      'is_completed': 1,
      'completed_at': completedAt
    };
    let predicates = new relationalStore.RdbPredicates('echo_task');
    predicates.equalTo('id', taskId);
    predicates.equalTo('account_key', accountKey);
    const updatedRows = await this.rdbStore.update(valueBucket, predicates);
    return updatedRows > 0;
  }

  // 获取所有未完成的任务，以便展示在首页抽屉
  async getPendingTasks(): Promise<EchoTask[]> {
    if (!this.rdbStore) return [];
    const accountKey = await this.getCurrentAccountKey();
    let predicates = new relationalStore.RdbPredicates('echo_task');
    predicates.equalTo('is_completed', 0);
    predicates.equalTo('account_key', accountKey);
    predicates.orderByDesc('created_at'); // 最新的在前面

    let resultSet = await this.rdbStore.query(predicates, ['id', 'seed_id', 'account_key', 'action', 'is_completed', 'completed_at', 'created_at']);
    let tasks: EchoTask[] = [];
    
    while (resultSet.goToNextRow()) {
      tasks.push({
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        seed_id: resultSet.getLong(resultSet.getColumnIndex('seed_id')),
        account_key: resultSet.getString(resultSet.getColumnIndex('account_key')),
        action: resultSet.getString(resultSet.getColumnIndex('action')),
        is_completed: resultSet.getLong(resultSet.getColumnIndex('is_completed')) === 1,
        completed_at: resultSet.getLong(resultSet.getColumnIndex('completed_at')),
        created_at: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      });
    }
    resultSet.close();
    return tasks;
  }
}

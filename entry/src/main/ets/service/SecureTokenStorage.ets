import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { huks } from '@kit.UniversalKeystoreKit';
import common from '@ohos.app.ability.common';

const STORE_NAME: string = 'echoing_secure_session';
const REFRESH_TOKEN_BLOB: string = 'refresh_token_blob';
const WRAPPING_KEY_ALIAS: string = 'echoing_refresh_token_wrapping_v1';
const AAD: Uint8Array = new util.TextEncoder().encodeInto('echoing-refresh-token-v1');

interface StoredTokenBlob {
  nonce: string;
  ciphertext: string;
  authTag: string;
}

interface ProtectedToken {
  nonce: Uint8Array;
  ciphertext: Uint8Array;
  authTag: Uint8Array;
}

export class SecureTokenStorage {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async saveRefreshToken(token: string): Promise<void> {
    await this.ensureWrappingKey();
    const plaintext: Uint8Array = new util.TextEncoder().encodeInto(token);
    const protectedToken: ProtectedToken = await this.protect(plaintext);
    const base64 = new util.Base64Helper();
    const stored: StoredTokenBlob = {
      nonce: base64.encodeToStringSync(protectedToken.nonce),
      ciphertext: base64.encodeToStringSync(protectedToken.ciphertext),
      authTag: base64.encodeToStringSync(protectedToken.authTag)
    };
    const store = await preferences.getPreferences(this.context, STORE_NAME);
    await store.put(REFRESH_TOKEN_BLOB, JSON.stringify(stored));
    await store.flush();
    plaintext.fill(0);
  }

  async loadRefreshToken(): Promise<string> {
    const store = await preferences.getPreferences(this.context, STORE_NAME);
    const raw = await store.get(REFRESH_TOKEN_BLOB, '') as string;
    if (!raw) {
      return '';
    }
    await this.ensureWrappingKey();
    const stored = JSON.parse(raw) as StoredTokenBlob;
    const base64 = new util.Base64Helper();
    const plaintext = await this.unprotect(
      base64.decodeSync(stored.ciphertext),
      base64.decodeSync(stored.nonce),
      base64.decodeSync(stored.authTag)
    );
    const token = new util.TextDecoder('utf-8').decodeToString(plaintext);
    plaintext.fill(0);
    return token;
  }

  async clearRefreshToken(): Promise<void> {
    const store = await preferences.getPreferences(this.context, STORE_NAME);
    await store.delete(REFRESH_TOKEN_BLOB);
    await store.flush();
  }

  private async ensureWrappingKey(): Promise<void> {
    const exists = await huks.isKeyItemExist(WRAPPING_KEY_ALIAS, { properties: [] });
    if (exists) {
      return;
    }
    await huks.generateKeyItem(WRAPPING_KEY_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
            huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
        },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
      ]
    });
  }

  private async protect(plaintext: Uint8Array): Promise<ProtectedToken> {
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const options = this.operationOptions(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, undefined, plaintext);
    const session = await huks.initSession(WRAPPING_KEY_ALIAS, options);
    const result = await huks.finishSession(session.handle, options);
    const output = result.outData || new Uint8Array([]);
    const authTag = this.findAuthTag(result.properties);
    if (authTag.length > 0) {
      return { nonce: nonce, ciphertext: output, authTag: authTag };
    }
    if (output.length < 16) {
      throw new Error('Secure storage did not return an authentication tag');
    }
    return {
      nonce: nonce,
      ciphertext: output.subarray(0, output.length - 16),
      authTag: output.subarray(output.length - 16)
    };
  }

  private async unprotect(
    ciphertext: Uint8Array, nonce: Uint8Array, authTag: Uint8Array
  ): Promise<Uint8Array> {
    const options = this.operationOptions(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, authTag, ciphertext);
    const session = await huks.initSession(WRAPPING_KEY_ALIAS, options);
    const result = await huks.finishSession(session.handle, options);
    return result.outData || new Uint8Array([]);
  }

  private operationOptions(
    purpose: huks.HuksKeyPurpose,
    nonce: Uint8Array,
    authTag: Uint8Array | undefined,
    input: Uint8Array
  ): huks.HuksOptions {
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: AAD }
    ];
    if (authTag) {
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: authTag });
    }
    return { properties: properties, inData: input };
  }

  private findAuthTag(properties: Array<huks.HuksParam> | undefined): Uint8Array {
    if (!properties) {
      return new Uint8Array([]);
    }
    const property = properties.find((item: huks.HuksParam) =>
      item.tag === huks.HuksTag.HUKS_TAG_AE_TAG);
    return property ? property.value as Uint8Array : new Uint8Array([]);
  }
}

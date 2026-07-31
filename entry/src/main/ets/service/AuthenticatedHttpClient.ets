import { router } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { AuthSessionService } from './AuthSessionService';

export interface EchoingHttpOptions {
  method: http.RequestMethod;
  extraData?: string;
  connectTimeout?: number;
  readTimeout?: number;
}

export class AuthenticatedHttpClient {
  static async request(url: string, options: EchoingHttpOptions): Promise<http.HttpResponse> {
    const auth = AuthSessionService.getInstance();
    let accessToken: string;
    try {
      accessToken = await auth.getAccessToken();
    } catch (error) {
      await AuthenticatedHttpClient.expireSession(auth);
      throw new Error('Session is no longer valid');
    }
    const firstResponse = await AuthenticatedHttpClient.execute(url, options, accessToken);
    if (firstResponse.responseCode !== 401) {
      return firstResponse;
    }
    try {
      const refreshedToken = await auth.refreshSession();
      const retryResponse = await AuthenticatedHttpClient.execute(url, options, refreshedToken);
      if (retryResponse.responseCode === 401) {
        throw new Error('Session is no longer valid');
      }
      return retryResponse;
    } catch (error) {
      await AuthenticatedHttpClient.expireSession(auth);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('Authenticated request failed');
    }
  }

  static async requestPublic(url: string, options: EchoingHttpOptions): Promise<http.HttpResponse> {
    return AuthenticatedHttpClient.execute(url, options, '');
  }

  private static async expireSession(auth: AuthSessionService): Promise<void> {
    await auth.clearLocalSession();
    router.replaceUrl({ url: 'pages/LoginPage' }).catch(() => {});
  }

  private static async execute(
    url: string, options: EchoingHttpOptions, accessToken: string
  ): Promise<http.HttpResponse> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (accessToken) {
        headers.Authorization = `Bearer ${accessToken}`;
      }
      return await request.request(url, {
        method: options.method,
        header: headers,
        extraData: options.extraData,
        connectTimeout: options.connectTimeout || 10000,
        readTimeout: options.readTimeout || 15000
      });
    } finally {
      request.destroy();
    }
  }
}

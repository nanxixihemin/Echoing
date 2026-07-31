import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { AuthenticatedHttpClient } from './AuthenticatedHttpClient';

export class SharedForestService {
  static async fetchLeaves(): Promise<http.HttpResponse> {
    return AuthenticatedHttpClient.requestPublic(
      `${AppConfig.SHARED_FOREST_API_BASE}/api/leaves`,
      { method: http.RequestMethod.GET, connectTimeout: 10000, readTimeout: 10000 }
    );
  }

  static async checkConnection(): Promise<boolean> {
    try {
      const response = await SharedForestService.fetchLeaves();
      return response.responseCode === 200;
    } catch (e) {
      return false;
    }
  }

  static async likeLeaf(leafId: string): Promise<http.HttpResponse> {
    return AuthenticatedHttpClient.requestPublic(
      `${AppConfig.SHARED_FOREST_API_BASE}/api/leaves/${leafId}/like`,
      { method: http.RequestMethod.POST, connectTimeout: 10000, readTimeout: 10000 }
    );
  }

  static async submitLeaf(content: string, nickname: string): Promise<http.HttpResponse> {
    return AuthenticatedHttpClient.request(
      `${AppConfig.SHARED_FOREST_API_BASE}/api/leaves`,
      {
        method: http.RequestMethod.POST,
        extraData: JSON.stringify({ content: content, nickname: nickname }),
        connectTimeout: 10000,
        readTimeout: 10000
      }
    );
  }
}

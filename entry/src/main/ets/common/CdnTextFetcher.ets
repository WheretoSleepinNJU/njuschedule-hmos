/**
 * 上游 CDN 静态文本获取。
 *
 * 学校列表、解析脚本、complete.json 等导入辅助数据共用这一层，
 * 统一 HTTPS 校验、超时和 HttpRequest 释放，避免各处重复实现。
 */
import { http } from '@kit.NetworkKit';

export class CdnTextFetcher {
  static async fetch(url: string, connectTimeout: number = 10000,
    readTimeout: number = 15000): Promise<string> {
    if (!url.startsWith('https://')) {
      throw new Error('CDN URL 必须是 HTTPS');
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return `${response.result}`;
    } finally {
      request.destroy();
    }
  }
}

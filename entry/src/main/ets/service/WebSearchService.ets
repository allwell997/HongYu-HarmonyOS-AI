import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface WebSearchItem {
  title: string;
  url: string;
  snippet: string;
}

/**
 * 轻量联网搜索：通过 Bing 的 RSS 结果获取网页标题、链接和摘要。
 * 只用于个人、非商业的实时信息辅助；商用请替换为官方搜索 API。
 */
export class WebSearchService {
  async search(query: string): Promise<WebSearchItem[]> {
    const q: string = query.trim();
    if (q.length === 0) {
      return [];
    }
    const url: string = `https://cn.bing.com/search?format=rss&q=${encodeURIComponent(q)}&setlang=zh-CN&cc=CN`;
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36'
        },
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 10000,
        readTimeout: 20000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`搜索服务返回 HTTP ${response.responseCode}`);
      }
      return this.parseRss(this.resultToString(response.result));
    } catch (error) {
      const businessError = error as BusinessError;
      throw new Error(`联网搜索失败：${businessError.message ?? '网络不可用'}`);
    } finally {
      request.destroy();
    }
  }

  private parseRss(xml: string): WebSearchItem[] {
    const items: WebSearchItem[] = [];
    const itemPattern: RegExp = /<item>([\s\S]*?)<\/item>/g;
    let match: RegExpExecArray | null = itemPattern.exec(xml);
    while (match !== null && items.length < 6) {
      const block: string = match[1];
      const title: string = this.clean(this.extract(block, 'title'));
      const url: string = this.clean(this.extract(block, 'link'));
      const snippet: string = this.clean(this.extract(block, 'description'));
      if (title.length > 0 && url.length > 0) {
        items.push({
          title: title,
          url: url,
          snippet: snippet.length > 320 ? `${snippet.slice(0, 320)}…` : snippet
        });
      }
      match = itemPattern.exec(xml);
    }
    return items;
  }

  private extract(block: string, tag: string): string {
    const pattern: RegExp = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`);
    const match: RegExpExecArray | null = pattern.exec(block);
    return match !== null ? match[1] : '';
  }

  private clean(value: string): string {
    let text: string = value;
    text = text.replace(/<!\[CDATA\[/g, '');
    text = text.replace(/\]\]>/g, '');
    text = text.replace(/<[^>]+>/g, ' ');
    text = text.replace(/&amp;/g, '&');
    text = text.replace(/&quot;/g, '"');
    text = text.replace(/&#39;/g, "'");
    text = text.replace(/&apos;/g, "'");
    text = text.replace(/&lt;/g, '<');
    text = text.replace(/&gt;/g, '>');
    text = text.replace(/&nbsp;/g, ' ');
    text = text.replace(/\s+/g, ' ');
    return text.trim();
  }

  private resultToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    return JSON.stringify(result);
  }
}

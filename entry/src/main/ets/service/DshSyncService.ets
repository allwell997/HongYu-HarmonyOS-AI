import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettings, ChatMessage, Conversation } from '../model/Models';

interface SyncMessageDto {
  id: string;
  role: string;
  content: string;
  createdAt: number;
}

interface SyncConversationDto {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: SyncMessageDto[];
}

interface SyncPushBody {
  deviceName: string;
  conversations: SyncConversationDto[];
}

interface SyncMessageResponse {
  id?: string;
  role?: string;
  content?: string;
  createdAt?: number;
}

interface SyncConversationResponse {
  id: string;
  title?: string;
  createdAt?: number;
  updatedAt?: number;
  messages?: SyncMessageResponse[];
}

interface SyncInfoResponse {
  ok?: boolean;
  service?: string;
  version?: string;
  conversations?: number;
  totalMessages?: number;
  dataDir?: string;
  error?: string;
}

interface SyncResponse {
  ok?: boolean;
  imported?: number;
  updated?: number;
  total?: number;
  conversations?: SyncConversationResponse[];
  error?: string;
}

export interface DshSyncResult {
  imported: number;
  updated: number;
  total: number;
  conversations: Conversation[];
}

export interface DshSyncInfo {
  service: string;
  version: string;
  conversationCount: number;
  messageCount: number;
  dataDir: string;
}

/**
 * 手机与 DSH 插件（HongYu Sync Bridge）之间的局域网同步客户端。
 *
 * 插件默认监听 0.0.0.0:17860，提供：
 *   GET  /health          无需鉴权
 *   GET  /api/info        需要 Bearer token
 *   GET  /api/conversations
 *   POST /api/sync
 *
 * 只同步文字，不同步图片文件；图片在 DSH 侧以 [图片] 占位。
 */
export class DshSyncService {
  async test(settings: AppSettings): Promise<DshSyncInfo> {
    this.assertConfigured(settings);
    const response = await this.request(settings, http.RequestMethod.GET, '/api/info');
    const parsed = this.parseJson<SyncInfoResponse>(response);
    if (!parsed.ok) {
      throw new Error(parsed.error ? parsed.error : 'DSH 插件返回异常。');
    }
    return {
      service: parsed.service ? parsed.service : 'hongyu-sync',
      version: parsed.version ? parsed.version : 'unknown',
      conversationCount: typeof parsed.conversations === 'number' ? parsed.conversations : 0,
      messageCount: typeof parsed.totalMessages === 'number' ? parsed.totalMessages : 0,
      dataDir: parsed.dataDir ? parsed.dataDir : ''
    };
  }

  async sync(settings: AppSettings, conversations: Conversation[]): Promise<DshSyncResult> {
    this.assertConfigured(settings);
    const payload: SyncPushBody = {
      deviceName: 'HarmonyOS 手机',
      conversations: this.toDto(conversations)
    };
    const response = await this.request(settings, http.RequestMethod.POST, '/api/sync',
      JSON.stringify(payload));
    const parsed = this.parseJson<SyncResponse>(response);
    if (!parsed.ok) {
      throw new Error(parsed.error ? parsed.error : 'DSH 插件同步失败。');
    }
    const remote: Conversation[] = [];
    if (parsed.conversations && Array.isArray(parsed.conversations)) {
      parsed.conversations.forEach((item: SyncConversationResponse, index: number) => {
        const imported = this.fromDto(item, index);
        if (imported) {
          remote.push(imported);
        }
      });
    }
    return {
      imported: typeof parsed.imported === 'number' ? parsed.imported : 0,
      updated: typeof parsed.updated === 'number' ? parsed.updated : 0,
      total: typeof parsed.total === 'number' ? parsed.total : remote.length,
      conversations: remote
    };
  }

  private toDto(conversations: Conversation[]): SyncConversationDto[] {
    const result: SyncConversationDto[] = [];
    const maxConversations: number = 200;
    for (let i = 0; i < conversations.length && result.length < maxConversations; i++) {
      const conversation = conversations[i];
      if (!conversation.messages || conversation.messages.length === 0) {
        continue;
      }
      const messages: SyncMessageDto[] = [];
      const start: number = Math.max(0, conversation.messages.length - 200);
      for (let j = start; j < conversation.messages.length; j++) {
        const message = conversation.messages[j];
        if (message.role !== 'user' && message.role !== 'assistant') {
          continue;
        }
        let content: string = message.content;
        if (content.trim().length === 0 && message.imagePaths.length > 0) {
          content = `[图片 x${message.imagePaths.length}]`;
        }
        if (content.trim().length === 0) {
          continue;
        }
        messages.push({
          id: message.id,
          role: message.role,
          content: content,
          createdAt: message.createdAt
        });
      }
      if (messages.length === 0) {
        continue;
      }
      result.push({
        id: conversation.id,
        title: conversation.title,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
        messages: messages
      });
    }
    return result;
  }

  private fromDto(raw: SyncConversationResponse, index: number): Conversation | undefined {
    if (!raw || !raw.id) {
      return undefined;
    }
    const messages: ChatMessage[] = [];
    if (raw.messages && Array.isArray(raw.messages)) {
      raw.messages.forEach((item: SyncMessageResponse, messageIndex: number) => {
        if (!item || !item.content) {
          return;
        }
        const role: string = item.role === 'assistant' ? 'assistant' : 'user';
        const message = new ChatMessage(
          item.id ? item.id : `remote_${index}_${messageIndex}`,
          role === 'assistant' ? 'assistant' : 'user',
          item.content,
          [],
          item.createdAt ? item.createdAt : Date.now()
        );
        messages.push(message);
      });
    }
    const conversation = new Conversation(
      raw.id,
      raw.title && raw.title.length > 0 ? raw.title : 'DSH 同步对话',
      messages,
      raw.createdAt ? raw.createdAt : Date.now(),
      raw.updatedAt ? raw.updatedAt : Date.now()
    );
    return conversation;
  }

  private async request(settings: AppSettings, method: http.RequestMethod, path: string,
    body?: string): Promise<string> {
    const url: string = `${this.baseUrl(settings)}${path}`;
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: method,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${settings.dshToken.trim()}`
        },
        extraData: body ? body : '',
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode === 401) {
        throw new Error('配对码不正确（HTTP 401）。请在 DSH 中调用 hongyu_sync 的 status 重新获取。');
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`DSH 插件请求失败（HTTP ${response.responseCode}）：${raw.slice(0, 180)}`);
      }
      return raw;
    } catch (error) {
      if (error instanceof Error && error.message.startsWith('DSH 插件')) {
        throw error;
      }
      const businessError = error as BusinessError;
      throw new Error(`无法连接 DSH 插件：${businessError.message ? businessError.message : '网络错误'}。请确认电脑与手机在同一局域网、插件已启动，并允许防火墙访问。`);
    } finally {
      request.destroy();
    }
  }

  private parseJson<T>(raw: string): T {
    try {
      return JSON.parse(raw) as T;
    } catch (error) {
      throw new Error('DSH 插件返回的内容不是有效 JSON。');
    }
  }

  private baseUrl(settings: AppSettings): string {
    let host: string = settings.dshHost.trim();
    host = host.replace(/^https?:\/\//i, '');
    host = host.replace(/\/.*$/, '');
    if (host.length === 0) {
      throw new Error('请填写电脑的局域网 IP。');
    }
    if (host.indexOf(':') >= 0) {
      return `http://${host}`;
    }
    return `http://${host}:${settings.dshPort}`;
  }

  private assertConfigured(settings: AppSettings): void {
    if (settings.dshHost.trim().length === 0) {
      throw new Error('请先填写 DSH 同步的电脑局域网 IP。');
    }
    if (settings.dshToken.trim().length === 0) {
      throw new Error('请先填写 DSH 配对码。');
    }
    if (settings.dshPort <= 0 || settings.dshPort > 65535) {
      throw new Error('DSH 同步端口无效。');
    }
  }
}

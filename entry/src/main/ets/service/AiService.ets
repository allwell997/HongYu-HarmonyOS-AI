import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettings, ChatMessage } from '../model/Models';
import { AttachmentService } from './AttachmentService';

interface ApiMessage {
  role: string;
  content: string | Record<string, Object>[];
}

interface ApiChatRequest {
  model: string;
  messages: ApiMessage[];
  temperature: number;
  stream: boolean;
}

interface ApiErrorBody {
  message?: string;
  type?: string;
  code?: string;
}

interface ApiErrorEnvelope {
  error?: ApiErrorBody;
  message?: string;
}

interface ApiChoiceMessage {
  content?: string;
  reasoning_content?: string;
}

interface ApiChoice {
  message?: ApiChoiceMessage;
  finish_reason?: string;
}

interface ApiChatResponse {
  choices?: ApiChoice[];
  error?: ApiErrorBody;
}

export class AiError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AiError';
  }
}

/**
 * 标准 OpenAI Chat Completions 客户端，可直接连接 DeepSeek、
 * 通义千问兼容模式、智谱等任何兼容接口。
 *
 * 图片按 OpenAI vision 格式发送：
 * content: [{ type: 'text' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,...' } }]
 * 因此需要把模型切换到支持视觉的模型。
 */
export class AiService {
  private attachmentService: AttachmentService = new AttachmentService();

  /**
   * 发送一条极短的测试消息，验证 DeepSeek（或其他兼容接口）的
   * Base URL、API Key、模型名和网络是否可用。
   */
  async testConnection(settings: AppSettings): Promise<string> {
    const probe = ChatMessage.user(`probe_${Date.now()}`, '请只回复：连接成功', []);
    return await this.send(settings, [probe], probe);
  }

  async send(settings: AppSettings, history: ChatMessage[], lastUserMessage: ChatMessage,
    webContext: string = ''): Promise<string> {
    if (settings.apiKey.trim().length === 0) {
      throw new AiError('尚未填写 API Key，请先到设置中配置。');
    }
    if (settings.model.trim().length === 0) {
      throw new AiError('模型名称为空，请到设置中填写。');
    }

    const url: string = this.buildEndpoint(settings.baseUrl);
    const messages: ApiMessage[] = await this.buildMessages(settings, history, lastUserMessage, webContext);
    const body: ApiChatRequest = {
      model: settings.model.trim(),
      messages: messages,
      temperature: settings.temperature,
      stream: false
    };

    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${settings.apiKey.trim()}`
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 30000,
        readTimeout: 180000
      });

      const raw: string = this.resultToString(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new AiError(this.describeHttpError(response.responseCode, raw));
      }

      let parsed: ApiChatResponse = {};
      try {
        parsed = JSON.parse(raw) as ApiChatResponse;
      } catch (error) {
        throw new AiError('接口返回的内容不是有效 JSON，请检查 Base URL 是否指向 OpenAI 兼容接口。');
      }

      if (parsed.error) {
        throw new AiError(parsed.error.message ?? '模型服务返回错误。');
      }
      if (!parsed.choices || parsed.choices.length === 0) {
        throw new AiError('接口没有返回 choices，请检查模型名称是否正确。');
      }
      const choiceMessage = parsed.choices[0].message;
      if (!choiceMessage) {
        throw new AiError('接口返回了空的 message。');
      }
      const content: string = (choiceMessage.content ?? '').trim();
      if (content.length === 0) {
        if (choiceMessage.reasoning_content && choiceMessage.reasoning_content.length > 0) {
          return choiceMessage.reasoning_content;
        }
        throw new AiError('模型返回了空内容，请重试或更换模型。');
      }
      return content;
    } catch (error) {
      if (error instanceof AiError) {
        throw error;
      }
      const businessError = error as BusinessError;
      const message: string = businessError.message ? businessError.message : '未知网络错误';
      throw new AiError(`网络请求失败：${message}。请检查网络、Base URL 与设备网络权限。`);
    } finally {
      httpRequest.destroy();
    }
  }

  private async buildMessages(settings: AppSettings, history: ChatMessage[],
    lastUserMessage: ChatMessage, webContext: string): Promise<ApiMessage[]> {
    const messages: ApiMessage[] = [];
    if (settings.systemPrompt.trim().length > 0) {
      messages.push({
        role: 'system',
        content: settings.systemPrompt.trim()
      });
    }
    if (webContext.trim().length > 0) {
      messages.push({
        role: 'system',
        content: `以下是刚刚通过 Bing 搜索到的实时网页结果，可作为回答外部信息问题的参考。` +
          `请优先使用其中与问题相关的事实，并在回答末尾用 [1][2] 形式列出实际引用的来源和链接；` +
          `如果结果与问题无关或不足以回答，请明确说明“联网结果不足”，不要编造来源。\n\n${webContext}`
      });
    }

    // 控制上下文长度，避免一次把超长对话全部发出去。
    // 从一条 user 消息开始截断，避免历史以 assistant 消息开头造成上下文错位。
    let startIndex: number = Math.max(0, history.length - 40);
    while (startIndex < history.length && history[startIndex].role !== 'user') {
      startIndex += 1;
    }
    for (let i = startIndex; i < history.length; i++) {
      const item: ChatMessage = history[i];
      if (item.role === 'assistant') {
        if (item.content.trim().length > 0) {
          messages.push({
            role: 'assistant',
            content: item.content
          });
        }
        continue;
      }

      if (item.id === lastUserMessage.id && item.imagePaths.length > 0) {
        const parts: Record<string, Object>[] = [];
        const promptText: string = item.content.trim().length > 0 ? item.content : '请描述并分析这些图片。';
        const textPart: Record<string, Object> = {
          'type': 'text',
          'text': promptText
        };
        parts.push(textPart);
        for (let j = 0; j < item.imagePaths.length; j++) {
          try {
            const base64: string = this.attachmentService.readBase64(item.imagePaths[j]);
            const imageUrl: Record<string, Object> = {
              'url': `data:image/jpeg;base64,${base64}`
            };
            const imagePart: Record<string, Object> = {
              'type': 'image_url',
              'image_url': imageUrl
            };
            parts.push(imagePart);
          } catch (error) {
            // 文件可能被系统清理；跳过坏图，仍然让文本消息送达。
          }
        }
        messages.push({
          role: 'user',
          content: parts
        });
      } else {
        let content: string = item.content;
        if (item.imagePaths.length > 0) {
          const note: string = `[用户此前上传了 ${item.imagePaths.length} 张图片]`;
          content = content.length > 0 ? `${content}\n${note}` : note;
        }
        messages.push({
          role: 'user',
          content: content
        });
      }
    }
    return messages;
  }

  private buildEndpoint(baseUrl: string): string {
    let base: string = baseUrl.trim();
    if (base.length === 0) {
      throw new AiError('Base URL 为空，请到设置中填写。');
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      throw new AiError('Base URL 必须以 http:// 或 https:// 开头。');
    }
    while (base.endsWith('/')) {
      base = base.slice(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      return base;
    }
    return `${base}/chat/completions`;
  }

  private resultToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    return JSON.stringify(result);
  }

  private describeHttpError(statusCode: number, raw: string): string {
    let detail: string = '';
    try {
      const parsed = JSON.parse(raw) as ApiErrorEnvelope;
      if (parsed.error && parsed.error.message) {
        detail = parsed.error.message;
      } else if (parsed.message) {
        detail = parsed.message;
      }
    } catch (error) {
      detail = '';
    }
    if (detail.length === 0 && raw.length > 0) {
      detail = raw.length > 180 ? raw.slice(0, 180) : raw;
    }

    if (statusCode === 401 || statusCode === 403) {
      return `API Key 无效或无权限（HTTP ${statusCode}）${detail ? '：' + detail : ''}`;
    }
    if (statusCode === 404) {
      return `接口地址或模型不存在（HTTP 404）${detail ? '：' + detail : ''}。请检查 Base URL（如 https://api.deepseek.com）和模型名。`;
    }
    if (statusCode === 429) {
      return `请求过于频繁或额度不足（HTTP 429）${detail ? '：' + detail : ''}`;
    }
    return `模型服务请求失败（HTTP ${statusCode}）${detail ? '：' + detail : ''}`;
  }
}

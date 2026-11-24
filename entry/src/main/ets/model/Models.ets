/**
 * 全局数据模型。
 * 所有会被 JSON 序列化到 Preferences 的类都提供 fromPlain 做一次防御性恢复，
 * 避免版本升级或异常退出造成的字段缺失直接导致页面崩溃。
 */

export type MessageRole = 'user' | 'assistant';
export type MessageStatus = 'done' | 'loading' | 'error';

export class ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  imagePaths: string[];
  createdAt: number;
  status: MessageStatus;
  rev: number;

  constructor(id: string, role: MessageRole, content: string, imagePaths: string[], createdAt: number) {
    this.id = id;
    this.role = role;
    this.content = content;
    this.imagePaths = imagePaths;
    this.createdAt = createdAt;
    this.status = 'done';
    this.rev = createdAt;
  }

  static user(id: string, content: string, imagePaths: string[]): ChatMessage {
    return new ChatMessage(id, 'user', content, imagePaths, Date.now());
  }

  static assistant(id: string, content: string): ChatMessage {
    return new ChatMessage(id, 'assistant', content, [], Date.now());
  }

  static fromPlain(raw: ChatMessage): ChatMessage {
    const paths: string[] = [];
    if (raw.imagePaths && Array.isArray(raw.imagePaths)) {
      raw.imagePaths.forEach((item: string) => {
        if (item.length > 0) {
          paths.push(item);
        }
      });
    }
    const message = new ChatMessage(
      raw.id ?? Math.random().toString(36).slice(2),
      raw.role === 'assistant' ? 'assistant' : 'user',
      raw.content ?? '',
      paths,
      raw.createdAt ?? Date.now()
    );
    if (raw.status === 'loading') {
      // 上次进程在回复途中被杀掉，重新打开时不能一直转圈。
      message.status = 'error';
      message.content = '上次回复未完成，请点击重试。';
    } else {
      message.status = raw.status === 'error' ? 'error' : 'done';
    }
    message.rev = raw.rev ?? message.createdAt;
    return message;
  }
}

export class Conversation {
  id: string;
  title: string;
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
  pinned: boolean;

  constructor(id: string, title: string, messages: ChatMessage[], createdAt: number, updatedAt: number,
    pinned: boolean = false) {
    this.id = id;
    this.title = title;
    this.messages = messages;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.pinned = pinned;
  }

  static create(id: string): Conversation {
    const now = Date.now();
    return new Conversation(id, '新对话', [], now, now, false);
  }

  static fromPlain(raw: Conversation, fallbackId: string): Conversation {
    const messages: ChatMessage[] = [];
    if (raw.messages && Array.isArray(raw.messages)) {
      raw.messages.forEach((item: ChatMessage) => {
        messages.push(ChatMessage.fromPlain(item));
      });
    }
    const conversation = new Conversation(
      raw.id ?? fallbackId,
      raw.title && raw.title.length > 0 ? raw.title : '新对话',
      messages,
      raw.createdAt ?? Date.now(),
      raw.updatedAt ?? Date.now(),
      raw.pinned === true
    );
    return conversation;
  }

  lastPreview(): string {
    if (this.messages.length === 0) {
      return '开始一段新的对话';
    }
    const last = this.messages[this.messages.length - 1];
    if (last.role === 'assistant' && last.status === 'loading') {
      return '正在思考…';
    }
    if (last.content.length > 0) {
      const preview: string = last.content.length > 80 ? last.content.slice(0, 80) : last.content;
      return preview.replace(/\s+/g, ' ').trim();
    }
    if (last.imagePaths.length > 0) {
      return `[${last.imagePaths.length} 张图片]`;
    }
    return '开始一段新的对话';
  }
}

export class AppSettings {
  baseUrl: string;
  apiKey: string;
  model: string;
  systemPrompt: string;
  temperature: number;
  autoRead: boolean;
  speechRate: number;
  speechVolume: number;
  speechPitch: number;
  speechVoice: string;
  speechEngine: string;
  deepseekVoice: string;
  dshHost: string;
  dshPort: number;
  dshToken: string;
  themeMode: string;
  fontScale: number;
  webSearchEnabled: boolean;

  constructor() {
    this.baseUrl = 'https://api.deepseek.com';
    this.apiKey = '';
    this.model = 'deepseek-flash';
    this.systemPrompt = '你是一个乐于助人的中文 AI 助手。回答要清晰、准确，尽量使用简洁的结构；必要时使用 Markdown 列表和代码块。';
    this.temperature = 0.7;
    this.autoRead = false;
    this.speechRate = 1.0;
    this.speechVolume = 1.0;
    this.speechPitch = 1.0;
    this.speechVoice = 'xiaoshan';
    this.speechEngine = 'deepseek';
    this.deepseekVoice = 'stella';
    this.dshHost = '';
    this.dshPort = 17860;
    this.dshToken = '';
    this.themeMode = 'system';
    this.fontScale = 1.0;
    this.webSearchEnabled = true;
  }

  static fromPlain(raw: AppSettings): AppSettings {
    const settings = new AppSettings();
    if (!raw) {
      return settings;
    }
    if (raw.baseUrl) {
      settings.baseUrl = raw.baseUrl;
    }
    if (raw.apiKey) {
      settings.apiKey = raw.apiKey;
    }
    if (raw.model) {
      settings.model = raw.model;
    }
    if (raw.systemPrompt !== undefined) {
      settings.systemPrompt = raw.systemPrompt;
    }
    if (typeof raw.temperature === 'number') {
      settings.temperature = Math.min(2, Math.max(0, raw.temperature));
    }
    if (typeof raw.autoRead === 'boolean') {
      settings.autoRead = raw.autoRead;
    }
    if (typeof raw.speechRate === 'number') {
      settings.speechRate = Math.min(2, Math.max(0.5, raw.speechRate));
    }
    if (typeof raw.speechVolume === 'number') {
      settings.speechVolume = Math.min(2, Math.max(0, raw.speechVolume));
    }
    if (typeof raw.speechPitch === 'number') {
      settings.speechPitch = Math.min(2, Math.max(0.5, raw.speechPitch));
    }
    if (raw.speechVoice === 'lingfeizhe' || raw.speechVoice === 'shell' || raw.speechVoice === 'xiaoshan') {
      settings.speechVoice = raw.speechVoice;
    }
    if (raw.speechEngine === 'system' || raw.speechEngine === 'deepseek') {
      settings.speechEngine = raw.speechEngine;
    }
    if (raw.deepseekVoice === 'stella' || raw.deepseekVoice === 'tide') {
      settings.deepseekVoice = raw.deepseekVoice;
    }
    if (typeof raw.dshHost === 'string') {
      settings.dshHost = raw.dshHost;
    }
    if (typeof raw.dshPort === 'number' && raw.dshPort > 0 && raw.dshPort < 65536) {
      settings.dshPort = Math.round(raw.dshPort);
    }
    if (typeof raw.dshToken === 'string') {
      settings.dshToken = raw.dshToken;
    }
    if (raw.themeMode === 'light' || raw.themeMode === 'dark' || raw.themeMode === 'system') {
      settings.themeMode = raw.themeMode;
    }
    if (typeof raw.fontScale === 'number') {
      settings.fontScale = Math.min(1.3, Math.max(0.85, raw.fontScale));
    }
    if (typeof raw.webSearchEnabled === 'boolean') {
      settings.webSearchEnabled = raw.webSearchEnabled;
    }
    return settings;
  }

  clone(): AppSettings {
    const settings = new AppSettings();
    settings.baseUrl = this.baseUrl;
    settings.apiKey = this.apiKey;
    settings.model = this.model;
    settings.systemPrompt = this.systemPrompt;
    settings.temperature = this.temperature;
    settings.autoRead = this.autoRead;
    settings.speechRate = this.speechRate;
    settings.speechVolume = this.speechVolume;
    settings.speechPitch = this.speechPitch;
    settings.speechVoice = this.speechVoice;
    settings.speechEngine = this.speechEngine;
    settings.deepseekVoice = this.deepseekVoice;
    settings.dshHost = this.dshHost;
    settings.dshPort = this.dshPort;
    settings.dshToken = this.dshToken;
    settings.themeMode = this.themeMode;
    settings.fontScale = this.fontScale;
    settings.webSearchEnabled = this.webSearchEnabled;
    return settings;
  }

  isVisionConfigured(): boolean {
    const lower: string = this.model.toLowerCase();
    // DeepSeek 官方当前由 deepseek-flash 提供图文输入能力；
    // 同时兼容常见 OpenAI Vision 模型名，避免误报“不支持图片”。
    return lower.includes('deepseek-flash') || lower.includes('deepseek-v4-flash-vision') ||
      lower.includes('vl') || lower.includes('vision') || lower.includes('gpt-4o') ||
      lower.includes('glm-4v') || lower.includes('multimodal') || lower.includes('omni');
  }
}

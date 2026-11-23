import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Conversation, ChatMessage } from '../model/Models';

interface DeepSeekManifest {
  export_format_version?: number;
}

interface DeepSeekIndexEntry {
  id: string;
  inserted_at?: string;
  updated_at?: string;
  title?: string;
}

interface DeepSeekFragment {
  type?: string;
  content?: string;
}

interface DeepSeekMessage {
  id: number;
  parent_id?: number | null;
  role?: string;
  inserted_at?: string;
  fragments?: DeepSeekFragment[];
}

interface DeepSeekSessionFile {
  id: string;
  title?: string | null;
  current_message_id?: number | null;
  inserted_at?: string;
  messages?: DeepSeekMessage[];
}

interface ImportConversationShape {
  id?: string;
  title?: string;
  createdAt?: number;
  updatedAt?: number;
  messages?: ImportMessageShape[];
}

interface ImportMessageShape {
  id?: string;
  role?: string;
  content?: string;
  createdAt?: number;
}

/**
 * 导入 DeepSeek 聊天记录。
 *
 * 支持三类文件：
 * 1. DeepSeek 官网导出的 deepseek_data-*.zip（export_format_version: 3）；
 * 2. 单独导出的 chat_sessions/<id>.json 或 App 自己的同步 JSON；
 * 3. Markdown / TXT，按 User/Assistant 等角色标记拆分。
 *
 * 只导入文字；官网 ZIP 中的图片文件最多在消息里留下 [图片] 占位。
 */
export class ImportService {
  async pickImportFile(context: common.UIAbilityContext): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['DeepSeek 导出或文本|.zip,.json,.md,.txt', '所有文件|.*'];
    const documentPicker = new picker.DocumentViewPicker(context);
    const result: string[] = await documentPicker.select(options);
    if (!result || result.length === 0) {
      return '';
    }
    return result[0];
  }

  async importFromUri(context: common.UIAbilityContext, uri: string): Promise<Conversation[]> {
    const tempBase: string = `${context.cacheDir}/deepseek_import_${Date.now()}`;
    // zlib.decompressFile 要求输入文件以 .zip 结尾；非 ZIP 文件只是按文本读取，
    // 使用 .zip 后缀不会影响内容识别。
    const tempFile: string = `${tempBase}.zip`;
    this.copyUriToFile(uri, tempFile);

    const kind: string = this.detectKind(tempFile);
    try {
      if (kind === 'zip') {
        return await this.importZip(context, tempFile, tempBase);
      }
      const text: string = this.readText(tempFile);
      if (kind === 'json') {
        return this.importJson(text);
      }
      return this.importText(text);
    } finally {
      this.deleteFile(tempFile);
    }
  }

  isUserCancel(error: BusinessError): boolean {
    return error.code === 13900042;
  }

  private copyUriToFile(uri: string, destPath: string): void {
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(source.fd).size;
      if (size > 200 * 1024 * 1024) {
        throw new Error('文件超过 200 MB，暂不支持在手机上导入这么大的导出包。');
      }
      const dest = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(source.fd, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
    } finally {
      fs.closeSync(source);
    }
  }

  private detectKind(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const header = new ArrayBuffer(4);
      fs.readSync(file.fd, header);
      const bytes = new Uint8Array(header);
      if (bytes[0] === 0x50 && bytes[1] === 0x4B) {
        return 'zip';
      }
      if (bytes[0] === 0x7B || bytes[0] === 0x5B) {
        return 'json';
      }
      return 'text';
    } finally {
      fs.closeSync(file);
    }
  }

  private async importZip(context: common.UIAbilityContext, zipPath: string,
    basePath: string): Promise<Conversation[]> {
    const extractDir: string = `${basePath}_unzipped`;
    if (!fs.accessSync(extractDir)) {
      fs.mkdirSync(extractDir);
    }
    await zlib.decompressFile(zipPath, extractDir);
    try {
      const manifestPath: string = `${extractDir}/manifest.json`;
      if (!fs.accessSync(manifestPath)) {
        throw new Error('ZIP 中缺少 manifest.json，可能不是 DeepSeek 官网导出的数据包。');
      }
      const manifest = JSON.parse(this.readText(manifestPath)) as DeepSeekManifest;
      if (manifest.export_format_version !== 3) {
        throw new Error(`不支持导出格式版本 ${manifest.export_format_version ?? '未知'}，当前支持 v3。`);
      }
      const indexPath: string = `${extractDir}/chat_session_index.json`;
      if (!fs.accessSync(indexPath)) {
        throw new Error('ZIP 中缺少 chat_session_index.json。');
      }
      const index = JSON.parse(this.readText(indexPath)) as DeepSeekIndexEntry[];
      if (!Array.isArray(index) || index.length === 0) {
        throw new Error('导出包中没有可导入的对话。');
      }
      const sorted: DeepSeekIndexEntry[] = index.slice();
      sorted.sort((a: DeepSeekIndexEntry, b: DeepSeekIndexEntry) => {
        const ta: number = a.updated_at ? Date.parse(a.updated_at) : 0;
        const tb: number = b.updated_at ? Date.parse(b.updated_at) : 0;
        return tb - ta;
      });

      const conversations: Conversation[] = [];
      const maxConversations: number = 100;
      for (let i = 0; i < sorted.length && conversations.length < maxConversations; i++) {
        const entry = sorted[i];
        const sessionPath: string = `${extractDir}/chat_sessions/${entry.id}.json`;
        if (!fs.accessSync(sessionPath)) {
          continue;
        }
        try {
          const session = JSON.parse(this.readText(sessionPath)) as DeepSeekSessionFile;
          const conversation = this.convertDeepSeekSession(session, entry);
          if (conversation && conversation.messages.length > 0) {
            conversations.push(conversation);
          }
        } catch (error) {
          console.error(`跳过无法解析的 DeepSeek 会话 ${entry.id}: ${(error as BusinessError).message}`);
        }
      }
      if (conversations.length === 0) {
        throw new Error('没有解析出可导入的对话，文件可能已损坏或缺少文字内容。');
      }
      return conversations;
    } finally {
      this.removeDirectory(extractDir);
    }
  }

  private convertDeepSeekSession(session: DeepSeekSessionFile,
    entry: DeepSeekIndexEntry): Conversation | undefined {
    if (!session || !session.messages || session.messages.length === 0) {
      return undefined;
    }
    const byId: Map<number, DeepSeekMessage> = new Map<number, DeepSeekMessage>();
    for (let i = 0; i < session.messages.length; i++) {
      const message = session.messages[i];
      byId.set(message.id, message);
    }

    let leaf: DeepSeekMessage | undefined = undefined;
    if (session.current_message_id !== null && session.current_message_id !== undefined) {
      leaf = byId.get(session.current_message_id);
    }
    if (!leaf) {
      let maxId: number = -1;
      for (let i = 0; i < session.messages.length; i++) {
        if (session.messages[i].id > maxId) {
          maxId = session.messages[i].id;
          leaf = session.messages[i];
        }
      }
    }
    if (!leaf) {
      return undefined;
    }

    const chain: DeepSeekMessage[] = [];
    let cursor: DeepSeekMessage | undefined = leaf;
    const seen: Set<number> = new Set<number>();
    while (cursor && !seen.has(cursor.id)) {
      seen.add(cursor.id);
      chain.push(cursor);
      if (cursor.parent_id === null || cursor.parent_id === undefined) {
        break;
      }
      cursor = byId.get(cursor.parent_id);
    }
    chain.reverse();

    const messages: ChatMessage[] = [];
    for (let i = 0; i < chain.length; i++) {
      const raw = chain[i];
      const role: string = raw.role === 'ASSISTANT' ? 'assistant' : 'user';
      let content: string = '';
      if (raw.fragments) {
        for (let j = 0; j < raw.fragments.length; j++) {
          const fragment = raw.fragments[j];
          if (role === 'user' && fragment.type === 'REQUEST' && fragment.content) {
            content += fragment.content;
          }
          if (role === 'assistant' && fragment.type === 'RESPONSE' && fragment.content) {
            content += fragment.content;
          }
        }
      }
      if (content.trim().length === 0) {
        continue;
      }
      const time: number = raw.inserted_at ? Date.parse(raw.inserted_at) : Date.now();
      const message = new ChatMessage(
        `deepseek_${session.id}_${raw.id}`,
        role === 'assistant' ? 'assistant' : 'user',
        content,
        [],
        Number.isNaN(time) ? Date.now() : time
      );
      messages.push(message);
    }
    if (messages.length === 0) {
      return undefined;
    }

    const firstUser = messages.find((message: ChatMessage) => message.role === 'user');
    let title: string = session.title && session.title.length > 0 ? session.title : '';
    if (title.length === 0 && firstUser) {
      title = firstUser.content.replace(/\s+/g, ' ').slice(0, 24);
    }
    if (title.length === 0) {
      title = entry.title && entry.title.length > 0 ? entry.title : 'DeepSeek 导入对话';
    }
    const createdAt: number = session.inserted_at ? Date.parse(session.inserted_at) : messages[0].createdAt;
    const updatedAt: number = entry.updated_at ? Date.parse(entry.updated_at) : messages[messages.length - 1].createdAt;
    return new Conversation(
      `deepseek_${session.id}`,
      title,
      messages,
      Number.isNaN(createdAt) ? Date.now() : createdAt,
      Number.isNaN(updatedAt) ? Date.now() : updatedAt
    );
  }

  private importJson(text: string): Conversation[] {
    const parsed = JSON.parse(text) as Object;
    if (parsed === null || parsed === undefined) {
      throw new Error('JSON 文件为空。');
    }
    // App / DSH 同步格式：数组或 { conversations: [...] }
    let rawList: Object[] = [];
    if (Array.isArray(parsed)) {
      rawList = parsed as Object[];
    } else {
      const container = parsed as Record<string, Object>;
      if (Array.isArray(container.conversations)) {
        rawList = container.conversations as Object[];
      }
    }
    if (rawList.length > 0) {
      return this.convertGeneric(rawList);
    }

    // 单个 DeepSeek chat_sessions/<id>.json
    const session = parsed as DeepSeekSessionFile;
    if (session.id && Array.isArray(session.messages)) {
      const conversation = this.convertDeepSeekSession(session, { id: session.id });
      return conversation ? [conversation] : [];
    }
    throw new Error('无法识别这个 JSON 文件。请选择 DeepSeek 导出的 ZIP、会话 JSON 或 App 同步 JSON。');
  }

  private convertGeneric(rawList: Object[]): Conversation[] {
    const result: Conversation[] = [];
    const maxConversations: number = 100;
    for (let i = 0; i < rawList.length && result.length < maxConversations; i++) {
      const raw = rawList[i] as ImportConversationShape;
      if (!raw) {
        continue;
      }
      const messages: ChatMessage[] = [];
      if (raw.messages && Array.isArray(raw.messages)) {
        for (let j = 0; j < raw.messages.length; j++) {
          const item = raw.messages[j];
          if (!item || !item.content) {
            continue;
          }
          const role: string = item.role === 'assistant' ? 'assistant' : 'user';
          messages.push(new ChatMessage(
            item.id ? item.id : `import_${i}_${j}`,
            role === 'assistant' ? 'assistant' : 'user',
            item.content,
            [],
            item.createdAt ? item.createdAt : Date.now()
          ));
        }
      }
      if (messages.length === 0) {
        continue;
      }
      const computedTitle: string = raw.title && raw.title.length > 0 ? raw.title :
        messages[0].content.replace(/\s+/g, ' ').slice(0, 24);
      result.push(new Conversation(
        raw.id ? raw.id : `import_${Date.now()}_${i}`,
        computedTitle,
        messages,
        raw.createdAt ? raw.createdAt : messages[0].createdAt,
        raw.updatedAt ? raw.updatedAt : messages[messages.length - 1].createdAt
      ));
    }
    return result;
  }

  private importText(text: string): Conversation[] {
    const normalized: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines: string[] = normalized.split('\n');
    const messages: ChatMessage[] = [];
    let currentRole: string = '';
    let currentContent: string[] = [];
    let title: string = '';

    const flush = () => {
      if (currentRole.length > 0 && currentContent.join('\n').trim().length > 0) {
        const content: string = currentContent.join('\n').trim();
        messages.push(new ChatMessage(
          `text_${messages.length}_${Date.now()}`,
          currentRole === 'assistant' ? 'assistant' : 'user',
          content,
          [],
          Date.now()
        ));
      }
      currentContent = [];
    };

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (title.length === 0 && /^#\s+/.test(line)) {
        title = line.replace(/^#\s+/, '').trim();
        continue;
      }
      const match = /^(?:#{1,6}\s*)?(?:\*\*)?(User|You|Human|Assistant|AI|DeepSeek|用户|助手|我|你)(?:\*\*)?\s*[:：]\s*(.*)$/i.exec(line);
      if (match) {
        flush();
        const roleText: string = match[1].toLowerCase();
        currentRole = (roleText === 'assistant' || roleText === 'ai' || roleText === 'deepseek' ||
          roleText === '助手' || roleText === '你') ? 'assistant' : 'user';
        if (match[2].trim().length > 0) {
          currentContent.push(match[2]);
        }
      } else if (currentRole.length > 0) {
        currentContent.push(line);
      }
    }
    flush();

    if (messages.length === 0) {
      const fallback = normalized.trim();
      if (fallback.length === 0) {
        throw new Error('文件内容为空，无法导入。');
      }
      messages.push(new ChatMessage(`text_${Date.now()}`, 'user', fallback, [], Date.now()));
    }
    if (title.length === 0) {
      const firstUser = messages.find((message: ChatMessage) => message.role === 'user');
      title = firstUser ? firstUser.content.replace(/\s+/g, ' ').slice(0, 24) : '导入的文本对话';
    }
    return [new Conversation(
      `text_import_${Date.now()}`,
      title,
      messages,
      messages[0].createdAt,
      messages[messages.length - 1].createdAt
    )];
  }

  private readText(path: string): string {
    return fs.readTextSync(path);
  }

  private deleteFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      console.warn(`清理临时导入文件失败: ${(error as BusinessError).message}`);
    }
  }

  private removeDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const names: string[] = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        const child: string = `${path}/${names[i]}`;
        const stat = fs.statSync(child);
        if (stat.isDirectory()) {
          this.removeDirectory(child);
        } else {
          fs.unlinkSync(child);
        }
      }
      fs.rmdirSync(path);
    } catch (error) {
      console.warn(`清理临时解压目录失败: ${(error as BusinessError).message}`);
    }
  }
}

import { common } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { promptAction, window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { AppSettings, ChatMessage, Conversation } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { AttachmentService } from '../service/AttachmentService';
import { AiService } from '../service/AiService';
import { SpeechService } from '../service/SpeechService';
import { DeepSeekSpeechService } from '../service/DeepSeekSpeechService';
import { ImportService } from '../service/ImportService';
import { DshSyncService } from '../service/DshSyncService';

const ACCENT: string = '#4D6BFE';
const ACCENT_SOFT: string = '#EEF1FF';
const BG: string = '#F4F5F9';
const PANEL: string = '#FFFFFF';
const TEXT_MAIN: string = '#1B1F2A';
const TEXT_SECONDARY: string = '#7A8194';
const TEXT_FAINT: string = '#A3A9B8';
const LINE: string = '#EDEFF4';
const DANGER: string = '#D92D20';
const DANGER_SOFT: string = '#FFF4F3';
const WARNING: string = '#B45309';
const WARNING_SOFT: string = '#FFF8E7';
const MAX_IMAGES: number = 9;

const SUGGESTIONS: string[] = [
  '帮我制定一个一周学习计划',
  '解释一下什么是量子纠缠，尽量通俗',
  '把下面这段话改写得更简洁：',
  '上传图片，帮我分析画面内容'
];

@Entry
@Component
struct Index {
  @State conversations: Conversation[] = [];
  @State activeId: string = '';
  @State inputText: string = '';
  @State attachments: string[] = [];
  @State loading: boolean = false;
  @State booting: boolean = true;
  @State isWide: boolean = false;
  @State showSidebar: boolean = false;
  @State showSettings: boolean = false;
  @State speakingMessageId: string = '';
  @State previewPath: string = '';
  @State pickingImages: boolean = false;
  @State importingHistory: boolean = false;
  @State syncingDsh: boolean = false;
  @State testingDsh: boolean = false;
  @State settings: AppSettings = new AppSettings();
  @State testingConnection: boolean = false;
  @StorageProp('systemDark') systemDark: boolean = false;

  @State draftBaseUrl: string = '';
  @State draftApiKey: string = '';
  @State draftModel: string = '';
  @State draftSystemPrompt: string = '';
  @State draftTemperature: number = 0.7;
  @State draftAutoRead: boolean = false;
  @State draftSpeechRate: number = 1.0;
  @State draftSpeechVolume: number = 1.0;
  @State draftSpeechPitch: number = 1.0;
  @State draftSpeechVoice: string = 'xiaoshan';
  @State draftSpeechEngine: string = 'deepseek';
  @State draftDeepseekVoice: string = 'stella';
  @State previewingVoice: boolean = false;
  @State previewingVoiceName: string = '';
  @State draftDshHost: string = '';
  @State draftDshPort: string = '17860';
  @State draftDshToken: string = '';
  @State draftThemeMode: string = 'system';
  @State draftFontScale: number = 1.0;

  @State conversationMenuId: string = '';
  @State messageMenuId: string = '';
  @State renamingConversationId: string = '';
  @State renameText: string = '';
  @State selectTextMessageId: string = '';

  private store: StoreService = new StoreService();
  private attachmentService: AttachmentService = new AttachmentService();
  private aiService: AiService = new AiService();
  private speechService: SpeechService = new SpeechService();
  private deepSeekSpeechService: DeepSeekSpeechService = new DeepSeekSpeechService();
  private importService: ImportService = new ImportService();
  private dshSyncService: DshSyncService = new DshSyncService();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.bootstrap();
  }

  aboutToDisappear(): void {
    this.speechService.release();
    this.deepSeekSpeechService.stop();
    this.attachmentService.deleteFiles(this.attachments);
  }

  onBackPress(): boolean {
    if (this.selectTextMessageId.length > 0) {
      this.selectTextMessageId = '';
      return true;
    }
    if (this.renamingConversationId.length > 0) {
      this.renamingConversationId = '';
      return true;
    }
    if (this.messageMenuId.length > 0) {
      this.messageMenuId = '';
      return true;
    }
    if (this.conversationMenuId.length > 0) {
      this.conversationMenuId = '';
      return true;
    }
    if (this.previewPath.length > 0) {
      this.previewPath = '';
      return true;
    }
    if (this.showSettings) {
      this.stopVoicePreview();
      this.showSettings = false;
      this.applySystemBarTheme();
      return true;
    }
    if (this.showSidebar) {
      this.showSidebar = false;
      return true;
    }
    return false;
  }

  private async bootstrap(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.store.init(context);
      this.settings = this.store.loadSettings();
      this.conversations = this.store.loadConversations();
      if (this.conversations.length === 0) {
        const conversation = Conversation.create(this.newId());
        this.conversations = [conversation];
        this.activeId = conversation.id;
        await this.store.saveConversations(this.conversations);
      } else {
        this.activeId = this.conversations[0].id;
      }
    } catch (error) {
      const businessError = error as BusinessError;
      this.toast(`本地数据加载失败：${businessError.message ?? '未知错误'}`);
      const conversation = Conversation.create(this.newId());
      this.conversations = [conversation];
      this.activeId = conversation.id;
    }

    this.bindSpeechCallbacks();
    this.booting = false;
    this.applySystemBarTheme();
    this.scrollToBottom();
  }

  private bindSpeechCallbacks(): void {
    this.speechService.setCallbacks({
      onStart: () => {
      },
      onComplete: () => {
        this.speakingMessageId = '';
      },
      onError: (message: string) => {
        this.speakingMessageId = '';
        this.toast(message);
      }
    });
  }

  private newId(): string {
    return util.generateRandomUUID(true);
  }

  private toast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 2200
    });
  }

  private getActiveConversation(): Conversation | undefined {
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id === this.activeId) {
        return this.conversations[i];
      }
    }
    return undefined;
  }

  private getActiveMessages(): ChatMessage[] {
    const conversation = this.getActiveConversation();
    return conversation ? conversation.messages.slice() : [];
  }

  /**
   * 侧栏只展示真正聊过的对话。空白“新对话”作为当前草稿保留，
   * 但不进入历史列表，避免删除后出现多个同名空对话。
   */
  private visibleConversations(): Conversation[] {
    return this.conversations.filter((conversation: Conversation) => conversation.messages.length > 0);
  }

  private headerTitle(): string {
    const conversation = this.getActiveConversation();
    return conversation ? conversation.title : '新对话';
  }

  private isDarkMode(): boolean {
    const mode: string = this.showSettings ? this.draftThemeMode : this.settings.themeMode;
    if (mode === 'dark') {
      return true;
    }
    if (mode === 'light') {
      return false;
    }
    return this.systemDark;
  }

  private colorBg(): string {
    return this.isDarkMode() ? '#101218' : '#F4F5F9';
  }

  private colorPanel(): string {
    return this.isDarkMode() ? '#181B22' : '#FFFFFF';
  }

  private colorTextMain(): string {
    return this.isDarkMode() ? '#F2F4FA' : '#1B1F2A';
  }

  private colorTextSecondary(): string {
    return this.isDarkMode() ? '#A7AFBF' : '#7A8194';
  }

  private colorTextFaint(): string {
    return this.isDarkMode() ? '#788195' : '#A3A9B8';
  }

  private colorLine(): string {
    return this.isDarkMode() ? '#2A2F3B' : '#EDEFF4';
  }

  private colorAccentSoft(): string {
    return this.isDarkMode() ? '#252B45' : '#EEF1FF';
  }

  private colorDanger(): string {
    return this.isDarkMode() ? '#FF7B72' : '#D92D20';
  }

  private colorDangerSoft(): string {
    return this.isDarkMode() ? '#3A1E20' : '#FFF4F3';
  }

  private colorWarning(): string {
    return this.isDarkMode() ? '#F0B35B' : '#B45309';
  }

  private colorWarningSoft(): string {
    return this.isDarkMode() ? '#352A18' : '#FFF8E7';
  }

  private colorSurfaceAlt(): string {
    return this.isDarkMode() ? '#232731' : '#F2F4F8';
  }

  private colorInputBg(): string {
    return this.isDarkMode() ? '#20242D' : '#F5F6FA';
  }

  private colorDisabled(): string {
    return this.isDarkMode() ? '#3B4252' : '#D6DBE8';
  }

  private fs(size: number): number {
    return Math.round(size * this.settings.fontScale);
  }

  private applyThemeMode(mode: string): void {
    this.draftThemeMode = mode;
    const next: AppSettings = this.settings.clone();
    next.themeMode = mode;
    this.settings = next;
    this.store.saveSettings(next).catch((error: BusinessError) => {
      console.error(`保存主题失败: ${error.message}`);
    });
    this.applySystemBarTheme();
  }

  private applySystemBarTheme(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((lastWindow: window.Window) => {
      lastWindow.setWindowSystemBarProperties({
        statusBarColor: this.colorBg(),
        statusBarContentColor: this.isDarkMode() ? '#FFFFFF' : '#1A1D26',
        navigationBarColor: this.colorBg(),
        navigationBarContentColor: this.isDarkMode() ? '#FFFFFF' : '#1A1D26'
      });
    }).catch((error: BusinessError) => {
      console.warn(`设置系统栏失败: ${error.message}`);
    });
  }

  private sortConversations(): void {
    const sorted: Conversation[] = this.conversations.slice();
    sorted.sort((a: Conversation, b: Conversation) => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt - a.updatedAt;
    });
    this.conversations = sorted;
  }

  private findConversation(id: string): Conversation | undefined {
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id === id) {
        return this.conversations[i];
      }
    }
    return undefined;
  }

  private findMessage(id: string): ChatMessage | undefined {
    const conversation = this.getActiveConversation();
    if (!conversation) {
      return undefined;
    }
    for (let i = 0; i < conversation.messages.length; i++) {
      if (conversation.messages[i].id === id) {
        return conversation.messages[i];
      }
    }
    return undefined;
  }

  private persistConversations(): void {
    this.store.saveConversations(this.conversations).catch((error: BusinessError) => {
      console.error(`保存对话失败: ${error.message}`);
    });
  }

  private touchConversation(conversation: Conversation): void {
    this.sortConversations();
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 90);
  }

  private cleanupDraftAttachments(): void {
    if (this.attachments.length > 0) {
      this.attachmentService.deleteFiles(this.attachments);
      this.attachments = [];
    }
  }

  private stopReading(): void {
    this.speechService.stop();
    this.deepSeekSpeechService.stop();
    this.speakingMessageId = '';
  }

  private stopVoicePreview(): void {
    if (!this.previewingVoice) {
      return;
    }
    this.previewingVoice = false;
    this.previewingVoiceName = '';
    this.speechService.stop();
    this.deepSeekSpeechService.stop();
    this.bindSpeechCallbacks();
  }

  private finishVoicePreview(): void {
    if (!this.previewingVoice) {
      return;
    }
    this.previewingVoice = false;
    this.previewingVoiceName = '';
    this.bindSpeechCallbacks();
  }

  private voicePreviewText(): string {
    return '你好，我是鸿语。\n你好呀，今天想聊点什么？\n我想听你用通俗的话讲讲量子纠缠。\n好的。两个粒子可以形成一个整体，测量其中一个，另一个的状态也会随之确定。';
  }

  private deepseekVoiceLabel(voiceId: string): string {
    return voiceId === 'tide' ? '暗潮' : '海星';
  }

  private previewDeepSeekVoice(voiceId: string): void {
    this.stopVoicePreview();
    this.stopReading();
    this.draftDeepseekVoice = voiceId;
    this.previewingVoice = true;
    this.previewingVoiceName = `DeepSeek · ${this.deepseekVoiceLabel(voiceId)}`;
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.deepSeekSpeechService.speak(context, this.settings.apiKey, this.voicePreviewText(), voiceId, {
      onComplete: () => {
        this.finishVoicePreview();
      },
      onError: (message: string) => {
        this.finishVoicePreview();
        this.toast(message);
      }
    }).catch((error: Error) => {
      this.finishVoicePreview();
      this.toast(`试听失败：${error.message}`);
    });
  }

  private previewVoice(voice: string): void {
    this.stopVoicePreview();
    this.stopReading();
    this.draftSpeechVoice = voice;
    if (voice === 'shell') {
      this.draftSpeechPitch = 1.15;
      this.draftSpeechRate = 1.08;
    }
    this.previewingVoice = true;
    this.previewingVoiceName = voice === 'lingfeizhe' ? '凌飞哲' : (voice === 'shell' ? '贝壳风格' : '聆小珊');
    this.speechService.setCallbacks({
      onStart: () => {
      },
      onComplete: () => {
        this.finishVoicePreview();
      },
      onError: (message: string) => {
        this.finishVoicePreview();
        this.toast(message);
      }
    });
    this.speechService.speak(this.voicePreviewText(), this.draftSpeechRate, Math.min(1, this.draftSpeechVolume),
      this.draftSpeechPitch, voice === 'lingfeizhe' ? 21 : 13).catch((error: Error) => {
      this.finishVoicePreview();
      this.toast(`试听失败：${error.message}。请确认系统语音服务可用。`);
    });
  }

  private selectConversation(id: string): void {
    if (this.loading) {
      this.toast('请等待当前回复完成后再切换对话');
      return;
    }
    if (this.pickingImages) {
      this.toast('图片处理中，请稍候');
      return;
    }
    if (this.importingHistory || this.syncingDsh) {
      this.toast('请等待导入或同步完成');
      return;
    }
    this.showSidebar = false;
    if (id === this.activeId) {
      return;
    }
    this.cleanupDraftAttachments();
    this.stopReading();
    this.inputText = '';
    this.activeId = id;
    this.scrollToBottom();
  }

  private newConversation(): void {
    if (this.loading) {
      this.toast('请等待当前回复完成');
      return;
    }
    if (this.pickingImages) {
      this.toast('图片处理中，请稍候');
      return;
    }
    if (this.importingHistory || this.syncingDsh) {
      this.toast('请等待导入或同步完成');
      return;
    }
    this.cleanupDraftAttachments();
    this.stopReading();
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].messages.length === 0) {
        this.activeId = this.conversations[i].id;
        this.inputText = '';
        this.showSidebar = false;
        this.scrollToBottom();
        return;
      }
    }
    const conversation = Conversation.create(this.newId());
    this.conversations = [conversation].concat(this.conversations);
    this.activeId = conversation.id;
    this.inputText = '';
    this.showSidebar = false;
    this.sortConversations();
    this.persistConversations();
    this.scrollToBottom();
  }

  private showDeleteDialog(conversation: Conversation): void {
    if (this.loading) {
      this.toast('请等待当前回复完成');
      return;
    }
    if (this.pickingImages) {
      this.toast('图片处理中，请稍候');
      return;
    }
    if (this.importingHistory || this.syncingDsh) {
      this.toast('请等待导入或同步完成');
      return;
    }
    AlertDialog.show({
      title: '删除对话',
      message: `确定删除“${conversation.title}”吗？删除后无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.colorDanger(),
        action: () => {
          this.deleteConversation(conversation);
        }
      }
    });
  }

  private deleteConversation(conversation: Conversation): void {
    this.stopReading();
    const imagePaths: string[] = [];
    for (let i = 0; i < conversation.messages.length; i++) {
      const paths: string[] = conversation.messages[i].imagePaths;
      for (let j = 0; j < paths.length; j++) {
        imagePaths.push(paths[j]);
      }
    }
    this.attachmentService.deleteFiles(imagePaths);

    const remaining: Conversation[] = [];
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id !== conversation.id) {
        remaining.push(this.conversations[i]);
      }
    }
    if (remaining.length === 0) {
      this.activeId = '';
    } else if (this.activeId === conversation.id) {
      this.activeId = remaining[0].id;
    }
    this.conversations = remaining;
    this.showSidebar = false;
    this.persistConversations();
    this.scrollToBottom();
    this.toast('对话已删除');
  }

  private makeTitle(text: string, imageCount: number): string {
    let title: string = text.replace(/\s+/g, ' ').trim();
    if (title.length === 0) {
      title = imageCount > 0 ? `图片对话（${imageCount} 张）` : '新对话';
    }
    if (title.length > 20) {
      title = `${title.slice(0, 20)}…`;
    }
    return title;
  }

  private openConversationMenu(conversation: Conversation): void {
    this.conversationMenuId = conversation.id;
  }

  private menuConversationTitle(): string {
    const conversation = this.findConversation(this.conversationMenuId);
    return conversation ? conversation.title : '对话';
  }

  private menuConversationPinned(): boolean {
    const conversation = this.findConversation(this.conversationMenuId);
    return conversation ? conversation.pinned : false;
  }

  private pinMenuConversation(): void {
    const conversation = this.findConversation(this.conversationMenuId);
    if (conversation) {
      this.togglePin(conversation);
    }
  }

  private renameMenuConversation(): void {
    const conversation = this.findConversation(this.conversationMenuId);
    if (conversation) {
      this.beginRename(conversation);
    }
  }

  private deleteMenuConversation(): void {
    const conversation = this.findConversation(this.conversationMenuId);
    this.conversationMenuId = '';
    if (conversation) {
      this.showDeleteDialog(conversation);
    }
  }

  private copyMenuMessage(): void {
    const message = this.findMessage(this.messageMenuId);
    this.messageMenuId = '';
    if (message) {
      this.copyMessage(message.content);
    }
  }

  private selectMenuMessageText(): void {
    const message = this.findMessage(this.messageMenuId);
    if (message) {
      this.beginSelectText(message);
    }
  }

  private regenerateMenuMessage(): void {
    const message = this.findMessage(this.messageMenuId);
    if (message) {
      this.regenerateMessage(message);
    }
  }

  private readMenuMessage(): void {
    const message = this.findMessage(this.messageMenuId);
    this.messageMenuId = '';
    if (message) {
      this.toggleRead(message);
    }
  }

  private togglePin(conversation: Conversation): void {
    conversation.pinned = !conversation.pinned;
    this.sortConversations();
    this.conversationMenuId = '';
    this.persistConversations();
    this.toast(conversation.pinned ? '已置顶' : '已取消置顶');
  }

  private beginRename(conversation: Conversation): void {
    this.conversationMenuId = '';
    this.renamingConversationId = conversation.id;
    this.renameText = conversation.title;
  }

  private commitRename(): void {
    const conversation = this.findConversation(this.renamingConversationId);
    const title: string = this.renameText.trim();
    if (!conversation) {
      this.renamingConversationId = '';
      return;
    }
    if (title.length === 0) {
      this.toast('对话名称不能为空');
      return;
    }
    conversation.title = title.slice(0, 40);
    conversation.updatedAt = Date.now();
    this.sortConversations();
    this.renamingConversationId = '';
    this.persistConversations();
    this.toast('已重命名');
  }

  private openMessageMenu(message: ChatMessage): void {
    if (message.role !== 'assistant' || message.status !== 'done') {
      return;
    }
    this.messageMenuId = message.id;
  }

  private beginSelectText(message: ChatMessage): void {
    this.messageMenuId = '';
    this.selectTextMessageId = message.id;
  }

  private selectedText(): string {
    const message = this.findMessage(this.selectTextMessageId);
    return message ? message.content : '';
  }

  private selectedTextTitle(): string {
    const message = this.findMessage(this.selectTextMessageId);
    return message ? '选择文本' : '文本';
  }

  private async regenerateMessage(message: ChatMessage): Promise<void> {
    if (this.loading) {
      this.toast('请等待当前回复完成');
      return;
    }
    const conversation = this.getActiveConversation();
    if (!conversation) {
      return;
    }
    let index: number = -1;
    for (let i = 0; i < conversation.messages.length; i++) {
      if (conversation.messages[i].id === message.id) {
        index = i;
        break;
      }
    }
    if (index < 0 || message.role !== 'assistant') {
      return;
    }
    let lastUser: ChatMessage | undefined = undefined;
    for (let i = index - 1; i >= 0; i--) {
      if (conversation.messages[i].role === 'user') {
        lastUser = conversation.messages[i];
        break;
      }
    }
    if (!lastUser) {
      this.toast('没有找到对应的用户问题');
      return;
    }
    if (this.settings.apiKey.trim().length === 0) {
      this.messageMenuId = '';
      this.toast('请先在设置中填写 API Key');
      this.openSettings();
      return;
    }
    this.messageMenuId = '';
    const placeholder = ChatMessage.assistant(this.newId(), '');
    placeholder.status = 'loading';
    conversation.messages = conversation.messages.slice(0, index);
    conversation.messages.push(placeholder);
    conversation.updatedAt = Date.now();
    this.loading = true;
    this.touchConversation(conversation);
    this.persistConversations();
    this.scrollToBottom();
    await this.requestReply(conversation, placeholder, lastUser);
  }

  private conversationIndex(): number {
    for (let i = 0; i < this.conversations.length; i++) {
      if (this.conversations[i].id === this.activeId) {
        return i;
      }
    }
    return -1;
  }

  private canGoAdjacent(delta: number): boolean {
    const index: number = this.conversationIndex();
    const target: number = index + delta;
    return index >= 0 && target >= 0 && target < this.conversations.length;
  }

  private goAdjacentConversation(delta: number): void {
    if (this.loading) {
      this.toast('请等待当前回复完成');
      return;
    }
    const index: number = this.conversationIndex();
    const target: number = index + delta;
    if (target < 0) {
      this.toast('已经是第一个对话');
      return;
    }
    if (target >= this.conversations.length) {
      this.toast('已经是最后一个对话');
      return;
    }
    this.selectConversation(this.conversations[target].id);
  }

  private ensureConversationForSend(): Conversation {
    const active = this.getActiveConversation();
    if (active) {
      return active;
    }
    const conversation = Conversation.create(this.newId());
    this.conversations = [conversation].concat(this.conversations);
    this.activeId = conversation.id;
    return conversation;
  }

  private async sendMessage(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (this.pickingImages) {
      this.toast('图片处理中，请稍候');
      return;
    }
    if (this.importingHistory || this.syncingDsh) {
      this.toast('请等待导入或同步完成');
      return;
    }
    const text: string = this.inputText.trim();
    if (text.length === 0 && this.attachments.length === 0) {
      this.toast('请输入消息或先选择图片');
      return;
    }
    if (this.settings.apiKey.trim().length === 0) {
      this.toast('请先在设置中填写 API Key');
      this.openSettings();
      return;
    }

    const conversation = this.ensureConversationForSend();
    const images: string[] = this.attachments.slice();
    const userMessage = ChatMessage.user(this.newId(), text, images);
    const assistantMessage = ChatMessage.assistant(this.newId(), '');
    assistantMessage.status = 'loading';
    conversation.messages.push(userMessage);
    conversation.messages.push(assistantMessage);
    conversation.updatedAt = Date.now();
    if (conversation.title === '新对话') {
      conversation.title = this.makeTitle(text, images.length);
    }

    this.inputText = '';
    // 图片的所有权已经转交给消息，不能再 cleanup。
    this.attachments = [];
    this.loading = true;
    this.touchConversation(conversation);
    this.persistConversations();
    this.scrollToBottom();

    await this.requestReply(conversation, assistantMessage, userMessage);
  }

  private async requestReply(conversation: Conversation, assistantMessage: ChatMessage,
    lastUserMessage: ChatMessage): Promise<void> {
    try {
      const history: ChatMessage[] = conversation.messages.filter((item: ChatMessage) => {
        return item.id !== assistantMessage.id;
      });
      const answer: string = await this.aiService.send(this.settings, history, lastUserMessage);
      assistantMessage.content = answer;
      assistantMessage.status = 'done';
      assistantMessage.rev = Date.now();
      conversation.updatedAt = Date.now();
      if (this.settings.autoRead) {
        this.startReading(assistantMessage);
      }
    } catch (error) {
      const businessError = error as Error;
      const message: string = businessError.message ? businessError.message : '未知错误';
      assistantMessage.content = `请求失败：${message}`;
      assistantMessage.status = 'error';
      assistantMessage.rev = Date.now();
      conversation.updatedAt = Date.now();
    } finally {
      this.loading = false;
      this.touchConversation(conversation);
      this.persistConversations();
      this.scrollToBottom();
    }
  }

  private async retryMessage(message: ChatMessage): Promise<void> {
    if (this.loading) {
      return;
    }
    const conversation = this.getActiveConversation();
    if (!conversation) {
      return;
    }
    if (this.settings.apiKey.trim().length === 0) {
      this.toast('请先在设置中填写 API Key');
      this.openSettings();
      return;
    }
    let index: number = -1;
    for (let i = 0; i < conversation.messages.length; i++) {
      if (conversation.messages[i].id === message.id) {
        index = i;
        break;
      }
    }
    if (index !== conversation.messages.length - 1) {
      this.toast('只能重试最新的一条失败消息');
      return;
    }
    let lastUser: ChatMessage | undefined = undefined;
    for (let i = index - 1; i >= 0; i--) {
      if (conversation.messages[i].role === 'user') {
        lastUser = conversation.messages[i];
        break;
      }
    }
    if (!lastUser) {
      this.toast('没有找到可以重试的问题');
      return;
    }
    message.content = '';
    message.status = 'loading';
    message.rev = Date.now();
    this.loading = true;
    this.touchConversation(conversation);
    this.persistConversations();
    this.scrollToBottom();
    await this.requestReply(conversation, message, lastUser);
  }

  private isLastMessage(message: ChatMessage): boolean {
    const messages: ChatMessage[] = this.getActiveMessages();
    return messages.length > 0 && messages[messages.length - 1].id === message.id;
  }

  private startReading(message: ChatMessage): void {
    if (message.content.trim().length === 0) {
      return;
    }
    this.speakingMessageId = message.id;
    if (this.settings.speechEngine === 'deepseek') {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.deepSeekSpeechService.speak(context, this.settings.apiKey, message.content,
        this.settings.deepseekVoice, {
          onComplete: () => {
            if (this.speakingMessageId === message.id) {
              this.speakingMessageId = '';
            }
          },
          onError: (text: string) => {
            if (this.speakingMessageId === message.id) {
              this.speakingMessageId = '';
            }
            this.toast(text);
          }
        }).catch((error: Error) => {
          if (this.speakingMessageId === message.id) {
            this.speakingMessageId = '';
          }
          this.toast(`在线朗读失败：${error.message}`);
        });
      return;
    }
    this.speakSystem(message);
  }

  private speakSystem(message: ChatMessage): void {
    this.speechService.speak(message.content, this.settings.speechRate, this.settings.speechVolume,
      this.settings.speechPitch, this.settings.speechVoice === 'lingfeizhe' ? 21 : 13)
      .catch((error: Error) => {
        if (this.speakingMessageId === message.id) {
          this.speakingMessageId = '';
        }
        this.toast(`朗读失败：${error.message}。请确认使用真机且系统语音服务可用。`);
      });
  }

  private toggleRead(message: ChatMessage): void {
    if (this.speakingMessageId === message.id) {
      this.stopReading();
      return;
    }
    this.startReading(message);
  }

  private toggleAutoRead(): void {
    this.settings.autoRead = !this.settings.autoRead;
    this.settings = this.settings.clone();
    this.store.saveSettings(this.settings).catch((error: BusinessError) => {
      console.error(`保存朗读设置失败: ${error.message}`);
    });
    if (!this.settings.autoRead) {
      this.speechService.stop();
      this.speakingMessageId = '';
      this.toast('已关闭自动朗读');
    } else {
      this.toast('已开启自动朗读');
    }
  }

  private async copyMessage(content: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制');
    } catch (error) {
      this.toast('复制失败');
    }
  }

  private async pickImages(): Promise<void> {
    if (this.pickingImages || this.importingHistory || this.syncingDsh) {
      return;
    }
    const remaining: number = MAX_IMAGES - this.attachments.length;
    if (remaining <= 0) {
      this.toast(`最多上传 ${MAX_IMAGES} 张图片`);
      return;
    }
    this.pickingImages = true;
    try {
      const uris: string[] = await this.attachmentService.pickUris(remaining);
      if (uris.length === 0) {
        return;
      }
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const added: string[] = [];
      let failed: number = 0;
      for (let i = 0; i < uris.length; i++) {
        try {
          const path: string = await this.attachmentService.saveCompressed(context, uris[i], i);
          added.push(path);
        } catch (error) {
          failed += 1;
          console.error(`图片处理失败: ${(error as BusinessError).message}`);
        }
      }
      if (added.length > 0) {
        this.attachments = this.attachments.concat(added);
      }
      if (failed > 0) {
        this.toast(`${failed} 张图片处理失败，请重试`);
      }
    } catch (error) {
      const businessError = error as BusinessError;
      if (!this.attachmentService.isUserCancel(businessError)) {
        this.toast(`选择图片失败：${businessError.message ?? '未知错误'}`);
      }
    } finally {
      this.pickingImages = false;
    }
  }

  private removeAttachment(path: string): void {
    this.attachmentService.deleteFiles([path]);
    this.attachments = this.attachments.filter((item: string) => {
      return item !== path;
    });
  }

  private formatRelativeTime(timestamp: number): string {
    const now = new Date();
    const target = new Date(timestamp);
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const targetStart = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    const diffDays: number = Math.floor((todayStart - targetStart) / 86400000);
    if (diffDays <= 0) {
      const hours: number = target.getHours();
      const minutes: number = target.getMinutes();
      return `${hours < 10 ? '0' : ''}${hours}:${minutes < 10 ? '0' : ''}${minutes}`;
    }
    if (diffDays === 1) {
      return '昨天';
    }
    if (diffDays < 7) {
      return `${diffDays} 天前`;
    }
    return `${target.getMonth() + 1}月${target.getDate()}日`;
  }

  private openSettings(): void {
    this.draftBaseUrl = this.settings.baseUrl;
    this.draftApiKey = this.settings.apiKey;
    this.draftModel = this.settings.model;
    this.draftSystemPrompt = this.settings.systemPrompt;
    this.draftTemperature = this.settings.temperature;
    this.draftAutoRead = this.settings.autoRead;
    this.draftSpeechRate = this.settings.speechRate;
    this.draftSpeechVolume = this.settings.speechVolume;
    this.draftSpeechPitch = this.settings.speechPitch;
    this.draftSpeechVoice = this.settings.speechVoice;
    this.draftSpeechEngine = this.settings.speechEngine;
    this.draftDeepseekVoice = this.settings.deepseekVoice;
    this.draftDshHost = this.settings.dshHost;
    this.draftDshPort = `${this.settings.dshPort}`;
    this.draftDshToken = this.settings.dshToken;
    this.draftThemeMode = this.settings.themeMode;
    this.draftFontScale = this.settings.fontScale;
    this.showSettings = true;
  }

  private buildSettingsFromDraft(): AppSettings {
    const next = new AppSettings();
    next.baseUrl = this.draftBaseUrl.trim();
    next.apiKey = this.draftApiKey.trim();
    next.model = this.draftModel.trim();
    next.systemPrompt = this.draftSystemPrompt;
    next.temperature = this.draftTemperature;
    next.autoRead = this.draftAutoRead;
    next.speechRate = this.draftSpeechRate;
    next.speechVolume = this.draftSpeechVolume;
    next.speechPitch = this.draftSpeechPitch;
    next.speechVoice = this.draftSpeechVoice;
    next.speechEngine = this.draftSpeechEngine;
    next.deepseekVoice = this.draftDeepseekVoice;
    next.dshHost = this.draftDshHost.trim();
    next.dshToken = this.draftDshToken.trim();
    next.themeMode = this.draftThemeMode;
    next.fontScale = this.draftFontScale;
    const port: number = parseInt(this.draftDshPort, 10);
    next.dshPort = Number.isNaN(port) || port <= 0 || port > 65535 ? 17860 : port;
    return next;
  }

  private saveSettings(): void {
    const baseUrl: string = this.draftBaseUrl.trim();
    const model: string = this.draftModel.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.toast('Base URL 必须以 http:// 或 https:// 开头');
      return;
    }
    if (model.length === 0) {
      this.toast('请填写模型名称');
      return;
    }
    const next = this.buildSettingsFromDraft();
    this.settings = next;
    this.store.saveSettings(next).catch((error: BusinessError) => {
      console.error(`保存设置失败: ${error.message}`);
    });
    this.stopVoicePreview();
    this.showSettings = false;
    this.applySystemBarTheme();
    if (next.apiKey.length === 0) {
      this.toast('已保存，填写 API Key 后即可开始对话');
    } else {
      this.toast('设置已保存');
    }
  }

  private async testConnection(): Promise<void> {
    if (this.testingConnection) {
      return;
    }
    const baseUrl: string = this.draftBaseUrl.trim();
    const model: string = this.draftModel.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.toast('Base URL 必须以 http:// 或 https:// 开头');
      return;
    }
    if (model.length === 0) {
      this.toast('请填写模型名称');
      return;
    }
    if (this.draftApiKey.trim().length === 0) {
      this.toast('请先填写 DeepSeek API Key');
      return;
    }
    this.testingConnection = true;
    try {
      const reply: string = await this.aiService.testConnection(this.buildSettingsFromDraft());
      const preview: string = reply.replace(/\s+/g, ' ').trim().slice(0, 30);
      this.toast(`连接成功：${preview}`);
    } catch (error) {
      const err = error as Error;
      const message: string = err && err.message ? err.message : '未知错误';
      this.toast(`连接失败：${message.slice(0, 100)}`);
    } finally {
      this.testingConnection = false;
    }
  }

  private isDraftVisionConfigured(): boolean {
    const probe = new AppSettings();
    probe.baseUrl = this.draftBaseUrl;
    probe.model = this.draftModel;
    return probe.isVisionConfigured();
  }

  private async importDeepSeekHistory(): Promise<void> {
    if (this.importingHistory) {
      return;
    }
    if (this.loading || this.pickingImages || this.syncingDsh) {
      this.toast('请等待当前操作完成');
      return;
    }
    this.importingHistory = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri: string = await this.importService.pickImportFile(context);
      if (uri.length === 0) {
        return;
      }
      const imported: Conversation[] = await this.importService.importFromUri(context, uri);
      if (imported.length === 0) {
        this.toast('没有解析出可导入的对话');
        return;
      }

      const byId: Map<string, Conversation> = new Map<string, Conversation>();
      // 去掉没有消息的空会话；保留真实历史。
      this.conversations.forEach((conversation: Conversation) => {
        if (conversation.messages.length > 0) {
          byId.set(conversation.id, conversation);
        }
      });
      let added: number = 0;
      imported.forEach((conversation: Conversation) => {
        if (!byId.has(conversation.id)) {
          byId.set(conversation.id, conversation);
          added += 1;
        }
      });
      const next: Conversation[] = [];
      byId.forEach((conversation: Conversation) => {
        next.push(conversation);
      });
      next.sort((a: Conversation, b: Conversation) => {
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return b.updatedAt - a.updatedAt;
      });
      this.conversations = next;
      this.activeId = imported[0].id;
      this.showSidebar = false;
      this.persistConversations();
      this.scrollToBottom();
      if (added === 0) {
        this.toast('这些对话已经在本地，未重复导入');
      } else {
        this.toast(`已导入 ${added} 个 DeepSeek 对话`);
      }
    } catch (error) {
      const businessError = error as BusinessError;
      if (!this.importService.isUserCancel(businessError)) {
        this.toast(`导入失败：${businessError.message ? businessError.message : '未知错误'}`);
      }
    } finally {
      this.importingHistory = false;
    }
  }

  private async takePhoto(): Promise<void> {
    if (this.pickingImages || this.importingHistory || this.syncingDsh) {
      return;
    }
    if (this.attachments.length >= MAX_IMAGES) {
      this.toast(`最多上传 ${MAX_IMAGES} 张图片`);
      return;
    }
    this.pickingImages = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri: string = await this.attachmentService.takePhoto(context);
      if (uri.length === 0) {
        return;
      }
      const path: string = await this.attachmentService.saveCompressed(context, uri, this.attachments.length);
      this.attachments = this.attachments.concat([path]);
    } catch (error) {
      const businessError = error as BusinessError;
      const message: string = businessError.message ? businessError.message : '';
      if (!this.attachmentService.isUserCancel(businessError) &&
        !message.toLowerCase().includes('cancel') && !message.includes('取消')) {
        this.toast(`拍照失败：${message.length > 0 ? message : '未知错误'}`);
      }
    } finally {
      this.pickingImages = false;
    }
  }

  private async testDshSync(): Promise<void> {
    if (this.testingDsh) {
      return;
    }
    this.testingDsh = true;
    try {
      const info = await this.dshSyncService.test(this.buildSettingsFromDraft());
      this.persistDshSettings();
      this.toast(`DSH 已连接：${info.service} ${info.version}，共 ${info.conversationCount} 个同步对话`);
    } catch (error) {
      this.toast(`DSH 连接失败：${(error as Error).message}`);
    } finally {
      this.testingDsh = false;
    }
  }

  private async syncDsh(): Promise<void> {
    if (this.syncingDsh) {
      return;
    }
    if (this.loading || this.importingHistory) {
      this.toast('请等待当前操作完成后再同步');
      return;
    }
    if (this.pickingImages) {
      this.toast('图片处理中，请稍候');
      return;
    }
    this.syncingDsh = true;
    try {
      const result = await this.dshSyncService.sync(this.buildSettingsFromDraft(), this.conversations);
      const byId: Map<string, Conversation> = new Map<string, Conversation>();
      this.conversations.forEach((conversation: Conversation) => {
        byId.set(conversation.id, conversation);
      });
      let pulled: number = 0;
      result.conversations.forEach((conversation: Conversation) => {
        const local = byId.get(conversation.id);
        if (!local || conversation.updatedAt > local.updatedAt) {
          byId.set(conversation.id, conversation);
          pulled += 1;
        }
      });
      const next: Conversation[] = [];
      byId.forEach((conversation: Conversation) => {
        next.push(conversation);
      });
      next.sort((a: Conversation, b: Conversation) => {
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return b.updatedAt - a.updatedAt;
      });
      this.conversations = next;
      if (this.activeId.length === 0 || !byId.has(this.activeId)) {
        this.activeId = next.length > 0 ? next[0].id : '';
      }
      this.persistDshSettings();
      this.persistConversations();
      this.scrollToBottom();
      this.toast(`同步完成：上传 ${result.imported}，更新 ${result.updated}，拉取 ${pulled} 个对话`);
    } catch (error) {
      this.toast(`DSH 同步失败：${(error as Error).message}`);
    } finally {
      this.syncingDsh = false;
    }
  }

  private persistDshSettings(): void {
    const next: AppSettings = this.settings.clone();
    next.dshHost = this.draftDshHost.trim();
    next.dshToken = this.draftDshToken.trim();
    const port: number = parseInt(this.draftDshPort, 10);
    next.dshPort = Number.isNaN(port) || port <= 0 || port > 65535 ? 17860 : port;
    this.settings = next;
    this.store.saveSettings(next).catch((error: BusinessError) => {
      console.error(`保存 DSH 同步设置失败: ${error.message}`);
    });
  }

  private usePreset(baseUrl: string, model: string): void {
    this.draftBaseUrl = baseUrl;
    this.draftModel = model;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        if (this.isWide) {
          this.sidebarBuilder();
        }
        this.chatBuilder();
      }
      .width('100%')
      .height('100%')

      if (!this.isWide && this.showSidebar) {
        this.mobileSidebarOverlay();
      }
      if (this.showSettings) {
        this.settingsOverlay();
      }
      if (this.previewPath.length > 0) {
        this.previewOverlay();
      }
      if (this.conversationMenuId.length > 0) {
        this.conversationMenuOverlay();
      }
      if (this.messageMenuId.length > 0) {
        this.messageMenuOverlay();
      }
      if (this.renamingConversationId.length > 0) {
        this.renameOverlay();
      }
      if (this.selectTextMessageId.length > 0) {
        this.selectTextOverlay();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg())
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width: number = parseFloat(newValue.width.toString());
      const wide: boolean = width >= 760;
      if (wide !== this.isWide) {
        this.isWide = wide;
        if (wide) {
          this.showSidebar = false;
        }
      }
    })
  }

  @Builder
  sidebarBuilder() {
    Column() {
      Row() {
        Image($r('app.media.app_icon'))
          .width(42)
          .height(42)
          .borderRadius(12)
        Column() {
          Text('鸿语')
            .fontSize(this.fs(20))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colorTextMain())
          Text('多会话 AI 助手')
            .fontSize(this.fs(11))
            .fontColor(this.colorTextFaint())
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
        .layoutWeight(1)

        if (!this.isWide) {
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor(this.colorTextSecondary())
          }
          .width(36)
          .height(36)
          .backgroundColor(this.colorSurfaceAlt())
          .onClick(() => {
            this.showSidebar = false;
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.ic_plus'))
            .width(18)
            .height(18)
            .fillColor(Color.White)
          Text('新建对话')
            .fontSize(this.fs(15))
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
      .width('100%')
      .height(44)
      .backgroundColor(ACCENT)
      .borderRadius(12)
      .margin({ top: 18, bottom: 20 })
      .onClick(() => {
        this.newConversation();
      })

      Row() {
        Text('最近对话')
          .fontSize(this.fs(12))
          .fontColor(this.colorTextFaint())
          .layoutWeight(1)
        Text(`${this.visibleConversations().length}`)
          .fontSize(this.fs(11))
          .fontColor(this.colorTextFaint())
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 8 })

      List({ space: 3 }) {
        ForEach(this.visibleConversations(), (conversation: Conversation) => {
          ListItem() {
            Row() {
              Column() {
                Text(conversation.title)
                  .fontSize(this.fs(14))
                  .fontWeight(this.activeId === conversation.id ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.activeId === conversation.id ? ACCENT : this.colorTextMain())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(conversation.lastPreview())
                  .fontSize(this.fs(11))
                  .fontColor(this.colorTextFaint())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text(conversation.pinned ? '置顶' : this.formatRelativeTime(conversation.updatedAt))
                  .fontSize(this.fs(10))
                  .fontColor(conversation.pinned ? ACCENT : this.colorTextFaint())
                  .margin({ top: 2 })
                if (conversation.pinned) {
                  Text(this.formatRelativeTime(conversation.updatedAt))
                    .fontSize(this.fs(9))
                    .fontColor(this.colorTextFaint())
                    .margin({ top: 1 })
                }
              }
              .alignItems(HorizontalAlign.End)
              .margin({ left: 6 })
            }
            .width('100%')
            .padding({ left: 12, right: 8, top: 9, bottom: 9 })
            .borderRadius(12)
            .backgroundColor(this.activeId === conversation.id ? this.colorAccentSoft() : Color.Transparent)
            .onClick(() => {
              this.selectConversation(conversation.id);
            })
            .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction(() => {
              this.openConversationMenu(conversation);
            }))
          }
        }, (conversation: Conversation) => `${conversation.id}_${conversation.updatedAt}_${conversation.pinned}_${this.activeId === conversation.id}`)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 8, right: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Divider()
        .strokeWidth(0.5)
        .color(this.colorLine())
        .margin({ top: 10, bottom: 8 })

      Row() {
        Image($r('app.media.ic_import'))
          .width(19)
          .height(19)
          .fillColor(this.colorTextSecondary())
        Text(this.importingHistory ? '正在导入…' : '导入 DeepSeek 聊天记录')
          .fontSize(this.fs(13))
          .fontColor(this.colorTextMain())
          .margin({ left: 8 })
          .layoutWeight(1)
        if (this.importingHistory) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(ACCENT)
        }
      }
      .width('100%')
      .height(42)
      .padding({ left: 10, right: 10 })
      .borderRadius(10)
      .onClick(() => {
        this.importDeepSeekHistory();
      })

      Row() {
        Image($r('app.media.ic_settings'))
          .width(19)
          .height(19)
          .fillColor(this.colorTextSecondary())
        Text('设置')
          .fontSize(this.fs(14))
          .fontColor(this.colorTextMain())
          .margin({ left: 8 })
          .layoutWeight(1)
        Text('v1.0.0')
          .fontSize(this.fs(10))
          .fontColor(this.colorTextFaint())
      }
      .width('100%')
      .height(42)
      .padding({ left: 10, right: 10 })
      .borderRadius(10)
      .onClick(() => {
        this.showSidebar = false;
        this.openSettings();
      })
    }
    .width(this.isWide ? '296vp' : '84%')
    .height('100%')
    .backgroundColor(this.colorPanel())
    .padding({ left: 8, right: 8, top: 16, bottom: 12 })
    .border({ width: { right: 0.5 }, color: this.colorLine() })
    .onClick(() => {
    })
  }

  @Builder
  mobileSidebarOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.showSidebar = false;
        })
      this.sidebarBuilder()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  chatBuilder() {
    Column() {
      this.chatHeader()

      if (this.booting) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(ACCENT)
          Text('正在加载对话…')
            .fontSize(this.fs(13))
            .fontColor(this.colorTextSecondary())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)

      } else if (this.getActiveMessages().length === 0) {
        Column() {
          this.welcomeView()
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Stack({ alignContent: Alignment.TopEnd }) {
          List({ scroller: this.scroller, space: 22 }) {
            ForEach(this.getActiveMessages(), (message: ChatMessage) => {
              ListItem() {
                this.messageItem(message)
              }
            }, (message: ChatMessage) => `${message.id}_${message.rev}_${message.status}_${this.speakingMessageId === message.id}_${this.isLastMessage(message)}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 50, top: 18, bottom: 12 })
          .scrollBar(BarState.On)
          .scrollBarWidth(5)
          .scrollBarColor(this.colorTextFaint())
          .edgeEffect(EdgeEffect.Spring)

          Column({ space: 8 }) {
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_chevron_up'))
                .width(19)
                .height(19)
                .fillColor(this.colorTextSecondary())
            }
            .width(34)
            .height(34)
            .backgroundColor(this.colorPanel())
            .border({ width: 0.5, color: this.colorLine() })
            .opacity(this.canGoAdjacent(-1) ? 1 : 0.35)
            .enabled(this.canGoAdjacent(-1))
            .onClick(() => {
              this.goAdjacentConversation(-1);
            })

            Blank()

            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_chevron_down'))
                .width(19)
                .height(19)
                .fillColor(this.colorTextSecondary())
            }
            .width(34)
            .height(34)
            .backgroundColor(this.colorPanel())
            .border({ width: 0.5, color: this.colorLine() })
            .opacity(this.canGoAdjacent(1) ? 1 : 0.35)
            .enabled(this.canGoAdjacent(1))
            .onClick(() => {
              this.goAdjacentConversation(1);
            })
          }
          .height('100%')
          .padding({ top: 10, right: 6, bottom: 10 })
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .layoutWeight(1)
        .width('100%')
      }

      if (this.speakingMessageId.length > 0) {
        Row({ space: 6 }) {
          Image($r('app.media.ic_stop'))
            .width(15)
            .height(15)
            .fillColor(ACCENT)
          Text('正在朗读，点击停止')
            .fontSize(this.fs(11))
            .fontColor(ACCENT)
            .layoutWeight(1)
          Image($r('app.media.ic_close'))
            .width(14)
            .height(14)
            .fillColor(ACCENT)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.colorAccentSoft())
        .onClick(() => {
          this.stopReading();
        })
      }

      this.composerBuilder()
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(this.colorBg())
  }

  @Builder
  chatHeader() {
    Row() {
      if (!this.isWide) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_menu'))
            .width(22)
            .height(22)
            .fillColor(this.colorTextMain())
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showSidebar = true;
        })
      }

      Column() {
        Text(this.headerTitle())
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colorTextMain())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 5 }) {
          Row()
            .width(5)
            .height(5)
            .borderRadius(2.5)
            .backgroundColor(this.settings.apiKey.length > 0 ? '#22C55E' : '#F59E0B')
          Text(this.settings.model)
            .fontSize(this.fs(10))
            .fontColor(this.colorTextSecondary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.isWide ? 8 : 6, right: 6 })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_volume'))
          .width(20)
          .height(20)
          .fillColor(this.settings.autoRead ? ACCENT : this.colorTextSecondary())
      }
      .width(40)
      .height(40)
      .backgroundColor(this.settings.autoRead ? this.colorAccentSoft() : Color.Transparent)
      .onClick(() => {
        this.toggleAutoRead();
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_new_chat'))
          .width(20)
          .height(20)
          .fillColor(this.colorTextSecondary())
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .margin({ left: 2 })
      .onClick(() => {
        this.newConversation();
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_settings'))
          .width(20)
          .height(20)
          .fillColor(this.colorTextSecondary())
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .margin({ left: 2 })
      .onClick(() => {
        this.openSettings();
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.colorBg())
    .border({ width: { bottom: 0.5 }, color: this.colorLine() })
  }

  @Builder
  welcomeView() {
    Column() {
      Image($r('app.media.app_icon'))
        .width(80)
        .height(80)
        .borderRadius(24)
      Text('你好，我是鸿语')
        .fontSize(this.fs(25))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colorTextMain())
        .margin({ top: 16 })
      Text('多轮对话 · 多图理解 · 语音朗读')
        .fontSize(this.fs(13))
        .fontColor(this.colorTextSecondary())
        .margin({ top: 7 })

      if (this.settings.apiKey.trim().length === 0) {
        Row() {
          Column() {
            Text('先配置 API Key')
              .fontSize(this.fs(14))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.colorWarning())
            Text('支持 DeepSeek 官方 API 及任意 OpenAI 兼容接口')
              .fontSize(this.fs(11))
              .fontColor(this.colorWarning())
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('去设置')
            .fontSize(this.fs(13))
            .height(34)
            .backgroundColor(this.colorWarningSoft())
            .fontColor(this.colorWarning())
            .borderRadius(9)
            .onClick(() => {
              this.openSettings();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 10, top: 11, bottom: 11 })
        .backgroundColor(this.colorWarningSoft())
        .borderRadius(14)
        .margin({ top: 24 })
      }

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(SUGGESTIONS, (prompt: string, index: number) => {
          Column() {
            Text(prompt)
              .fontSize(this.fs(13))
              .fontColor(this.colorTextMain())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .width('48.5%')
          .height(62)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.colorPanel())
          .borderRadius(14)
          .border({ width: 0.5, color: this.colorLine() })
          .margin({ top: 12 })
          .onClick(() => {
            this.inputText = prompt;
          })
        }, (prompt: string) => prompt)
      }
      .width('100%')
      .margin({ top: 12 })

      Text(this.settings.isVisionConfigured() ?
        `当前模型 ${this.settings.model} 支持图片与文字对话` :
        `当前模型 ${this.settings.model} 不支持图片，请切换 deepseek-flash`)
        .fontSize(this.fs(10))
        .fontColor(this.colorTextFaint())
        .textAlign(TextAlign.Center)
        .margin({ top: 16 })
        .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  messageItem(message: ChatMessage) {
    if (message.role === 'user') {
      Row() {
        Blank()
        Column() {
          if (message.imagePaths.length > 0) {
            this.messageImages(message.imagePaths)
          }
          if (message.content.length > 0) {
            Text(message.content)
              .fontSize(this.fs(16))
              .lineHeight(this.fs(25))
              .fontColor(Color.White)
              .copyOption(CopyOptions.LocalDevice)
              .margin({ top: message.imagePaths.length > 0 ? 6 : 0 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: '84%' })
        .padding({ left: 13, right: 13, top: 10, bottom: 10 })
        .backgroundColor(ACCENT)
        .borderRadius(18)
      }
      .width('100%')

    } else {
      Row() {
        Image($r('app.media.app_icon'))
          .width(34)
          .height(34)
          .borderRadius(11)

        Column() {
          if (message.status === 'loading') {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(ACCENT)
              Text('正在思考…')
                .fontSize(this.fs(14))
                .fontColor(this.colorTextSecondary())
            }
            .height(32)
          } else if (message.status === 'error') {
            Column() {
              Text(message.content)
                .fontSize(this.fs(14))
                .lineHeight(this.fs(22))
                .fontColor(this.colorDanger())
                .width('100%')
              if (this.isLastMessage(message)) {
                Button('重试')
                  .fontSize(this.fs(12))
                  .height(30)
                  .backgroundColor(this.colorDangerSoft())
                  .fontColor(this.colorDanger())
                  .borderRadius(8)
                  .margin({ top: 8 })
                  .onClick(() => {
                    this.retryMessage(message);
                  })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(12)
            .backgroundColor(this.colorDangerSoft())
            .borderRadius(12)
          } else {
            Text(message.content)
              .fontSize(this.fs(16))
              .lineHeight(this.fs(26))
              .fontColor(this.colorTextMain())
              .width('100%')

            Row({ space: 2 }) {
              Text('AI 生成')
                .fontSize(this.fs(9))
                .fontColor(this.colorTextFaint())
                .margin({ right: 4 })
              Button({ type: ButtonType.Normal }) {
                Row({ space: 4 }) {
                  if (this.speakingMessageId === message.id) {
                    Image($r('app.media.ic_stop'))
                      .width(15)
                      .height(15)
                      .fillColor(ACCENT)
                  } else {
                    Image($r('app.media.ic_volume'))
                      .width(16)
                      .height(16)
                      .fillColor(this.colorTextSecondary())
                  }
                  Text(this.speakingMessageId === message.id ? '停止' : '朗读')
                    .fontSize(this.fs(11))
                    .fontColor(this.speakingMessageId === message.id ? ACCENT : this.colorTextSecondary())
                }
                .padding({ left: 6, right: 6 })
              }
              .height(28)
              .backgroundColor(Color.Transparent)
              .borderRadius(7)
              .onClick(() => {
                this.toggleRead(message);
              })

              Button({ type: ButtonType.Normal }) {
                Row({ space: 4 }) {
                  Image($r('app.media.ic_copy'))
                    .width(15)
                    .height(15)
                    .fillColor(this.colorTextSecondary())
                  Text('复制')
                    .fontSize(this.fs(11))
                    .fontColor(this.colorTextSecondary())
                }
                .padding({ left: 6, right: 6 })
              }
              .height(28)
              .backgroundColor(Color.Transparent)
              .borderRadius(7)
              .onClick(() => {
                this.copyMessage(message.content);
              })
            }
            .margin({ top: 7 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
        .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction(() => {
          this.openMessageMenu(message);
        }))
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  messageImages(paths: string[]) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(paths, (path: string) => {
        Image(this.attachmentService.getDisplayUri(path))
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius(9)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.previewPath = path;
          })
      }, (path: string) => path)
    }
    .width(paths.length === 1 ? 70 : (paths.length === 2 ? 140 : 210))
    .constraintSize({ maxWidth: '100%' })
  }

  @Builder
  composerBuilder() {
    Column() {
      if (this.attachments.length > 0) {
        Row() {
          Text('已选图片')
            .fontSize(this.fs(11))
            .fontColor(this.colorTextSecondary())
            .layoutWeight(1)
          Text(`${this.attachments.length}/${MAX_IMAGES}`)
            .fontSize(this.fs(11))
            .fontColor(this.colorTextFaint())
        }
        .width('100%')
        .margin({ bottom: 6 })

        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.attachments, (path: string) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(this.attachmentService.getDisplayUri(path))
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(10)
                  .onClick(() => {
                    this.previewPath = path;
                  })
                Button({ type: ButtonType.Circle }) {
                  Image($r('app.media.ic_close'))
                    .width(10)
                    .height(10)
                    .fillColor(Color.White)
                }
                .width(20)
                .height(20)
                .backgroundColor('#99000000')
                .margin({ top: 3, right: 3 })
                .onClick(() => {
                  this.removeAttachment(path);
                })
              }
            }, (path: string) => path)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: 8 })
      }

      if (this.pickingImages) {
        Row({ space: 6 }) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(ACCENT)
          Text('正在压缩并保存图片…')
            .fontSize(this.fs(11))
            .fontColor(this.colorTextSecondary())
        }
        .width('100%')
        .margin({ bottom: 6 })
      }

      if (this.attachments.length > 0 && !this.settings.isVisionConfigured()) {
        Text('当前模型不支持图片，请切换到 DeepSeek Flash 或其他视觉模型后再发送。')
          .fontSize(this.fs(11))
          .fontColor(this.colorWarning())
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.colorWarningSoft())
          .borderRadius(8)
          .margin({ bottom: 6 })
      }

      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_camera'))
            .width(22)
            .height(22)
            .fillColor(this.colorTextSecondary())
        }
        .width(42)
        .height(42)
        .backgroundColor(this.colorSurfaceAlt())
        .margin({ right: 6 })
        .enabled(!this.pickingImages && !this.importingHistory && this.attachments.length < MAX_IMAGES)
        .onClick(() => {
          this.takePhoto();
        })

        Button({ type: ButtonType.Circle }) {
          if (this.pickingImages) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.colorTextSecondary())
          } else {
            Image($r('app.media.ic_image'))
              .width(22)
              .height(22)
              .fillColor(this.colorTextSecondary())
          }
        }
        .width(42)
        .height(42)
        .backgroundColor(this.colorSurfaceAlt())
        .margin({ right: 4 })
        .opacity(this.attachments.length >= MAX_IMAGES ? 0.45 : 1)
        .enabled(!this.pickingImages && !this.importingHistory && this.attachments.length < MAX_IMAGES)
        .onClick(() => {
          this.pickImages();
        })

        TextArea({
          text: this.inputText,
          placeholder: '给鸿语发送消息…'
        })
          .layoutWeight(1)
          .constraintSize({ minHeight: 42, maxHeight: 118 })
          .fontSize(this.fs(16))
          .fontColor(this.colorTextMain())
          .placeholderColor(this.colorTextFaint())
          .backgroundColor(Color.Transparent)
          .padding({ left: 9, right: 9, top: 8, bottom: 8 })
          .maxLength(8000)
          .maxLines(5)
          .onChange((value: string) => {
            this.inputText = value;
          })

        Button({ type: ButtonType.Circle }) {
          if (this.loading) {
            LoadingProgress()
              .width(21)
              .height(21)
              .color(Color.White)
          } else {
            Image($r('app.media.ic_send'))
              .width(21)
              .height(21)
              .fillColor(Color.White)
          }
        }
        .width(42)
        .height(42)
        .backgroundColor((!this.loading && !this.importingHistory && !this.syncingDsh &&
          (this.inputText.trim().length > 0 || this.attachments.length > 0)) ? ACCENT : this.colorDisabled())
        .enabled(!this.loading && !this.importingHistory && !this.syncingDsh &&
          (this.inputText.trim().length > 0 || this.attachments.length > 0))
        .onClick(() => {
          this.sendMessage();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Text('内容由 AI 生成，请仔细甄别')
        .fontSize(this.fs(10))
        .fontColor(this.colorTextFaint())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 6 })
    .backgroundColor(this.colorPanel())
    .border({ width: { top: 0.5 }, color: this.colorLine() })
  }

  @Builder
  settingsOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.stopVoicePreview();
          this.showSettings = false;
          this.applySystemBarTheme();
        })

      Column() {
        Row() {
          Column() {
            Text('设置')
              .fontSize(this.fs(20))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorTextMain())
            Text('模型服务、语音与 DSH 同步')
              .fontSize(this.fs(11))
              .fontColor(this.colorTextFaint())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_close'))
              .width(15)
              .height(15)
              .fillColor(this.colorTextSecondary())
          }
          .width(32)
          .height(32)
          .backgroundColor(this.colorSurfaceAlt())
          .onClick(() => {
            this.stopVoicePreview();
            this.showSettings = false;
            this.applySystemBarTheme();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 14 })

        Divider()
          .strokeWidth(0.5)
          .color(this.colorLine())

        Scroll() {
          Column() {
            this.settingsSection('模型服务')

            this.settingsLabel('快速配置')
            Row({ space: 8 }) {
              Button('DeepSeek Flash')
                .layoutWeight(1)
                .fontSize(this.fs(12))
                .height(32)
                .backgroundColor(this.draftModel === 'deepseek-flash' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftModel === 'deepseek-flash' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.usePreset('https://api.deepseek.com', 'deepseek-flash');
                })
              Button('DeepSeek V4 Pro')
                .layoutWeight(1)
                .fontSize(this.fs(12))
                .height(32)
                .backgroundColor(this.draftModel === 'deepseek-v4-pro' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftModel === 'deepseek-v4-pro' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.usePreset('https://api.deepseek.com', 'deepseek-v4-pro');
                })
            }
            .width('100%')
            .margin({ top: 8 })
            Text('Flash 支持文字与多图理解；V4 Pro 适合纯文本深度推理。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 6 })

            this.settingsLabel('Base URL')
            TextInput({
              text: this.draftBaseUrl,
              placeholder: 'https://api.deepseek.com'
            })
              .width('100%')
              .height(44)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftBaseUrl = value;
              })
            Text('DeepSeek 官方填 https://api.deepseek.com，App 会自动拼接 /chat/completions。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 5 })

            this.settingsLabel('API Key')
            TextInput({
              text: this.draftApiKey,
              placeholder: 'sk-...'
            })
              .width('100%')
              .type(InputType.Password)
              .showPasswordIcon(true)
              .height(44)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftApiKey = value;
              })
            Text('在 platform.deepseek.com/api_keys 获取；API Key 只保存在本机 Preferences 中。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 5 })

            this.settingsLabel('模型')
            TextInput({
              text: this.draftModel,
              placeholder: 'deepseek-flash'
            })
              .width('100%')
              .height(44)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftModel = value;
              })
            Text(this.isDraftVisionConfigured() ?
              '当前模型支持图片输入，图片会按 OpenAI Vision 格式发送。' :
              '当前模型不支持图片输入；需要图文对话时请选择 DeepSeek Flash。')
              .fontSize(this.fs(10))
              .fontColor(this.isDraftVisionConfigured() ? this.colorTextFaint() : this.colorWarning())
              .width('100%')
              .margin({ top: 5 })

            Button() {
              Row({ space: 7 }) {
                if (this.testingConnection) {
                  LoadingProgress()
                    .width(15)
                    .height(15)
                    .color(ACCENT)
                }
                Text(this.testingConnection ? '正在连接 DeepSeek…' : '测试 DeepSeek API 连接')
                  .fontSize(this.fs(12))
                  .fontColor(ACCENT)
                  .fontWeight(FontWeight.Medium)
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
            }
            .width('100%')
            .height(38)
            .backgroundColor(this.colorAccentSoft())
            .borderRadius(9)
            .margin({ top: 12 })
            .enabled(!this.testingConnection)
            .onClick(() => {
              this.testConnection();
            })
            Text('测试会使用上方 Base URL、API Key 和模型发送一条极短消息，不会保存设置。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 5 })

            Row() {
              Text('温度')
                .fontSize(this.fs(13))
                .fontColor(this.colorTextMain())
                .layoutWeight(1)
              Text(this.draftTemperature.toFixed(1))
                .fontSize(this.fs(12))
                .fontColor(this.colorTextSecondary())
            }
            .width('100%')
            .margin({ top: 18 })
            Slider({
              value: this.draftTemperature,
              min: 0,
              max: 2,
              step: 0.1
            })
              .selectedColor(ACCENT)
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode) => {
                this.draftTemperature = value;
              })

            this.settingsLabel('系统提示词')
            TextArea({
              text: this.draftSystemPrompt,
              placeholder: '给模型的长期指令'
            })
              .width('100%')
              .height(96)
              .fontSize(this.fs(13))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding(10)
              .maxLength(2000)
              .onChange((value: string) => {
                this.draftSystemPrompt = value;
              })

            Divider()
              .strokeWidth(0.5)
              .color(this.colorLine())
              .margin({ top: 20, bottom: 16 })

            this.settingsSection('语音朗读')

            Row() {
              Column() {
                Text('自动朗读回复')
                  .fontSize(this.fs(14))
                  .fontColor(this.colorTextMain())
                Text('回复完成后自动用当前朗读引擎播报')
                  .fontSize(this.fs(10))
                  .fontColor(this.colorTextFaint())
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.draftAutoRead })
                .selectedColor(ACCENT)
                .onChange((isOn: boolean) => {
                  this.draftAutoRead = isOn;
                })
            }
            .width('100%')
            .margin({ top: 4 })

            this.settingsLabel('朗读引擎')
            Row({ space: 8 }) {
              Button('系统离线')
                .layoutWeight(1)
                .height(34)
                .fontSize(this.fs(12))
                .backgroundColor(this.draftSpeechEngine === 'system' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftSpeechEngine === 'system' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.stopVoicePreview();
                  this.draftSpeechEngine = 'system';
                })
              Button('DeepSeek 在线')
                .layoutWeight(1)
                .height(34)
                .fontSize(this.fs(12))
                .backgroundColor(this.draftSpeechEngine === 'deepseek' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftSpeechEngine === 'deepseek' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.stopVoicePreview();
                  this.draftSpeechEngine = 'deepseek';
                })
            }
            .width('100%')

            Text(this.draftSpeechEngine === 'deepseek'
              ? 'DeepSeek 服务端合成，音质明显好于本地系统 TTS；需要 API Key 和网络。'
              : 'HarmonyOS Core Speech Kit 离线合成，不耗流量，但音色偏机械。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 5 })

            if (this.draftSpeechEngine === 'system') {
              this.settingsLabel('系统音色')
              Row({ space: 8 }) {
                Button('聆小珊')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(this.fs(12))
                  .backgroundColor(this.draftSpeechVoice === 'xiaoshan' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                  .fontColor(this.draftSpeechVoice === 'xiaoshan' ? ACCENT : this.colorTextSecondary())
                  .borderRadius(9)
                  .onClick(() => {
                    this.previewVoice('xiaoshan');
                  })
                Button('凌飞哲')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(this.fs(12))
                  .backgroundColor(this.draftSpeechVoice === 'lingfeizhe' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                  .fontColor(this.draftSpeechVoice === 'lingfeizhe' ? ACCENT : this.colorTextSecondary())
                  .borderRadius(9)
                  .onClick(() => {
                    this.previewVoice('lingfeizhe');
                  })
                Button('贝壳风格')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(this.fs(12))
                  .backgroundColor(this.draftSpeechVoice === 'shell' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                  .fontColor(this.draftSpeechVoice === 'shell' ? ACCENT : this.colorTextSecondary())
                  .borderRadius(9)
                  .onClick(() => {
                    this.previewVoice('shell');
                  })
              }
              .width('100%')

              Text('系统 TTS 仅提供聆小珊女声和凌飞哲男声；“贝壳风格”只是调音近似。')
                .fontSize(this.fs(10))
                .fontColor(this.colorTextFaint())
                .width('100%')
                .margin({ top: 6 })

              Row() {
                Text('语速')
                  .fontSize(this.fs(13))
                  .fontColor(this.colorTextMain())
                  .layoutWeight(1)
                Text(`${this.draftSpeechRate.toFixed(1)}x`)
                  .fontSize(this.fs(12))
                  .fontColor(this.colorTextSecondary())
              }
              .width('100%')
              .margin({ top: 16 })
              Slider({
                value: this.draftSpeechRate,
                min: 0.5,
                max: 2,
                step: 0.1
              })
                .selectedColor(ACCENT)
                .width('100%')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.draftSpeechRate = value;
                })

              Row() {
                Text('音量')
                  .fontSize(this.fs(13))
                  .fontColor(this.colorTextMain())
                  .layoutWeight(1)
                Text(this.draftSpeechVolume.toFixed(1))
                  .fontSize(this.fs(12))
                  .fontColor(this.colorTextSecondary())
              }
              .width('100%')
              .margin({ top: 10 })
              Slider({
                value: this.draftSpeechVolume,
                min: 0,
                max: 2,
                step: 0.1
              })
                .selectedColor(ACCENT)
                .width('100%')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.draftSpeechVolume = value;
                })

              Row() {
                Text('音调')
                  .fontSize(this.fs(13))
                  .fontColor(this.colorTextMain())
                  .layoutWeight(1)
                Text(this.draftSpeechPitch.toFixed(1))
                  .fontSize(this.fs(12))
                  .fontColor(this.colorTextSecondary())
              }
              .width('100%')
              .margin({ top: 10 })
              Slider({
                value: this.draftSpeechPitch,
                min: 0.5,
                max: 2,
                step: 0.1
              })
                .selectedColor(ACCENT)
                .width('100%')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.draftSpeechPitch = value;
                })

              Text('语音基于 HarmonyOS Core Speech Kit 离线合成，模拟器可能不支持，请用真机测试。')
                .fontSize(this.fs(10))
                .fontColor(this.colorTextFaint())
                .width('100%')
                .margin({ top: 8 })
            } else {
              this.settingsLabel('DeepSeek 音色')
              Row({ space: 8 }) {
                Button('海星')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(this.fs(12))
                  .backgroundColor(this.draftDeepseekVoice === 'stella' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                  .fontColor(this.draftDeepseekVoice === 'stella' ? ACCENT : this.colorTextSecondary())
                  .borderRadius(9)
                  .onClick(() => {
                    this.previewDeepSeekVoice('stella');
                  })
                Button('暗潮')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(this.fs(12))
                  .backgroundColor(this.draftDeepseekVoice === 'tide' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                  .fontColor(this.draftDeepseekVoice === 'tide' ? ACCENT : this.colorTextSecondary())
                  .borderRadius(9)
                  .onClick(() => {
                    this.previewDeepSeekVoice('tide');
                  })
              }
              .width('100%')

              Text('DeepSeek 公开 TTS API 只支持海星（stella）和暗潮（tide），二者都由服务端合成、音质接近真人。DeepSeek App 的“贝壳（mira）/白浪（echo）”是私有音色，接口实测返回 Invalid voice_id，第三方无法调用。')
                .fontSize(this.fs(10))
                .fontColor(this.colorTextFaint())
                .width('100%')
                .margin({ top: 6 })
            }

            Row() {
              Text(this.previewingVoice ? `正在试听：${this.previewingVoiceName}` : '点击任一音色，会试听一段模拟对话')
                .fontSize(this.fs(10))
                .fontColor(this.previewingVoice ? ACCENT : this.colorTextFaint())
                .layoutWeight(1)
              if (this.previewingVoice) {
                Button('停止')
                  .height(26)
                  .fontSize(this.fs(10))
                  .fontColor(ACCENT)
                  .backgroundColor(this.colorAccentSoft())
                  .borderRadius(7)
                  .onClick(() => {
                    this.stopVoicePreview();
                  })
              }
            }
            .width('100%')
            .margin({ top: 6 })


            Divider()
              .strokeWidth(0.5)
              .color(this.colorLine())
              .margin({ top: 20, bottom: 16 })

            this.settingsSection('外观与阅读')
            this.settingsLabel('外观')
            Row({ space: 8 }) {
              Button('跟随系统')
                .layoutWeight(1)
                .fontSize(this.fs(12))
                .height(34)
                .backgroundColor(this.draftThemeMode === 'system' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftThemeMode === 'system' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.applyThemeMode('system');
                })
              Button('浅色')
                .layoutWeight(1)
                .fontSize(this.fs(12))
                .height(34)
                .backgroundColor(this.draftThemeMode === 'light' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftThemeMode === 'light' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.applyThemeMode('light');
                })
              Button('深色')
                .layoutWeight(1)
                .fontSize(this.fs(12))
                .height(34)
                .backgroundColor(this.draftThemeMode === 'dark' ? this.colorAccentSoft() : this.colorSurfaceAlt())
                .fontColor(this.draftThemeMode === 'dark' ? ACCENT : this.colorTextSecondary())
                .borderRadius(9)
                .onClick(() => {
                  this.applyThemeMode('dark');
                })
            }
            .width('100%')
            .margin({ top: 6 })

            Row() {
              Text('字体大小')
                .fontSize(this.fs(13))
                .fontColor(this.colorTextMain())
                .layoutWeight(1)
              Text(`${Math.round(this.draftFontScale * 100)}%`)
                .fontSize(this.fs(12))
                .fontColor(this.colorTextSecondary())
            }
            .width('100%')
            .margin({ top: 16 })
            Slider({
              value: this.draftFontScale,
              min: 0.85,
              max: 1.3,
              step: 0.05
            })
              .selectedColor(ACCENT)
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode) => {
                this.draftFontScale = value;
              })
            Text('预览：你好，我是鸿语。多轮对话、图片理解与语音朗读。')
              .fontSize(Math.round(16 * this.draftFontScale))
              .lineHeight(Math.round(24 * this.draftFontScale))
              .fontColor(this.colorTextMain())
              .width('100%')
              .padding(10)
              .backgroundColor(this.colorInputBg())
              .borderRadius(9)
              .margin({ top: 8 })
            Text('主题点击后立即切换并保存；字体大小在保存设置后生效。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 5 })

            Divider()
              .strokeWidth(0.5)
              .color(this.colorLine())
              .margin({ top: 20, bottom: 16 })

            this.settingsSection('DSH 同步')
            Text('与电脑上的 DeepSeek Harness 插件（HongYu Sync Bridge）通过局域网同步文字对话。')
              .fontSize(this.fs(11))
              .fontColor(this.colorTextSecondary())
              .width('100%')
              .margin({ top: 4, bottom: 2 })

            this.settingsLabel('电脑 IP / 主机名')
            TextInput({
              text: this.draftDshHost,
              placeholder: '192.168.1.100'
            })
              .width('100%')
              .height(42)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftDshHost = value;
              })

            this.settingsLabel('端口')
            TextInput({
              text: this.draftDshPort,
              placeholder: '17860'
            })
              .width('100%')
              .height(42)
              .type(InputType.Number)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftDshPort = value;
              })

            this.settingsLabel('配对码')
            TextInput({
              text: this.draftDshToken,
              placeholder: '在 DSH 中调用 hongyu_sync 的 status 获取'
            })
              .width('100%')
              .height(42)
              .type(InputType.Password)
              .showPasswordIcon(true)
              .fontSize(this.fs(14))
              .fontColor(this.colorTextMain())
              .backgroundColor(this.colorInputBg())
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.draftDshToken = value;
              })

            Row({ space: 8 }) {
              Button() {
                Row({ space: 6 }) {
                  if (this.testingDsh) {
                    LoadingProgress()
                      .width(14)
                      .height(14)
                      .color(ACCENT)
                  }
                  Text(this.testingDsh ? '连接中…' : '测试连接')
                    .fontSize(this.fs(12))
                    .fontColor(ACCENT)
                }
                .justifyContent(FlexAlign.Center)
                .width('100%')
              }
              .layoutWeight(1)
              .height(38)
              .backgroundColor(this.colorAccentSoft())
              .borderRadius(9)
              .enabled(!this.testingDsh && !this.syncingDsh)
              .onClick(() => {
                this.testDshSync();
              })

              Button() {
                Row({ space: 6 }) {
                  if (this.syncingDsh) {
                    LoadingProgress()
                      .width(14)
                      .height(14)
                      .color(Color.White)
                  }
                  Text(this.syncingDsh ? '同步中…' : '立即同步')
                    .fontSize(this.fs(12))
                    .fontColor(Color.White)
                }
                .justifyContent(FlexAlign.Center)
                .width('100%')
              }
              .layoutWeight(1)
              .height(38)
              .backgroundColor(ACCENT)
              .borderRadius(9)
              .enabled(!this.testingDsh && !this.syncingDsh)
              .onClick(() => {
                this.syncDsh();
              })
            }
            .width('100%')
            .margin({ top: 12 })

            Text('需要电脑与手机在同一 Wi-Fi，且防火墙允许该端口。同步只包含文字，图片不会上传；DSH 侧可把当前对话导出后由手机拉取。')
              .fontSize(this.fs(10))
              .fontColor(this.colorTextFaint())
              .width('100%')
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        Divider()
          .strokeWidth(0.5)
          .color(this.colorLine())

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(46)
            .backgroundColor(this.colorSurfaceAlt())
            .fontColor(this.colorTextMain())
            .borderRadius(12)
            .onClick(() => {
              this.stopVoicePreview();
              this.showSettings = false;
              this.applySystemBarTheme();
            })
          Button('保存设置')
            .layoutWeight(1)
            .height(46)
            .backgroundColor(ACCENT)
            .fontColor(Color.White)
            .borderRadius(12)
            .onClick(() => {
              this.saveSettings();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .height('92%')
      .backgroundColor(this.colorPanel())
      .borderRadius({ topLeft: 24, topRight: 24 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  settingsSection(title: string) {
    Text(title)
      .fontSize(this.fs(12))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.colorTextSecondary())
      .width('100%')
      .margin({ top: 4, bottom: 2 })
  }

  @Builder
  settingsLabel(title: string) {
    Text(title)
      .fontSize(this.fs(12))
      .fontColor(this.colorTextSecondary())
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }

  @Builder
  previewOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#EE000000')
        .onClick(() => {
          this.previewPath = '';
        })

      Image(this.attachmentService.getDisplayUri(this.previewPath))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .padding({ left: 10, right: 10, top: 50, bottom: 30 })

      Row() {
        Blank()
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(Color.White)
        }
        .width(42)
        .height(42)
        .backgroundColor('#33FFFFFF')
        .onClick(() => {
          this.previewPath = '';
        })
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 48, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  conversationMenuOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .onClick(() => {
          this.conversationMenuId = '';
        })

      Column({ space: 8 }) {
        Row() {
          Text('对话操作')
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colorTextMain())
            .layoutWeight(1)
          Text(this.menuConversationTitle())
            .fontSize(this.fs(12))
            .fontColor(this.colorTextFaint())
            .maxLines(1)
            .constraintSize({ maxWidth: '55%' })
        }
        .width('100%')
        .margin({ bottom: 8 })

        Button('重命名')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorSurfaceAlt())
          .borderRadius(10)
          .onClick(() => {
            this.renameMenuConversation();
          })
        Button(this.menuConversationPinned() ? '取消置顶' : '置顶')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorSurfaceAlt())
          .borderRadius(10)
          .onClick(() => {
            this.pinMenuConversation();
          })
        Button('删除')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorDanger())
          .backgroundColor(this.colorDangerSoft())
          .borderRadius(10)
          .onClick(() => {
            this.deleteMenuConversation();
          })
        Button('取消')
          .width('100%')
          .height(42)
          .fontSize(this.fs(14))
          .fontColor(this.colorTextSecondary())
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.conversationMenuId = '';
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 18 })
      .backgroundColor(this.colorPanel())
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  messageMenuOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .onClick(() => {
          this.messageMenuId = '';
        })

      Column({ space: 8 }) {
        Text('回答操作')
          .fontSize(this.fs(18))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colorTextMain())
          .width('100%')
          .margin({ bottom: 8 })

        Button('复制')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorSurfaceAlt())
          .borderRadius(10)
          .onClick(() => {
            this.copyMenuMessage();
          })
        Button('选择文本')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorSurfaceAlt())
          .borderRadius(10)
          .onClick(() => {
            this.selectMenuMessageText();
          })
        Button('重新生成')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorSurfaceAlt())
          .borderRadius(10)
          .onClick(() => {
            this.regenerateMenuMessage();
          })
        Button(this.speakingMessageId === this.messageMenuId ? '停止朗读' : '朗读')
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(ACCENT)
          .backgroundColor(this.colorAccentSoft())
          .borderRadius(10)
          .onClick(() => {
            this.readMenuMessage();
          })
        Button('取消')
          .width('100%')
          .height(42)
          .fontSize(this.fs(14))
          .fontColor(this.colorTextSecondary())
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.messageMenuId = '';
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 18 })
      .backgroundColor(this.colorPanel())
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  renameOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .onClick(() => {
          this.renamingConversationId = '';
        })

      Column({ space: 12 }) {
        Text('重命名对话')
          .fontSize(this.fs(18))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colorTextMain())
          .width('100%')
        TextInput({
          text: this.renameText,
          placeholder: '输入新的对话名称'
        })
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.colorTextMain())
          .backgroundColor(this.colorInputBg())
          .borderRadius(9)
          .padding({ left: 12, right: 12 })
          .maxLength(40)
          .onChange((value: string) => {
            this.renameText = value;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(this.fs(14))
            .fontColor(this.colorTextMain())
            .backgroundColor(this.colorSurfaceAlt())
            .borderRadius(10)
            .onClick(() => {
              this.renamingConversationId = '';
            })
          Button('保存')
            .layoutWeight(1)
            .height(42)
            .fontSize(this.fs(14))
            .fontColor(Color.White)
            .backgroundColor(ACCENT)
            .borderRadius(10)
            .onClick(() => {
              this.commitRename();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(18)
      .backgroundColor(this.colorPanel())
      .borderRadius(16)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  selectTextOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .onClick(() => {
          this.selectTextMessageId = '';
        })

      Column() {
        Row() {
          Text('选择文本')
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colorTextMain())
            .layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_close'))
              .width(16)
              .height(16)
              .fillColor(this.colorTextSecondary())
          }
          .width(34)
          .height(34)
          .backgroundColor(this.colorSurfaceAlt())
          .onClick(() => {
            this.selectTextMessageId = '';
          })
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 12, bottom: 10 })

        Divider()
          .strokeWidth(0.5)
          .color(this.colorLine())

        Scroll() {
          Text(this.selectedText())
            .fontSize(this.fs(16))
            .lineHeight(this.fs(26))
            .fontColor(this.colorTextMain())
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding(14)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        Text('长按文字可选择部分内容，或使用下方按钮复制全文。')
          .fontSize(this.fs(10))
          .fontColor(this.colorTextFaint())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 4, bottom: 6 })

        Row({ space: 10 }) {
          Button('复制全文')
            .layoutWeight(1)
            .height(42)
            .fontSize(this.fs(14))
            .fontColor(ACCENT)
            .backgroundColor(this.colorAccentSoft())
            .borderRadius(10)
            .onClick(() => {
              this.copyMessage(this.selectedText());
            })
          Button('关闭')
            .layoutWeight(1)
            .height(42)
            .fontSize(this.fs(14))
            .fontColor(this.colorTextMain())
            .backgroundColor(this.colorSurfaceAlt())
            .borderRadius(10)
            .onClick(() => {
              this.selectTextMessageId = '';
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 14 })
      }
      .width('92%')
      .height('82%')
      .backgroundColor(this.colorPanel())
      .borderRadius(16)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}

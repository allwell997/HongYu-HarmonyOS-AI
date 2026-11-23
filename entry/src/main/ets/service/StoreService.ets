import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSettings, Conversation } from '../model/Models';

const STORE_NAME: string = 'hongyu_chat_store';
const KEY_CONVERSATIONS: string = 'conversations_v1';
const KEY_SETTINGS: string = 'settings_v1';
const DOMAIN: number = 0x0001;
const TAG: string = 'HongYuStore';

/**
 * 使用 Preferences 保存对话和设置。
 * 图片不写入 Preferences，只保存压缩后的沙箱文件路径，避免首选项文件膨胀。
 */
export class StoreService {
  private pref: preferences.Preferences | undefined = undefined;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.pref = await preferences.getPreferences(context, STORE_NAME);
  }

  loadConversations(): Conversation[] {
    if (!this.pref) {
      return [];
    }
    const stored = this.pref.getSync(KEY_CONVERSATIONS, '[]');
    const rawText: string = typeof stored === 'string' ? stored : '[]';
    try {
      const parsed = JSON.parse(rawText) as Conversation[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: Conversation[] = [];
      parsed.forEach((item: Conversation, index: number) => {
        if (item && item.id) {
          result.push(Conversation.fromPlain(item, `restored_${index}`));
        }
      });
      result.sort((a: Conversation, b: Conversation) => {
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return b.updatedAt - a.updatedAt;
      });
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to parse conversations: %{public}s',
        (error as BusinessError).message);
      return [];
    }
  }

  loadSettings(): AppSettings {
    if (!this.pref) {
      return new AppSettings();
    }
    const stored = this.pref.getSync(KEY_SETTINGS, '');
    const rawText: string = typeof stored === 'string' ? stored : '';
    if (rawText.length === 0) {
      return new AppSettings();
    }
    try {
      const parsed = JSON.parse(rawText) as AppSettings;
      return AppSettings.fromPlain(parsed);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to parse settings: %{public}s',
        (error as BusinessError).message);
      return new AppSettings();
    }
  }

  async saveConversations(conversations: Conversation[]): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_CONVERSATIONS, JSON.stringify(conversations));
    await this.pref.flush();
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_SETTINGS, JSON.stringify(settings));
    await this.pref.flush();
  }
}

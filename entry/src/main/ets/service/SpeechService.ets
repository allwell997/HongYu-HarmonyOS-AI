import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface SpeechCallbacks {
  onStart?: () => void;
  onComplete?: () => void;
  onError?: (message: string) => void;
}

/**
 * 封装 HarmonyOS Core Speech Kit 的离线文本转语音。
 * 注意：系统 TTS 在模拟器上可能不可用，需要真机验证。
 */
export class SpeechService {
  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private enginePerson: number = -1;
  private callbacks: SpeechCallbacks = {};
  private initPromise: Promise<void> | undefined = undefined;
  private currentRequestId: string = '';
  private speakToken: number = 0;

  setCallbacks(callbacks: SpeechCallbacks): void {
    this.callbacks = callbacks;
  }

  async init(person: number = 13): Promise<void> {
    if (this.engine && this.enginePerson === person) {
      return;
    }
    if (this.engine || this.initPromise) {
      // 切换音色时必须重建引擎，旧引擎的语种/音色参数无法热切换。
      this.disposeEngine();
    }
    if (!this.initPromise) {
      this.initPromise = this.createAndSetup(person);
    }
    try {
      await this.initPromise;
    } catch (error) {
      this.initPromise = undefined;
      const businessError = error as BusinessError;
      throw new Error(businessError.message ? businessError.message : '语音引擎初始化失败');
    }
  }

  private async createAndSetup(person: number): Promise<void> {
    let engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
    let actualPerson: number = person;
    try {
      engine = await this.createEngine(person);
    } catch (error) {
      try {
        // 凌飞哲男声在部分设备上需要额外下载，失败时回退到聆小珊。
        engine = await this.createEngine(person === 13 ? 0 : 13);
        actualPerson = person === 13 ? 0 : 13;
      } catch (fallbackError) {
        try {
          engine = await this.createEngine(0);
          actualPerson = 0;
        } catch (defaultError) {
          const businessError = defaultError as BusinessError;
          throw new Error(`语音引擎初始化失败：${businessError.message ?? '当前设备不支持'}`);
        }
      }
    }
    if (!engine) {
      throw new Error('语音引擎初始化失败：当前设备不支持系统 TTS。');
    }
    engine.setListener(this.buildListener());
    this.engine = engine;
    this.enginePerson = actualPerson;
  }

  private async createEngine(person: number): Promise<textToSpeech.TextToSpeechEngine> {
    const extraParams: Record<string, Object> = {
      'style': 'interaction-broadcast',
      'locate': 'CN',
      'name': 'HongYuSpeech',
      'isBackStage': false
    };
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: person,
      // 系统文档中 online=1 表示当前唯一支持的离线模式。
      online: 1,
      extraParams: extraParams
    };
    return await textToSpeech.createEngine(params);
  }

  private buildListener(): textToSpeech.SpeakListener {
    return {
      onStart: (requestId: string, response: textToSpeech.StartResponse) => {
        if (requestId === this.currentRequestId && this.callbacks.onStart) {
          this.callbacks.onStart();
        }
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
        // 0 为合成完成，1 为播报完成；UI 只关心真正读完。
        if (requestId === this.currentRequestId && response.type === 1 && this.callbacks.onComplete) {
          this.callbacks.onComplete();
        }
      },
      onStop: (requestId: string, response: textToSpeech.StopResponse) => {
        if (requestId === this.currentRequestId && this.callbacks.onComplete) {
          this.callbacks.onComplete();
        }
      },
      onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
      },
      onError: (requestId: string, errorCode: number, errorMessage: string) => {
        if (requestId === this.currentRequestId && this.callbacks.onError) {
          this.callbacks.onError(`语音朗读失败（${errorCode}）：${errorMessage}`);
        }
      }
    };
  }

  async speak(text: string, rate: number, volume: number, pitch: number, person: number = 13): Promise<void> {
    const content: string = this.prepareText(text);
    if (content.length === 0) {
      throw new Error('这条回复没有可朗读的文字。');
    }
    this.speakToken += 1;
    const token: number = this.speakToken;
    await this.init(person);
    if (token !== this.speakToken) {
      // 初始化期间用户已经点了停止，或者已经开始朗读另一条消息。
      return;
    }
    if (!this.engine) {
      throw new Error('语音引擎未就绪。');
    }
    const requestId: string = `speak_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    const extraParams: Record<string, Object> = {
      'queueMode': 1,
      'speed': rate,
      'volume': volume,
      'pitch': pitch,
      'languageContext': 'zh-CN',
      'audioType': 'pcm',
      'playType': 1,
      'soundChannel': 3
    };
    const params: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: extraParams
    };
    this.currentRequestId = requestId;
    this.engine.speak(content, params);
  }

  stop(): void {
    this.speakToken += 1;
    if (this.engine) {
      this.engine.stop();
    }
    this.currentRequestId = '';
  }

  release(): void {
    this.speakToken += 1;
    this.disposeEngine();
    this.currentRequestId = '';
    this.callbacks = {};
  }

  private disposeEngine(): void {
    if (!this.engine) {
      this.enginePerson = -1;
      this.initPromise = undefined;
      return;
    }
    try {
      this.engine.stop();
    } catch (error) {
      console.warn(`停止语音失败: ${(error as BusinessError).message}`);
    }
    try {
      this.engine.shutdown();
    } catch (error) {
      console.warn(`释放语音引擎失败: ${(error as BusinessError).message}`);
    }
    this.engine = undefined;
    this.enginePerson = -1;
    this.initPromise = undefined;
  }

  /**
   * 朗读前清理 Markdown，避免把 #、**、代码围栏之类符号逐字读出来。
   * 系统单次最多 10000 字，超长时读前 10000 字。
   */
  prepareText(text: string): string {
    let clean: string = text;
    clean = clean.replace(/```[\s\S]*?```/g, ' 代码块已省略。 ');
    clean = clean.replace(/!\[[^\]]*\]\([^)]*\)/g, ' ');
    clean = clean.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');
    clean = clean.replace(/https?:\/\/\S+/g, ' ');
    clean = clean.replace(/[*_`#>~|]/g, ' ');
    clean = clean.replace(/^\s*[-+]\s+/gm, '');
    clean = clean.replace(/\n{2,}/g, '。 ');
    clean = clean.replace(/\s+/g, ' ');
    clean = clean.trim();
    if (clean.length > 10000) {
      clean = clean.slice(0, 10000);
    }
    return clean;
  }
}

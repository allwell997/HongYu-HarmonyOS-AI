import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0003;
const TAG: string = 'HongYuDeepSeekTTS';
const TTS_ENDPOINT: string = 'https://api.deepseek.com/v1/tools/tts';

export interface DeepSeekSpeechCallbacks {
  onStart?: () => void;
  onComplete?: () => void;
  onError?: (message: string) => void;
}

/**
 * DeepSeek 服务端语音合成。
 *
 * DeepSeek App 的“贝壳/白浪/海星/暗潮”是服务端合成后下发的音频，
 * 这里直接调用官方 /v1/tools/tts，把 WAV 写到 cacheDir 后用 AVPlayer 播放。
 * 注意：公开文档只列出 stella/tide；mira/echo 是否能调用取决于账号放行。
 */
export class DeepSeekSpeechService {
  private player: media.AVPlayer | undefined = undefined;
  private mediaFile: fs.File | undefined = undefined;
  private tempPath: string = '';
  private requestToken: number = 0;
  private httpRequest: http.HttpRequest | undefined = undefined;

  async speak(context: common.UIAbilityContext, apiKey: string, text: string, voiceId: string,
    callbacks: DeepSeekSpeechCallbacks): Promise<void> {
    this.stop();
    const content: string = text.trim();
    if (content.length === 0) {
      throw new Error('这段内容没有可朗读的文字。');
    }
    if (apiKey.trim().length === 0) {
      throw new Error('DeepSeek 在线朗读需要 API Key，请先在设置中填写。');
    }
    const token: number = this.requestToken + 1;
    this.requestToken = token;
    const request = http.createHttp();
    this.httpRequest = request;
    try {
      const response: http.HttpResponse = await request.request(TTS_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey.trim()}`
        },
        extraData: JSON.stringify({
          text: content,
          voice_id: voiceId,
          format: 'wav',
          filter_markdown: true
        }),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 30000,
        readTimeout: 180000
      });
      if (token !== this.requestToken) {
        return;
      }
      if (response.responseCode !== 200) {
        throw new Error(`DeepSeek 语音合成失败（HTTP ${response.responseCode}）。` +
          '可能是 API Key 无 TTS 权限、音色未开放或内容审核未通过。');
      }
      if (!(response.result instanceof ArrayBuffer)) {
        throw new Error('DeepSeek 语音合成返回了非音频数据。');
      }
      const audio: ArrayBuffer = response.result as ArrayBuffer;
      hilog.info(DOMAIN, TAG, 'HTTP 200, audio bytes=%{public}d, voice=%{public}s', audio.byteLength, voiceId);
      const path: string = `${context.cacheDir}/tts_${Date.now()}_${Math.floor(Math.random() * 1000)}.wav`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, audio);
      } finally {
        fs.closeSync(file);
      }
      this.tempPath = path;
      await this.startPlayer(path, token, callbacks);
    } catch (error) {
      if (token !== this.requestToken) {
        return;
      }
      const businessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'DeepSeek TTS failed: code=%{public}d, message=%{public}s',
        businessError.code, businessError.message);
      await this.releasePlayer();
      this.cleanupFile();
      throw new Error(businessError.message ? businessError.message : 'DeepSeek 语音合成失败');
    } finally {
      if (this.httpRequest === request) {
        this.httpRequest = undefined;
      }
      request.destroy();
    }
  }

  private async startPlayer(path: string, token: number, callbacks: DeepSeekSpeechCallbacks): Promise<void> {
    const player: media.AVPlayer = await media.createAVPlayer();
    this.player = player;
    const stat = fs.statSync(path);
    const sourceFile = fs.openSync(path, fs.OpenMode.READ_ONLY);
    this.mediaFile = sourceFile;
    let finished: boolean = false;
    const finish = (): void => {
      if (finished) {
        return;
      }
      finished = true;
      this.releasePlayer().finally(() => {
        this.cleanupFile();
      });
      if (token === this.requestToken && callbacks.onComplete) {
        callbacks.onComplete();
      }
    };
    player.on('stateChange', (state: media.AVPlayerState) => {
      hilog.info(DOMAIN, TAG, 'AVPlayer state=%{public}s', state);
      if (token !== this.requestToken) {
        return;
      }
      if (state === 'initialized') {
        player.prepare().catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'prepare failed: code=%{public}d, message=%{public}s',
            error.code, error.message);
          if (callbacks.onError) {
            callbacks.onError(`语音准备失败：${error.message}`);
          }
          finish();
        });
      } else if (state === 'prepared') {
        player.play().then(() => {
          if (callbacks.onStart) {
            callbacks.onStart();
          }
        }).catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'play failed: code=%{public}d, message=%{public}s',
            error.code, error.message);
          if (callbacks.onError) {
            callbacks.onError(`语音播放失败：${error.message}`);
          }
          finish();
        });
      } else if (state === 'completed') {
        finish();
      } else if (state === 'error') {
        if (callbacks.onError) {
          callbacks.onError('语音播放失败：播放器进入错误状态。');
        }
        finish();
      }
    });
    player.on('error', (error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'AVPlayer error: code=%{public}d, message=%{public}s',
        error.code, error.message);
      if (token !== this.requestToken) {
        return;
      }
      if (callbacks.onError) {
        callbacks.onError(`语音播放失败：${error.message}`);
      }
      finish();
    });
    player.fdSrc = {
      fd: sourceFile.fd,
      offset: 0,
      length: stat.size
    };
  }

  private async releasePlayer(): Promise<void> {
    const player = this.player;
    this.player = undefined;
    try {
      if (player) {
        try {
          await player.stop();
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'AVPlayer stop: %{public}s', (error as BusinessError).message);
        }
        try {
          await player.release();
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'AVPlayer release: %{public}s', (error as BusinessError).message);
        }
      }
    } finally {
      if (this.mediaFile) {
        try {
          fs.closeSync(this.mediaFile);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'close media file: %{public}s', (error as BusinessError).message);
        }
        this.mediaFile = undefined;
      }
    }
  }

  private cleanupFile(): void {
    const path: string = this.tempPath;
    this.tempPath = '';
    if (path.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to delete temp TTS file: %{public}s', (error as BusinessError).message);
    }
  }

  stop(): void {
    this.requestToken += 1;
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = undefined;
    }
    this.releasePlayer().finally(() => {
      this.cleanupFile();
    });
  }
}

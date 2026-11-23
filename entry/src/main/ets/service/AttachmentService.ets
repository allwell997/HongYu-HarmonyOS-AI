import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0002;
const TAG: string = 'HongYuAttachment';
const MAX_EDGE: number = 1280;
const JPEG_QUALITY: number = 82;

/**
 * 图片选择、压缩、沙箱存储和转 Base64。
 *
 * 原图 URI 来自系统图库选择器，权限只在该次选择后短暂有效；
 * 因此这里立刻解码、按最长边 1280 压缩为 JPEG，再写入应用自己的 filesDir。
 */
export class AttachmentService {
  async pickUris(maxSelectNumber: number): Promise<string[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxSelectNumber;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    if (!result.photoUris) {
      return [];
    }
    return result.photoUris;
  }

  /**
   * 拉起系统相机拍照。CameraPicker 由系统提供拍摄/确认界面，
   * 不需要申请 ohos.permission.CAMERA；返回值是临时图片 URI，随后走统一压缩流程。
   */
  async takePhoto(context: common.UIAbilityContext): Promise<string> {
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
    };
    try {
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        profile
      );
      hilog.info(DOMAIN, TAG, 'camera result uri=%{public}s', result.resultUri ?? '');
      return result.resultUri ? result.resultUri : '';
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'cameraPicker failed: code=%{public}d, message=%{public}s',
        businessError.code, businessError.message);
      throw new Error(businessError.message ? businessError.message : '打开相机失败');
    }
  }

  async saveCompressed(context: common.UIAbilityContext, sourceUri: string, index: number): Promise<string> {
    const dir: string = `${context.filesDir}/chat_images`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }

    let sourceFile: fs.File | undefined = undefined;
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      // Picker 返回的 URI（尤其是相机结果的 file://media/...）不能总被
      // ImageSource 当普通路径打开；先拿只读文件描述符再解码最稳妥。
      sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(sourceFile.fd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const srcWidth: number = info.size.width > 0 ? info.size.width : 1080;
      const srcHeight: number = info.size.height > 0 ? info.size.height : 1080;
      const scale: number = Math.min(1, MAX_EDGE / Math.max(srcWidth, srcHeight));
      const targetWidth: number = Math.max(1, Math.round(srcWidth * scale));
      const targetHeight: number = Math.max(1, Math.round(srcHeight * scale));

      const decodeOptions: image.DecodingOptions = {
        desiredSize: {
          width: targetWidth,
          height: targetHeight
        },
        editable: false
      };
      pixelMap = await imageSource.createPixelMap(decodeOptions);

      const packOptions: image.PackingOption = {
        format: 'image/jpeg',
        quality: JPEG_QUALITY
      };
      const compressed: ArrayBuffer = await packer.packing(pixelMap, packOptions);
      const fileName: string = `${Date.now()}_${index}_${Math.floor(Math.random() * 1000)}.jpg`;
      const path: string = `${dir}/${fileName}`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, compressed);
      } finally {
        fs.closeSync(file);
      }
      return path;
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'saveCompressed failed: code=%{public}d, message=%{public}s, uri=%{public}s',
        businessError.code, businessError.message, sourceUri);
      throw new Error(businessError.message ? businessError.message : '图片解码或压缩失败');
    } finally {
      if (pixelMap) {
        await pixelMap.release();
      }
      if (imageSource) {
        await imageSource.release();
      }
      if (sourceFile) {
        fs.closeSync(sourceFile);
      }
      await packer.release();
    }
  }

  readBase64(path: string): string {
    const stat = fs.statSync(path);
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(buffer));
  }

  getDisplayUri(path: string): string {
    if (path.length === 0) {
      return '';
    }
    if (path.startsWith('file://') || path.startsWith('http://') || path.startsWith('https://') ||
      path.startsWith('data:')) {
      return path;
    }
    return fileUri.getUriFromPath(path);
  }

  deleteFiles(paths: string[]): void {
    paths.forEach((path: string) => {
      try {
        if (fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to delete attachment: %{public}s',
          (error as BusinessError).message);
      }
    });
  }

  isUserCancel(error: BusinessError): boolean {
    return error.code === 13900042;
  }
}

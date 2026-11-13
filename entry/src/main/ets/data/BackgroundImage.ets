/**
 * 课表背景图：内置预设 + 用户自定义多图（可多选轮播，退出课表时按「切换时机」换图）。
 *
 * HarmonyOS 侧用系统图库选择器（`photoAccessHelper.PhotoViewPicker`，无需申请读相册权限）
 * 选图后把文件复制进应用沙箱（临时 URI 不能长期使用）；自定义图片列表（路径 + 显示名）
 * 以 JSON 存 prefs `backgroundCustomImages`，当前背景路径仍存 `bgImgPath`，
 * 课表页按路径加载 PixelMap 作为背景。
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { AppContext } from '../app/AppContext';
import { AppPreferences, PrefKeys } from '../app/AppPreferences';
import { AppState } from '../app/AppState';

/** prefs 中自定义背景列表的持久化结构。 */
interface CustomBackgroundJson {
  path?: string;
  name?: string;
}

/** 用户自定义背景图：沙箱路径 + 列表显示名（默认「自定义图片N」，可重命名）。 */
export class CustomBackground {
  path: string = '';
  name: string = '';

  constructor(path: string = '', name: string = '') {
    this.path = path;
    this.name = name;
  }
}

export class BackgroundImage {
  /** 内置背景（rawfile/backgrounds），无需相册权限即可切换。 */
  static readonly PRESETS: string[] = ['bg_mist.png', 'bg_sunset.png', 'bg_forest.png'];

  private static readonly PRESET_PREFIX: string = 'bg_builtin_';
  private static readonly BUILTIN_KEY_PREFIX: string = 'builtin:';
  private static readonly CUSTOM_KEY_PREFIX: string = 'custom:';
  private static readonly CUSTOM_NAME_PREFIX: string = '自定义图片';

  static presetLabel(name: string): string {
    if (name === 'bg_mist.png') {
      return '晨雾';
    }
    if (name === 'bg_sunset.png') {
      return '晚霞';
    }
    if (name === 'bg_forest.png') {
      return '森林';
    }
    return name;
  }

  /** 从沙箱路径解析内置背景名（非内置返回空串）。 */
  private static presetNameOf(path: string): string {
    const index: number = path.lastIndexOf(BackgroundImage.PRESET_PREFIX);
    if (index < 0) {
      return '';
    }
    return path.substring(index + BackgroundImage.PRESET_PREFIX.length);
  }

  /** 缩略图 URI：Image 组件不能直接接收沙箱路径，需要先转成沙箱 URI。 */
  static thumbnailUri(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  /** 把内置背景复制到沙箱并设为当前背景。 */
  private static async applyPreset(name: string): Promise<void> {
    await BackgroundImage.setCurrentPath(await BackgroundImage.ensurePresetFile(name));
  }

  /** 写入当前背景（prefs + Store）并刷新轮播计时。 */
  private static async setCurrentPath(path: string): Promise<void> {
    await AppPreferences.put(PrefKeys.BgImgPath, path);
    AppState.setBackgroundImagePath(path);
    await BackgroundImage.markChanged();
  }

  private static async ensurePresetFile(name: string): Promise<string> {
    const context = AppContext.get();
    const content: Uint8Array = await context.resourceManager.getRawFileContent(`backgrounds/${name}`);
    const dest: string = `${context.filesDir}/${BackgroundImage.PRESET_PREFIX}${name}`;
    const file: fs.File = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const buffer: ArrayBuffer = content.buffer.slice(
        content.byteOffset, content.byteOffset + content.byteLength) as ArrayBuffer;
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return dest;
  }

  /**
   * 读取自定义背景列表。旧版只有单张相册背景（`bgImgPath` 指向 `bg_image_*`），
   * 首次读取时自动迁移成列表第一张。
   */
  static async loadCustom(): Promise<CustomBackground[]> {
    const list: CustomBackground[] = await BackgroundImage.readCustom();
    const current: string = BackgroundImage.currentPath();
    if (current !== '' && BackgroundImage.presetNameOf(current) === '' &&
      !BackgroundImage.hasPath(list, current) && BackgroundImage.exists(current)) {
      list.push(new CustomBackground(current,
        `${BackgroundImage.CUSTOM_NAME_PREFIX}${BackgroundImage.nextCustomIndex(list)}`));
      await BackgroundImage.saveCustom(list);
    }
    return list;
  }

  /** 从相册选一张图追加到自定义列表（不自动切换当前背景）。返回 null 表示用户取消。 */
  static async addCustom(): Promise<CustomBackground | null> {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    // 系统图库自带编辑能力：允许用户在系统 UI 中裁剪/旋转，而不是由应用强行缩放。
    options.isEditSupported = true;
    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    if (result.photoUris.length === 0) {
      return null;
    }
    const uri: string = result.photoUris[0];
    const dest: string = `${AppContext.get().filesDir}/bg_custom_${Date.now()}${BackgroundImage.extensionOf(uri)}`;
    const srcFile: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(srcFile.fd, dest);
    } finally {
      fs.closeSync(srcFile);
    }
    const list: CustomBackground[] = await BackgroundImage.loadCustom();
    const item: CustomBackground = new CustomBackground(dest,
      `${BackgroundImage.CUSTOM_NAME_PREFIX}${BackgroundImage.nextCustomIndex(list)}`);
    list.push(item);
    await BackgroundImage.saveCustom(list);
    return item;
  }

  static async renameCustom(path: string, name: string): Promise<void> {
    const list: CustomBackground[] = await BackgroundImage.readCustom();
    for (let i = 0; i < list.length; i++) {
      if (list[i].path === path) {
        list[i].name = name;
        break;
      }
    }
    await BackgroundImage.saveCustom(list);
  }

  /** 删除自定义图片；若该图正在使用，同时清空当前背景。 */
  static async deleteCustom(item: CustomBackground): Promise<void> {
    const list: CustomBackground[] = await BackgroundImage.readCustom();
    const remaining: CustomBackground[] =
      list.filter((entry: CustomBackground): boolean => entry.path !== item.path);
    await BackgroundImage.saveCustom(remaining);
    if (BackgroundImage.exists(item.path)) {
      try {
        fs.unlinkSync(item.path);
      } catch (err) {
        console.warn(`[BackgroundImage] unlink custom failed: ${JSON.stringify(err)}`);
      }
    }
    const key: string = BackgroundImage.customKey(item.path);
    const remainingKeys: string[] =
      (await BackgroundImage.loadSelectedKeys()).filter((entry: string): boolean => entry !== key);
    await BackgroundImage.saveSelectedKeys(remainingKeys);
    if (BackgroundImage.currentPath() === item.path) {
      if (remainingKeys.length > 0) {
        await BackgroundImage.applyKey(remainingKeys[0]);
      } else {
        await BackgroundImage.clear();
      }
    }
  }

  /** 清空当前背景选择（自定义图片文件仍保留在列表中）。 */
  private static async clear(): Promise<void> {
    await BackgroundImage.setCurrentPath('');
  }

  private static currentPath(): string {
    return AppState.store().backgroundImagePath;
  }

  /** 选中状态 key：内置图用 builtin:名字，自定义图用 custom:路径。 */
  static presetKey(name: string): string {
    return `${BackgroundImage.BUILTIN_KEY_PREFIX}${name}`;
  }

  static customKey(path: string): string {
    return `${BackgroundImage.CUSTOM_KEY_PREFIX}${path}`;
  }

  /**
   * 启动恢复：上次退出时已经轮播好的背景 + 参与轮播的选中列表。
   * 旧数据没有选中列表时，会把当前背景迁移成唯一选中项。
   */
  static async restore(): Promise<void> {
    let path: string = '';
    try {
      path = await AppPreferences.getString(PrefKeys.BgImgPath, '');
    } catch (err) {
      path = '';
    }
    if (path !== '' && !BackgroundImage.exists(path)) {
      path = '';
    }
    AppState.setBackgroundImagePath(path);
    AppState.setBackgroundSelectedKeys(await BackgroundImage.loadSelectedKeys());
  }

  /** 读取参与的轮播图片；没有历史 key 时把当前背景迁移为唯一选中项。 */
  private static async loadSelectedKeys(): Promise<string[]> {
    return BackgroundImage.readSelectedKeys(BackgroundImage.currentPath());
  }

  private static async readSelectedKeys(currentPath: string): Promise<string[]> {
    let raw: string = '';
    try {
      raw = await AppPreferences.getString(PrefKeys.BackgroundSelected, '');
    } catch (err) {
      raw = '';
    }
    if (raw !== '') {
      try {
        const items: string[] = JSON.parse(raw) as string[];
        const keys: string[] = [];
        for (let i = 0; i < items.length; i++) {
          if (typeof items[i] === 'string' && items[i] !== '') {
            keys.push(items[i]);
          }
        }
        return keys;
      } catch (err) {
        return [];
      }
    }
    const keys: string[] = [];
    if (currentPath !== '') {
      keys.push(BackgroundImage.keyOfPath(currentPath));
      await AppPreferences.put(PrefKeys.BackgroundSelected, JSON.stringify(keys));
    }
    return keys;
  }

  private static async saveSelectedKeys(keys: string[]): Promise<void> {
    await AppPreferences.put(PrefKeys.BackgroundSelected, JSON.stringify(keys));
    AppState.setBackgroundSelectedKeys(keys);
  }

  /** UTC 天序号，用于「自定义天数」判断是否到期。 */
  private static dayNumber(): number {
    return Math.floor(Date.now() / 86400000);
  }

  private static async markChanged(): Promise<void> {
    await AppPreferences.put(PrefKeys.BackgroundChangedDay, BackgroundImage.dayNumber());
  }

  /** 路径对应的选择 key。 */
  private static keyOfPath(path: string): string {
    if (path === '') {
      return '';
    }
    const presetName: string = BackgroundImage.presetNameOf(path);
    return presetName === '' ? BackgroundImage.customKey(path) : BackgroundImage.presetKey(presetName);
  }

  /** 当前背景对应的选择 key。 */
  private static currentKey(): string {
    return BackgroundImage.keyOfPath(BackgroundImage.currentPath());
  }

  /** 把 key 对应的图片设为当前背景。 */
  private static async applyKey(key: string): Promise<void> {
    if (key.startsWith(BackgroundImage.BUILTIN_KEY_PREFIX)) {
      await BackgroundImage.applyPreset(key.substring(BackgroundImage.BUILTIN_KEY_PREFIX.length));
      return;
    }
    if (key.startsWith(BackgroundImage.CUSTOM_KEY_PREFIX)) {
      await BackgroundImage.setCurrentPath(key.substring(BackgroundImage.CUSTOM_KEY_PREFIX.length));
    }
  }

  /** 点击缩略图切换选中状态；没有当前背景时，选中即设为当前。 */
  static async toggleSelected(key: string): Promise<void> {
    const keys: string[] = await BackgroundImage.loadSelectedKeys();
    const index: number = keys.indexOf(key);
    if (index >= 0) {
      keys.splice(index, 1);
      await BackgroundImage.saveSelectedKeys(keys);
      if (BackgroundImage.currentKey() === key) {
        if (keys.length > 0) {
          await BackgroundImage.applyKey(keys[0]);
        } else {
          await BackgroundImage.clear();
        }
      }
      return;
    }
    keys.push(key);
    await BackgroundImage.saveSelectedKeys(keys);
    if (BackgroundImage.currentPath() === '') {
      await BackgroundImage.applyKey(key);
    }
  }

  /** 退出课表/退到后台时的轮播：按「切换时机」决定是否到期；没有选中图片则清空背景。 */
  static async rotateOnLeave(): Promise<void> {
    const keys: string[] = await BackgroundImage.loadSelectedKeys();
    AppState.setBackgroundSelectedKeys(keys);
    if (keys.length === 0) {
      if (BackgroundImage.currentPath() !== '') {
        await BackgroundImage.clear();
      }
      return;
    }
    const mode: string = await AppPreferences.getString(PrefKeys.BackgroundSwitchMode, 'exit');
    if (mode === 'days') {
      const days: number = Math.max(1,
        Math.min(365, await AppPreferences.getInt(PrefKeys.BackgroundSwitchDays, 1)));
      const changed: number = await AppPreferences.getInt(PrefKeys.BackgroundChangedDay, 0);
      const today: number = BackgroundImage.dayNumber();
      if (changed > 0 && today - changed < days) {
        return;
      }
    }
    const current: string = BackgroundImage.currentKey();
    const index: number = keys.indexOf(current);
    const next: string = index < 0 ? keys[0] : keys[(index + 1) % keys.length];
    if (next !== current) {
      await BackgroundImage.applyKey(next);
    }
  }

  /** 按路径解码成受控尺寸的 PixelMap（避免整图进内存）。 */
  static async loadPixelMap(path: string): Promise<image.PixelMap | undefined> {
    if (path === '' || !BackgroundImage.exists(path)) {
      return undefined;
    }
    try {
      const source: image.ImageSource = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      // 不再固定解码成 1080x1800；按原图比例限制最大边，交给 ImageFit.Cover 按屏幕自适应取景。
      const maxSide: number = 2048;
      const scale: number = Math.min(1, maxSide / Math.max(info.size.width, info.size.height));
      const options: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        }
      };
      const pixelMap: image.PixelMap = await source.createPixelMap(options);
      await source.release();
      return pixelMap;
    } catch (err) {
      console.error(`[BackgroundImage] decode failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  private static async readCustom(): Promise<CustomBackground[]> {
    let raw: string = '';
    try {
      raw = await AppPreferences.getString(PrefKeys.BackgroundCustom, '');
    } catch (err) {
      raw = '';
    }
    if (raw === '') {
      return [];
    }
    try {
      const items: CustomBackgroundJson[] = JSON.parse(raw) as CustomBackgroundJson[];
      const list: CustomBackground[] = [];
      for (let i = 0; i < items.length; i++) {
        const item: CustomBackgroundJson = items[i];
        const path: string = item.path === undefined ? '' : item.path;
        const name: string = item.name === undefined ? '' : item.name;
        if (path !== '') {
          list.push(new CustomBackground(path, name));
        }
      }
      return list;
    } catch (err) {
      console.warn(`[BackgroundImage] parse custom list failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  private static async saveCustom(list: CustomBackground[]): Promise<void> {
    await AppPreferences.put(PrefKeys.BackgroundCustom, JSON.stringify(list));
  }

  private static hasPath(list: CustomBackground[], path: string): boolean {
    return list.some((entry: CustomBackground): boolean => entry.path === path);
  }

  /** 下一个默认名称序号：在「自定义图片N」类名字里取最大 N + 1。 */
  private static nextCustomIndex(list: CustomBackground[]): number {
    let max: number = 0;
    for (let i = 0; i < list.length; i++) {
      const name: string = list[i].name;
      if (!name.startsWith(BackgroundImage.CUSTOM_NAME_PREFIX)) {
        continue;
      }
      const value: number = Number(name.substring(BackgroundImage.CUSTOM_NAME_PREFIX.length));
      if (!Number.isNaN(value) && value > max) {
        max = value;
      }
    }
    return max + 1;
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private static extensionOf(uri: string): string {
    const questionIndex: number = uri.indexOf('?');
    const clean: string = questionIndex >= 0 ? uri.substring(0, questionIndex) : uri;
    const dotIndex: number = clean.lastIndexOf('.');
    if (dotIndex < 0) {
      return '.jpg';
    }
    const ext: string = clean.substring(dotIndex);
    return ext.length <= 5 ? ext : '.jpg';
  }
}

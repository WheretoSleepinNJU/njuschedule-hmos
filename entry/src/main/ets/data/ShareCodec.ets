/**
 * 分享 / 导入码编解码：1:1 移植旧版 `lib/Pages/Share/qr_payload_codec.dart`。
 *
 * 格式（不可改，旧 App 仍在流通）：
 * - URI：`ncs://qr/v2/s/<payload>`（单帧）或 `ncs://qr/v2/m/<idx>/<total>/<groupId>/<part>`（多帧）
 * - payload = URL-safe base64( gzip( UTF-8( JSON ) ) )
 * - JSON：{ t, v, alg, meta{...checksum}, table{name,data}, courses[] }
 * - checksum = crc32( UTF-8( JSON({table:{name,data}, courses}) ) )，meta 不参与校验
 *
 * HarmonyOS 侧用 `@kit.BasicServicesKit` 的 zlib 流式接口（API 12+）做内存 gzip：
 * `deflateInit2(windowBits = 15 + 16)` 产出 gzip 容器，`inflateInit2(31)` 解 gzip。
 */
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { Course } from './models/Models';

const SCHEME: string = 'ncs';
const HOST: string = 'qr';
const VERSION_TAG: string = 'v2';
const PAYLOAD_TYPE: string = 'ncs_qr_schedule';
const ALG_GZIP: string = 'gz';
const PAYLOAD_MAX_CHARS: number = 20000;
const MAX_DECOMPRESSED_BYTES: number = 256 * 1024;
const PART_MAX_LENGTH: number = 1400;
/** Scan Kit generateBarcode 的文本上限是 512 字符，这里留余量按 500 控制整条 URI 长度。 */
const QR_CONTENT_MAX_LENGTH: number = 500;

/** 解码失败原因（与旧版 FormatException message 对齐）。 */
export class ShareCodeError {
  static readonly PayloadTooLarge: string = 'payload_too_large';
  static readonly Base64Failed: string = 'base64_decode_failed';
  static readonly GzipFailed: string = 'gzip_decode_failed';
  static readonly DecompressedTooLarge: string = 'decompressed_payload_too_large';
  static readonly InvalidShape: string = 'invalid_payload_shape';
  static readonly UnsupportedType: string = 'unsupported_payload_type';
  static readonly UnsupportedVersion: string = 'unsupported_payload_version';
  static readonly UnsupportedAlg: string = 'unsupported_payload_algorithm';
  static readonly InvalidFields: string = 'invalid_payload_fields';
  static readonly MissingTableName: string = 'missing_table_name';
  static readonly ChecksumMismatch: string = 'checksum_mismatch';
  static readonly NotShareCode: string = 'not_ncs_qr_payload';
  static readonly GzipEncodeFailed: string = 'gzip_encode_failed';
}

/** 分享码里的课程（字段与旧版 `dbCourseToPayloadMap` 对齐，snake_case）。 */
export class SharePayloadCourse {
  name: string = '';
  classroom: string = '';
  class_number: string = '';
  teacher: string = '';
  test_time: string = '';
  test_location: string = '';
  link: string = '';
  info: string = '';
  weeks: number[] = [];
  week_time: number = 0;
  start_time: number = 0;
  time_count: number = 0;
  import_type: number = 1;
  course_id: number = -1;
}

class SharePayloadTable {
  name: string = '';
  data: string = '';
}

class SharePayloadMeta {
  app: string = 'wheretosleepinnju';
  exportedAt: string = '';
  source: string = 'local_sqlite';
  checksum: string = '';
}

/** payload 的顶层结构。 */
export class SharePayload {
  t: string = PAYLOAD_TYPE;
  v: number = 2;
  alg: string = ALG_GZIP;
  meta: SharePayloadMeta = new SharePayloadMeta();
  table: SharePayloadTable = new SharePayloadTable();
  courses: SharePayloadCourse[] = [];
}

/** 解码成功后的结果。 */
export class DecodedSharePayload {
  tableName: string = '';
  tableData: string = '';
  courses: SharePayloadCourse[] = [];
  /** 压缩前后字节数，用于分享页展示。 */
  jsonBytes: number = 0;
  compressedBytes: number = 0;
}

/** 分享码统计信息。 */
/** 单帧/多帧信息（扫码导入时判断是否需要继续扫）。 */
export class ShareFrame {
  isMulti: boolean = false;
  index: number = 0;
  total: number = 1;
  group: string = '';
}

export class ShareCodeStats {
  code: string = '';
  jsonBytes: number = 0;
  compressedBytes: number = 0;
  base64Chars: number = 0;
}

export class ShareCodec {
  /** CRC32（多项式 0xEDB88320，与旧版一致）。 */
  static crc32(bytes: Uint8Array): number {
    const table: number[] = ShareCodec.crc32Table();
    let crc: number = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) {
      const index: number = (crc ^ bytes[i]) & 0xFF;
      crc = (table[index] ^ (crc >>> 8)) >>> 0;
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  /** UTF-8 字符串的 crc32，返回 8 位小写十六进制。 */
  static crc32Hex(text: string): string {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(text);
    const value: number = ShareCodec.crc32(bytes);
    let hex: string = value.toString(16);
    while (hex.length < 8) {
      hex = `0${hex}`;
    }
    return hex;
  }

  /** 把当前课表与课程编码成分享码 URI。 */
  static async encode(tableName: string, tableData: string, courses: Course[]): Promise<ShareCodeStats> {
    const payload: SharePayload = new SharePayload();
    payload.meta = new SharePayloadMeta();
    payload.meta.exportedAt = new Date().toISOString();
    payload.table = new SharePayloadTable();
    payload.table.name = tableName;
    payload.table.data = tableData;
    payload.courses = [];

    const courseMaps: SharePayloadCourse[] = [];
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      const map: SharePayloadCourse = new SharePayloadCourse();
      map.name = course.name;
      map.classroom = course.classroom;
      map.class_number = course.classNumber;
      map.teacher = course.teacher;
      map.test_time = course.testTime;
      map.test_location = course.testLocation;
      map.link = course.link;
      map.info = course.info;
      map.weeks = course.weeks;
      map.week_time = course.weekTime;
      map.start_time = course.startTime;
      map.time_count = course.timeCount;
      map.import_type = course.importType;
      map.course_id = course.courseId;
      courseMaps.push(map);
    }

    // checksum 只覆盖 table + courses，且字段顺序必须与旧版 JSON 一致。
    const dataForChecksum: string = JSON.stringify(new ChecksumEnvelope(tableName, tableData, courseMaps));
    payload.meta.checksum = ShareCodec.crc32Hex(dataForChecksum);
    payload.courses = courseMaps;

    const payloadJson: string = JSON.stringify(payload);
    const rawBytes: Uint8Array = new util.TextEncoder().encodeInto(payloadJson);
    const compressed: Uint8Array = await ShareCodec.gzipCompress(rawBytes);
    const encoded: string = ShareCodec.base64UrlEncode(compressed);

    const stats: ShareCodeStats = new ShareCodeStats();
    stats.jsonBytes = rawBytes.length;
    stats.compressedBytes = compressed.length;
    stats.base64Chars = encoded.length;
    stats.code = `${SCHEME}://${HOST}/${VERSION_TAG}/s/${encoded}`;
    return stats;
  }

  /** 解析单帧 URI（`ncs://qr/v2/s/<payload>`）。 */
  static async decode(uri: string): Promise<DecodedSharePayload> {
    return ShareCodec.decodeImpl(ShareCodec.extractSingleFrame(uri));
  }

  /** 判断字符串是否是本应用的分享码（旧版 isNcsQrPayload 的宽松版：看前缀）。 */
  static isShareCode(raw: string): boolean {
    const text: string = raw.trim();
    if (!text.startsWith(`${SCHEME}://${HOST}/`)) {
      return false;
    }
    const rest: string = text.substring((`${SCHEME}://${HOST}/`).length);
    return rest.startsWith(`${VERSION_TAG}/`);
  }

  /** 解析 URI 的帧信息；非分享码返回 null。 */
  static frameOf(uri: string): ShareFrame | null {
    const parsed: FrameInfo | null = ShareCodec.parseFrame(uri);
    if (parsed === null) {
      return null;
    }
    const frame: ShareFrame = new ShareFrame();
    frame.isMulti = parsed.isMulti;
    frame.index = parsed.index;
    frame.total = parsed.total;
    frame.group = parsed.group;
    return frame;
  }

  /**
   * 生成二维码用的帧序列：Scan Kit 单张二维码文本上限 512 字符，
   * 因此整条 URI 控制在 500 以内；单帧放得下就返回单帧，否则拆成多帧（旧版 App 可按 idx/total 合并）。
   */
  static splitQrFrames(code: string, groupId?: string): string[] {
    const encoded: string = ShareCodec.extractSingleFrame(code);
    if (encoded === '') {
      return [];
    }
    const single: string = `${SCHEME}://${HOST}/${VERSION_TAG}/s/${encoded}`;
    if (single.length <= QR_CONTENT_MAX_LENGTH) {
      return [single];
    }
    const group: string = groupId !== undefined && groupId !== '' ? groupId : `${Date.now()}`;
    let partLimit: number = 420;
    let parts: string[] = [];
    for (let attempt = 0; attempt < 8; attempt++) {
      parts = [];
      for (let i = 0; i < encoded.length; i += partLimit) {
        parts.push(encoded.substring(i, Math.min(i + partLimit, encoded.length)));
      }
      const total: number = parts.length;
      let fits: boolean = true;
      for (let i = 0; i < total; i++) {
        const uri: string = `${SCHEME}://${HOST}/${VERSION_TAG}/m/${i + 1}/${total}/${group}/${parts[i]}`;
        if (uri.length > QR_CONTENT_MAX_LENGTH) {
          fits = false;
          break;
        }
      }
      if (fits) {
        const frames: string[] = [];
        for (let i = 0; i < total; i++) {
          frames.push(`${SCHEME}://${HOST}/${VERSION_TAG}/m/${i + 1}/${total}/${group}/${parts[i]}`);
        }
        return frames;
      }
      partLimit = Math.max(partLimit - 40, 120);
    }
    return [single];
  }

  /**
   * 多帧合并：只认帧内容里的 group/idx/total（不依赖 Map 的 key），
   * 收齐 1..total 才返回合并后的单帧 URI，否则返回 null。
   */
  static mergeFrames(collected: Map<string, string>): string | null {
    const frames: FrameInfo[] = [];
    for (const value of collected.values()) {
      const parsed: FrameInfo | null = ShareCodec.parseFrame(value);
      if (parsed !== null && parsed.isMulti) {
        frames.push(parsed);
      }
    }
    if (frames.length === 0) {
      return null;
    }
    const group: string = frames[0].group;
    const total: number = frames[0].total;
    // 与上游一致：用索引表收集，不按 total 预分配数组。
    const parts: Map<number, string> = new Map();
    for (let i = 0; i < frames.length; i++) {
      const frame: FrameInfo = frames[i];
      if (frame.group !== group || frame.index < 1 || frame.index > total) {
        continue;
      }
      if (!parts.has(frame.index)) {
        parts.set(frame.index, frame.part);
      }
    }
    if (parts.size !== total) {
      return null;
    }
    let merged: string = '';
    for (let i = 1; i <= total; i++) {
      const part: string | undefined = parts.get(i);
      if (part === undefined) {
        return null;
      }
      merged += part;
    }
    return `${SCHEME}://${HOST}/${VERSION_TAG}/s/${merged}`;
  }

  // ------------------------------------------------------------------ 内部

  private static async decodeImpl(encoded: string): Promise<DecodedSharePayload> {
    if (encoded.length > PAYLOAD_MAX_CHARS) {
      return Promise.reject(new Error(ShareCodeError.PayloadTooLarge));
    }
    let compressed: Uint8Array;
    try {
      compressed = ShareCodec.base64UrlDecode(encoded);
    } catch (err) {
      return Promise.reject(new Error(ShareCodeError.Base64Failed));
    }
    let rawBytes: Uint8Array;
    try {
      rawBytes = await ShareCodec.gzipDecompress(compressed);
    } catch (err) {
      return Promise.reject(new Error(ShareCodeError.GzipFailed));
    }
    if (rawBytes.length > MAX_DECOMPRESSED_BYTES) {
      return Promise.reject(new Error(ShareCodeError.DecompressedTooLarge));
    }
    const json: string = new util.TextDecoder().decodeToString(rawBytes);
    let payload: SharePayload;
    try {
      payload = JSON.parse(json) as SharePayload;
    } catch (err) {
      return Promise.reject(new Error(ShareCodeError.InvalidShape));
    }
    if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
      return Promise.reject(new Error(ShareCodeError.InvalidShape));
    }
    ShareCodec.validate(payload);
    const result: DecodedSharePayload = new DecodedSharePayload();
    result.tableName = payload.table.name;
    result.tableData = payload.table.data ?? '';
    result.courses = payload.courses ?? [];
    result.jsonBytes = rawBytes.length;
    result.compressedBytes = compressed.length;
    return result;
  }

  private static validate(payload: SharePayload): void {
    if (payload.t !== PAYLOAD_TYPE) {
      throw new Error(ShareCodeError.UnsupportedType);
    }
    const version: number = typeof payload.v === 'number' ? payload.v : parseInt(`${payload.v}`, 10);
    if (version !== 1 && version !== 2) {
      throw new Error(ShareCodeError.UnsupportedVersion);
    }
    if (payload.alg !== ALG_GZIP) {
      throw new Error(ShareCodeError.UnsupportedAlg);
    }
    if (payload.table === null || payload.table === undefined ||
      !Array.isArray(payload.courses) || payload.meta === null || payload.meta === undefined) {
      throw new Error(ShareCodeError.InvalidFields);
    }
    const tableName: string = payload.table.name === null || payload.table.name === undefined ?
      '' : `${payload.table.name}`;
    if (tableName === '') {
      throw new Error(ShareCodeError.MissingTableName);
    }
    for (let i = 0; i < payload.courses.length; i++) {
      const course: Object = payload.courses[i] as Object;
      if (course === null || typeof course !== 'object' || Array.isArray(course)) {
        throw new Error(ShareCodeError.InvalidFields);
      }
    }
    const dataForChecksum: string = JSON.stringify(
      new ChecksumEnvelope(tableName, payload.table.data ?? '', payload.courses)
    );
    const expected: string = ShareCodec.crc32Hex(dataForChecksum);
    const actual: string = payload.meta.checksum === null || payload.meta.checksum === undefined ?
      '' : `${payload.meta.checksum}`;
    if (actual !== expected) {
      throw new Error(ShareCodeError.ChecksumMismatch);
    }
  }

  private static extractSingleFrame(uri: string): string {
    const text: string = uri.trim();
    const prefix: string = `${SCHEME}://${HOST}/${VERSION_TAG}/s/`;
    if (!text.startsWith(prefix)) {
      throw new Error(ShareCodeError.NotShareCode);
    }
    return text.substring(prefix.length);
  }

  private static parseFrame(raw: string): FrameInfo | null {
    const text: string = raw.trim();
    const prefix: string = `${SCHEME}://${HOST}/${VERSION_TAG}/`;
    if (!text.startsWith(prefix)) {
      return null;
    }
    const rest: string = text.substring(prefix.length);
    const parts: string[] = rest.split('/');
    const info: FrameInfo = new FrameInfo();
    if (parts.length === 2 && parts[0] === 's') {
      info.isMulti = false;
      info.part = parts[1];
      return info;
    }
    if (parts.length === 5 && parts[0] === 'm') {
      if (!/^[+-]?\d+$/.test(parts[1]) || !/^[+-]?\d+$/.test(parts[2])) {
        return null;
      }
      const index: number = Number(parts[1]);
      const total: number = Number(parts[2]);
      const group: string = parts[3];
      const part: string = parts[4];
      if (!Number.isInteger(index) || !Number.isInteger(total) || group === '' || part === '') {
        return null;
      }
      info.isMulti = true;
      info.index = index;
      info.total = total;
      info.group = group;
      info.part = part;
      return info;
    }
    return null;
  }

  private static crc32Table(): number[] {
    const cached: number[] | null = ShareCodec.cachedTable;
    if (cached !== null) {
      return cached;
    }
    const table: number[] = [];
    for (let i = 0; i < 256; i++) {
      let c: number = i;
      for (let j = 0; j < 8; j++) {
        if ((c & 1) !== 0) {
          c = (0xEDB88320 ^ (c >>> 1)) >>> 0;
        } else {
          c = (c >>> 1) >>> 0;
        }
      }
      table.push(c >>> 0);
    }
    ShareCodec.cachedTable = table;
    return table;
  }

  private static cachedTable: number[] | null = null;

  private static base64UrlEncode(bytes: Uint8Array): string {
    const basic: string = new util.Base64Helper().encodeToStringSync(bytes);
    // 保留 `=` 填充：上游 Dart base64Url 解码按标准长度校验，去掉填充会导致扫码端 base64_decode_failed。
    return basic.replace(/\+/g, '-').replace(/\//g, '_');
  }

  private static base64UrlDecode(encoded: string): Uint8Array {
    let normalized: string = encoded.replace(/-/g, '+').replace(/_/g, '/');
    while (normalized.length % 4 !== 0) {
      normalized += '=';
    }
    return new util.Base64Helper().decodeSync(normalized);
  }

  /** 内存 gzip 压缩：windowBits = 15 + 16 表示 gzip 容器（RFC1952）。 */
  private static async gzipCompress(bytes: Uint8Array): Promise<Uint8Array> {
    const zip: zlib.Zip = zlib.createZipSync();
    const strm: zlib.ZStream = {};
    const source: ArrayBuffer = bytes.buffer.slice(
      bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    const bound: number = await zip.compressBound(source.byteLength);
    const buffer: ArrayBuffer = new ArrayBuffer(bound + 64);
    try {
      try {
        await zip.deflateInit2(strm, zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          zlib.CompressMethod.DEFLATED, 31, zlib.MemLevel.MEM_LEVEL_DEFAULT,
          zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY);
      } catch (initErr) {
        console.error(`[ShareCodec] deflateInit2 failed: ${JSON.stringify(initErr)}`);
        throw initErr as Error;
      }
      strm.nextIn = source;
      strm.availableIn = source.byteLength;
      strm.nextOut = buffer;
      strm.availableOut = buffer.byteLength;
      await zip.deflate(strm, zlib.CompressFlushMode.FINISH);
      // 流状态在 native 侧，必须重新 getZStream() 才能拿到 totalOut（官方 FAQ 明确）。
      const written: number = (await zip.getZStream()).totalOut ?? 0;
      const result: Uint8Array = new Uint8Array(buffer.slice(0, written));
      if (result.length < 2 || result[0] !== 0x1F || result[1] !== 0x8B) {
        throw new Error(ShareCodeError.GzipEncodeFailed);
      }
      return result;
    } finally {
      try {
        await zip.deflateEnd(strm);
      } catch (err) {
        console.warn(`[ShareCodec] deflateEnd failed: ${JSON.stringify(err)}`);
      }
    }
  }

  /** 内存 gzip 解压：gzip trailer 的 ISIZE 给出解压后长度，先据此分配缓冲。 */
  private static async gzipDecompress(bytes: Uint8Array): Promise<Uint8Array> {
    if (bytes.length < 18 || bytes[0] !== 0x1F || bytes[1] !== 0x8B) {
      throw new Error(ShareCodeError.GzipFailed);
    }
    const source: ArrayBuffer = bytes.buffer.slice(
      bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    const trailer: DataView = new DataView(source, source.byteLength - 4, 4);
    const size: number = trailer.getUint32(0, true);
    if (size <= 0 || size > MAX_DECOMPRESSED_BYTES) {
      throw new Error(ShareCodeError.DecompressedTooLarge);
    }
    const zip: zlib.Zip = zlib.createZipSync();
    const strm: zlib.ZStream = {};
    const buffer: ArrayBuffer = new ArrayBuffer(size + 1);
    try {
      await zip.inflateInit2(strm, 31);
      strm.nextIn = source;
      strm.availableIn = source.byteLength;
      strm.nextOut = buffer;
      strm.availableOut = buffer.byteLength;
      await zip.inflate(strm, zlib.CompressFlushMode.FINISH);
      const written: number = (await zip.getZStream()).totalOut ?? 0;
      return new Uint8Array(buffer.slice(0, written));
    } catch (err) {
      throw new Error(ShareCodeError.GzipFailed);
    } finally {
      try {
        await zip.inflateEnd(strm);
      } catch (err) {
        console.warn(`[ShareCodec] inflateEnd failed: ${JSON.stringify(err)}`);
      }
    }
  }
}

/** 多帧信息。 */
class FrameInfo {
  isMulti: boolean = false;
  index: number = 0;
  total: number = 0;
  group: string = '';
  part: string = '';
}

/** checksum 计算用的 JSON 包装，字段顺序必须与旧版一致：table 在前、courses 在后。 */
class ChecksumEnvelope {
  table: SharePayloadTable;
  courses: SharePayloadCourse[];

  constructor(tableName: string, tableData: string, courses: SharePayloadCourse[]) {
    this.table = new SharePayloadTable();
    this.table.name = tableName;
    this.table.data = tableData;
    this.courses = courses;
  }
}

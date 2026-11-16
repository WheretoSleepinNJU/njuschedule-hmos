// Node 侧 @kit.ArkTS 的最小替身：只覆盖被测纯逻辑用到的 util 接口。
export const util = {
  TextEncoder: class {
    encodeInto(text) {
      return new Uint8Array(Buffer.from(text, 'utf8'));
    }
  },
  TextDecoder: class {
    decodeToString(bytes) {
      return Buffer.from(bytes).toString('utf8');
    }
  },
  Base64Helper: class {
    encodeToStringSync(bytes) {
      return Buffer.from(bytes).toString('base64');
    }
    decodeSync(text) {
      return new Uint8Array(Buffer.from(text, 'base64'));
    }
  }
};

// 用 esbuild 把无 UI 依赖的 .ets 模块编译成 Node 可执行的 CJS。
// 只允许加入纯逻辑文件；涉及 @kit 的调用通过 test/stubs/ 最小替身隔离。
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { rmSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const outdir = path.join(root, 'test', '.build');
rmSync(outdir, { recursive: true, force: true });

await build({
  entryPoints: [
    'entry/src/main/ets/common/DateUtils.ets',
    'entry/src/main/ets/data/ShareCodec.ets',
    'entry/src/main/ets/features/import/SemesterStartResolver.ets'
  ].map((file) => path.join(root, file)),
  outdir,
  bundle: true,
  format: 'cjs',
  platform: 'node',
  outExtension: { '.js': '.cjs' },
  loader: { '.ets': 'ts' },
  resolveExtensions: ['.ets', '.ts', '.js', '.json'],
  alias: {
    '@kit.ArkTS': path.join(root, 'test/stubs/kit-arkts.mjs'),
    '@kit.BasicServicesKit': path.join(root, 'test/stubs/kit-basic-services.mjs'),
    '@kit.NetworkKit': path.join(root, 'test/stubs/kit-network.mjs')
  },
  logLevel: 'warning'
});
console.log('pure modules built');

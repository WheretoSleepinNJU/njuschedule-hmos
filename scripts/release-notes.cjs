'use strict';

const fs = require('node:fs');
const path = require('node:path');

const version = process.argv[2];
if (!version) {
  console.error('usage: node scripts/release-notes.cjs <version>');
  process.exit(1);
}

const changelog = fs.readFileSync(path.resolve(__dirname, '..', 'CHANGELOG.md'), 'utf8');
const lines = changelog.split(/\r?\n/);
const start = lines.findIndex((line) => line.startsWith(`## [${version}]`));
if (start < 0) {
  console.error(`CHANGELOG.md 缺少 ## [${version}] 版本章节`);
  process.exit(1);
}
let end = lines.length;
for (let i = start + 1; i < lines.length; i++) {
  if (/^## \[/.test(lines[i])) {
    end = i;
    break;
  }
}
const section = lines.slice(start, end).join('\n').trim();
const artifact = `njuschedule-hmos-${version}-unsigned.hap`;

process.stdout.write(`${section}

## 安装说明

- 本 Release 提供**未签名 HAP**：\`${artifact}\`；
- 未签名 HAP 不能直接安装，仅供检查或自行签名后使用；
- 正式安装包通过 AppGallery 分发。

## 版本

- versionName: \`${version}\`
- versionCode: \`${JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', 'AppScope', 'app.json5'), 'utf8')).app.versionCode}\`
`);

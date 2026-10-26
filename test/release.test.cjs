'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const APP_JSON = path.join(ROOT, 'AppScope', 'app.json5');
const CHANGELOG = path.join(ROOT, 'CHANGELOG.md');
const FALLBACK_FILES = [
  'entry/src/main/ets/features/settings/AboutPage.ets',
  'entry/src/main/ets/features/settings/OpenSourceLicensesPage.ets',
];

const app = JSON.parse(fs.readFileSync(APP_JSON, 'utf8')).app;
const version = app.versionName;
const [major, minor, patch] = version.split('.').map((part) => Number.parseInt(part, 10));
const expectedCode = 1000000 + major * 10000 + minor * 100 + patch;

test('versionCode follows the documented formula', () => {
  assert.equal(app.versionCode, expectedCode, `expected ${expectedCode} for ${version}`);
  assert.ok(Number.isInteger(app.versionCode) && app.versionCode > 0);
});

test('About and license fallback versions match AppScope', () => {
  for (const relative of FALLBACK_FILES) {
    const source = fs.readFileSync(path.join(ROOT, relative), 'utf8');
    const match = source.match(/const FALLBACK_VERSION: string = '([^']+)'/);
    assert.ok(match, `${relative} missing FALLBACK_VERSION`);
    assert.equal(match[1], version, `${relative} fallback version mismatch`);
  }
});

test('CHANGELOG contains the current version section', () => {
  const changelog = fs.readFileSync(CHANGELOG, 'utf8');
  assert.match(changelog, new RegExp(`^## \\[${version.replaceAll('.', '\\.')}\\]`, 'm'));
});

test('tag matches version when running for a tag', () => {
  if (process.env.GITHUB_REF_TYPE !== 'tag') {
    return;
  }
  assert.equal(process.env.GITHUB_REF_NAME, `v${version}`, 'tag and AppScope version differ');
});

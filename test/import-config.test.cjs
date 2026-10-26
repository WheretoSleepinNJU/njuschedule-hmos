'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const IMPORT_DIR = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'import');
const TOOLS_DIR = path.join(IMPORT_DIR, 'tools');
const SCHOOL_LIST = path.join(IMPORT_DIR, 'schoolList.json');

const config = JSON.parse(fs.readFileSync(SCHOOL_LIST, 'utf8'));
const entries = Array.isArray(config.data) ? config.data : [];

test('school list is non-empty', () => {
  assert.ok(entries.length > 0, 'schoolList.json data is empty');
});

test('every school entry has a usable identity and URL', () => {
  const titles = new Set();
  for (const entry of entries) {
    assert.equal(typeof entry.title, 'string');
    assert.ok(entry.title.trim().length > 0);
    assert.ok(!titles.has(entry.title), `duplicate title: ${entry.title}`);
    titles.add(entry.title);

    assert.equal(typeof entry.pinyin, 'string');
    assert.ok(entry.pinyin.trim().length > 0);
    assert.equal(typeof entry.initialUrl, 'string');
    assert.ok(entry.initialUrl.startsWith('http'), `${entry.title}: initialUrl is not HTTP(S)`);
    assert.equal(typeof entry.delayTime, 'number');
    assert.ok(entry.delayTime >= 0);
    assert.equal(typeof entry['isGrey3.1.0'], 'boolean');
  }
});

test('every local tool reference exists in rawfile tools', () => {
  const available = new Set(fs.readdirSync(TOOLS_DIR).filter((name) => name.endsWith('.js')));
  for (const entry of entries) {
    const url = entry.extractJSfileOHOS;
    if (typeof url !== 'string' || url.trim() === '') {
      continue;
    }
    const name = path.basename(url.split('?')[0].split('#')[0]);
    assert.ok(available.has(name), `${entry.title}: missing tool ${name}`);
  }
});

test('all bundled import scripts parse as JavaScript', () => {
  for (const name of fs.readdirSync(TOOLS_DIR).filter((file) => file.endsWith('.js'))) {
    const source = fs.readFileSync(path.join(TOOLS_DIR, name), 'utf8');
    assert.doesNotThrow(() => new Function(source), `${name} has invalid JavaScript syntax`);
  }
});

test('optional semester start dates are valid', () => {
  for (const entry of entries) {
    const value = entry.semester_start_monday;
    if (typeof value !== 'string' || value === '') {
      continue;
    }
    assert.match(value, /^\d{4}-\d{2}-\d{2}$/, `${entry.title}: invalid semester_start_monday`);
  }
});

test('optional class time lists have start/end pairs', () => {
  for (const entry of entries) {
    const periods = entry.class_time_list;
    if (periods === undefined) {
      continue;
    }
    assert.ok(Array.isArray(periods), `${entry.title}: class_time_list is not an array`);
    for (const period of periods) {
      assert.match(period.start, /^\d{2}:\d{2}$/, `${entry.title}: invalid class start`);
      assert.match(period.end, /^\d{2}:\d{2}$/, `${entry.title}: invalid class end`);
    }
  }
});

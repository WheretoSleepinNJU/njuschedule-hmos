// 纯逻辑单测：覆盖分享码 CRC/帧协议、日期工具、学期周一校验。
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { DateUtils } = require('../.build/common/DateUtils.cjs');
const { ShareCodec } = require('../.build/data/ShareCodec.cjs');
const { SemesterStartResolver } = require('../.build/features/import/SemesterStartResolver.cjs');

test('DateUtils: 格式与解析', () => {
  assert.equal(DateUtils.pad2(3), '03');
  assert.equal(DateUtils.formatIsoDate(new Date(2026, 0, 5)), '2026-01-05');
  assert.equal(DateUtils.parseIsoDate('2026-01-05').getMonth(), 0);
  assert.equal(DateUtils.formatMonthDay(new Date(2026, 10, 16)), '11/16');
  assert.equal(DateUtils.formatHm(new Date(2026, 10, 16, 8, 5)), '08:05');
  assert.equal(DateUtils.weekdayOneBased(new Date(2026, 10, 16)), 1);
});

test('DateUtils: 周一与跨日计算', () => {
  const sunday = new Date(2026, 10, 15);
  assert.equal(DateUtils.formatIsoDate(DateUtils.mondayOf(sunday)), '2026-11-09');
  assert.equal(DateUtils.daysBetween(new Date(2026, 10, 9), new Date(2026, 10, 16)), 7);
  assert.equal(DateUtils.formatIsoDate(DateUtils.addDays(new Date(2026, 10, 16), -1)), '2026-11-15');
});

test('ShareCodec: CRC32 标准向量', () => {
  assert.equal(ShareCodec.crc32Hex('123456789'), 'cbf43926');
  assert.equal(ShareCodec.crc32Hex(''), '00000000');
  assert.equal(ShareCodec.crc32(new Uint8Array([])), 0);
});

test('ShareCodec: 分享码前缀与帧解析', () => {
  assert.equal(ShareCodec.isShareCode('ncs://qr/v2/s/abc'), true);
  assert.equal(ShareCodec.isShareCode('ncs://qr/v1/s/abc'), false);

  const single = ShareCodec.frameOf('ncs://qr/v2/s/abc');
  assert.notEqual(single, null);
  assert.equal(single.isMulti, false);

  const multi = ShareCodec.frameOf('ncs://qr/v2/m/1/2/groupA/part1');
  assert.notEqual(multi, null);
  assert.equal(multi.isMulti, true);
  assert.equal(multi.index, 1);
  assert.equal(multi.total, 2);
  assert.equal(multi.group, 'groupA');
  assert.equal(ShareCodec.frameOf('ncs://qr/v2/m/x/2/groupA/part1'), null);
});

test('ShareCodec: 多帧合并只认组号与序号', () => {
  const complete = new Map([
    ['a', 'ncs://qr/v2/m/1/2/groupA/AAA'],
    ['b', 'ncs://qr/v2/m/2/2/groupA/BBB']
  ]);
  assert.equal(ShareCodec.mergeFrames(complete), 'ncs://qr/v2/s/AAABBB');

  const partial = new Map([['a', 'ncs://qr/v2/m/1/2/groupA/AAA']]);
  assert.equal(ShareCodec.mergeFrames(partial), null);

  const wrongGroup = new Map([
    ['a', 'ncs://qr/v2/m/1/2/groupA/AAA'],
    ['b', 'ncs://qr/v2/m/2/2/groupB/BBB']
  ]);
  assert.equal(ShareCodec.mergeFrames(wrongGroup), null);

  assert.equal(ShareCodec.mergeFrames(new Map([['s', 'ncs://qr/v2/s/abc']])), null);
});

test('ShareCodec: 长内容拆分与合并可往返', () => {
  const payload = 'A'.repeat(900);
  const code = `ncs://qr/v2/s/${payload}`;
  const frames = ShareCodec.splitQrFrames(code, 'fixedGroup');
  assert.ok(frames.length > 1);
  for (const frame of frames) {
    assert.ok(frame.length <= 500);
  }
  const collected = new Map(frames.map((frame, index) => [`${index}`, frame]));
  assert.equal(ShareCodec.mergeFrames(collected), code);
});

test('SemesterStartResolver: 学期开始周一校验', () => {
  assert.equal(SemesterStartResolver.isValidMonday('2026-09-07'), true);
  assert.equal(SemesterStartResolver.isValidMonday('2026-09-08'), false);
  assert.equal(SemesterStartResolver.isValidMonday('2026/09/07'), false);
  assert.equal(SemesterStartResolver.fromTableData('{"semester_start_monday":"2026-09-07"}'), '2026-09-07');
  assert.equal(SemesterStartResolver.fromTableData('{"semester_start_monday":"2026-09-08"}'), '');
  assert.equal(SemesterStartResolver.fromTableData('not-json'), '');
});

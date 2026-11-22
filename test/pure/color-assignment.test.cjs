// 色池分配：同一课表内先不放回抽满一轮，再进入下一轮。
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { ColorAssignment } = require('../.build/data/ColorAssignment.cjs');

const POOL = Array.from({ length: 14 }, (_, i) => i);

function course(tableId, courseId) {
  return { tableId, courseId };
}

function coursesOf(tableId, ids) {
  return ids.map((id) => course(tableId, id));
}

function colorsOf(assignments, tableId, ids) {
  return ids.map((id) => ColorAssignment.colorOf(assignments, course(tableId, id)));
}

test('ColorAssignment: 前一轮 14 门课颜色不重复', () => {
  const ids = Array.from({ length: 14 }, (_, i) => i + 1);
  const assignments = ColorAssignment.build(coursesOf(7, ids), POOL, 123456);
  const colors = colorsOf(assignments, 7, ids);
  assert.equal(new Set(colors).size, 14);
  for (const color of colors) {
    assert.ok(color >= 0 && color < POOL.length);
  }
});

test('ColorAssignment: 第 15 门进入下一轮且本轮仍不重复', () => {
  const firstRound = Array.from({ length: 14 }, (_, i) => i + 1);
  const secondRound = Array.from({ length: 6 }, (_, i) => i + 15);
  const assignments = ColorAssignment.build(coursesOf(7, firstRound.concat(secondRound)), POOL, 42);
  const firstColors = colorsOf(assignments, 7, firstRound);
  const secondColors = colorsOf(assignments, 7, secondRound);
  assert.equal(new Set(firstColors).size, 14);
  assert.equal(new Set(secondColors).size, 6);
});

test('ColorAssignment: 新增高 courseId 不改变已有课程颜色', () => {
  const base = Array.from({ length: 10 }, (_, i) => i + 1);
  const before = ColorAssignment.build(coursesOf(3, base), POOL, 99);
  const after = ColorAssignment.build(coursesOf(3, base.concat([11, 12])), POOL, 99);
  assert.deepEqual(colorsOf(after, 3, base), colorsOf(before, 3, base));
});

test('ColorAssignment: 不同课表分开计算轮次', () => {
  const ids = [1, 2, 3];
  const assignments = ColorAssignment.build(coursesOf(1, ids).concat(coursesOf(2, ids)), POOL, 5);
  assert.equal(new Set(colorsOf(assignments, 1, ids)).size, 3);
  assert.equal(new Set(colorsOf(assignments, 2, ids)).size, 3);
});

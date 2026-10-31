// اجرای آزمون‌ها: node --test tests/
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPlan, dayCapacity, currentPhase, coverage, stepMinutes, unitList } from '../js/lib/planner.js';
import { DEFAULT_CATALOG, STEPS } from '../js/data/curriculum.js';
import { addDays } from '../js/lib/jalali.js';
import { review, newSrs, isDue } from '../js/lib/srs.js';

const TODAY = '2026-10-31';
const profile = (over = {}) => ({
  target_stage: 1,
  exam_dates: { 1: '2027-02-04', 2: '2027-04-17', 3: '2027-07-23' },
  daily_minutes: { base: 180 },
  levels: {},
  settings: {},
  ...over,
});
const at = (key, h = 10) => new Date(`${key}T${String(h).padStart(2, '0')}:00:00`).toISOString();

test('capacity respects base, perDay, off days and overrides', () => {
  const p = profile({ daily_minutes: { base: 100, perDay: [60, 60, 60, 60, 60, 60, 0] }, settings: { offDays: ['2026-11-02'], dayOverrides: { '2026-11-03': 15 } } });
  assert.equal(dayCapacity(p, '2026-10-31'), 60);       // شنبه
  assert.equal(dayCapacity(p, '2026-11-06'), 0);        // جمعه
  assert.equal(dayCapacity(p, '2026-11-02'), 0);        // تعطیل
  assert.equal(dayCapacity(p, '2026-11-03'), 15);       // استثنا
});

test('phase selection moves to stage 2 after stage 1 date', () => {
  const p = profile({ target_stage: 3 });
  assert.equal(currentPhase(p, DEFAULT_CATALOG, TODAY).stage, 1);
  assert.equal(currentPhase(p, DEFAULT_CATALOG, '2027-02-05').stage, 2);
  assert.equal(currentPhase(p, DEFAULT_CATALOG, '2027-05-01').stage, 3);
  assert.equal(currentPhase(profile(), DEFAULT_CATALOG, '2027-03-01'), null);
});

test('plan never exceeds daily capacity and covers days until exam', () => {
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: profile(), progress: [], prefs: {}, today: TODAY });
  assert.equal(plan.days.length, 96);
  for (const d of plan.days) {
    const sum = d.tasks.reduce((s, t) => s + t.minutes, 0);
    assert.ok(sum <= d.capacity, `day ${d.key} over capacity ${sum}>${d.capacity}`);
    assert.equal(sum, d.used, `used mismatch on ${d.key}`);
  }
  assert.ok(plan.phase.reviewDays >= 3);
});

test('every remaining step is scheduled exactly once in total minutes (when capacity suffices)', () => {
  const p = profile({ daily_minutes: { base: 600 } });
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: [], prefs: {}, today: TODAY });
  assert.equal(plan.unscheduled.length, 0);
  const scheduled = new Map();
  for (const d of plan.days) for (const t of d.tasks) if (t.kind === 'step' && !t.stretch) {
    const k = `${t.unitId}|${t.step}`;
    scheduled.set(k, (scheduled.get(k) || 0) + t.minutes);
  }
  const units = unitList(DEFAULT_CATALOG).filter((u) => u.stages.includes(1));
  for (const u of units) for (const s of STEPS) {
    assert.equal(scheduled.get(`${u.id}|${s.id}`), stepMinutes(u, s.id, p, {}), `${u.id}|${s.id}`);
  }
  assert.notEqual(plan.status.level, 'behind');
});

test('steps of a unit keep order and review is ≥3 days after test', () => {
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: profile({ daily_minutes: { base: 300 } }), progress: [], prefs: {}, today: TODAY });
  const firstDay = {}, lastDay = {};
  plan.days.forEach((d, i) => d.tasks.forEach((t) => {
    if (t.kind !== 'step') return;
    const k = `${t.unitId}|${t.step}`;
    if (!(k in firstDay)) firstDay[k] = i;
    lastDay[k] = i;
  }));
  const order = STEPS.map((s) => s.id);
  const units = new Set(Object.keys(firstDay).map((k) => k.split('|')[0]));
  for (const u of units) {
    for (let i = 1; i < order.length; i++) {
      const a = `${u}|${order[i - 1]}`, b = `${u}|${order[i]}`;
      if (a in lastDay && b in firstDay) assert.ok(firstDay[b] >= lastDay[a], `${b} before ${a}`);
    }
    const t = `${u}|test`, r = `${u}|review`;
    if (t in lastDay && r in firstDay) assert.ok(firstDay[r] - lastDay[t] >= 3, `review too soon for ${u}`);
  }
});

test('low capacity → behind with unscheduled work and neededPerDay > capacity', () => {
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: profile({ daily_minutes: { base: 30 } }), progress: [], prefs: {}, today: TODAY });
  assert.equal(plan.status.level, 'behind');
  assert.ok(plan.unscheduled.length > 0);
  assert.ok(plan.status.neededPerDay > 30);
});

test('completed steps (before today) are excluded; steps done today stay on today list', () => {
  const p = profile();
  const base = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: [], prefs: {}, today: TODAY });
  const firstTask = base.days[0].tasks[0];
  const doneYesterday = [{ unit_id: firstTask.unitId, step: firstTask.step, done_at: at(addDays(TODAY, -1)) }];
  const p2 = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: doneYesterday, prefs: {}, today: TODAY });
  assert.ok(!p2.days.some((d) => d.tasks.some((t) => t.unitId === firstTask.unitId && t.step === firstTask.step)));

  const doneToday = [{ unit_id: firstTask.unitId, step: firstTask.step, done_at: at(TODAY) }];
  const p3 = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: doneToday, prefs: {}, today: TODAY });
  assert.deepEqual(p3.days[0].tasks.map((t) => t.unitId + t.step), base.days[0].tasks.map((t) => t.unitId + t.step));
});

test('a task done today that was planned for a future day moves to today', () => {
  const p = profile();
  const base = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: [], prefs: {}, today: TODAY });
  const future = base.days[10].tasks.find((t) => t.kind === 'step');
  const prog = [{ unit_id: future.unitId, step: future.step, done_at: at(TODAY) }];
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: prog, prefs: {}, today: TODAY });
  assert.ok(plan.days[0].tasks.some((t) => t.unitId === future.unitId && t.step === future.step && t.extra));
  assert.ok(!plan.days.slice(1).some((d) => d.tasks.some((t) => t.unitId === future.unitId && t.step === future.step)));
});

test('skipped units and disabled video reduce workload', () => {
  const p = profile();
  const a = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: [], prefs: {}, today: TODAY });
  const b = buildPlan({ catalog: DEFAULT_CATALOG, profile: profile({ settings: { useVideo: false } }), progress: [], prefs: { 'econ10-1': { skip: true } }, today: TODAY });
  assert.ok(b.status.requiredLearn < a.status.requiredLearn);
  assert.ok(!b.days.some((d) => d.tasks.some((t) => t.step === 'video' || t.unitId === 'econ10-1')));
});

test('changing exam date reflows plan length', () => {
  const p = profile({ exam_dates: { 1: addDays(TODAY, 20) } });
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: [], prefs: {}, today: TODAY });
  assert.equal(plan.days.length, 20);
  assert.equal(plan.days.filter((d) => d.kind === 'review').length, 3);
});

test('exam day and very short horizons do not crash', () => {
  for (const n of [0, 1, 2, 3, 4, 5]) {
    const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: profile({ exam_dates: { 1: addDays(TODAY, n) } }), progress: [], prefs: {}, today: TODAY });
    assert.equal(plan.days.length, n);
  }
});

test('coverage is 0 → 100 and weighted by minutes', () => {
  const p = profile();
  assert.equal(coverage(DEFAULT_CATALOG, p, [], {}, 1).percent, 0);
  const all = [];
  for (const u of unitList(DEFAULT_CATALOG).filter((x) => x.stages.includes(1))) for (const s of STEPS) all.push({ unit_id: u.id, step: s.id, done_at: at('2026-10-01') });
  const c = coverage(DEFAULT_CATALOG, p, all, {}, 1);
  assert.ok(Math.abs(c.percent - 100) < 1e-9);
  const plan = buildPlan({ catalog: DEFAULT_CATALOG, profile: p, progress: all, prefs: {}, today: TODAY });
  assert.equal(plan.unscheduled.length, 0);
  assert.equal(plan.status.requiredLearn, 0);
});

test('weak level increases minutes', () => {
  const u = unitList(DEFAULT_CATALOG)[0];
  assert.ok(stepMinutes(u, 'read', profile({ levels: { econ: 1 } }), {}) > stepMinutes(u, 'read', profile({ levels: { econ: 3 } }), {}));
});

test('srs: intervals grow on success and reset on failure', () => {
  let s = newSrs('2026-10-31');
  assert.ok(isDue(s, '2026-10-31'));
  s = review(s, 2, '2026-10-31'); assert.equal(s.interval, 1);
  s = review(s, 2, '2026-11-01'); assert.equal(s.interval, 3);
  s = review(s, 2, '2026-11-04'); assert.ok(s.interval > 3);
  const before = s.interval;
  s = review(s, 0, '2026-11-20'); assert.equal(s.interval, 0); assert.ok(s.ease < 2.5);
  assert.ok(before > 0);
  assert.ok(isDue(s, '2026-11-20'));
});

import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

// node tests/race-api.mjs [--only=core,draw,disconnect,forfeit]
// Four rooms at most per full run. Never contacts the public deployment.
const base = new URL(process.env.RACE_API_BASE ?? 'http://127.0.0.1:5188');
if (base.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname) || base.username || base.password) {
  throw new Error('Race API tests are restricted to an HTTP loopback server.');
}
const available = ['core', 'draw', 'disconnect', 'forfeit'];
const selection = process.argv.find(value => value.startsWith('--only='))?.slice(7).split(',') ?? available;
if (selection.length === 0 || selection.some(value => !available.includes(value)) || new Set(selection).size !== selection.length) {
  throw new Error('Choose --only=core,draw,disconnect,forfeit without duplicates.');
}
const results = [];
const fixtures = new Map();
const startedAt = Date.now();
let createdRooms = 0;

function check(condition, label, detail = '') {
  results.push({ pass: Boolean(condition), label, ...(condition || !detail ? {} : { detail }) });
  console.log(`[${condition ? 'PASS' : 'FAIL'}] ${label}${condition || !detail ? '' : `: ${detail}`}`);
}

async function request(path, { method = 'GET', token, body, headers = {} } = {}) {
  const response = await fetch(new URL(path, base), {
    method,
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(10_000),
  });
  const data = await response.json();
  return { status: response.status, data, cache: response.headers.get('cache-control') };
}

const endpoint = fixture => `/api/rooms/${fixture.code}`;
const player = (snapshot, client) => snapshot.players.find(value => value.id === client.id);
const post = (fixture, client, body) => request(endpoint(fixture), { method: 'POST', token: client?.token, body: { rulesVersion: 'endless_race_v4', ...body } });
const get = (fixture, client) => request(endpoint(fixture), { token: client?.token });
function requireSuccess(response, expected, label) {
  if (response.status !== expected) throw new Error(`${label}: expected HTTP ${expected}, got ${response.status} (${response.data.error ?? 'unexpected response'})`);
  return response.data;
}

async function createFixture(name) {
  if (createdRooms >= 4) throw new Error('Per-run room budget exhausted.');
  const created = requireSuccess(await request('/api/rooms', { method: 'POST', body: { name: `测试甲-${name}`, rulesVersion: 'endless_race_v4' } }), 201, 'create');
  createdRooms += 1;
  const fixture = { name, code: created.room.code, seed: created.room.seed, a: { token: created.token, id: created.room.selfId, instance: randomUUID(), seq: 0 } };
  check(created.room.phase === 'waiting' && created.room.players.length === 1 && /^[A-HJ-NP-Z2-9]{7}$/.test(fixture.code), `${name}: create opens a one-player waiting room`);
  const joined = requireSuccess(await post(fixture, null, { action: 'join', name: `测试乙-${name}` }), 200, 'join');
  fixture.b = { token: joined.token, id: joined.room.selfId, instance: randomUUID(), seq: 0 };
  check(joined.room.seed === fixture.seed && joined.room.players.length === 2 && fixture.a.id !== fixture.b.id && fixture.a.token !== fixture.b.token, `${name}: separate clients join one shared seed with distinct credentials`);
  fixtures.set(name, fixture);
  return fixture;
}

async function readyAndStart(fixture) {
  const first = requireSuccess(await post(fixture, fixture.a, { action: 'ready', instanceId: fixture.a.instance }), 200, 'first ready');
  check(first.phase === 'waiting' && player(first, fixture.a).ready && !player(first, fixture.b).ready, `${fixture.name}: one ready client cannot start the opponent`);
  const second = requireSuccess(await post(fixture, fixture.b, { action: 'ready', instanceId: fixture.b.instance }), 200, 'second ready');
  fixture.startAt = second.startAt;
  check(second.phase === 'running' && second.startAt - second.serverNow >= 4500 && second.startAt - second.serverNow <= 5100, `${fixture.name}: both ready clients receive one server-owned five-second countdown`);
  const premature = requireSuccess(await heartbeat(fixture, fixture.a, { seq: 9999, elapsed: 9999, kills: 9999 }), 200, 'premature heartbeat');
  check(player(premature, fixture.a).elapsed === 0 && player(premature, fixture.a).kills === 0, `${fixture.name}: countdown reports cannot earn survival time or kills`);
  await sleep(Math.max(0, second.startAt - second.serverNow) + 150);
  return second;
}

function heartbeat(fixture, client, fields = {}) {
  const seq = fields.seq ?? ++client.seq;
  return post(fixture, client, { action: 'heartbeat', instanceId: client.instance, seq, status: 'alive', elapsed: 0, kills: 0, health: 1, ...fields });
}

async function core(fixture) {
  const third = await post(fixture, null, { action: 'join', name: '第三人' });
  check(third.status === 409, 'core: a third player is rejected');
  check((await get(fixture, null)).status === 401, 'core: room reads require membership credentials');
  check((await request(endpoint(fixture), { token: randomUUID() })).status === 401, 'core: an unrelated token cannot read room state');
  check((await post(fixture, null, { action: 'leave', playerId: fixture.a.id })).status === 401, 'core: a player id alone cannot modify membership');
  const another = [...fixtures.values()].find(value => value !== fixture);
  if (another) {
    check((await request(endpoint(another), { token: fixture.a.token })).status === 401, 'core: a valid token is restricted to its original room');
    check((await request(endpoint(another), { method: 'POST', token: fixture.a.token, body: { action: 'leave' } })).status === 401, 'core: cross-room credentials cannot forfeit another player');
  }
  const identity = requireSuccess(await get(fixture, fixture.a), 200, 'identity read');
  check(identity.selfId === fixture.a.id && identity.players.every(value => !('token' in value) && !('token_hash' in value) && !('instance_id' in value)), 'core: snapshots expose public players but no peer secrets');
  check((await get(fixture, fixture.b)).cache?.includes('no-store'), 'core: authenticated snapshots cannot be cached');
  check((await post(fixture, fixture.a, { action: 'ready', instanceId: 'bad' })).status === 400, 'core: malformed instance ids are rejected');
  check((await post(fixture, fixture.a, { action: 'ready', instanceId: fixture.a.instance, rulesVersion: 'endless_race_v1' })).status === 409, 'core: old map and objective rules cannot join the new game');
  check((await post(fixture, fixture.a, { action: 'heartbeat', rulesVersion: undefined })).status === 409, 'core: unversioned clients cannot submit survival time');
  requireSuccess(await post(fixture, fixture.a, { action: 'ready', instanceId: fixture.a.instance }), 200, 'bind instance');
  check((await post(fixture, fixture.a, { action: 'ready', instanceId: randomUUID() })).status === 409, 'core: a second page cannot replace the bound ready instance');
  check((await heartbeat(fixture, fixture.a, { instanceId: randomUUID() })).status === 409, 'core: heartbeat credentials cannot bypass the bound page instance');
  await readyAndStart(fixture);
  await sleep(250);
  let snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: 0.3, kills: 3, health: 0.7, playerId: fixture.b.id }), 200, 'first real report');
  check(player(snapshot, fixture.a).elapsed === 0.3 && player(snapshot, fixture.a).kills === 3 && player(snapshot, fixture.b).elapsed === 0, 'core: body playerId cannot redirect a report to the opponent');
  snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: 1e12, kills: 3 }), 200, 'large elapsed');
  const accepted = player(snapshot, fixture.a).elapsed;
  check(accepted <= (snapshot.serverNow - snapshot.startAt) / 1000 + 0.01 && accepted < 10, 'core: reported survival is capped by actual server wall time');
  snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: -1, kills: -500 }), 200, 'negative counters');
  check(player(snapshot, fixture.a).elapsed === accepted && player(snapshot, fixture.a).kills === 3, 'core: time and kills cannot roll backward');
  const latestSeq = fixture.a.seq;
  for (const [kind, seq] of [['duplicate', latestSeq], ['stale', latestSeq - 1], ['fractional', latestSeq + 0.5]]) {
    const unchanged = requireSuccess(await heartbeat(fixture, fixture.a, { seq, status: 'dead', elapsed: 1e12, kills: 9999 }), 200, kind);
    check(player(unchanged, fixture.a).status === 'alive' && player(unchanged, fixture.a).kills === 3 && player(unchanged, fixture.a).elapsed === accepted, `core: ${kind} sequences cannot change score or terminal state`);
  }
  await sleep(300);
  snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { status: 'reward', elapsed: accepted, kills: 3 }), 200, 'reward report');
  check(player(snapshot, fixture.a).elapsed === accepted && player(snapshot, fixture.a).status === 'reward', 'core: reward heartbeat remains connected without adding score');
  requireSuccess(await heartbeat(fixture, fixture.b, { elapsed: 0 }), 200, 'opponent live');
  snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { status: 'dead', elapsed: accepted, kills: 3, health: 0 }), 200, 'death');
  check(player(snapshot, fixture.a).status === 'dead' && snapshot.phase === 'running', 'core: death freezes one score while a trailing survivor may continue');
  snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { status: 'alive', elapsed: 1e12, kills: 9999, health: 1 }), 200, 'resurrection attempt');
  check(player(snapshot, fixture.a).status === 'dead' && player(snapshot, fixture.a).elapsed === accepted && player(snapshot, fixture.a).health === 0, 'core: a higher sequence cannot resurrect a dead player');
  check((await post(fixture, fixture.a, { action: 'ready', instanceId: randomUUID() })).status === 409, 'core: a dead player cannot reopen the match in a refreshed page');
  await sleep(1000);
  snapshot = requireSuccess(await heartbeat(fixture, fixture.b, { elapsed: accepted + 0.2 }), 200, 'winner exceeds dead score');
  check(snapshot.phase === 'finished' && snapshot.result?.winner === fixture.b.id && snapshot.result?.draw === false, 'core: survivor wins once effective time exceeds the frozen opponent score');
  const finalScore = player(snapshot, fixture.b).elapsed;
  snapshot = requireSuccess(await heartbeat(fixture, fixture.b, { status: 'dead', elapsed: 1e12, kills: 5000, health: 0 }), 200, 'finished write');
  check(snapshot.phase === 'finished' && snapshot.result?.winner === fixture.b.id && player(snapshot, fixture.b).elapsed === finalScore && player(snapshot, fixture.b).status === 'alive', 'core: finished rooms cannot accept new score or change their winner');
  check((await post(fixture, null, { action: 'join', name: '赛后进入' })).status === 409, 'core: finished rooms cannot accept a new entrant');
}

async function draw(fixture) {
  await readyAndStart(fixture);
  await sleep(250);
  requireSuccess(await heartbeat(fixture, fixture.a, { status: 'dead', elapsed: 0.2, health: 0 }), 200, 'first equal death');
  const snapshot = requireSuccess(await heartbeat(fixture, fixture.b, { status: 'dead', elapsed: 0.2, health: 0 }), 200, 'second equal death');
  check(snapshot.phase === 'finished' && snapshot.result?.draw === true && snapshot.result?.winner === null, 'draw: equal effective survival produces a stable draw');
  const again = requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: 9999, status: 'alive' }), 200, 'draw replay');
  check(again.result?.draw === true && player(again, fixture.a).status === 'dead', 'draw: terminal replay cannot break the draw');
}

async function forfeit(fixture) {
  await readyAndStart(fixture);
  await sleep(700);
  requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: 0.6 }), 200, 'leader score');
  requireSuccess(await heartbeat(fixture, fixture.b, { elapsed: 0.1 }), 200, 'trailing score');
  const snapshot = requireSuccess(await post(fixture, fixture.a, { action: 'leave' }), 200, 'leader forfeits');
  check(player(snapshot, fixture.a).status === 'forfeit', 'forfeit: leaving an active game records an irreversible forfeit');
  check(snapshot.phase === 'finished' && snapshot.result?.winner === fixture.b.id, 'forfeit: deliberate abandonment loses even when the abandoner had a higher score', `phase=${snapshot.phase}, result=${JSON.stringify(snapshot.result)}`);
  const again = requireSuccess(await heartbeat(fixture, fixture.b, { elapsed: 0.1, status: 'dead', health: 0 }), 200, 'trailing player stops');
  check(again.result?.winner === fixture.b.id && player(again, fixture.a).status === 'forfeit', 'forfeit: the abandoned leader cannot become winner after the other player stops', JSON.stringify(again.result));
}

async function disconnect(fixture) {
  await readyAndStart(fixture);
  requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: 0.1 }), 200, 'connected player');
  const initial = requireSuccess(await heartbeat(fixture, fixture.b, { elapsed: 0.1 }), 200, 'last disconnected report');
  const deadline = Date.now() + 30_500;
  let snapshot = initial;
  let preDeadlineChecked = false;
  console.log('[WAIT] disconnect: retaining one live client while the other is silent for 30 seconds');
  while (Date.now() < deadline) {
    await sleep(Math.min(2000, deadline - Date.now()));
    snapshot = requireSuccess(await heartbeat(fixture, fixture.a, { elapsed: Math.max(0.1, (Date.now() - fixture.startAt) / 1000 - 0.2) }), 200, 'healthy heartbeat');
    const silentFor = snapshot.serverNow - initial.serverNow;
    if (!preDeadlineChecked && silentFor > 26_000 && silentFor < 29_500) {
      check(player(snapshot, fixture.b).status === 'alive' && snapshot.phase === 'running', 'disconnect: less than thirty silent seconds does not prematurely forfeit');
      preDeadlineChecked = true;
    }
  }
  snapshot = requireSuccess(await get(fixture, fixture.a), 200, 'disconnect resolution');
  check(player(snapshot, fixture.b).status === 'disconnected' && snapshot.phase === 'finished' && snapshot.result?.winner === fixture.a.id, 'disconnect: thirty seconds of silence forfeits the absent client while the live peer wins');
  const retry = requireSuccess(await heartbeat(fixture, fixture.b, { seq: 999_999, elapsed: 999_999, status: 'alive' }), 200, 'late reconnect');
  check(player(retry, fixture.b).status === 'disconnected' && player(retry, fixture.b).elapsed === 0.1 && retry.result?.winner === fixture.a.id, 'disconnect: reconnect cannot restore life, add time, or change the completed result');
}

try {
  for (const name of selection) await createFixture(name);
  const cases = { core, draw, disconnect, forfeit };
  const outcomes = await Promise.allSettled(selection.map(name => cases[name](fixtures.get(name))));
  outcomes.forEach((outcome, index) => {
    if (outcome.status === 'rejected') check(false, `${selection[index]}: scenario completed without transport/setup error`, String(outcome.reason));
  });
} catch (error) {
  check(false, 'test setup', String(error));
}
const report = {
  base: base.origin, createdRooms, durationMs: Date.now() - startedAt,
  rooms: [...fixtures.values()].map(({ name, code }) => ({ name, code })),
  passed: results.filter(value => value.pass).length,
  failed: results.filter(value => !value.pass).length,
  results,
};
const output = resolve('build/test-runtime/race-api-results.json');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify(report, null, 2));
console.log(`RACE_API: ${report.failed ? 'FAIL' : 'PASS'} (${report.passed} passed, ${report.failed} failed; ${createdRooms} rooms; ${Math.round(report.durationMs / 1000)} seconds)`);
console.log(`Report: ${output}`);
process.exitCode = report.failed ? 1 : 0;

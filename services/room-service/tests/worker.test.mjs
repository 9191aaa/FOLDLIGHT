import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.ts';
import { RACE_RULES_VERSION } from '../src/race-rules.ts';

const origin = 'https://rooms.example';
const noDatabase = { prepare() { throw new Error('Unexpected database access'); } };
function request(path = '/api/rooms', options = {}) {
  return new Request(origin + path, options);
}
function post(body, headers = {}) {
  return request('/api/rooms', { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body });
}

test('same-origin browser and relay requests are allowed; other origins are rejected', async () => {
  const health = await worker.fetch(request('/health', { headers: { origin } }), { DB: noDatabase });
  assert.equal(health.status, 200);
  assert.equal((await health.json()).rulesVersion, RACE_RULES_VERSION);
  const foreign = await worker.fetch(post('{}', { origin: 'https://unrelated.example' }), { DB: noDatabase });
  assert.equal(foreign.status, 403);
  assert.equal(foreign.headers.get('access-control-allow-origin'), null);
  for (const headers of [{}, { origin }]) {
    assert.equal((await worker.fetch(post('{}', headers), { DB: noDatabase })).status, 400);
  }
});

test('routes, methods and missing bindings fail explicitly before SQL', async () => {
  assert.equal((await worker.fetch(request('/unknown'), {})).status, 404);
  assert.equal((await worker.fetch(request('/api/rooms/not-valid'), {})).status, 400);
  assert.equal((await worker.fetch(request(), {})).status, 405);
  assert.equal((await worker.fetch(request('/api/rooms/ABC2345', { method: 'DELETE' }), {})).status, 405);
  const missing = await worker.fetch(post('{"name":"旅人"}'), {});
  assert.equal(missing.status, 503);
  assert.match(missing.headers.get('cache-control'), /no-store/);
});

test('input rejects non-objects, malformed JSON and bodies over 4096 bytes', async () => {
  for (const value of ['null', '[]', '123', '"hello"', '{']) {
    assert.equal((await worker.fetch(post(value), { DB: noDatabase })).status, 400, value);
  }
  const oversizedUtf8 = JSON.stringify({ name: '纸'.repeat(1400) });
  assert.ok(oversizedUtf8.length < 4096 && Buffer.byteLength(oversizedUtf8) > 4096);
  assert.equal((await worker.fetch(post(oversizedUtf8), { DB: noDatabase })).status, 413);
  assert.equal((await worker.fetch(post('{}', { 'content-length': '5000' }), { DB: noDatabase })).status, 413);
  assert.equal((await worker.fetch(post('{}', { 'content-type': 'text/plain' }), { DB: noDatabase })).status, 415);
});

function fixtureDatabase(id, firstRead) {
  let reads = 0;
  const now = Date.now();
  const room = { code: 'ABC2345', seed: id === 'alpha' ? 101 : 202, phase: 'waiting', created_at: now, expires_at: now + 60_000, start_at: null, creator_hash: id };
  const player = { id, name: id, room: room.code, slot: 0, ready: 0, status: 'waiting', elapsed: 0, kills: 0, health: 1, seen_at: now };
  return {
    prepare(sql) {
      return {
        bind() { return this; },
        async first() {
          if (sql.includes('FROM race_rooms')) {
            if (++reads === 1 && firstRead) await firstRead;
            return room;
          }
          if (sql.includes('FROM race_players')) return player;
          throw new Error('Unexpected SQL: ' + sql);
        },
        async all() { return { results: [player] }; },
      };
    },
  };
}

test('overlapping fetch invocations retain separate D1 bindings after awaits', async () => {
  let release;
  const delayedRead = new Promise(resolve => { release = resolve; });
  const authenticated = () => request('/api/rooms/ABC2345', { headers: { authorization: 'Bearer test-token' } });
  const first = worker.fetch(authenticated(), { DB: fixtureDatabase('alpha', delayedRead) });
  const second = await worker.fetch(authenticated(), { DB: fixtureDatabase('beta') });
  release();
  const [a, b] = await Promise.all([(await first).json(), second.json()]);
  assert.equal(a.selfId, 'alpha');
  assert.equal(a.seed, 101);
  assert.equal(a.players[0].id, 'alpha');
  assert.equal(b.selfId, 'beta');
  assert.equal(b.seed, 202);
  assert.equal(b.players[0].id, 'beta');
});

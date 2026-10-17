import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { createRoomService } from '../src/race-server.ts';

function fixture(t) {
  const sqlite = new DatabaseSync(':memory:');
  t.after(() => sqlite.close());
  sqlite.exec(readFileSync(new URL('../migrations/0001_rooms.sql', import.meta.url), 'utf8'));
  sqlite.exec("INSERT INTO race_rooms(code,seed,created_at,expires_at,creator_hash) VALUES ('OLD2345',1,0,9999999999999,'legacy')");
  sqlite.exec(readFileSync(new URL('../migrations/0002_room_rules.sql', import.meta.url), 'utf8'));
  const db = {
    prepare(sql) {
      let args = [];
      return {
        bind(...values) { args = values; return this; },
        async first() { return sqlite.prepare(sql).get(...args); },
        async all() { return { results: sqlite.prepare(sql).all(...args) }; },
        async run() { return { meta: { changes: Number(sqlite.prepare(sql).run(...args).changes) } }; },
      };
    },
    async batch(statements) {
      sqlite.exec('BEGIN');
      try { const results = []; for (const s of statements) results.push(await s.run()); sqlite.exec('COMMIT'); return results; }
      catch (e) { sqlite.exec('ROLLBACK'); throw e; }
    },
  };
  const service = createRoomService(db);
  async function call(body, code, token) {
    const req = new Request('https://rooms.example/api/rooms' + (code ? '/' + code : ''), {
      method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify(body),
    });
    const response = code ? await service.updateRoom(req, code) : await service.createRoom(req);
    return { status: response.status, data: await response.json() };
  }
  return { sqlite, call };
}

test('migration retains v3; v3/v4/v5/v6/v7 matches reject every other rules version before allocating slots', async t => {
  const { sqlite, call } = fixture(t);
  assert.equal(sqlite.prepare("SELECT rules_version FROM race_rooms WHERE code='OLD2345'").get().rules_version, 'endless_race_v3');
  const supported = ['endless_race_v3', 'endless_race_v4', 'endless_race_v5', 'endless_race_v6', 'endless_race_v7'];
  for (const version of supported) {
    const rules = version === 'endless_race_v3' ? {} : { rulesVersion: version };
    const created = await call({ name: '甲', ...rules });
    assert.equal(created.status, 201);
    const room = created.data.room, code = room.code;
    assert.equal(room.rulesVersion, version);
    const others = supported.filter(candidate => candidate !== version);
    for (const different of others) {
      assert.equal((await call({ action: 'join', name: '错误版本', rulesVersion: different }, code)).status, 409);
    }
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM race_players WHERE room=?').get(code).n, 1);
    const joined = await call({ action: 'join', name: '乙', ...rules }, code);
    assert.equal(joined.status, 200);
    const a = randomUUID(), b = randomUUID();
    assert.equal((await call({ action: 'ready', instanceId: a, rulesVersion: version }, code, created.data.token)).status, 200);
    const ready = await call({ action: 'ready', instanceId: b, rulesVersion: version }, code, joined.data.token);
    assert.equal(ready.status, 200);
    assert.equal(ready.data.phase, 'running');
    assert.equal(ready.data.rulesVersion, version);
    sqlite.prepare('UPDATE race_rooms SET start_at=? WHERE code=?').run(Date.now() - 1000, code);
    const beat = await call({ action: 'heartbeat', rulesVersion: version, instanceId: a, seq: 1, elapsed: 0.5, kills: 1, health: 1, status: 'alive' }, code, created.data.token);
    assert.equal(beat.status, 200);
    assert.equal(beat.data.players.find(p => p.id === room.selfId).elapsed, 0.5);
    for (const different of others) {
      assert.equal((await call({ action: 'heartbeat', rulesVersion: different, instanceId: a, seq: 2 }, code, created.data.token)).status, 409);
    }
  }
  assert.equal((await call({ name: '未知版本', rulesVersion: 'endless_race_v999' })).status, 409);
});

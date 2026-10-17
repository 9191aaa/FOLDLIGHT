import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import worker from '../src/index.ts';

const schema = readFileSync(new URL('../migrations/0001_rooms.sql', import.meta.url), 'utf8');
const code = 'ABC2345';
const token = 'alpha-token';
const instance = '12345678-1234-4234-8234-123456789012';

function fixture({ phase = 'running', aElapsed = 4, bElapsed = 3, bStatus = 'dead' } = {}) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(schema);
  const now = Date.now();
  sqlite.prepare('INSERT INTO race_rooms VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(code, 501, phase, now, now + 3600_000, phase === 'running' ? now - 120_000 : null, 'test');
  const insert = sqlite.prepare('INSERT INTO race_players (id,room,name,token_hash,slot,instance_id,ready,status,elapsed,kills,health,seq,joined_at,seen_at,reported_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
  insert.run('alpha', code, 'alpha', createHash('sha256').update(token).digest('hex'), 0, instance, 1, 'alive', aElapsed, 1, 1, 1, now, now, now - 60_000);
  insert.run('beta', code, 'beta', 'unused', 1, instance, 1, bStatus, bElapsed, 1, bStatus === 'dead' ? 0 : 1, 1, now, now, now - 60_000);
  let hook;
  const db = {
    prepare(sql) {
      let values = [];
      async function execute(kind) {
        await hook?.('before', sql, values);
        const statement = sqlite.prepare(sql);
        const output = kind === 'first' ? statement.get(...values)
          : kind === 'all' ? { results: statement.all(...values) }
          : { success: true, meta: { changes: Number(statement.run(...values).changes) } };
        await hook?.('after', sql, values, output);
        return output;
      }
      return {
        bind(...parameters) { values = parameters; return this; },
        first: () => execute('first'), all: () => execute('all'), run: () => execute('run'),
      };
    },
  };
  function gate(stage, pattern) {
    let reached, release, used = false;
    const waiting = new Promise(resolve => { reached = resolve; });
    const paused = new Promise(resolve => { release = resolve; });
    hook = async (step, sql) => {
      if (!used && step === stage && pattern.test(sql)) {
        used = true;
        reached();
        await paused;
      }
    };
    return { waiting, release };
  }
  async function call(body) {
    const headers = { authorization: 'Bearer ' + token };
    if (body) headers['content-type'] = 'application/json';
    const request = new Request('https://rooms.example/api/rooms/' + code, {
      headers, method: body ? 'POST' : 'GET',
      ...(body ? { body: JSON.stringify({ rulesVersion: 'endless_race_v3', instanceId: instance, ...body }) } : {}),
    });
    const response = await worker.fetch(request, { DB: db });
    const value = await response.json();
    assert.equal(response.status, 200, JSON.stringify(value));
    return value;
  }
  return { sqlite, call, gate, close: () => sqlite.close() };
}

test('heartbeat read before a finish cannot rewrite the announced winner', async t => {
  const f = fixture(); t.after(f.close);
  const barrier = f.gate('before', /^UPDATE race_players SET status = \?, elapsed/);
  const late = f.call({ action: 'heartbeat', seq: 2, status: 'forfeit', elapsed: 4, kills: 1, health: 1 });
  await barrier.waiting;
  const finished = await f.call();
  assert.equal(finished.result.winner, 'alpha');
  barrier.release();
  const after = await late;
  assert.equal(after.phase, 'finished');
  assert.equal(after.result.winner, 'alpha');
  assert.equal(after.players.find(p => p.id === 'alpha').status, 'alive');
});

test('waiting leave concurrent with ready becomes forfeit instead of expiring a running room', async t => {
  const f = fixture({ phase: 'waiting', bStatus: 'waiting', aElapsed: 0, bElapsed: 0 }); t.after(f.close);
  f.sqlite.prepare("UPDATE race_players SET status = 'waiting', ready = 0 WHERE id = 'alpha'").run();
  const barrier = f.gate('before', /^UPDATE race_rooms SET expires_at/);
  const leaving = f.call({ action: 'leave' });
  await barrier.waiting;
  const ready = await f.call({ action: 'ready' });
  assert.equal(ready.phase, 'running');
  barrier.release();
  const result = await leaving;
  assert.equal(result.phase, 'finished');
  assert.equal(result.result.winner, 'beta');
  assert.ok(result.expiresAt > Date.now());
  assert.equal((await f.call()).result.winner, 'beta');
});

test('a higher sequence calculated from stale rows cannot roll back counters or connection times', async t => {
  const f = fixture({ aElapsed: 10, bElapsed: 0, bStatus: 'alive' }); t.after(f.close);
  const barrier = f.gate('after', /^SELECT \* FROM race_players WHERE room = \? AND token_hash/);
  const stale = f.call({ action: 'heartbeat', seq: 3, status: 'alive', elapsed: 11, kills: 2, health: 1 });
  await barrier.waiting;
  await f.call({ action: 'heartbeat', seq: 2, status: 'alive', elapsed: 20, kills: 8, health: 1 });
  const fresh = f.sqlite.prepare("SELECT * FROM race_players WHERE id = 'alpha'").get();
  assert.equal(fresh.elapsed, 20);
  barrier.release();
  const result = await stale;
  const player = result.players.find(p => p.id === 'alpha');
  const row = f.sqlite.prepare("SELECT * FROM race_players WHERE id = 'alpha'").get();
  assert.equal(player.elapsed, 20);
  assert.equal(player.kills, 8);
  assert.equal(row.seq, 3);
  assert.ok(row.seen_at >= fresh.seen_at);
  assert.ok(row.reported_at >= fresh.reported_at);
});

test('a stale winner snapshot re-reads after another request commits a forfeit', async t => {
  const f = fixture(); t.after(f.close);
  const barrier = f.gate('before', /^UPDATE race_rooms SET phase = 'finished'/);
  const stale = f.call();
  await barrier.waiting;
  const correct = await f.call({ action: 'leave' });
  assert.equal(correct.result.winner, 'beta');
  barrier.release();
  const replay = await stale;
  assert.equal(replay.phase, 'finished');
  assert.equal(replay.result.winner, 'beta');
  assert.equal((await f.call()).result.winner, 'beta');
});

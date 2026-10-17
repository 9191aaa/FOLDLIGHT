import { acceptedElapsed, CODE_PATTERN, COUNTDOWN_MS, DISCONNECT_MS, resultFor, ROOM_TTL_MS, SUPPORTED_RACE_RULES_VERSIONS, LEGACY_RACE_RULES_VERSION, terminal, type Player, type Room } from "./race-rules.ts";

// Extracted from the verified Sites API; database lifetime is request-scoped.
export function createRoomService(databaseBinding: D1Database) {
  function db(): D1Database {
    if (!databaseBinding) throw new Error("Room service is unavailable");
    return databaseBinding;
  }
  class ApiError extends Error { status: number; constructor(status: number, message: string) { super(message); this.status = status; } }
  const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
  async function hash(value: string) {
    return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), b => b.toString(16).padStart(2, "0")).join("");
  }
  function randomToken() { return crypto.randomUUID() + crypto.randomUUID(); }
  function code() {
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    return Array.from(crypto.getRandomValues(new Uint8Array(7)), value => alphabet[value % alphabet.length]).join("");
  }
  async function body(request: Request) {
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) throw new ApiError(403, "请从折光网站发起操作。");
    if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) throw new ApiError(415, "请求格式不正确。");
    if (Number(request.headers.get("content-length")) > 4096) throw new ApiError(413, "请求内容过长。");
    const reader = request.body?.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    if (reader) {
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        length += next.value.byteLength;
        if (length > 4096) {
          await reader.cancel();
          throw new ApiError(413, "请求内容过长。");
        }
        chunks.push(next.value);
      }
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    try {
      const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("object required");
      return value as Record<string, unknown>;
    }
    catch { throw new ApiError(400, "请求内容不完整，请重试。"); }
  }
  function nameOf(value: unknown) {
    const name = typeof value === "string" ? value.trim().replace(/[\p{C}]/gu, "") : "";
    if (!name || [...name].length > 16) throw new ApiError(400, "请输入 1–16 字的称呼。");
    return name;
  }
  function rulesOf(value: unknown) {
    const version = value ?? LEGACY_RACE_RULES_VERSION;
    if (typeof version !== "string" || !SUPPORTED_RACE_RULES_VERSIONS.some(supported => supported === version)) throw new ApiError(409, "游戏规则已更新，请更新游戏或刷新网页后重新建房。");
    return version;
  }
  const roomRules = (room: Room) => room.rules_version ?? LEGACY_RACE_RULES_VERSION;
  async function readRoom(roomCode: string) {
    if (!CODE_PATTERN.test(roomCode)) throw new ApiError(400, "房间码为 7 位字母或数字。");
    const room = await db().prepare("SELECT * FROM race_rooms WHERE code = ?").bind(roomCode).first<Room>();
    if (!room || room.expires_at < Date.now()) throw new ApiError(404, "房间不存在或已过期，请创建新房间。");
    return room;
  }
  async function auth(request: Request, roomCode: string) {
    const token = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
    if (!token || token.length > 100) throw new ApiError(401, "请先加入房间。");
    const player = await db().prepare("SELECT * FROM race_players WHERE room = ? AND token_hash = ?").bind(roomCode, await hash(token)).first<Player>();
    if (!player) throw new ApiError(401, "房间身份失效，请重新加入。");
    return player;
  }
  async function playersIn(roomCode: string) { return (await db().prepare("SELECT * FROM race_players WHERE room = ? ORDER BY slot").bind(roomCode).all<Player>()).results; }
  async function snapshot(roomCode: string, selfId: string, retry = 0): Promise<{
    code: string; seed: number; phase: string; startAt: number | null; rulesVersion: string;
    serverNow: number; expiresAt: number; selfId: string;
    result: { winner: string | null; draw: boolean } | null;
    players: { id: string; name: string; slot: number; ready: boolean; status: string; elapsed: number; kills: number; health: number; connected: boolean }[];
  }> {
    let room = await readRoom(roomCode);
    const now = Date.now();
    if (room.phase === "running" && room.start_at! <= now) {
      await db().prepare("UPDATE race_players SET status = 'disconnected' WHERE room = ? AND status IN ('waiting','alive','reward','paused') AND seen_at < ? AND EXISTS (SELECT 1 FROM race_rooms WHERE code = ? AND phase = 'running' AND start_at <= ?)").bind(roomCode, now - DISCONNECT_MS, roomCode, now).run();
    }
    const players = await playersIn(roomCode);
    if (room.phase === "waiting" && players.length === 2 && players.every(p => p.ready && now - p.seen_at < 10_000 && !terminal(p.status))) {
      await db().prepare("UPDATE race_rooms SET phase = 'running', start_at = ? WHERE code = ? AND phase = 'waiting' AND expires_at >= ? AND (SELECT COUNT(*) FROM race_players WHERE room = ? AND ready = 1 AND seen_at > ? AND status NOT IN ('dead','forfeit','disconnected')) = 2").bind(now + COUNTDOWN_MS, roomCode, now, roomCode, now - 10_000).run();
      room = await readRoom(roomCode);
      // Another request may already have forfeited/finished the new round.
      // Reload its players together with the new phase before reporting it.
      if (room.phase !== "waiting") return snapshot(roomCode, selfId, retry);
    }
    const result = room.phase !== "waiting" ? resultFor(players) : null;
    if (result && room.phase !== "finished") {
      // Commit only the exact pair whose scores produced this result. A
      // heartbeat/leave between SELECT and UPDATE must force a fresh result.
      const [a, b] = players;
      const committed = await db().prepare("UPDATE race_rooms SET phase = 'finished' WHERE code = ? AND phase = 'running' AND EXISTS (SELECT 1 FROM race_players WHERE id = ? AND room = ? AND status = ? AND seq = ? AND elapsed = ?) AND EXISTS (SELECT 1 FROM race_players WHERE id = ? AND room = ? AND status = ? AND seq = ? AND elapsed = ?)")
        .bind(roomCode, a.id, roomCode, a.status, a.seq, a.elapsed, b.id, roomCode, b.status, b.seq, b.elapsed).run();
      if (!committed.meta.changes) {
        if (retry >= 3) throw new ApiError(503, "成绩正在同步，请稍后重试。");
        return snapshot(roomCode, selfId, retry + 1);
      }
      room.phase = "finished";
    }
    return {
      code: room.code, seed: room.seed, phase: room.phase, startAt: room.start_at, rulesVersion: roomRules(room),
      serverNow: now, expiresAt: room.expires_at, selfId, result,
      players: players.map(({ id, name, slot, ready, status, elapsed, kills, health, seen_at }) => ({ id, name, slot, ready: !!ready, status, elapsed, kills, health, connected: now - seen_at < 5000 })),
    };
  }
  async function createRoom(request: Request) {
    return respond(async () => {
      const input = await body(request), name = nameOf(input.name), database = db(), now = Date.now();
      const rulesVersion = rulesOf(input.rulesVersion);
      const creatorHash = await hash(request.headers.get("cf-connecting-ip") ?? "local");
      const recent = await database.prepare("SELECT COUNT(*) AS n FROM race_rooms WHERE creator_hash = ? AND created_at > ?").bind(creatorHash, now - 3600_000).first<{ n: number }>();
      if ((recent?.n ?? 0) >= 20) throw new ApiError(429, "创建房间过于频繁，请稍后再试。");
      await database.prepare("DELETE FROM race_rooms WHERE expires_at < ?").bind(now).run();
      const roomCode = code(), token = randomToken(), playerId = crypto.randomUUID();
      const seed = crypto.getRandomValues(new Uint32Array(1))[0] % 2_000_000_000 + 1;
      await database.batch([
        database.prepare("INSERT INTO race_rooms (code, seed, created_at, expires_at, creator_hash, rules_version) VALUES (?, ?, ?, ?, ?, ?)").bind(roomCode, seed, now, now + ROOM_TTL_MS, creatorHash, rulesVersion),
        database.prepare("INSERT INTO race_players (id, room, name, token_hash, slot, joined_at, seen_at) VALUES (?, ?, ?, ?, 0, ?, ?)").bind(playerId, roomCode, name, await hash(token), now, now),
      ]);
      return json({ token, room: await snapshot(roomCode, playerId) }, 201);
    });
  }
  async function getRoom(request: Request, roomCode: string) {
    return respond(async () => { await readRoom(roomCode); const self = await auth(request, roomCode); return json(await snapshot(roomCode, self.id)); });
  }
  async function updateRoom(request: Request, roomCode: string) {
    return respond(async () => {
      const room = await readRoom(roomCode), input = await body(request), database = db(), now = Date.now();
      if (input.action === "join") {
        if (rulesOf(input.rulesVersion) !== roomRules(room)) throw new ApiError(409, "双方游戏版本不同，请更新到同一版本后重新建房。");
        if (room.phase !== "waiting") throw new ApiError(409, "这场比赛已开始，请创建新房间。");
        const token = randomToken(), id = crypto.randomUUID();
        const result = await database.prepare("INSERT OR IGNORE INTO race_players (id, room, name, token_hash, slot, joined_at, seen_at) SELECT ?, ?, ?, ?, 1, ?, ? WHERE (SELECT COUNT(*) FROM race_players WHERE room = ?) = 1 AND (SELECT phase FROM race_rooms WHERE code = ?) = 'waiting'")
          .bind(id, roomCode, nameOf(input.name), await hash(token), now, now, roomCode, roomCode).run();
        if (!result.meta.changes) throw new ApiError(409, "房间已有两人，请创建另一个房间。");
        return json({ token, room: await snapshot(roomCode, id) });
      }
      const self = await auth(request, roomCode);
      if (input.action === "leave") {
        if (room.phase === "waiting") {
        const closed = await database.prepare("UPDATE race_rooms SET expires_at = ? WHERE code = ? AND phase = 'waiting'").bind(now - 1, roomCode).run();
        if (closed.meta.changes) return json({ left: true });
        }
      await database.prepare("UPDATE race_players SET status = 'forfeit', seen_at = MAX(seen_at, ?) WHERE id = ? AND status NOT IN ('dead','forfeit','disconnected') AND EXISTS (SELECT 1 FROM race_rooms WHERE code = ? AND phase = 'running')").bind(now, self.id, roomCode).run();
      } else if (input.action === "ready") {
        if (input.rulesVersion !== roomRules(room)) throw new ApiError(409, "游戏规则已更新，请更新游戏或刷新网页后重新建房。");
        const instance = typeof input.instanceId === "string" && /^[a-f0-9-]{36}$/.test(input.instanceId) ? input.instanceId : null;
        if (!instance) throw new ApiError(400, "游戏加载标识无效，请重新建房。");
        if (self.instance_id && self.instance_id !== instance) throw new ApiError(409, "本局已在其他页面加载，请创建新房间。");
        if (room.phase === "waiting" && !terminal(self.status)) {
          await database.prepare("UPDATE race_players SET ready = 1, instance_id = ?, seen_at = MAX(seen_at, ?) WHERE id = ? AND (instance_id IS NULL OR instance_id = ?) AND status NOT IN ('dead','forfeit','disconnected') AND EXISTS (SELECT 1 FROM race_rooms WHERE code = ? AND phase = 'waiting' AND expires_at >= ?)").bind(instance, now, self.id, instance, roomCode, now).run();
          const current = await auth(request, roomCode);
          if (current.instance_id !== instance) throw new ApiError(409, "本局已在其他页面加载。");
        }
      } else if (input.action === "heartbeat") {
        if (input.rulesVersion !== roomRules(room)) throw new ApiError(409, "游戏规则已更新，请更新游戏或刷新网页后重新建房。");
        if (self.instance_id && self.instance_id !== input.instanceId) throw new ApiError(409, "本局已在其他页面加载，请创建新房间。");
        if (room.phase === "running" && now >= room.start_at! && !terminal(self.status)) {
          if (now - self.seen_at > DISCONNECT_MS) {
            await database.prepare("UPDATE race_players SET status = 'disconnected' WHERE id = ? AND seen_at < ? AND status NOT IN ('dead','forfeit','disconnected') AND EXISTS (SELECT 1 FROM race_rooms WHERE code = ? AND phase = 'running')").bind(self.id, now - DISCONNECT_MS, roomCode).run();
          } else if (Number.isSafeInteger(input.seq) && Number(input.seq) > self.seq) {
            const status = ["alive", "reward", "paused", "dead", "forfeit"].includes(String(input.status)) ? String(input.status) : self.status;
            const elapsed = acceptedElapsed(self, room, Number(input.elapsed), now);
            const kills = Number.isFinite(Number(input.kills)) ? Math.max(self.kills, Math.min(1_000_000, Math.floor(Number(input.kills)))) : self.kills;
            const health = Number.isFinite(Number(input.health)) ? Math.min(1, Math.max(0, Number(input.health))) : self.health;
            await database.prepare("UPDATE race_players SET status = ?, elapsed = MAX(elapsed, ?), kills = MAX(kills, ?), health = ?, seq = ?, seen_at = MAX(seen_at, ?), reported_at = MAX(COALESCE(reported_at, 0), ?) WHERE id = ? AND seq < ? AND status NOT IN ('dead','forfeit','disconnected') AND instance_id = ? AND EXISTS (SELECT 1 FROM race_rooms WHERE code = ? AND phase = 'running' AND start_at <= ?)")
              .bind(status, elapsed, kills, health, Number(input.seq), now, now, self.id, Number(input.seq), String(input.instanceId ?? ""), roomCode, now).run();
          }
      } else { await database.prepare("UPDATE race_players SET seen_at = MAX(seen_at, ?) WHERE id = ?").bind(now, self.id).run(); }
      } else { throw new ApiError(400, "不支持的房间操作。"); }
      return json(await snapshot(roomCode, self.id));
    });
  }
  async function respond(action: () => Promise<Response>) {
    try { return await action(); }
    catch (error) {
      if (error instanceof ApiError) return json({ error: error.message }, error.status);
      console.error("Room request failed", error instanceof Error ? error.message : "unknown error");
      return json({ error: "房间连接暂时不可用，请稍后重试。" }, 503);
    }
  }

  return { createRoom, getRoom, updateRoom };
}

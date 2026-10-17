export const DISCONNECT_MS = 30_000;
export const ROOM_TTL_MS = 3 * 60 * 60 * 1000;
export const COUNTDOWN_MS = 5000;
export const RACE_RULES_VERSION = "endless_race_v8";
export const LEGACY_RACE_RULES_VERSION = "endless_race_v3";
export const SUPPORTED_RACE_RULES_VERSIONS = [LEGACY_RACE_RULES_VERSION, "endless_race_v4", "endless_race_v5", "endless_race_v6", "endless_race_v7", RACE_RULES_VERSION] as const;
export const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{7}$/;
export type Player = {
  id: string; room: string; name: string; token_hash: string; slot: number; instance_id: string | null;
  ready: number; status: string; elapsed: number; kills: number; health: number;
  seq: number; joined_at: number; seen_at: number; reported_at: number | null;
};
export type Room = {
  code: string; seed: number; phase: string; created_at: number;
  expires_at: number; start_at: number | null; creator_hash: string; rules_version?: string;
};
export function terminal(status: string) { return ["dead", "forfeit", "disconnected"].includes(status); }
export function resultFor(players: Player[]) {
  if (players.length !== 2) return null;
  const [a, b] = players;
  const forfeits = (p: Player) => p.status === "forfeit" || p.status === "disconnected";
  if (forfeits(a) || forfeits(b)) {
    if (forfeits(a) && forfeits(b)) return { winner: null, draw: true };
    return { winner: forfeits(a) ? b.id : a.id, draw: false };
  }
  if (terminal(a.status) && terminal(b.status)) {
    if (Math.abs(a.elapsed - b.elapsed) < 0.1) return { winner: null, draw: true };
    return { winner: a.elapsed > b.elapsed ? a.id : b.id, draw: false };
  }
  if (terminal(a.status) && b.elapsed > a.elapsed + 0.1) return { winner: b.id, draw: false };
  if (terminal(b.status) && a.elapsed > b.elapsed + 0.1) return { winner: a.id, draw: false };
  return null;
}
export function acceptedElapsed(player: Player, room: Room, incoming: number, now: number) {
  if (!Number.isFinite(incoming) || incoming < 0 || !room.start_at || now < room.start_at) return player.elapsed;
  const wall = (now - room.start_at) / 1000;
  const sinceReport = (now - Math.max(player.reported_at ?? room.start_at, room.start_at)) / 1000;
  return Math.max(player.elapsed, Math.min(incoming, wall, player.elapsed + Math.max(0, sinceReport) + 0.25));
}

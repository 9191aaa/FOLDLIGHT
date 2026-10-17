# Web friend survival

The companion Sites project provides the room service and browser wrapper; the Godot project exports the complete original game. The browser wrapper must define `window.FoldlightRace` before `Engine.startGame()` for a race. Ordinary web launch shows the main menu, while `?web_endless=1` launches isolated solo endless.

## Bridge v1

`config` contains `roomId`, `matchId`, `playerId`, a one-use `instanceId`, `seed` (1..2147483647), and `rulesVersion: "endless_race_v1"`.

- `ready(jsonString)` reports that the real endless scene is loaded and frozen.
- `getState()` returns a JSON string with `phase: waiting | running | finished`, `mayStart`, and optional `reason`. Only `running` plus `mayStart: true` admits a run.
- `report(jsonString)` sends the identity, increasing `seq`, `status`, `survivalMs`, `kills`, `health`, `maxHealth`, `paused`, `pauseReason`, `terminal` and `reason`. Reports occur roughly every second, immediately on death/abandonment, and stop after the terminal report.

The bridge is the first autoload. Race startup bypasses profile/settings disk reads and writes. Default equipment, zero meta upgrades and the shared seed avoid old-save advantages. Reward overlays freeze simulation and survival time. Race pause is disabled, and `finished` cancels reward guards before stopping combat. A running attempt cannot restart; both server instance admission and a browser session marker prevent refresh resets.

JavaScriptBridge's [4.6.3 implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/web/javascript_bridge_singleton.cpp#L307-L330) converts JavaScript boolean evaluation results to integer Variants. The attempt marker therefore returns explicit string outcomes rather than comparing the result to a GDScript `true`. This is covered by real dual-browser startup verification, beyond native bridge substitutes.

## Room behavior

The Sites companion uses D1 with two immutable player slots, hashed random tokens, one-use instance admission, a shared server countdown, monotonic heartbeat sequences, wall-time bounds and terminal-state protection. Tokens are held only in page memory. Invite URLs contain the room code, never the token.

Both loaded players start after the same five-second countdown. A normal death freezes its actual simulation score; the other player wins after exceeding it, or scores are compared once both die. Leaving/refreshing or a 30-second disconnect forfeits regardless of the forfeiting player's prior score. Two forfeits are a draw. Rooms expire after three hours. This is a friendly survival race using client simulation, not shared-world co-op or a server-authoritative anti-cheat mode.

The Site source is a separate Sites-managed repository alongside this game checkout (`foldlight-site`). It includes the room implementation, API tests, Godot asset packaging and browser wrapper. Public access was explicitly selected for friend invitations.

## Checks

- `test_web_endless_race_bridge.gd`: real endless scene startup gating, seed parity, default equipment, active time, death, pause/reward behavior, restart refusal and profile isolation.
- `test_reward_input_guard.gd`: held keyboard, mouse, gamepad and stick input cannot select across reward entry; fresh input works after the one-second reveal/neutral window.
- Companion `tests/race-api.mjs`: two-client API lifecycle, authentication, instance admission, timing, ordering, terminal state, forfeit and actual 30-second disconnect.
- Real Edge browser contexts: both exported engines load, report independently, start after the countdown, accumulate simulation time and settle the race on exit. The wrapper streams split WASM files below hosting asset limits.

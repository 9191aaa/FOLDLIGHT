# FOLDLIGHT — Two-hour campaign specification

## Product promise

The release must support a normal first clear of roughly two hours without adding combat buttons or turning the game into an endless score mode. The player keeps the current one-hand contract: move, hold Fold to gather, release Fold to return light.

The campaign is three chapters of four missions. Each mission is a short, complete six-tide build arc with safe checkpoints at tide boundaries. Static mission content is read-only `Resource` data; mutable campaign and combat state never modifies shared resources.

## Chosen structure

| Mission | Active budget | Core objective | New rule / payoff |
|---|---:|---|---|
| I-1 静水试灯 | 7 min | survive + return quota | first large returns |
| I-2 纸鸢航标 | 8 min | charge three beacons | crosswind routing |
| I-3 回声花庭 | 9 min | cleanse echo flowers | defend the center light |
| I-4 墨月裂相 | 11 min | chapter boss | Ink Moon rematch |
| II-1 无灯护航 | 8 min | escort a paper skiff | Fold protects, returns repair |
| II-2 赤轮开闸 | 9 min | lure Rams into relays | danger becomes the key |
| II-3 四秒倒流 | 10 min | relay through rewind lanes | route memory |
| II-4 沉庭潮钟 | 12 min | chapter boss | delayed echo patterns |
| III-1 镜海重名 | 9 min | stabilize name anchors | release streaks |
| III-2 断航群岛 | 10 min | rescue six echo skiffs | escort / pursuit alternation |
| III-3 百折长夜 | 11 min | three mastery contracts | changing goals under pressure |
| III-4 无名日轮 | 14 min | final boss | the player's own volleys return |

The configured active total is 7,080 seconds. First-time briefings, map decisions and Foldlight Court visits add approximately 8–14 minutes. Skilled replay may be shorter; ordinary failures should not erase more than one tide.

## Pacing contract

- A satisfying 8+ light release should be available every 20–35 seconds.
- A contract, event, enemy combination or arena rule changes every 90–150 seconds.
- A safe checkpoint is committed after every Herald and doctrine choice.
- A mission ends every 7–14 minutes; a chapter ends every 35–44 minutes.
- No six-minute interval may pass without a new rule, reward, narrative beat or enemy composition.
- Briefings are one to three confirmation pages, shown once and skipped on repeat clears.

## Objectives

All objectives use only movement, gathering and releasing:

1. `survive` — reach the Herald.
2. `return_quota` — land a target number of returned-light hits.
3. `beacon_charge` — release near authored beacons; returns auto-charge them.
4. `cleanse` — full releases remove corruption from fixed targets.
5. `escort` — the Fold protects a moving skiff; returned light repairs and accelerates it.
6. `ram_relay` — lure a charging Ram into a marked relay.
7. `pursuit` — defeat an escaping courier with returned light.
8. `mastery` — complete authored large-volley, chain or cleanse subcontracts.

Each objective has `PENDING → ACTIVE → SUCCESS/FAILURE`, visible progress and idempotent rewards. Main progression never soft-locks on an optional contract; failure lowers reward/rank or asks for a short retry.

## Content contract

- Keep the existing eight readable regular enemies.
- Add at least four mechanically distinct enemies: Tide Carver, Tide Bell, Name Thief and Echo Moth. Prefer six if performance remains within budget.
- Replace stat-only elite rolls with readable behavior affixes. At most two elites are active.
- Missions define enemy weights, two ritual events per tide, a scene modifier and an objective sequence.
- Chapter bosses are Ink Moon, Reverse Tide Bell and Nameless Sun. Mission finales use authored boss variants rather than merely larger health pools.
- Boss phases clear hostile shots, grant at least 0.8 seconds safety, produce ammunition every five seconds and expose an output window at least every eight seconds.
- Do not exceed 18 enemies, 300 hostile shots or 420 particles. Duration comes from authored combinations, not higher caps.

## Campaign state and save contract

`profile.json` version 4 keeps all version-3 stats and adds:

```json
"campaign": {
  "unlocked_missions": ["c1m1"],
  "completed": {},
  "reward_grants": [],
  "campaign_complete": false,
  "campaign_seconds": 0.0,
  "active_checkpoint": {}
}
```

A checkpoint contains stable IDs and JSON values only: mission ID/revision, tide start, seed, health/focus, score, captures, kills, chosen path, path step, doctrine IDs/stacks, mercy charges and mission flags. Enemies, shots, particles and runtime Resource references are never serialized.

Restore order:

1. reset the player and runtime arrays;
2. apply permanent Court upgrades;
3. replay doctrine effects in saved order without grant-time healing/reward side effects;
4. overwrite health, focus and consumable charges;
5. seed the next tide;
6. begin from an empty, safe tide boundary.

Profile migration maps a completed version-3 Chapter I to completed `c1m1` and unlocks `c1m2`; partial legacy runs remain historical stats. Future profile versions are not overwritten. Saves use a temporary file and backup replacement, and first-clear reward IDs prevent duplication.

## Runtime boundaries

The current battle scene remains the rendering and combat host for this release. New responsibilities are separated even if the scene is not fully rebuilt:

- `CampaignCatalog`: explicit preloads, mission lookup and validation.
- `MissionDefinition`: read-only authored mission data.
- `ObjectiveTracker`: runtime objective state and progress signals/snapshots.
- `FoldlightGame`: combat adapter, mission start/resume, enemy simulation and results.
- `ProfileManager`: profile migration, atomic persistence and campaign API.
- `HUD`: snapshot-only campaign map, objective and mission result rendering.

Do not introduce a global EventBus. Child systems report upward by signal or direct adapter methods. Keep `RunMode` for the existing one-scene release, but campaign screens must be isolated branches: `CAMPAIGN_MAP` and `MISSION_RESULT` may not advance combat simulation.

## Failure assistance

After two consecutive failures in one mission, the result screen offers explicit Wide Fold aid: either +1 life or -10% hostile-shot speed for that mission. Assisted clears cap the rank at B. Difficulty is never changed invisibly.

## Acceptance evidence

Automated gates:

- Catalog has 3 chapters, 12 unique missions, an acyclic unlock chain and exactly 7,080 configured active seconds.
- All objective, enemy, boss, event and background references validate.
- v0–v4 migration, corrupt-main backup recovery, future-version protection and checkpoint round-trip pass.
- A fast campaign state-graph simulation clears all 12 missions and proves first-clear rewards are idempotent.
- Every real checkpoint starts a playable empty tide with the saved build restored.
- Objective rewards settle once; failure cannot soft-lock the route.
- New enemy FSM states and all boss phases are reachable with readable telegraphs.
- A deterministic accelerated soak covers the configured 7,080 seconds without growing runtime arrays or memory unboundedly.
- Worst-case mixed roster stays at average ≤20.5 ms, p95 ≤26 ms and the existing entity caps.
- Windows release export launches and loads every explicitly referenced mission resource.

Product gate:

- One complete internal real-time clear must be recorded before calling the campaign finished.
- A later external playtest should target a 110–140 minute median, 4–8 deaths, understanding a new objective within 45 seconds, and no reported repetitive interval longer than six minutes.


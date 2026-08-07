# FOLDLIGHT Steam integration handoff

The release build runs without a Steamworks dependency. If GodotSteam (or another
binding that exposes the `Steam` engine singleton) is installed, `PlatformBridge`
automatically mirrors local achievements and integer stats.

## Achievement API names

| Local id | Steam API name | Condition |
|---|---|---|
| `first_dawn` | `FIRST_DAWN` | Defeat Ink Moon once |
| `uncreased` | `UNCREASED` | Win without taking an unblocked hit |
| `paper_storm` | `PAPER_STORM` | Capture at least 120 petals in one run |
| `perfect_fold` | `PERFECT_FOLD` | Earn rank S |

Integer stats: `TOTAL_RUNS`, `BEST_SCORE`, `TOTAL_CAPTURES`.

## Depot handoff

1. Install the production Steamworks/GodotSteam package outside this repository.
2. Create the four achievements and three integer stats with the API names above.
3. Put the real `steam_appid.txt` beside the executable only for local Steam testing.
4. Upload `build/windows/` with the private SteamPipe depot configuration.
5. Codesign `FOLDLIGHT.exe` before public distribution; no signing identity or secret
   is committed here.

The project intentionally does not ship the non-redistributable Steamworks SDK,
an App ID, signing certificate, or SteamPipe credentials.

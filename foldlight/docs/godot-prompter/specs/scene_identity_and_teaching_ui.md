# Scene Identity and Teaching UI

## Scene language

Each authored tide keeps the same readable arena bounds but gains a distinct low-contrast world motif:

- **Static Water:** mirror pools and paper reeds.
- **Paper Kite:** drifting kite silhouettes and diagonal wind script.
- **Echo:** nested paper gates and expanding echo arcs.
- **Eye of Wind:** broken vortex ribbons and orbiting paper shards.
- **Ink Moon:** moon cracks and pooled ink shadows.

World decoration stays behind enemies and projectiles. It uses low alpha, thin antialiased strokes, and no colors that can be mistaken for hostile or return projectiles.

## Teaching contract

`FoldlightTipQueue` owns two independent first-seen queues:

- `enemy`: a right-side dossier with name, behavior and a concrete counter.
- `effect`: a lower-left response card for statuses, special projectiles and battlefield modifiers.

Cards in different lanes may coexist. Cards within one lane wait their turn, and a `channel:id` pair appears only once per run. Central ritual messages remain reserved for authored encounter announcements.

Coverage includes all seven regular enemies, the Herald, Ink Moon, three player statuses, Seal petals, crosswind and lights-out.

## HUD hierarchy

1. Health, tide progress and score remain at the top edge.
2. The current scene identity and one-line tide objective sit under progress.
3. Active statuses use two-line chips with consequence and cleanse rule.
4. Focus, fold charge, current action and captured ammunition share one bottom-center action rail.
5. Teaching cards occupy stable side lanes and never cover the player action rail.

The HUD remains a single input-transparent `CanvasLayer` receiving pushed snapshots from the world.

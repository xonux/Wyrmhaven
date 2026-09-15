# studio-export/

Snapshot export of the Wyrmhaven code living in Roblox Studio ("TestingPlace"),
generated via the `Roblox_Studio` MCP (`search_game_tree` + `script_read`), not
Rojo. This is the resolution of `todo/git-versioning-strategy.md`.

## Convention

- Mirrors the Studio hierarchy 1:1 under the service name (`ReplicatedStorage/`,
  `ServerScriptService/`, `StarterPlayer/`, ...).
- `ModuleScript` → `Name.luau`
- `Script` → `Name.server.luau`
- `LocalScript` → `Name.client.luau`
- Non-script instances (Parts, geometry, GUI built at runtime, place properties
  like `Workspace.StreamingEnabled`) are **not** captured here — only code.

## This is a snapshot, not a live sync

There is no automation wiring this back into Studio and nothing keeps it in
sync automatically. Whoever (human or agent) does notable work in Studio
should re-export the changed scripts afterward: re-run `search_game_tree`
over the three roots above, `script_read` anything new or changed, and
overwrite the matching file(s) here — no need to touch files whose Studio
source didn't change.

Last partial export: 2026-09-15 (agent Claude Code - Lucas, during
`shop-ui.md`). Re-synced from live Studio at that moment:
Services/{HabitatService,EconomyService,DragonService,FarmService,
SaveService,HudService}, Server, Client, Controllers/ShopController
(new). **Known gap discovered immediately after this pass**: `Server`
was re-read once more right after and already showed
`DragonService.SetDecorationService`, `FarmService.SetDecorationService`
and `SaveService.SetDecorationService` calls (from `shop-decorations.md`,
landing concurrently) that are **not** reflected in this export's
DragonService/FarmService/SaveService files — Studio flipped to Play
mode before those three could be re-read a second time. Also still not
captured at all: `MonetizationService`, `ShopService`, `BreedingService`,
`DecorationService`, and `Config/DecorationDefs` (all landed during/after
this pass per `Server`'s require list). `CameraController`,
`InteractionController`, `HudController`, Config/* were not touched this
pass — status unknown, assume stale. Given how fast concurrent sessions
are landing Phase 2 tasks right now, treat this whole folder as a rough
snapshot, not a guarantee: whoever has a clear run (no other session
actively in Play) should do a full `search_game_tree` + `script_read`
sweep over the three roots rather than trust any single file verbatim.

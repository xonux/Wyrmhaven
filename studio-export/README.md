# studio-export/

Snapshot export of the Wyrmhaven code living in Roblox Studio (place
"Wyrmhaven", placeId 98608674053938 — called "TestingPlace" in the older
entries below), generated via the `Roblox_Studio` MCP, not Rojo. This is the
resolution of `todo/git-versioning-strategy.md`.

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

Export 2026-09-16 (Habitat UI redo, DML-style): re-synced from live Studio
`UI/{HabitatBar,DragonScreen,DragonViewport,Toast,UITheme,UIKit}` (UI folder
new in this export), `Controllers/HabitatUIController` (new), `Client`,
`Services/{DragonService,HabitatService}`, `Server`. Still in Studio but no
longer loaded by `Client` (not exported): `Controllers/InfoPopupController`,
`UI/InfoPopup`, `UI/PopupContent/{HabitatContent,DragonContent}`, and the
already-dead `Controllers/HabitatPanelController`.

## Export 2026-09-26 — full sweep, all 74 scripts

First **complete** pass over the three roots, not a partial one: every
`LuaSourceContainer` in Studio was dumped and written here, and each file was
checked byte for byte against `#script.Source` as Studio reports it. All 74
match. This clears the "assume stale" warning from the 2026-09-15 entry above —
`MonetizationService`, `ShopService`, `BreedingService`, `DecorationService`,
`DecorationDefs`, `CameraController`, `InteractionController`, `HudController`
and every Config module are all captured and current as of this date.

Newly exported (never in this folder before), mostly the combat system built
over the last sessions:

- Combat: `Config/{SkillDefs,SkillRules,StatusDefs,ElementChart,PveMap}`,
  `Services/{CombatEngine,CombatAI,PveService}`,
  `UI/{BattleScreen,PveMapScreen}`, `Controllers/PveController`.
- Dragons and progression: `Config/{DragonClasses,DragonLevels,DragonModels,
  DragonRules,FarmCrops,FarmDefs,GemSpeedUp,HabitatLevels,IslandObstacles,
  ObstacleDefs}`, `Services/{DevCommands,IslandService,LevelService,ReadyGlow,
  Scaffold}`.
- Client: `Controllers/{DecorationController,DragonVisualController,
  FarmVisualController,HabitatCoinController,HabitatPicker,ObstacleController}`,
  `UI/{BreedingScreen,DragonRig,DragonSale,ModelPreview,OptionBar,ShopScreen,
  UpgradeScreen,WorldArrow}`.
- Build tooling kept in ServerStorage: `WyrmhavenBuildKit/DragonBuilder`,
  `_DragonKit` (authored code, so versioned like the rest).

Deleted here because the script no longer exists in Studio:
`Config/BreedingTable` (breeding data now lives in `BreedingService` and
`DragonDefs`) and `UI/HabitatBar` (replaced by `OptionBar` / `HabitatUIController`).

Deliberately not exported: `ServerStorage.SkillPlan.Plan`, a scratch table used
once to generate `SkillDefs` and meant to be deleted from Studio; and
`StarterPlayerScripts.NewLocalScript`, an empty leftover Studio created.

### RemoteEvents

There are none to export: no RemoteEvent exists in the saved place. `Server`
creates all 50 of them at startup through its own `getOrCreateRemoteEvent`
helper, so `ServerScriptService/Wyrmhaven/Server.server.luau` **is** their
definition and it is versioned here. The combat ones are `RequestPveInfo`,
`RequestPveTeam`, `RequestPveFight`, `RequestPveAction` (client to server) and
`PveStatusUpdated`, `PveBattleStarted`, `PveBattleUpdate`, `PveBattleResult`
(server to client).

## Edited here, not yet in Studio — 2026-09-30 (new combat statuses)

Written in this folder (no Studio access in that session), tested with
`tools/combat-sim` (55 scripted checks + 300 AI fights), **to paste into
Studio by hand**:
`Config/StatusDefs`, `Services/{CombatEngine,CombatAI,PveService}`,
`UI/BattleScreen`.

- New statuses: Freeze, Sleep (controls, like Stun), Silence, Blind,
  Confuse, Expose (bad); Regen, Vigor, Thorns, Evade, Immune, Revive,
  MegaTaunt (good). Rules and numbers in `StatusDefs`.
- `stunTurns` is gone: every control is a status in `fighter.statuses`
  (`CombatEngine.IsDisabled(fighter)` / `battle:isDisabled` to ask).
- Cleanse now lifts every bad status (`StatusDefs.IsBad`), controls included.
- No skill in `SkillDefs` applies the new statuses yet.

# Roblox game page images (2D)

| File | Roblox slot | Size |
|---|---|---|
| `Icon.png` | Game icon | 512×512 |
| `Thumbnail.png` | Thumbnail, with the white logo | 1920×1080 (16:9) |
| `Thumbnail_Clean.png` | Same thumbnail, no text (Roblox shows the name next to it) | 1920×1080 |

`_preview_icon.png` shows the icon with Roblox's rounded corners at 512,
150 and 50 px.

3D renders built **only from the game's own models**, taken from the code
that builds them in the game (no model made up for these images):

| What | Source in the game | Extracted by |
|---|---|---|
| Island: grass plate, sea, lagoon, beach, cliffs, snowy mountain, palms | `IslandService.buildScenery` (+ the `IslandBase` part of `HabitatService`) | `game-models/extract_island.py` → `island_parts.json` |
| Obstacles: round trees, pines, rocks, big rocks, on their grid tiles | `IslandService` obstacle builders + `Config/IslandObstacles` | same |
| Fire Baby and Adult dragons | `DragonBuilder.luau` | `game-models/extract_dragons.py` → `fire_dragons.json` |
| Eggs | `DragonService` egg ball, `DragonDefs` Egg size 2×2.6×2 and egg colours | in `scene3d.html` |

The extractors run the game's Luau under standalone Luau with stand-ins for
Roblox (`island_stubs.luau`, `roblox_stubs.luau`) and record every part or
triangle the code creates; the game's files are not modified.

Not in the images because they aren't in this repo: the habitat, incubator,
building, decoration and crop models (`ReplicatedStorage.Wyrmhaven.Assets`,
made in Studio; the export only holds scripts). Exported from Studio as
.obj/.fbx into the repo, they can be added to the scene. Obstacle and
scenery placement uses the game's seeds but not Roblox's own `Random`
algorithm, so trees and rocks sit where the game's grid allows, not exactly
where a given server puts them.

- **Icon:** the adult Fire dragon, 3/4 towards the camera, island behind.
- **Thumbnail:** both Fire dragons and three eggs (Water, Nature, Dark) in
  the free starting area, the island's tree line and snowy mountain behind,
  the white logo centred at the top.

## Re-render

```
npm i three playwright-core                       # in this folder
python3 game-models/extract_dragons.py luau       # only if DragonBuilder changed
python3 game-models/extract_island.py luau        # only if IslandService / IslandObstacles changed
python3 compose.py                                # scene3d.html -> Icon.png, Thumbnail*.png, _preview_icon.png
```

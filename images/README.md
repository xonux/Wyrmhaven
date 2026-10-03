# images/

Icons for the game (upload the PNGs to Roblox: Asset Manager > Bulk Import).
Each folder keeps the script that draws its icons, to tweak and re-render.

| Folder | What | Size |
|---|---|---|
| `elements/` | Element badges (round): Fire, Water, Nature, Earth, Electric, Metal, Dark, Light | 512 |
| `statuses/` | Combat status icons (rounded squares: green = good, crimson = bad), incl. Mega Taunt, Lifesteal, Counter and the control protections as buffs (StunWard, FreezeWard, SleepWard, ControlWard). `_preview.png` shows them all (`make_preview.py`) | 256 |
| `attributes/` | Passive attributes, blue tiles; `...Ward` = protected against that status (gold shield), DotWard / ControlWard / DebuffWard = a whole family | 256 |
| `rarities/` | Rarity badges: round, letter C / R / E / L | 512 |
| `rarity-hex/` | Rarity badges, alternative: flat hexagons with the letter | 512 |
| `rarity-shards/` | One crystal shard per rarity | 512 |
| `rarity-star/` | 4-pointed star, one arm per rarity color | 512 |
| `shop/` | Shop tab icons (Dragons, Habitats, Buildings, Decorations) | — |
| `ui/` | Other UI icons, flat style: Combat, Shovel (SVG source + 512px PNG) | 512 |
| `illustrations/open-book/` | Illustration (not an icon): open book with an ink drawing of the baby fire dragon on the left page. `OpenBook.png` transparent, `OpenBook_preview.png` on a backdrop | 2400×1600 |

Files starting with `_preview` are contact sheets for review, not game assets.

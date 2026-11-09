# VeinKeeper

A lightweight World of Warcraft: Forever (1.60.1, interface 16001) addon that remembers every ore node you mine and shows it on your world map and minimap.

- Records a spot automatically when you finish mining a node.
- Custom icon per node type; a ring around it shows freshness (red = just mined, yellow = soon, green = likely respawned).
- World map pins (also shown on neighbouring zones and continent maps) with a tooltip: ores seen there, time since last mined, fastest respawn seen, visits, distance.
- Minimap pins, plus the nearest out-of-range spots on the minimap edge with their distance.
- Shared spawn points (e.g. Tin/Silver) merge into one pin; repeated hits on a multi-tap vein count as one visit; a spot's position is averaged over your first visits.
- Spots above your Mining skill are dimmed.

Type `/vk` in game for commands.

## Layout

| Path | What it is |
|---|---|
| `VeinKeeper/` | The addon itself (this folder goes in `Interface\AddOns`). |
| `VeinKeeper/Data.lua` | Every Forever mining node, its required skill and icon. Source: Wowhead's Forever object database. |
| `VeinKeeper/Icons/` | Generated 64x64 TGA icons. |
| `make_icons.py` | Draws the icons and `icon-preview.png` (needs Pillow). |
| `build.py` | Builds `VeinKeeper.zip`; `--install` copies the addon into the Forever AddOns folder. |

## Building

```bash
python make_icons.py VeinKeeper/Icons icon-preview.png   # only after changing icons
python build.py --install
```

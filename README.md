# VeinKeeper

A lightweight World of Warcraft: Forever (1.60.1, interface 16001) addon that remembers every ore node you mine and shows it on your world map and minimap.

- Records a spot automatically when you finish mining a node.
- Pins use the game's own ore icon for each node (Copper Ore, Thorium Ore, ...), cut round; a ring around it shows freshness (red = just mined, yellow = soon, green = likely respawned). Nodes with no ore item (Season of Discovery quest nodes) use VeinKeeper's drawn icons; `/vk icons` switches everything to the drawn set.
- With Find Minerals on, minimap spots in range turn into hollow rings, so the game's own yellow dot shows inside when the vein is up (addons can't read tracking blips, so this is the closest to hiding the pin). `/vk inrange hide` hides them instead, `/vk inrange icon` keeps the icons.
- World map pins (also shown on neighbouring zones and continent maps) with a tooltip: ores seen there, time since last mined, fastest respawn seen, visits, distance.
- Minimap pins, plus the nearest out-of-range spots on the minimap edge with their distance.
- Shared spawn points (e.g. Tin/Silver) merge into one pin; repeated hits on a multi-tap vein count as one visit; a spot's position is averaged over your first visits.
- Spots above your Mining skill are dimmed.

- Settings window (`/vk`, the minimap button, or the button in the top-right of the world map): world map and minimap pin opacity, respawn timer, edge pins, Find Minerals mode, icon style, and the buttons themselves.
- Shows up in the addon compartment (the minimap's addon list, which EllesmereUI keeps): left-click opens settings, right-click shows/hides pins. The minimap button is also a named minimap button, so button collectors can take it; once collected, VeinKeeper stops positioning it.

Type `/vk help` in game for the slash commands.

## Layout

| Path | What it is |
|---|---|
| `VeinKeeper/` | The addon itself (this folder goes in `Interface\AddOns`). |
| `VeinKeeper/Config.lua` | Settings window and the world map button. |
| `VeinKeeper/Data.lua` | Every Forever mining node, its required skill and icon. Source: Wowhead's Forever object database. |
| `VeinKeeper/Icons/` | Generated 64x64 TGA icons. |
| `make_icons.py` | Draws the icons and `icon-preview.png` (needs Pillow). |
| `build.py` | Builds `VeinKeeper.zip`; `--install` copies the addon into the Forever AddOns folder. |

## Building

```bash
python make_icons.py VeinKeeper/Icons icon-preview.png   # only after changing icons
python build.py --install
```

# VeinKeeper

A lightweight World of Warcraft: Forever addon (1.60.1, interface 16001) that remembers every ore vein you find and shows it on your world map and minimap, with respawn timers.

## Features

**Recording**
- Saves a spot when you finish mining a node. Shared spawn points (Tin/Silver, Mithril/Truesilver) merge into one spot, re-hitting a multi-tap vein counts as one visit, and the position is averaged over your first visits.
- With Find Minerals on, hovering a vein's yellow dot on the minimap saves it too, placed from the cursor position (a few yards' accuracy). It gets a blue ring until you mine it. Hovering a known spot's dot marks it as up.

**Pins**
- The game's own ore icon for each node, cut round. Season of Discovery quest nodes have no ore item and use VeinKeeper's drawn icons; `/vk icons` uses the drawn set everywhere.
- The ring shows freshness: red when just mined, yellow when soon, green when likely back, blue when seen but never mined.
- World map pins also appear on neighbouring zones and continent maps. Hover for ores seen, time since mined, fastest respawn seen, visits and distance. Click for a waypoint (TomTom if installed); shift + right-click forgets the spot.
- On the minimap, the nearest far spots sit on the rim with their distance. They're limited to spots likely back, within 500 yd by default.
- With Find Minerals on, spots in view become hollow rings so the game's yellow dot shows inside when the vein is up. Addons can't read tracking dots, so this is the closest thing to hiding the pin.
- Spots above your Mining skill are dimmed.

**Tools**
- `/vk next`, or a key under Key Bindings > AddOns: a waypoint to the nearest spot likely back. Ask again at an empty spot and it skips it.
- Ore filter: show just one ore, all its vein types together. Use the world map button's right-click menu, the settings window, or `/vk only thorium`.
- `/vk prune [days]`: delete spots visited only once and not seen for 30 days (or `[days]`).

**Settings** come up with `/vk`, the minimap button, the world map button (top right) or the addon compartment (which EllesmereUI also shows). The minimap button is a regular named minimap button, so button collectors can take it. `/vk help` lists the slash commands.

## Design

- **No per-frame work while idle.** The minimap tick (10 Hz) returns at once unless you moved, turned, zoomed or something changed. Saved spots are only searched again after you move 100 yd or the data changes, and pins are only restyled when their spot or the style changes. The tick stops entirely when minimap pins and hover recording are both off.
- **The world map does nothing while closed.** Changes made while it's closed are applied when it opens.
- **One event frame** for the whole addon, with internal messages: `VK_LOADED`, `VK_DATA` (rebuild) and `VK_STYLE` (restyle only).
- **No libraries.** The settings window is built the first time it's opened.

## Layout

| Path | What it is |
|---|---|
| `VeinKeeper/Core.lua` | Saved variables and defaults, event dispatcher, change messages, map/world coordinate math. |
| `VeinKeeper/Data.lua` | Every Forever mining node, its required skill and icon (source: Wowhead's Forever object database). |
| `VeinKeeper/Spots.lua` | The spot data model: filters, respawn timing, recording, mining detection, next spot, prune. |
| `VeinKeeper/Pins.lua` | Pin look, tooltip, waypoints and clicks shared by both maps. |
| `VeinKeeper/WorldMap.lua`, `WorldMap.xml` | World map data provider and pin template. |
| `VeinKeeper/Minimap.lua` | Minimap pins, rim pins and hover recording. |
| `VeinKeeper/Buttons.lua` | Minimap button, world map button, addon compartment. |
| `VeinKeeper/Config.lua` | Settings window and the ore filter menu. |
| `VeinKeeper/Commands.lua` | Slash commands. |
| `VeinKeeper/Bindings.xml` | Key bindings. |
| `VeinKeeper/Icons/` | Generated 64x64 TGA icons. |
| `make_icons.py` | Draws the icons and `icon-preview.png` (needs Pillow). |
| `build.py` | Builds `VeinKeeper.zip`; `--install` copies the addon into the Forever AddOns folder. |

## Building

```bash
python make_icons.py VeinKeeper/Icons icon-preview.png   # only after changing icons
python build.py --install
```

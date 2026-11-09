# Changelog

## 1.1.0

**New**
- `/vk next`, or a key under Key Bindings > AddOns: waypoint to the nearest spot that has likely respawned. Asking again at an empty spot skips it.
- Ore filter: show one ore only, all its vein types together. Right-click the world map button, use the settings window, or `/vk only thorium`.
- Minimap hover recording: with Find Minerals on, hovering a vein's dot on the minimap saves it (blue ring) or marks a known spot as up. Sweep the cursor across the dot for the best position; repeated hovers refine the same spot.
- Minimap rim pins only point at spots likely back, within 500 yd by default (both adjustable).
- `/vk prune [days]`: delete spots visited only once and not seen for 30 days.
- `/vk clear seen`: delete spots only ever seen on the minimap.
- Key bindings: next spot, show / hide pins, settings.
- Icon size sliders for the world map and minimap.
- Addon compartment entry (also shown by EllesmereUI).

**Changed**
- Two-column settings window with tooltips.
- Slash commands confirm with one line instead of repeating the help.
- Right-clicking a world map pin zooms the map out again; shift + right-click still forgets the spot.

**Performance**
- The minimap does no work while you stand still; saved spots are only searched again after moving 100 yd, and pins are only restyled when something changes.
- The world map does nothing while closed.
- One event frame for the whole addon; the skill check no longer expands the skill list on every weapon skill-up.

**Fixed**
- `ADDON_ACTION_BLOCKED` from world map pins.
- Minimap button not being collected by EllesmereUI.

## 1.0.0

- First release: records mined veins and shows them on the world map and minimap with game ore icons, freshness rings and respawn timers.

# Changelog

## 1.2.5

**New**
- Respawn times are learned per ore from your own play: mining a vein again, or first seeing its dot after mining, shows it was back by then. The estimate (the lower quartile of the last 24) replaces the respawn setting once an ore has 3 samples. Tooltips show it, and `/vk respawn` lists them.

**Performance**
- Minimap pins are only moved when they'd move by a pixel or more, and update at a third of the rate on a flight path.

**Changed**
- The "Likely back after" setting is now "Respawn until learned".

## 1.2.4

**Changed**
- A spot's position keeps improving: it combines the average of where you stood on every visit with the average of your Find Minerals hovers, weighted by how much each has seen.
- A hover is placed at the average cursor position while you rest on the vein's dot, not the middle of the area the cursor covered.
- A hover must last at least a second to count, so passing sweeps no longer save spots.

**Fixed**
- A vein that respawned quickly was saved as a second spot; duplicates already saved within 6 yd merge on login.
- Full sweeps across a dot indoors were discarded as too spread out.

## 1.2.3

**New**
- Pins too close to hover one by one: a pin's tooltip lists the spots overlapping it under "Also here:", with each one's state.
- Minimap tooltips with Find Minerals on: a ring shows its own tooltip, and a vein's yellow dot gets a VeinKeeper box under the game's tooltip.
- Sweeping the cursor across a mined vein's yellow dot (zoomed in) moves the spot from where you stood onto the vein.

**Fixed**
- Neighbouring veins mined on the same trip no longer merge into one spot: each node is told apart by its ID from the loot window, so a multi-tap vein still counts as one visit.
- Phantom "seen" spots from minimap hovers: a hover is dropped if the minimap zooms during it or the cursor strays too far, and mining a vein absorbs rough "seen" spots of it nearby.

## 1.2.2

**Performance**
- Much lower CPU use: checking the minimap's indoor / outdoor zoom no longer changes the zoom, which could make the check repeat every frame. The minimap now updates on a 10-per-second timer instead of checking every frame.

**New**
- `/vk cpu`: measures VeinKeeper's CPU use for 30 seconds.

**Changed**
- VeinKeeper has its own icon in the addon list and the addon compartment.

## 1.2.1

**Fixed**
- Installing and updating through WowUp on a WoW Forever installation.

## 1.2.0

**Changed**
- Mined veins are identified by their object ID (read from the loot window, or from the soft interact target when the game's SoftTargetInteract setting is on), so mining records correctly in every client language. The node's name is still the fallback.
- On non-English clients, the local name of each vein you mine is learned, so minimap hover recording recognizes it from then on.

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

# Changelog

## Unreleased

**New**
- Do veins come back where they were? Nothing documents whether WoW Forever respawns a mined vein at the same spot or somewhere else in a zone-wide pool, so VeinKeeper now measures it. Each time you come within 12 yd of a saved spot it notes whether the spot was likely back, and whether you then mined a vein there. `/vk pool` shows, per vein type, how often likely-back and not-back-yet spots had a vein, and what that says: spot timers can be trusted, veins come back across a shared pool, or something in between. Visits in combat or on a flight path aren't counted. `/vk pool reset` starts over.
- Pin tooltips show the measured chance a vein is there now ("Chance it's up: ~40% (23 visits)") once its type has 10 visits in that state.

## 1.2.14

**Changed**
- Respawn times are learned faster for vein types that share spawn points, such as Tin and Silver or Mithril and Truesilver: their samples are pooled, since a spawn point has one timer whatever spawns there. Types count as sharing once you've seen them together at two or more spots. `/vk respawn` lists each group on one line.

## 1.2.13

**New**
- Translations: VeinKeeper's own text (chat messages, tooltips, the settings and sharing windows, key binding names) now shows in German, French, Italian, Spanish (Spain and Latin America), Brazilian Portuguese, Russian, Korean and Chinese (simplified and traditional). These are first drafts; corrections from native speakers are very welcome (see *Translating* in the README). Text not yet translated stays English, and a translation with the wrong placeholders is ignored instead of causing an error.
- Vein names in tooltips and messages show as your game client names them once you've mined that kind of vein, and `/vk ignore` and `/vk only` accept those names too.

## 1.2.12

**New**
- Yield tracking: the loot of every vein you mine is counted per vein type (every tap of a multi-tap vein is one visit). Pin tooltips show the average ore a visit, such as "4.5 Thorium Ore a visit (14 visits)", once a type has 3 visits. `/vk yield` lists each type's ore, stone and gems (an amount a visit for what nearly always drops, a chance for the rest) and this session's haul with ore an hour. `/vk yield reset` starts the counts over.

## 1.2.11

**Performance**
- Much faster with many saved spots: finding the spots near a vein (when mining, hovering a minimap dot, importing, and tidying duplicates at login) only looks at the saved spots in the surrounding 240 yd square instead of every one. With 6,000 spots, the login tidy-up takes about 1/45th of the time and importing 3,000 spots about 1/40th. Results are exactly as before.

## 1.2.10

**New**
- Share spots: `/vk export` (or Export in the settings window) shows your spots as a text string to copy; `/vk export zone` only this zone's. It follows the ore filter and ignore list. `/vk import` (or Import) merges someone's string into your spots. Only positions and ores travel: your own spots, mining times and learned respawns stay as they are, and a vein you already have just gains any ore it lacked. New spots show as blue rings, "Imported" in their tooltip, until you mine or see them.
- `/vk clear imported`: delete imported spots you haven't mined or seen.

## 1.2.9

**New**
- Farm route: `/vk route` (or a key binding, or the world map button's menu) builds a short loop through every spot in your zone you can mine and draws it on the world map, with the leg to the next stop brighter. The waypoint moves on when you mine a stop, reach one that isn't back yet, or walk on from one that was empty. Veins you find while it runs join the loop; `/vk next` skips a stop, `/vk route off` ends it. With the ore filter set, the route only visits that ore.
- Pin tooltips show a spot's place on the route.

## 1.2.8

**Fixed**
- Pins in the sea on the World map: it shows each continent at its own scale, so each pin is now placed on its own continent there.

## 1.2.7

**Fixed**
- A Lua error when mining or hovering the minimap in a dungeon, where the game hides cast targets and some tooltip text. Spots still aren't saved inside instances (they have no map position).

## 1.2.6

**Fixed**
- Neighbouring veins hovered on the minimap no longer merge into one spot, or merge again on login: a hover only joins a spot within the error of both positions (about 8 px on the minimap at any zoom), instead of up to 60 yd. Repeat hovers of one vein still join it.

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

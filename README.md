# QuestHelper for WotLK 3.3.5a

QuestHelper 1.4.1 (Warperia build) for World of Warcraft 3.3.5a, with bug fixes and a few additions. QuestHelper works out a route through your quests and guides you along it with an arrow, map icons and its own quest tracker.

## Installing

1. Download the repository (**Code → Download ZIP**) and extract it.
2. Copy the `QuestHelper` folder into `World of Warcraft\Interface\AddOns\`, replacing any older copy. The folder must be named `QuestHelper`.
3. Restart the game if it's running.

## Changes from 1.4.1

- Crashes and Lua errors fixed, including the `collect_loot.lua` error when entering a dungeon and errors around loading screens.
- Quest progress in the tracker now updates reliably.
- The tracker groups quests under their quest log locations (Stormwind City, The Stockade and so on), and each heading has a show/hide button like the built-in tracker's. A minimised section keeps its heading only when something in it would have been listed.
- Right-clicking a quest in the tracker opens a menu in the game's own style: open the quest, track or stop tracking it, show it on the map, change its priority or ignore it, with Close at the bottom. QuestHelper's map menus use the same style.
- The tracker looks more like Questie's: objectives in white (tick Objective Color for red-to-green), and before each quest's title a quest giver's ?, grey while the quest is in progress and gold once it's ready to hand in. It's also the priority button: click it for High, double-click it for Highest, and click it again to put back the priority the quest had (Normal, if it was raised from the right-click menu). A quest's priority shows as a thin stripe down its left: red for Highest, orange for High, grey for Lowest and a fainter grey for Low. The stripe can be clicked and double-clicked the same way. A quest with objectives listed under it also has a button that shows or hides them.
- When your quest is complete but a party member still needs some of its objectives, those objectives stay listed under it, with the party member's own progress.
- Quest priorities are kept from one session to the next, for each character.
- The QuestHelper button on the world map sits beside Zoom Out, away from the corner where other map addons put their controls.
- The route's dots on the world map are twice as close together, and green on the way to the objective QuestHelper is taking you to, through any flight masters or portals on the way. Only those green dots march along; the rest of the route stands still. On a map a map addon has zoomed in or out (BetterMaps, Magnify and the like), they stay as close together on screen as on the unzoomed map.
- The world map no longer slows down with QuestHelper on it. Once the map had been opened, 1.4.1 drew the route, its map icons and the next objective's area all over again every frame; now they're drawn again only when something on them changes, and nothing is drawn while the map is closed.
- Where a map addon shows the land round a zone's map (BetterMaps' free camera), the route and QuestHelper's map icons carry on past the map's edges over that land, so a route into the next zone no longer stops at the edge. A stretch of the route to another continent (a boat or a portal) still stops at the map's edge, as on the game's own map.
- Objective areas on the world map are rounded off and filled to match, with thin outlines that stay thin however far a map addon zooms in.
- The orange glow QuestHelper puts on an objective while you hover its map icon stays on the objective when a map addon zooms in, and the same size on screen.
- Quests a party member has that you don't are listed under "*Name*'s quests".
- Creatures are identified correctly on 3.3.5, so a party member's quests no longer show on unrelated creatures' tooltips, and bad database entries no longer add route points and map icons in the wrong places.
- Settings that raised errors or didn't take effect when changed are fixed.

The first commit is the original 1.4.1, so the history shows every change.

## Credits

QuestHelper is by zorbathut, smariot, vipersniper and nesher ([quest-helper.com](http://www.quest-helper.com/)). Parts of `error.lua` come from Swatter by Norganna, under LGPL v3.0.

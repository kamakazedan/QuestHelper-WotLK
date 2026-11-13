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
- Right-clicking a quest in the tracker opens a menu in the game's own style: open the quest, track or stop tracking it, show it on the map, change its priority or ignore it. QuestHelper's map menus use the same style.
- The QuestHelper button on the world map sits beside Zoom Out, away from the corner where other map addons put their controls.
- Quests a party member has that you don't are listed under "*Name*'s quests".
- Settings that raised errors or didn't take effect when changed are fixed.

The first commit is the original 1.4.1, so the history shows every change.

## Credits

QuestHelper is by zorbathut, smariot, vipersniper and nesher ([quest-helper.com](http://www.quest-helper.com/)). Parts of `error.lua` come from Swatter by Norganna, under LGPL v3.0.

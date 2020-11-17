<p align="center"><img src="menu/logo.png"></p>

# Mine Game
Mine game, use the [Minetest](https://github.com/minetest/minetest) game engine.

The name of the game makes a word play with both meanings of mine, the mining
component of the game and the fact that this specific version of the game is
mine.

I started to used the modified version of the game by PetiAPocok 
[Minetest Extended](https://github.com/PetiAPocok/minetest_extended), I really
liked what he do with some mods and the core of the game.
Some things still needs changes, and some changes i didnt liked, so is a mix of
a lot of sources.

# Why
There are a lot of things that i loved of minetest and its mods, but also a
lot of things that i hated, the ggod thing about open source is that i can 
change the game as i wants... so that is what im doing.

# Changes

This mods are included from _minetest_extended_:
- 3d Armor with sfinv, stand and shields 
- Backpacks
- Carpets
- Clouds
- Doors
- Death Anounce
- Sfinv
- Fireflies
- Fire plus
- Fishing
- Flowerpot
- Frame
- Mobs, with animals and monster
- ts_furniture
- throwing

This mods are included from the oficial [_minetest_game_](https://github.com/minetest/minetest_game):
- Beds, Boats, Bones, Bucket, Default, Carts, Creative, Dye, Env Sounds,
Farming, Fire, Flowers, Player Api, Spawn, Gamme Commands, Vessels, TNT, Walls,
Weather, Wool, Stairs, Xpanes

I didn't include the following mods:
- Binoculars, Map, Screwdriver, Dungeon Loot, Give Initial Stuff, MTG Craftguide, Set Home

This ones are my own changes:
- Add [wooden_bucket](https://gitlab.com/h2mm/wooden_bucket) mod.
- Add Craftguide Mod
- Add Books Plus Mod
- Add mod Treasurer, with chests on piramids and dungeons
- Add [Thirsty](https://github.com/bendeutsch/minetest-thirsty), 
Sprint, Armor and Hunger mods, works with hudbars
- Add Bonemeal Mod
- Add [charcoal](https://forum.minetest.net/viewtopic.php?t=9779) 
- Remove corn as bait from fishing
- Fix bonemeal annd fishing to only rewrite default:dirt if drop is not defined
- Add Ambience
- Add Craft Table
- Add Item Drop
- Modifiy default, sfinv and crafting table to a 6x2 inventory and a 6 hotbar
- Remove Lava Pickaxe from Mobs Monster
- Change the backpac size to 6x4 grid
- fix the inventory size on armor view
- fix size in chests
- add [Sickles and Scythes](https://github.com/t-affeldt/sickles) mod
- add [trash can](https://github.com/minetest-mods/trash_can) mod 

# To Do
This are the things that are missing or the bugs to solve:
  - ~~fix the inventory size on chest~~
  - fix the inventory size on furnace
  - fix the inventory size on bookshelf
  - fix the inventory size on vessels shelf
  - fix the inventory size on armor stand
  - fix the inventory size on beehive 
  - modify the skin list to the windows size
  - remove senseless items from thrirsty
  - add hidratation behaviour to foods
  - ~~fix hidratation reset on login~~ (not happening in 5.3)
  - fix creative menu to avoid overlay
  - ~~fix carthographer error~~ (carthographer was removed)
  - ~~fix armor hudbar always on 0%~~ (not happening in 5.3)
  - ~~hide bed top and botton from crafting list~~ (not happening in 5.3)
  - ~~fix error when going to sleep~~ (not happening in 5.3)
  - fix armor bar at 0% when the game starts
  - change stamina rediction to 1 instead of 2
  - add stamina reduction when minning
  - ~~change buckets to be filled with water instead of river water~~ make only the river water drinkable
  - replace river water name for potable water
  - add a recipe to make potable water from water boiling it on the furnace
  - always open crafting when press inventory key
  - remove dumpster from trash can mod
  - fix shift click overflow of inventory
  - change inventory size on trash can

# Images
The logos and images were made with [TextCraft](https://textcraft.net) hoping
not breaking any copyright, but maybe I change the images for some created 
(or purchased) by me.

# License
The individual mods and games belongs to their owners with its own licence 
restrictions. 

The code writen by me is published under the Unlicence, see LICENSE.txt
I think that the knowledge is free and belongs to the world.

# Minecraft Commands
The goal of this mod is to add Minecraft command syntax (such as `/kill @e[type=mobs_mc:zombie, distance = 2..]`[/icode]`) to Minetest. It will also add command blocks that can run these commands.

## Current command list:
* `/bc`*: Allows players to run any command added by this mod even if its name matches the name of an existing command (for example, `/bc give @a default:dirt` or even `/bc bc bc bc give @a default:dirt`)
* `/?`: Alias for `/help`
* `/ability <player> <priv> [true/false]`: Shows or sets `<priv>` of `<player>`.
* `/kill [target]`: Kills entities (or self if left empty)
* `/killme`\*: Equivalent to `/kill @s`
* `/give <player> <item>`: Gives `<item>` to `<player>`
* `/giveme <item>`\*: Equivalent to `/give @s <item>`
* `/msg`: Alias for `/tell`
* `/say <message>`: Sends a message to all connected players (supports entity selectors in `<message>`)
* `/teleport [too many argument combinations]`: Sets entities' position and rotation
* `/tell <player> <message>`: Sends a message to specific players (supports entity selectors in `<message>`)
* `/tp`: Alias for `/teleport`
* `/w`: Alias for `/tell`

\* Not technically in Minecraft

## Entity selectors
Everywhere you would normally enter a player name, you can use an entity selector instead. Entity selectors let you choose multiple entities and narrow down exactly which ones you want to include.

There are 5 selectors:
* `@s`: Self (the player running the command)
* `@a`: All players
* `@e`: All entities
* `@r`: Random player
* `@p`: Nearest player

`@r` and `@p` can also select multiple players or other entities if using the `type` or `limit`/`c` **arguments** (explained below).

### Selector arguments
Selectors support various arguments, which allow you to select more specific entities. To add arguments to a selector, put them in `[square brackets]` like this:
```
@e[type=mobs_mc:zombie,name=Bob]
```
You can include spaces if you want (although this many spaces seems a bit excessive):
```
@e [ type = mobs_mc:zombie , name = Bob ]
```
This selector selects all MineClone2/5/ia zombies named Bob (note: `name` might not actually work yet in MCL; I've only tested in MTG so far).

All arguments must be satisfied for an entity to be selected.

`@s` ignores all arguments, unlike in Minecraft.

Here is the current list of arguments:
* `x`/`y`/`z`: Sets the position for the `distance`/`rm`/`r` arguments. If one or more are left out, it defaults to the position where the command was run.
* `distance`: Distance from where the command was run. This supports ranges (described below).
* `rm`/`r`: Identical to `distance=<rm>..<r>` (this is slightly different from Minecraft's usage).
* `name`: The name of the entity (only tested with players and Mobs Redo mobs)
* `type`: The entity ID (for example `mobs_mc:zombie`)
* `sort`: The method for sorting entities. Can be `arbitrary` (default for `@a` and `@e`), `nearest` (default for `@p`), `furthest`, or `random` (default for `@r`).
* `limit`/`c`: The maximum number of entites to match. `limit` and `c` do exactly the same thing.

#### Number ranges
Some arguments (currently just `distance` at the moment) support number ranges. These are basically `min..max` (you don't need both). Everywhere a range is accepted, a normal number will also be accepted.
Examples of ranges:
* `1..1`: Matches exactly 1
* `1..2`: Matches any number between 1 and 2 (inclusive)
* `1..`: Matches any number greater than or equal to 1
* `..-1.5`: Matches any number less than or equal to -1.5
* `1..-1`: Matches no numbers (since it would have to be greater than 1 *and* less than -1, which is impossible).

#### Excluding with arguments
Some arguments (such as `name` and `type`) allow you to prefix the value with `!`. This means that it will match anything *except* the entered value. For example, since `@e[type=player]` matches all players, `@e[type=!player]` matches all entities that are *not* players. Arguments testing for equality cannot be duplicated, while arguments testing for inequality can. In other words, you can have as many `type=!<something>` as you want but only one `type=<something>`.

## Known Issues:
(note: this is specifically the issues that I might not resolve before release)
1. There will probably be issues if there are registered items with the itemstring `e`, `a`, `s`, `r`, or `p`. `modname:e` is fine, just not `e` by itself. This applies to aliases as well.
2. I can't figure out how to do quotes or escape characters. This means that you cannot do things like `/kill @e[name="Trailing space "]` or have `]` in any part of entity/item data.
3. `/tp` does not support Bedrock's `checkForBlocks` argument since I didn't want figure out the code for loading un-generated mapblocks to see if nodes exist.
4. In games that do not support MTG or MCL digging methods, command blocks may be unbreakable.

## Textures
Command block textures are my own (CC-BY-SA-4.0), based on Minecraft's.
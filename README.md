# Better Commands
The goal of this mod is to add Minecraft command syntax (such as `/kill @e[type=mobs_mc:zombie, distance = 2..]`[/icode]`) to Minetest. It will also add command blocks that can run these commands.

## Known Issues:
(note: this is specifically the issues that I might not resolve before release)
1. There will probably be issues if there are registered items with the itemstring `e`, `a`, `s`, `r`, or `p`. `modname:e` is fine, just not `e` by itself. This applies to aliases as well.
2. Players with names that match itemstrings might not work correctly?
3. I can't figure out how to do quotes or escape characters. This means that you cannot do things like `/kill @e[name="Trailing space "]` or have `]` in any part of entity/item data.
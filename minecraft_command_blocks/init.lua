local mesecons = minetest.get_modpath("mesecons")
local command_blocks = {
    {"command_block", "Command Block"},
    {"repeating_command_block", "Repeating Command Block"},
    {"chain_command_block", "Chain Command Block"},
}

local anim = {type = "vertical_frames"}
local mesecons_rules = {
    {x = 0, y = 0, z = 1},
    {x = 0, y = 0, z = -1},
    {x = 0, y = 1, z = 0},
    {x = 0, y = -1, z = 0},
    {x = 1, y = 0, z = 0},
    {x = -1, y = 0, z = 0},
}

local already_run = {}

minetest.register_privilege("fast_command_block", {
    description = "Allows players to set the speed of repeating command blocks",
    give_to_singleplayer = true,
    give_to_admin = true
})

local function on_rightclick(pos, node, player, itemstack, pointed_thing)
    local command = minetest.get_meta(pos):get_string("minecraft_commands_command")
    local fast_command_block = minetest.check_player_privs(player, {fast_command_block = true})
end

local function run_command(pos)
    local node = minetest.get_node(pos)
    local meta = minetest.get_meta(pos)
    if meta:get_string("minecraft_commands_mesecons_activate") == "true" then
        if meta:get_string("mesecons_active") ~= "true" then
            return
        end
    end
    local group = minetest.get_item_group(node.name, "command_block")
    if group > 3 then -- conditional
        local dir = minetest.facedir_to_dir(node.param2)
        local previous = vector.add(dir, pos)
        if minetest.get_meta(previous):get_string("minecraft_commands_result") ~= "success" then
            if group == 6 then -- chain
                local next = vector.add(-dir, pos)
                local next_group = minetest.get_item_group(minetest.get_node(next).name, "command_block")
                if next_group == 3 or next_group == 6 then -- chain
                    local pos_string = minetest.pos_to_string(next)
                    if not already_run[pos_string] then
                        run_command(next)
                    end
                end
            end
            return
        end
    end

    if group == 3 or group == 6 then
        local pos_string = minetest.pos_to_string(pos)
        if already_run[pos_string] then return end
        already_run[pos_string] = true
        minetest.after(0, function() already_run[pos_string] = nil end)
    end

    local command = meta:get_string("minecraft_commands_command")
    if command ~= "" then
        local command_type, param = command:match("(%S+)%s+(.*)$")
        local def = minetest.registered_chatcommands[command_type]
        if def then
            local name = meta:get_string("minecraft_commands_name")
            -- Other mods' commands may require <name> to be a valid player name.
            if not minecraft_commands.commands[command_type] then
                name = meta:get_string("minecraft_commands_player")
                if name == "" then return end
            end
            def.func(name, param, pos)
        end
    end
end

local function mesecons_activate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("mesecons_active", "true")
    if meta:get_string("minecraft_commands_mesecons_activate") == "true" then
        if minetest.get_item_group(minetest.get_node(pos).name, "command_block") < 3 then
            run_command(pos)
        end
    end
end

local function mesecons_deactivate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("mesecons_active", "")
    if meta:get_string("minecraft_commands_mesecons_activate") == "true" then
        minetest.get_node_timer(pos):stop()
    end
end

for i, command_block in pairs(command_blocks) do
    local name, desc = unpack(command_block)
    local noic = name ~= "command_block"
    local def = {
        description = "Conditional "..desc,
        groups = {not_in_creative_inventory = noic and 1 or 0, command_block = i, creative_breakable=1, mesecon_effector_off=1, mesecon_effector_on=1},
        tiles = {
            {name = "minecraft_commands_"..name.."_top.png", animation = anim},
            {name = "minecraft_commands_"..name.."_bottom.png", animation = anim},
            {name = "minecraft_commands_"..name.."_right.png", animation = anim},
            {name = "minecraft_commands_"..name.."_left.png", animation = anim},
            {name = "minecraft_commands_"..name.."_front.png", animation = anim},
            {name = "minecraft_commands_"..name.."_back.png", animation = anim},
        },
        paramtype2 = "facedir",
        on_rightclick = on_rightclick,
        on_timer = run_command,
        mesecons = {
            effector = {
                action_on = mesecons_activate,
                action_off = mesecons_deactivate,
                rules = mesecons_rules
            },
        },
        _mcl_blast_resistance = 3600000,
        _mcl_hardness = -1,
    }
    minetest.register_node("minecraft_commands:"..name, table.copy(def))

    def.groups.not_in_creative_inventory = 1
    def.groups.command_block = i+3
    def.description = "Conditional "..desc
    def.tiles = {
        {name = "minecraft_commands_"..name.."_conditional_top.png", animation = anim},
        {name = "minecraft_commands_"..name.."_conditional_bottom.png", animation = anim},
        {name = "minecraft_commands_"..name.."_conditional_right.png", animation = anim},
        {name = "minecraft_commands_"..name.."_conditional_left.png", animation = anim},
        {name = "minecraft_commands_"..name.."_front.png", animation = anim},
        {name = "minecraft_commands_"..name.."_back.png", animation = anim},
    }

    minetest.register_node("minecraft_commands:"..name.."_conditional", table.copy(def))
end
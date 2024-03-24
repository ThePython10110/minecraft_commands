local command_blocks = {
    {"impulse", "Command Block"},
    {"repeating", "Repeating Command Block"},
    {"chain", "Chain Command Block"},
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

local function get_string_or(meta, key, fallback)
    local result = meta:get_string(key)
    return result == "" and fallback or result
end

local types = {
    [1] = {"Impulse", false},
    [2] = {"Repeat", false},
    [3] = {"Chain", false},
    [4] = {"Impulse", true},
    [5] = {"Repeat", true},
    [6] = {"Chain", true},
}

local function on_rightclick(pos, node, player)
    if not minetest.check_player_privs(player, "command_block") then return end
    local meta = minetest.get_meta(pos)
    local command = meta:get_string("_command")
    local group = minetest.get_item_group(node.name, "command_block")
    local power = meta:get_string("_power") == "true" and "Needs Power" or "Always Active"
    local result = meta:get_string("_result")
    local delay = get_string_or(meta, "_delay", (group == 2 or group == 5) and "1" or "0")
    local formspec = table.concat({
        "formspec_version[4]",
        "size[10,6]",
        "label[0.5,0.5;",ItemStack(node.name):get_short_description(),"]",
        "field[6.5,0.5;2,1;delay;Delay (seconds);",delay,"]",
        "field_close_on_enter[delay;false]",
        "button[8.5,0.5;1,1;set_delay;Set]",
        "field[0.5,2;8,1;command;Command;",minetest.formspec_escape(command),"]",
        "field_close_on_enter[command;false]",
        "button[8.5,2;1,1;set_command;Set]",
        "button[0.5,3.5;3,1;type;",types[group][1],"]",
        "button[3.5,3.5;3,1;conditional;",types[group][2] and "Conditional" or "Unconditional","]",
        "button[6.5,3.5;3,1;power;",power,"]",
        "textarea[0.5,5;9,1;;Previous output;",minetest.formspec_escape(result),"]",
    })
    local player_name = player:get_player_name()
    minetest.show_formspec(player_name, "minecraft_command_blocks:"..minetest.pos_to_string(pos), formspec)
end

function minecraft_commands.get_command_block_name(category, group)
    if not category or category == "" then category = "_" end
    return minecraft_commands.command_block_categories[category][group]
end

minecraft_commands.command_block_categories = {}

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local pos = minetest.string_to_pos(formname:match("^minecraft_command_blocks:(%([%d%.]+,[%d%.]+,[%d%.]+%))$"))
    if not pos then return end
    local meta = minetest.get_meta(pos)
    local node = minetest.get_node(pos)
    local group = minetest.get_item_group(node.name, "command_block")
    local category = minetest.registered_items[node.name].command_block_category
    local fast_command_block = minetest.check_player_privs(player, {fast_command_block = true})
    local show_formspec
    if fields.key_enter_field == "command" or fields.set_command then
        show_formspec = true
        meta:set_string("_command", fields.command)
    elseif fields.key_enter_field == "delay" or fields.set_delay then
        show_formspec = true
        local delay = tonumber(fields.delay)
        if delay and delay >= 0 then
            meta:set_string("_delay", fields.delay)
        end
    elseif fields.type then
        local new_group = group + 1
        if new_group == 4 or new_group == 7 then new_group = new_group - 3 end
        local new_node = table.copy(node)
        new_node.name = minecraft_commands.get_command_block_name(category, new_group)
        minetest.swap_node(pos, new_node)
        if new_group == 2 or new_group == 5 then
            minetest.get_node_timer(pos):start(1)
        else
            minetest.get_node_timer(pos):stop()
        end
        if new_group == 2 or new_group == 5 then -- repeating
            if (tonumber(meta:get_string("_delay")) or 1) < 1 then
                meta:set_string("_delay", "1")
            end
        elseif group == 2 or group == 5 then -- previous = repeating
            if (tonumber(meta:get_string("_delay")) or 1) == 1 then
                meta:set_string("_delay", "0")
            end
        end
        show_formspec = true
    elseif fields.conditional then
        local new_group = group + 3
        if new_group > 6 then new_group = new_group - 6 end
        local new_node = table.copy(node)
        new_node.name = minecraft_commands.get_command_block_name(category, new_group)
        minetest.swap_node(pos, new_node)
        show_formspec = true
    elseif fields.power then
        local result = fields.power == "Always Active" and "true" or ""
        meta:set_string("_power", result)
        if result ~= "true" then
            if group ~= 3 and group ~= 6 then
                minecraft_commands.run_command_block(pos)
            end
        end
        show_formspec = true
    end
    group = minetest.get_item_group(minetest.get_node(pos).name, "command_block")
    if group == 2 or group == 5 then
        if not fast_command_block then
            if (tonumber(meta:get_string("_delay")) or 1) < 1 then
                show_formspec = true
                meta:set_string("_delay", "1")
                minetest.chat_send_player(player:get_player_name(), "You do not have the `fast_command_block` privilege, meaning the minimum delay for a repeating command block is 1 second.")
            end
        end
    end
    if show_formspec then
        on_rightclick(pos, minetest.get_node(pos), player)
    end
end)

local function check_for_chain(pos)
    local dir = minetest.facedir_to_dir(minetest.get_node(pos).param2)
    local next = vector.add(dir, pos)
    local next_group = minetest.get_item_group(minetest.get_node(next).name, "command_block")
    if next_group == 0 then return end
    if next_group == 3 or next_group == 6 then -- chain
        local pos_string = minetest.pos_to_string(next)
        if not already_run[pos_string] then
            minecraft_commands.run_command_block(next)
        end
    end
end

function minecraft_commands.run_command_block(pos)
    local node = minetest.get_node(pos)
    local meta = minetest.get_meta(pos)
    if meta:get_string("_power") == "true" then
        if meta:get_string("_mesecons_active") ~= "true" then
            return
        end
    end
    local group = minetest.get_item_group(node.name, "command_block")
    if group > 3 then -- conditional
        local dir = minetest.facedir_to_dir(node.param2)
        local previous = vector.add(-dir, pos)
        if minetest.get_meta(previous):get_string("_result") ~= "Success" then
            if group == 6 then -- chain
                check_for_chain(pos)
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

    local command = meta:get_string("_command")
    if command ~= "" then
        local command_type, param = command:match("(%S+)%s+(.*)$")
        local def = minetest.registered_chatcommands[command_type]
        if def then
            local name = meta:get_string("_name")
            -- Other mods' commands may require <name> to be a valid player name.
            if not minecraft_commands.commands[command_type] then
                name = meta:get_string("_player")
                if name == "" then return end
            end
            if group == 2 or group == 5 then
                local success, result_text = def.func(name, param, pos)
                if success then result_text = "success" end
                meta:set_string("_result", result_text)
                minetest.get_node_timer(pos):start(tonumber(meta:get_string("_delay")) or 1)
                check_for_chain(pos)
            else
                local delay = tonumber(meta:get_string("_delay")) or 0
                if delay > 0 then
                    minetest.after(delay, function()
                        local success, result_text = def.func(name, param, pos)
                        if success then result_text = "success" end
                        meta:set_string("_result", result_text)
                        check_for_chain(pos)
                    end)
                else
                    local success, result_text = def.func(name, param, pos)
                    if success then result_text = "success" end
                    meta:set_string("_result", result_text)
                    check_for_chain(pos)
                end
            end
        end
    end
end

local function mesecons_activate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("_mesecons_active", "true")
    if meta:get_string("_power") == "true" then
        local group = minetest.get_item_group(minetest.get_node(pos).name, "command_block")
        if group ~= 3 and group ~= 6 then
            minecraft_commands.run_command_block(pos)
        end
    end
end

local function mesecons_deactivate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("_mesecons_active", "")
    if meta:get_string("_power") == "true" then
        minetest.get_node_timer(pos):stop()
    end
end

function minecraft_commands.register_command_block_category(category, overrides)
    category = category or ""
    overrides = overrides or {}
    local category2 = category == "" and category or category.."_"
    local category_key = category == "" and "_" or category
    minecraft_commands.command_block_categories[category_key] = {}
    for i, command_block in pairs(command_blocks) do
        local name, desc = unpack(command_block)
        local def = {
            description = desc,
            groups = {cracky = 1, command_block = i, creative_breakable=1, mesecon_effector_off=1, mesecon_effector_on=1},
            tiles = {
                {name = "minecraft_command_blocks_"..category2..name.."_top.png", animation = anim},
                {name = "minecraft_command_blocks_"..category2..name.."_bottom.png", animation = anim},
                {name = "minecraft_command_blocks_"..category2..name.."_right.png", animation = anim},
                {name = "minecraft_command_blocks_"..category2..name.."_left.png", animation = anim},
                {name = "minecraft_command_blocks_"..category2..name.."_front.png", animation = anim},
                {name = "minecraft_command_blocks_"..category2..name.."_back.png", animation = anim},
            },
            paramtype2 = "facedir",
            on_rightclick = on_rightclick,
            on_timer = minecraft_commands.run_command_block,
            command_block_category = category,
            mesecons = {
                effector = {
                    action_on = mesecons_activate,
                    action_off = mesecons_deactivate,
                    rules = mesecons_rules
                },
            },
            _mcl_blast_resistance = 3600000,
            _mcl_hardness = -1,
            can_dig = function(pos, player)
                return minetest.check_player_privs(player, "command_block")
            end,
            drop = "",
            after_place_node = function(pos, placer, itemstack, pointed_thing)
                minetest.get_meta(pos):set_string("_player", placer:get_player_name())
            end
        }
        if overrides.global then
            for key, value in pairs(overrides.global) do
                def.key = value
            end
        end
        local unconditional_def = table.copy(def)
        if overrides.unconditional then
            for key, value in pairs(overrides.unconditional_def) do
                def.key = value
            end
        end
        if overrides[i] then
            for key, value in pairs(overrides[i]) do
                unconditional_def.key = value
            end
        end
        local itemstring = "minecraft_command_blocks:"..category2..name.."_command_block"
        minecraft_commands.command_block_categories[category_key][i] = itemstring
        minetest.register_node(itemstring, unconditional_def)

        local conditional_def = table.copy(def)
        conditional_def.groups.not_in_creative_inventory = 1
        conditional_def.groups.command_block = i+3
        conditional_def.description = "Conditional "..desc
        conditional_def.tiles = {
            {name = "minecraft_command_blocks_"..category2..name.."_conditional_top.png", animation = anim},
            {name = "minecraft_command_blocks_"..category2..name.."_conditional_bottom.png", animation = anim},
            {name = "minecraft_command_blocks_"..category2..name.."_conditional_right.png", animation = anim},
            {name = "minecraft_command_blocks_"..category2..name.."_conditional_left.png", animation = anim},
            {name = "minecraft_command_blocks_"..category2..name.."_front.png", animation = anim},
            {name = "minecraft_command_blocks_"..category2..name.."_back.png", animation = anim},
        }
        if overrides.conditional then
            for key, value in pairs(overrides.unconditional) do
                conditional_def.key = value
            end
        end
        if overrides[i+3] then
            for key, value in pairs(overrides[i+3]) do
                conditional_def.key = value
            end
        end
        itemstring = "minecraft_command_blocks:"..category2..name.."_command_block_conditional"
        minecraft_commands.command_block_categories[category_key][i+3] = itemstring
        minetest.register_node(itemstring, conditional_def)
    end
    minetest.register_alias("minecraft_command_blocks:"..category2.."command_block", "minecraft_command_blocks:"..category2.."impulse_command_block")
    minetest.register_alias("minecraft_command_blocks:"..category2.."command_block_conditional", "minecraft_command_blocks:"..category2.."impulse_command_block_conditional")
end

minecraft_commands.register_command_block_category()

minetest.register_privilege("command_block", {
    description = "Allows players to use command blocks",
    give_to_singleplayer = false,
    give_to_admin = true
})

minetest.register_privilege("fast_command_block", {
    description = "Allows players to set the speed of repeating command blocks",
    give_to_singleplayer = false,
    give_to_admin = true
})
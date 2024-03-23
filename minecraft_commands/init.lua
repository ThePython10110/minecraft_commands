minecraft_commands = {commands = {}, players = {}}

local S = minetest.get_translator()

minetest.register_on_mods_loaded(function()

minecraft_commands.override = minetest.settings:get_bool("minecraft_commands_override", false)
minecraft_commands.edition = (minetest.settings:get("minecraft_commands_edition") or "java"):lower()


function minecraft_commands.register_command(name, def)
    minecraft_commands.commands[name] = def
    if minetest.registered_chatcommands[name] then
        if minecraft_commands.override then
            minetest.override_chatcommand(name, def)
            minetest.log("action", "[Minecraft Commands] Overriding "..name)
        else
            minetest.log("action", "[Minecraft Commands] Not registering "..name.." as it already exists.")
        end
    else
        minetest.register_chatcommand(name, def)
    end
end

function minecraft_commands.handle_alias(itemstring)
    local stack = ItemStack(itemstring)
    return stack:is_known() and stack:get_name() ~= "unknown"
end

function minecraft_commands.parse_params(str)
    local i = 1
    local tmp
    local found = {}
    -- selectors
    repeat
        tmp = {str:find("(@[psaer])%s*(%[.-%])", i)}
        if tmp[1] then
            i = tmp[2] + 1
            tmp.type = "selector"
            tmp.extra_data = true
            table.insert(found, table.copy(tmp))
        end
    until not tmp[1]

    -- items
    i = 1
    repeat
        tmp = {str:find("([_%w]*:?[_%w]+)%s*(%[.-%])%s*(%d*)", i)}
        if tmp[1] then
            i = tmp[2] + 1
            if minecraft_commands.handle_alias(tmp[3]) then
                tmp.type = "item"
                tmp.extra_data = true
                table.insert(found, table.copy(tmp))
            end
        end
    until not tmp[1]

    -- items without extra data
    i = 1
   repeat
       tmp = {str:find("([_%w]*:?[_%w]+)%s+(%d+)", i)}
       if tmp[1] then
           i = tmp[2] + 1
           if minecraft_commands.handle_alias(tmp[3]) then
               tmp.type = "item"
               tmp.extra_data = true
               table.insert(found, table.copy(tmp))
           end
       end
   until not tmp[1]

    -- everything else
    i = 1
    repeat
        tmp = {str:find("(%S+)", i)}
        if tmp[1] then
            i = tmp[2] + 1
            local overlap
            for _, thing in pairs(found) do
                if tmp[1] >= thing[1] and tmp[1] <= thing[2]
                or tmp[2] >= thing[1] and tmp[2] <= thing[2]
                or tmp[1] <= thing[1] and tmp[2] >= thing[2] then
                    overlap = true
                    break
                end
            end
            if not overlap then
                if tmp[3]:find("^@[psaer]$") then
                    tmp.type = "selector"
                elseif minecraft_commands.players[tmp[3]] then
                    tmp.type = "selector"
                elseif minecraft_commands.handle_alias(tmp[3]) then
                    tmp.type = "item"
                elseif tonumber(tmp[3]) then
                    tmp.type = "number"
                elseif tmp[3]:lower() == "true" or tmp[3]:lower() == "false" then
                    tmp.type = "boolean"
                elseif tmp[3]:find("^~%-?%d*%.?%d*$") then
                    tmp.type = "relative"
                elseif tmp[3]:find("^%^%-?%d*%.?%d*$") then
                    tmp.type = "look_relative"
                else
                    tmp.type = "string"
                end
                table.insert(found, table.copy(tmp))
            end
        end
    until not tmp[1]

    -- sort
    table.sort(found, function(a,b)
        return a[1] < b[1]
    end)

     --beginning

    minetest.log(dump(found))
    return found
end

function minecraft_commands.parse_range(num, range)
    if tonumber(range) then return num == range end
    -- "min..max" where both numbers are optional
    local _, _, min, max = range:find("(%d*%.?%d*)%s*%.%.%s*(%d*%.?%d*)")
    if not min then return end
    min = tonumber(min)
    max = tonumber(max)
    if min and num < min then return false end
    if max and num > max then return false end
    return true
end

function minecraft_commands.get_entity_name(obj, use_id)
    if obj:is_player() then
        return obj:get_player_name()
    else
        local luaentity = obj:get_luaentity()
        if luaentity then
            if not use_id then
                return luaentity._nametag or ""
            else
                local name = luaentity._nametag or luaentity.name
                return name or "1 object"
            end
        end
    end
end

function minecraft_commands.get_entity_rotation(obj)
    if obj:is_player() then
        return {x = obj:get_look_vertical(), y = obj:get_look_horizontal(), z = 0}
    else
        return obj:get_rotation()
    end
end

function minecraft_commands.set_entity_rotation(obj, rotation)
    if obj:is_player() then
        obj:set_look_vertical(rotation.x)
        obj:set_look_horizontal(rotation.y)
    else
        obj:set_rotation(rotation)
    end
end

-- key = handle duplicates automatically?
minecraft_commands.supported_keys = {
    distance = true,
    name = false,
    type = false,
    r = true,
    rm = true,
    sort = true,
    limit = false,
    c = false,
    x = true,
    y = true,
    z = true,
}

-- Returns a success boolean and either an error message or list of ObjectRefs matching the selector
-- (if @s with a command block, {command block's position} instead)
function minecraft_commands.parse_selector(selector_data, caller, require_one)
    local command_block = not caller.is_player
    local pos = command_block and caller or caller:get_pos()
    local result = {}
    if selector_data[3]:sub(1,1) ~= "@" then
        return true, {minetest.get_player_by_name(selector_data[3])}
    end
    local arg_table = {}
    if selector_data[4] then
        -- basically matching "(thing)=(thing)[,%]]"
        for key, value in selector_data[4]:gmatch("([%w_]+)%s*=%s*([^,%]]+)%s*[,%]]") do
            table.insert(arg_table, {key:trim(), value:trim()})
        end
    end

    local objects = {}
    local selector = selector_data[3]
    if selector == "@s" then
        return true, {caller}
    end
    if selector == "@e" then
        for _, luaentity in pairs(minetest.luaentities) do
            if luaentity.object:get_pos() then
                table.insert(objects, luaentity.object)
            end
        end
    end
    if selector == "@e" or selector == "@a" or selector == "@p" or selector == "@r" then
        for _, player in pairs(minetest.get_connected_players()) do
            if player:get_pos() then
                table.insert(objects, player)
            end
        end
    end
    -- Make type selector work for @r (since it does in Bedrock)
    if selector == "@r" or selector == "@p" then
        for _, arg in ipairs(arg_table) do
            if arg[1] == "type" and arg[2] ~= "player" then
                for _, luaentity in pairs(minetest.luaentities) do
                    if luaentity.object:get_pos() then
                        table.insert(objects, luaentity.object)
                    end
                end
            end
        end
    end

    local sort
    if selector == "@p" then
        sort = "nearest"
    elseif selector == "@r" then
        sort = "random"
    else
        sort = "arbitrary"
    end
    local limit
    if selector == "@p" then limit = 1 end

    if arg_table then
        -- Look for pos first
        local checked = {}
        for _, arg in pairs(arg_table) do
            local key, value = unpack(arg)
            if key == "x" or key == "y" or key == "z" then
                if checked[key] then
                    return false, "Duplicate key: "..key
                end
                if value:sub(1,1) == "~" then
                    value = value:sub(2,-1)
                    if value == "" then value = 0 end
                end
                checked[key] = true
                pos[key] = tonumber(value)
                if not pos[key] then
                    return false, "Invalid value for "..key
                end
                checked[key] = true
            end
        end
        for _, obj in pairs(objects) do
            local checked = {}
            if obj.is_player then -- checks if it is a valid entity
                local matches = true
                for _, arg in pairs(arg_table) do
                    local key, value = unpack(arg)
                    if minecraft_commands.supported_keys[key] == nil then
                        return false, "Unsupported key: "..key
                    elseif minecraft_commands.supported_keys[key] == true then
                        if checked[key] then
                            return false, "Duplicate key: "..key
                        end
                        checked[key] = true
                    end
                    if key == "distance" then
                        local distance = vector.distance(obj:get_pos(), pos)
                        if not minecraft_commands.parse_range(distance, value) then
                            matches = false
                        end
                    elseif key == "type" then
                        local obj_type
                        if obj:is_player() then
                            obj_type = "player"
                        else
                            obj_type = obj:get_luaentity().name
                        end
                        if value:sub(1,1) == "!" then
                            if obj_type == value:sub(2, -1) then
                                matches = false
                            end
                        else
                            if checked["type"] then
                                return false, "Duplicate key: type"
                            end
                            checked["type"] = true
                            if obj_type ~= value then
                                matches = false
                            end
                        end
                    elseif key == "name" then
                        local obj_name = minecraft_commands.get_entity_name(obj)
                        if value:sub(1,1) == "!" then
                            if obj_name == value:sub(2, -1) then
                                matches = false
                            end
                        else
                            if checked["name"] then
                                return false, "Duplicate key: name"
                            end
                            checked["name"] = true
                            if obj_name ~= value then
                                matches = false
                            end
                        end
                    elseif key == "r" then
                        matches = vector.distance(obj:get_pos(), pos) < value
                    elseif key == "rm" then
                        matches = vector.distance(obj:get_pos(), pos) > value
                    elseif key == "sort" then
                        sort = value
                    elseif key == "limit" or key == "c" then
                        if checked.limit then
                            return false, "Only 1 of keys c and limit can exist."
                        end
                        checked.limit = true
                        if not tonumber(value) then
                            return false, key.." must be a number."
                        end
                        limit = math.floor(tonumber(value))
                        if limit == 0 then
                            return false, key.." must not be 0."
                        end
                    end
                    if not matches then
                        break
                    end
                end
                if matches then
                    table.insert(result, obj)
                end
            end
        end
    else
        result = objects
    end
    -- Sort
    if sort == "random" then
        table.shuffle(result)
    elseif sort == "nearest" or (sort == "furthest" and limit < 0) then
        table.sort(result, function(a,b) return vector.distance(a:get_pos(), pos) < vector.distance(b:get_pos(), pos) end)
    elseif sort == "furthest" or (sort == "nearest" and limit < 0) then
        table.sort(result, function(a,b) return vector.distance(a:get_pos(), pos) > vector.distance(b:get_pos(), pos) end)
    end
    -- Limit
    if limit then
        local new_result = {}
        local i = 1
        while i <= limit do
            if not result[i] then break end
            table.insert(new_result, result[i])
            i = i + 1
        end
        result = new_result
    end
    if require_one then
        if #result == 0 then
            return false, "Target entity not found."
        elseif #result > 1 then
            return false, "Multiple target entities found."
        end
    end

    return true, result
end

function minecraft_commands.parse_item(item_data)
    if not minecraft_commands.handle_alias(item_data[3]) then
        return false, "Invalid item: "..tostring(item_data[3])
    end
    if item_data.type == "item" and not item_data.extra_data then
        local stack = ItemStack(item_data[3])
        stack:set_count(tonumber(item_data[4]) or 1)
        stack:set_wear(tonumber(item_data[5]) or 1)
        return stack
    elseif item_data.type == "item" then
        local arg_table = {}
        if item_data[4] then
            -- basically matching "(thing)=(thing)[,%]]"
            for key, value in item_data[4]:gmatch("([%w_]+)%s*=%s*([^,%]]+)%s*[,%]]") do
                arg_table[key:trim()] = value:trim()
            end
        end
        local stack = ItemStack(item_data[3])
        if arg_table then
            local meta = stack:get_meta()
            for key, value in pairs(arg_table) do
                meta:set_string(key, value)
            end
        end
        stack:set_count(tonumber(item_data[5]) or 1)
        stack:set_wear(tonumber(item_data[6]) or 1)
        return stack
    end
end

-- Slightly modified from builtin/game/chat.lua
local function handle_give_command(cmd, giver, receiver, stack_data)
	core.log("action", (giver or "Command Block").. " invoked " .. cmd
			.. ', stack_data=' .. dump(stack_data))
	local itemstack = minecraft_commands.parse_item(stack_data)
    if not itemstack then
        return false, S("Error")
    end
	if itemstack:is_empty() then
		return false, S("Cannot give an empty item.")
	elseif (not itemstack:is_known()) or (itemstack:get_name() == "unknown") then
		return false, S("Cannot give an unknown item.")
	-- Forbid giving 'ignore' due to unwanted side effects
	elseif itemstack:get_name() == "ignore" then
		return false, S("Giving 'ignore' is not allowed.")
	end
	local receiverref = core.get_player_by_name(receiver)
	if receiverref == nil then
		return false, S("@1 is not a known player.", receiver)
	end
	local leftover = receiverref:get_inventory():add_item("main", itemstack)
	local partiality
	if leftover:is_empty() then
		partiality = nil
	elseif leftover:get_count() == itemstack:get_count() then
		partiality = false
	else
		partiality = true
	end
	-- The actual item stack string may be different from what the "giver"
	-- entered (e.g. big numbers are always interpreted as 2^16-1).
	stack_data = itemstack:to_string()
	local msg
	if partiality == true then
		msg = S("@1 partially added to inventory.", stack_data)
	elseif partiality == false then
		msg = S("@1 could not be added to inventory.", stack_data)
	else
		msg = S("@1 added to inventory.", stack_data)
	end
	if giver == receiver then
		return true, msg
	else
		core.chat_send_player(receiver, msg)
		local msg_other
		if partiality == true then
			msg_other = S("@1 partially added to inventory of @2.",
					stack_data, receiver)
		elseif partiality == false then
			msg_other = S("@1 could not be added to inventory of @2.",
					stack_data, receiver)
		else
			msg_other = S("@1 added to inventory of @2.",
					stack_data, receiver)
		end
		return true, msg_other
	end
end

-- kind of unnecessary
local axes = {"x","y","z"}

function minecraft_commands.parse_pos(data, start, obj)
    local pos = obj.get_pos and obj:get_pos() or obj
    local result = {x = pos.x, y = pos.y, z = pos.z}
    local look
    for i = 0, 2 do
        if not data[start + i] then
            return false, "Missing coordinate."
        end
        local coordinate, _type = data[start + i][3], data[start + i].type
        if _type == "number" then
            if look then
                return false, "Cannot mix local and global coordinates."
            end
            result[axes[i+1]] = tonumber(coordinate)
            look = false
        elseif _type == "relative" then
            if look then
                return false, "Cannot mix local and global coordinates."
            end
            result[axes[i+1]] = result[axes[i+1]] + (tonumber(coordinate:sub(2,-1)) or 0)
            look = false
        elseif _type == "look_relative" then
            if look == false then
                return false, "Cannot mix local and global coordinates."
            end
            result[axes[i+1]] = tonumber(coordinate:sub(2,-1)) or 0
            look = true
        else
            return false, "Invalid coordinate: "..coordinate
        end
    end
    if look then
        local rotation = minecraft_commands.get_entity_rotation(obj)
        -- There's almost definitely a better way to do this...
        -- All I know is when moving in the Y direction,
        -- X/Z are backwards, and when moving in the Z direction,
        -- Y is backwards... so I fixed it (probably badly)
        local result_x = vector.rotate(vector.new(result.x,0,0), rotation)
        local result_y = vector.rotate(vector.new(0,result.y,0), rotation)
        result_y.z = -result_y.z
        result_y.x = -result_y.x
        local result_z = vector.rotate(vector.new(0,0,result.z), rotation)
        result_z.y = -result_z.y
        result = vector.add(vector.add(vector.add(pos, result_x), result_y), result_z)
    end
    return true, result
end

minecraft_commands.register_command("bc", {
    params = "<command data>",
    description = "Runs any Minecraft Command, so Minecraft Commands don't have to override existing commands.",
    privs = {},
    func = function(name, param, command_block)
        local command, command_param = param:match("^%/?([%S]+)%s*(.-)$")
        local def = minecraft_commands.commands[command]
        if def and (command_block or minetest.check_player_privs(name, def.privs)) then
            return def.func(name, command_param, command_block)
        else
            return false, "Invalid command: "..tostring(command)
        end
    end
})

minecraft_commands.register_command("?", minetest.registered_chatcommands.help)

minecraft_commands.register_command("ability", {
    params = "<player> <priv> [value]",
    description = "Sets <priv> of <player> to [value] (true/false). If [value] is not supplied, returns the existing value of <priv>.",
    privs = {privs = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if not split_param[1] and split_param[2] then
            return false
        end
        local set = split_param[3] and split_param[3][3]:lower()
        if set and set ~= "true" and set ~= "false" then
            return false, "[value] must be true or false (or missing)"
        end
        local parsed, targets = minecraft_commands.parse_selector(split_param[1], caller)
        if not parsed then
            return parsed, targets
        end
        local priv = split_param[2][3]
        if targets then
            for _, target in ipairs(targets) do
                if target.is_player and target:is_player() then
                    local target_name = target:get_player_name()
                    local privs = minetest.get_player_privs(target_name)
                    if not set then
                        if minetest.registered_privileges[priv] then
                            if privs[priv] then
                                return true, "true"
                            else
                                return true, "false"
                            end
                        else
                            return false, "Invalid privilege"
                        end
                    else
                        if not minetest.registered_privileges[priv] then
                            return false, "Invalid privilege"
                        else
                            if set == "true" then
                                privs[priv] = true
                            else
                                privs[priv] = nil
                            end
                            minetest.set_player_privs(target_name, privs)
                            minetest.chat_send_player(target_name, string.format("%s privilege %s by %s",priv, set == "true" and "granted" or "revoked", name))
                            return true
                        end
                    end
                end
            end
        end
    end
})

minecraft_commands.register_command("kill", {
    params = "[target]",
    description = "Kills targets or self",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        if param == "" then param = "@s" end
        local split_param = minecraft_commands.parse_params(param)
        local parsed, targets = minecraft_commands.parse_selector(split_param[1], caller)
        if not parsed then
            return parsed, targets
        end
        local count = 0
        local last
        for _, target in ipairs(targets) do
            if target.is_player then
                if not (target:is_player() and minetest.is_creative_enabled(target:get_player_name())) then
                    last = minecraft_commands.get_entity_name(target, true)
                    target:set_hp(0, {type = "set_hp", minecraft_commands = "kill"})
                    count = count + 1
                end
            end
        end
        if count < 1 then
            return true, "No matching entity found."
        elseif count == 1 then
            return true, string.format("Killed %s.", last)
        else
            return true, string.format("Killed %s entities.", count)
        end
    end
})

minecraft_commands.register_command("killme", {
    params = "",
    description = "Kills self",
    privs = {server = true},
    func = function(name, param, command_block)
        minecraft_commands.commands.kill.func(name, "", command_block)
    end
})

-- Make sure things really die when /killed
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if reason.minecraft_commands == "kill" then
        return -player:get_properties().hp_max, true
    end
    return hp_change
end, true)

minecraft_commands.register_command("give", {
    params = "<target> <item> [count] [wear]",
    description = "Gives [count] of <item> to <target>",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if not (split_param[1] and split_param[2]) then
            return false
        end
        local parsed, targets = minecraft_commands.parse_selector(split_param[1], caller)
        if not parsed then
            return parsed, targets
        end
        for _, target in ipairs(targets) do
            if target.is_player and target:is_player() then
                handle_give_command("/give", name, target:get_player_name(), split_param[2])
            end
        end
    end
})

minecraft_commands.register_command("giveme", {
    params = "<item> [count] [wear]",
    description = "Gives [count] of <item> to the caller",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if caller.is_player and caller:is_player() then
            handle_give_command("/give", name, name, split_param[1])
        end
    end
})

minecraft_commands.register_command("say", {
    params = "<message>",
    description = "Says <message> (which can include selectors such as @a)",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if not split_param[1] then return false end
        local message = "["..name.."] "
        for _, data in ipairs(split_param) do
            if data.type == "selector" then
                local parsed, targets = minecraft_commands.parse_selector(data, caller)
                if not parsed then
                    return parsed, targets
                end
                for i, obj in ipairs(targets) do
                    if not obj.is_player then
                        message = message.."Command Block"
                        break
                    end
                    message = message..minecraft_commands.get_entity_name(obj, true)
                    if #targets == 1 then
                        break
                    elseif #targets == 2 and i == 1 then
                        message = message.." and "
                    elseif i < #targets then
                        message = message..", "
                    end
                end
            else
                for i = 3,#data do
                    message = message.." "..data[i]
                end
            end
        end
        minetest.chat_send_all(message)
    end
})

local function point_at_pos(obj, pos)
    local obj_pos = obj:get_pos()
    if obj:is_player() then
        obj_pos.y = obj_pos.y + obj:get_properties().eye_height
    end
    local result = vector.dir_to_rotation(vector.direction(obj_pos, pos))
    result.x = -result.x -- no clue why this is necessary
    return result
end

local function handle_tp_rotation(caller, victim, split_param, i)
    local victim_rot = minecraft_commands.get_entity_rotation(victim)
    if split_param[i] then
        local yaw_pitch
        local facing
        if split_param[i].type == "number" then
            victim_rot.y = math.rad(tonumber(split_param[i][3]))
            yaw_pitch = true
        elseif split_param[i].type == "relative" then
            victim_rot.y = victim_rot.y+math.rad(tonumber(split_param[i][3]:sub(2,-1)) or 0)
            yaw_pitch = true
        elseif split_param[i].type == "string" and split_param[i][3] == "facing" then
            facing = true
        end
        if yaw_pitch and split_param[i+1] then
            if split_param[i+1].type == "number" then
                victim_rot.x = math.rad(tonumber(split_param[i+1][3]))
            elseif split_param[i+1].type == "relative" then
                victim_rot.x = victim_rot.x+math.rad(tonumber(split_param[i+1][3]:sub(2,-1)) or 0)
            end
        elseif facing and split_param[i+1] then
            if split_param[i+1].type == "selector" then
                local parsed, targets = minecraft_commands.parse_selector(split_param[i+1], caller, true)
                if not parsed then
                    return parsed, targets
                end
                local target_pos = targets[1].is_player and targets[1]:get_pos() or targets[1]
                victim_rot = point_at_pos(victim, target_pos)
            elseif split_param[i+1][3] == "entity" and split_param[i+2].type == "selector" then
                local parsed, targets = minecraft_commands.parse_selector(split_param[i+2], caller, true)
                if not parsed then
                    return parsed, targets
                end
                local target_pos = targets[1].is_player and targets[1]:get_pos() or targets[1]
                victim_rot = point_at_pos(victim, target_pos)
            else
                local parsed, target_pos = minecraft_commands.parse_pos(split_param, i+1, caller)
                if not parsed then
                    return parsed, target_pos
                end
                victim_rot = point_at_pos(victim, target_pos)
            end
        end
        if yaw_pitch or facing then
            minecraft_commands.set_entity_rotation(victim, victim_rot)
        end
    end
end

-- some duplicate code
minecraft_commands.register_command("teleport", {
    params = "[entity/ies] <location/entity> ([yaw] [pitch] | [facing <location/entity>])",
    description = "Teleports and rotates things.",
    privs = {teleport = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if not split_param[1] then return false end
        if split_param[1].type == "selector" then
            if not split_param[2] then
                if command_block then
                    return false, "Command blocks can't teleport (although I did consider making it possible)"
                end
                local parsed, targets = minecraft_commands.parse_selector(split_param[1], caller, true)
                if not parsed then
                    return parsed, targets
                end
                local target_pos = targets[1].is_player and targets[1]:get_pos() or targets[1]
                caller:set_pos(target_pos)
                caller:add_velocity(-caller:get_velocity())
                local rotation = minecraft_commands.get_entity_rotation(targets[1]) or vector.new(0,0,0)
                minecraft_commands.set_entity_rotation(caller, rotation)
                return true
            elseif split_param[2].type == "selector" then
                local parsed, victims = minecraft_commands.parse_selector(split_param[1], caller)
                if not parsed then
                    return parsed, victims
                end
                if #victims == 0 then
                    return false, "No entity found."
                end
                local parsed, targets = minecraft_commands.parse_selector(split_param[2], caller, true)
                if not parsed then
                    return parsed, targets
                end
                local target_pos = targets[1].is_player and targets[1]:get_pos() or targets[1]
                for _, victim in ipairs(victims) do
                    if victim.is_player then
                        victim:set_pos(target_pos)
                        if victim:is_player() then
                            victim:add_velocity(-victim:get_velocity())
                        else
                            victim:set_velocity(vector.new(0,0,0))
                        end
                        local rotation = minecraft_commands.get_entity_rotation(targets[1]) or vector.new(0,0,0)
                        minecraft_commands.set_entity_rotation(victim, rotation)
                    end
                end
                return true
            elseif split_param[2].type == "number" or split_param[2].type == "relative" or split_param[2].type == "look_relative" then
                local parsed, victims = minecraft_commands.parse_selector(split_param[1], caller)
                if not parsed then
                    return parsed, victims
                end
                local parsed, target_pos = minecraft_commands.parse_pos(split_param, 2, caller)
                if not parsed then
                    return parsed, target_pos
                end
                for _, victim in ipairs(victims) do
                    if victim.is_player then
                        victim:set_pos(target_pos)
                        if not (split_param[2].type == "look_relative"
                        or split_param[2].type == "relative"
                        or split_param[3].type == "relative"
                        or split_param[4].type == "relative") then
                            if victim:is_player() then
                                victim:add_velocity(-victim:get_velocity())
                            else
                                victim:set_velocity(vector.new(0,0,0))
                            end
                        end
                        handle_tp_rotation(caller, victim, split_param, 5)
                    end
                end
                return true
            end
        elseif split_param[1].type == "number" or split_param[1].type == "relative" or split_param[1].type == "look_relative" then
            if command_block then
                return false, "Command blocks can't teleport (although I did consider making it possible)"
            end
            local parsed, target_pos = minecraft_commands.parse_pos(split_param, 1, caller)
            if not parsed then
                return parsed, target_pos
            end
            if caller.is_player and caller:is_player() then
                caller:set_pos(target_pos)
                if not (split_param[1].type == "look_relative"
                or split_param[1].type == "relative"
                or split_param[2].type == "relative"
                or split_param[3].type == "relative") then
                    caller:add_velocity(-caller:get_velocity())
                end
            end
            handle_tp_rotation(caller, caller, split_param, 4)
            return true
        end
    end
})

minecraft_commands.register_command("tp", minecraft_commands.commands.teleport)

minecraft_commands.register_command("msg", {
    params = "<target> <message>",
    description = "Sends <message> privately to <target>",
    privs = {shout = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = minecraft_commands.parse_params(param)
        if not split_param[1] and split_param[2] then
            return false
        end
        local parsed, targets = minecraft_commands.parse_selector(split_param[1], caller)
        if not parsed then
            return parsed, targets
        end
        local message = string.format("<%s> %s whispers to you:\n", name, name)
        for i, data in ipairs(split_param) do
            if i > 1 then
                if data.type == "selector" then
                    local parsed, targets = minecraft_commands.parse_selector(data, caller)
                    if not parsed then
                        return parsed, targets
                    end
                    for j, obj in ipairs(targets) do
                        if not obj.is_player then
                            message = message.."Command Block"
                            break
                        end
                        message = message..minecraft_commands.get_entity_name(obj, true)
                        if #targets == 1 then
                            break
                        elseif #targets == 2 and i == 1 then
                            message = message.." and "
                        elseif j < #targets then
                            message = message..", "
                        end
                    end
                else
                    for j = 3,#data do
                        message = message.." "..data[j]
                    end
                end
            end
        end
        for _, target in ipairs(targets) do
            if target.is_player and target:is_player() then
                minetest.chat_send_player(target:get_player_name(), message)
            end
        end
    end
})

minecraft_commands.register_command("w", minecraft_commands.commands.msg)
minecraft_commands.register_command("tell", minecraft_commands.commands.msg)

end)

-- Build list of all registered players (https://forum.minetest.net/viewtopic.php?t=21582)
minetest.after(0,function()
	for name, value in minetest.get_auth_handler().iterate() do
        minecraft_commands.players[name] = true
	end
end)
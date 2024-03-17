local S = minetest.get_translator()

better_commands = {commands = {}}

better_commands.override = minetest.settings:get_bool("better_commands_override", false)
better_commands.edition = (minetest.settings:get("better_commands_edition") or "java"):lower()
better_commands.messages = {
    player_error = "%s does not appear to be a valid player. It could be a typo or the player could be offline."
}


local function register_command(name, def)
    if minetest.registered_chatcommands[name] then
        if better_commands.override then
            minetest.override_chatcommand(name, def)
            better_commands.commands[name] = def
            minetest.log("action", "[Better Commands] Overriding "..name)
        else
            minetest.log("action", "[Better Commands] Not registering "..name.." as it already exists.")
        end
    else
        minetest.register_chatcommand(name, def)
    end
end

local function handle_alias(itemstring)
    local stack = ItemStack(itemstring)
    return stack:is_known() and stack:get_name() ~= "unknown"
end

local function parse_args(str)
    local i = 1
    local tmp
    local found = {}
     -- selectors
    repeat
        tmp = {str:find("(@[psaer])%s*(%[.-%])", i)}
        if tmp[1] then
            i = tmp[2] + 1
            tmp.type = "selector_data"
            table.insert(found, table.copy(tmp))
        end
    until not tmp[1]

     -- items
    repeat
        tmp = {str:find("([_%w]*:?[_%w]+)%s*(%[.-%])%s*(%d*)", i)}
        if tmp[1] then
            i = tmp[2] + 1
            if handle_alias(tmp[3]) then
                tmp.type = "item_data"
                table.insert(found, table.copy(tmp))
            end
        end
    until not tmp[1]

    -- items without extra data
   repeat
       tmp = {str:find("([_%w]*:?[_%w]+)%s+(%d+)", i)}
       if tmp[1] then
           i = tmp[2] + 1
           if handle_alias(tmp[3]) then
               tmp.type = "item"
               table.insert(found, table.copy(tmp))
           end
       end
   until not tmp[1]

     -- everything else
    repeat
        tmp = {str:find("%s-(%S+)%s-", i)}
        if tmp[1] then
            i = tmp[2] + 1
            local overlap
            for _, thing in pairs(found) do
                if tmp[1] > thing[1] and tmp[1] < thing[2]
                or tmp[2] > thing[1] and tmp[2] < thing[2]
                or tmp[1] < thing[1] and tmp[2] < thing[2] then
                    overlap = true
                    break
                end
            end
            if not overlap then
                if tmp[3]:find("^@[psaer]$") then
                    tmp.type = "selector"
                elseif handle_alias(tmp[3]) then
                    tmp.type = "item"
                end
                table.insert(found, table.copy(tmp))
            end
        end
    until not tmp[1]

    -- sort
    table.sort(found, function(a,b)
        return a[1] < b[1]
    end)

     -- beginning
    if #found > 0 and found[1][1] > 1 then
        local beginning = {str:find("^(.-)%s")}
        if beginning then
            table.insert(found, 1, {1, #(beginning[3]:trim()), beginning[3]:trim()})
        end
    end
    return found
end

local function parse_range(num, range)
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

local function get_entity_name(obj)
    if obj:is_player() then
        return obj:get_player_name()
    else
        local luaentity = obj:get_luaentity()
        if luaentity then
            return luaentity._nametag
        end
    end
end

-- Returns a list of ObjectRefs matching the selector
-- (if @s with a command block, {command block's position} instead)
local function parse_selector(selector_data, caller)
    local command_block = not caller.is_player
    local pos = command_block and caller or caller:get_pos()
    local result = {}
    if selector_data[3]:sub(1,1) ~= "@" then
        return {minetest.get_player_by_name(selector_data[3])}
    end
    local arg_table = {}
    if selector_data[4] then
        -- basically matching "(thing)=(thing)[,%]]"
        for key, value in selector_data[4]:gmatch("([%w_]+)%s*=%s*([^,%]]+)%s*[,%]]") do
            arg_table[key:trim()] = value:trim()
        end
        minetest.log(dump(arg_table))
    end

    local objects = {}
    if selector_data[3] == "@s" then
        return {caller}
    end
    if selector_data[3] == "@e" then
        for _, luaentity in pairs(minetest.luaentities) do
            if luaentity.object:get_pos() then
                table.insert(objects, luaentity.object)
            end
        end
        for _, player in pairs(minetest.get_connected_players()) do
            table.insert(objects, player)
        end
    end
    if selector_data[3] == "@a" or selector_data[3] == "@p" or selector_data[3] == "@r" then
        for _, player in pairs(minetest.get_connected_players()) do
            table.insert(objects, player)
        end
    end

    if arg_table then
        for _, obj in pairs(objects) do
            if obj.is_player then -- checks if it is a valid entity
                local matches = true
                for key, value in pairs(arg_table) do
                    if key == "distance" then
                        minetest.log(dump(obj:get_pos()))
                        local distance = vector.distance(obj:get_pos(), pos)
                        if not parse_range(distance, value) then
                            matches = false
                            break
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
                        elseif obj_type ~= value then
                            matches = false
                        end
                    elseif key == "name" then
                        matches = get_entity_name(obj) == value
                    elseif key == "r" then
                        matches = vector.distance(obj:get_pos(), pos) < value
                    elseif key == "rm" then
                        matches = vector.distance(obj:get_pos(), pos) > value
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
    minetest.log(dump(result))
    return result
end

local function parse_item(item_data)
    if not handle_alias(item_data[3]) then return end
    if item_data.type == "item" then
        local stack = ItemStack(item_data[3])
        stack:set_count(tonumber(item_data[4]) or 1)
        stack:set_wear(tonumber(item_data[5]) or 1)
        return stack
    elseif item_data.type == "item_data" then
        local arg_table = {}
        if item_data[4] then
            -- basically matching "(thing)=(thing)[,%]]"
            for key, value in item_data[4]:gmatch("([%w_]+)%s*=%s*([^,%]]+)%s*[,%]]") do
                arg_table[key:trim()] = value:trim()
            end
            minetest.log(dump(arg_table))
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
	local itemstack = parse_item(stack_data)
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

register_command("?", minetest.registered_chatcommands.help)

register_command("ability", {
    params = "<player> <priv> [value]",
    description = "Sets <priv> of <player> to [value] (true/false). If [value] is not supplied, returns the existing value of <priv>.",
    privs = {privs = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = parse_args(param)
        if not split_param[1] and split_param[2] then
            return false
        end
        local set = split_param[3] and split_param[3][3]:lower()
        if set and set ~= "true" and set ~= "false" then
            return false, "[value] must be true or false (or missing)"
        end
        local targets = parse_selector(split_param[1][3], caller)
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

register_command("kill", {
    params = "<target>",
    description = "Kills targets",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        if param == "" then param = "@s" end
        local split_param = parse_args(param)
        local targets = parse_selector(split_param[1], caller)
        local count = 0
        local last
        for _, target in ipairs(targets) do
            if target.is_player then
                if not (target:is_player() and minetest.is_creative_enabled(target:get_player_name())) then
                    target:set_hp(0, {type = "set_hp", better_commands = "kill"})
                    count = count + 1
                    last = get_entity_name(target)
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

minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if reason.better_commands == "kill" then
        return -player:get_properties().hp_max, true
    end
    return hp_change
end, true)

register_command("give", {
    params = "<target> <item> [count] [wear]",
    description = "Gives [count] of <item> to <target> (item can have data, for instance default:dirt[inventory_image=default_cobble.png])",
    privs = {server = true},
    func = function(name, param, command_block)
        local caller = command_block or minetest.get_player_by_name(name)
        if not caller then return end
        local split_param = parse_args(param)
        minetest.log(dump(split_param))
        if not (split_param[1] and split_param[2]) then
            return false
        end
        for _, target in ipairs(parse_selector(split_param[1], caller)) do
            if target.is_player and target:is_player() then
                minetest.log(dump({handle_give_command("/give", name, target:get_player_name(), split_param[2])}))
            end
        end
    end
})
craftguide = {}

-- Caches
local pdata         = {}
local init_items    = {}
local searches      = {}
local recipes_cache = {}
local usages_cache  = {}
local fuel_cache    = {}
local replacements  = {fuel = {}}
local toolrepair

local progressive_mode = core.settings:get_bool "craftguide_progressive_mode"
local sfinv_only = core.settings:get_bool "craftguide_sfinv_only" and rawget(_G, "sfinv")

local http = core.request_http_api()
local singleplayer = core.is_singleplayer()

local reg_items = core.registered_items
local reg_tools = core.registered_tools
local reg_aliases = core.registered_aliases

local log = core.log
local after = core.after
local clr = core.colorize
local sound_play = core.sound_play
local parse_json = core.parse_json
local write_json = core.write_json
local chat_send = core.chat_send_player
local show_formspec = core.show_formspec
local globalstep = core.register_globalstep
local on_shutdown = core.register_on_shutdown
local get_players = core.get_connected_players
local get_craft_result = core.get_craft_result
local translate = minetest.get_translated_string
local on_joinplayer = core.register_on_joinplayer
local get_all_recipes = core.get_all_craft_recipes
local register_command = core.register_chatcommand
local get_player_by_name = core.get_player_by_name
local slz, dslz = core.serialize, core.deserialize
local on_mods_loaded = core.register_on_mods_loaded
local on_leaveplayer = core.register_on_leaveplayer
local get_player_info = core.get_player_information
local on_receive_fields = core.register_on_player_receive_fields

local ESC = core.formspec_escape
local S = core.get_translator "craftguide"

local ES = function(...)
	return ESC(S(...))
end

local maxn, sort, concat, copy, insert, remove =
	table.maxn, table.sort, table.concat, table.copy,
	table.insert, table.remove

local fmt, find, gmatch, match, sub, split, upper, lower =
	string.format, string.find, string.gmatch, string.match,
	string.sub, string.split, string.upper, string.lower

local min, max, floor, ceil, abs = math.min, math.max, math.floor, math.ceil, math.abs
local pairs, next, type, unpack = pairs, next, type, unpack
local vec_add, vec_mul = vector.add, vector.multiply

local ROWS = 9
local LINES = sfinv_only and 5 or 10
local IPP = ROWS * LINES
local WH_LIMIT = 10
local MAX_FAVS = 6
local ITEM_BTN_SIZE = 1.1

local XOFFSET = sfinv_only and 3.83 or 11.2
local YOFFSET = sfinv_only and 4.9 or 1

-- Progressive mode
local POLL_FREQ = 0.25
local HUD_TIMER_MAX = 1.5

local PNG = {
	bg = "craftguide_bg.png",
	bg_full = "craftguide_bg_full.png",
	search = "craftguide_search_icon.png",
	clear = "craftguide_clear_icon.png",
	prev = "craftguide_next_icon.png^\\[transformFX",
	next = "craftguide_next_icon.png",
	arrow = "craftguide_arrow.png",
	fire = "craftguide_fire.png",
	fire_anim = "craftguide_fire_anim.png",
	book = "craftguide_book.png",
	sign = "craftguide_sign.png",
	nothing = "craftguide_no.png",
	selected = "craftguide_selected.png",
	furnace_anim = "craftguide_furnace_anim.png",

	search_hover = "craftguide_search_icon_hover.png",
	clear_hover = "craftguide_clear_icon_hover.png",
	prev_hover = "craftguide_next_icon_hover.png^\\[transformFX",
	next_hover = "craftguide_next_icon_hover.png",
}

local FMT = {
	box = "box[%f,%f;%f,%f;%s]",
	label = "label[%f,%f;%s]",
	image = "image[%f,%f;%f,%f;%s]",
	button = "button[%f,%f;%f,%f;%s;%s]",
	tooltip = "tooltip[%f,%f;%f,%f;%s]",
	hypertext = "hypertext[%f,%f;%f,%f;;%s]",
	item_image = "item_image[%f,%f;%f,%f;%s]",
	image_button = "image_button[%f,%f;%f,%f;%s;%s;%s]",
	animated_image = "animated_image[%f,%f;%f,%f;;%s;%u;%u]",
	item_image_button = "item_image_button[%f,%f;%f,%f;%s;%s;%s]",
	arrow = "image_button[%f,%f;0.8,0.8;%s;%s;;;false;%s]",
}

local styles = fmt([[
	style[filter;border=false]
	style_type[label,field;font_size=16]
	style_type[image_button;border=false]
	style_type[button;border=false;font=bold;font_size=18]
	style_type[item_image_button;border=false;bgimg_hovered=%s;bgimg_pressed=%s]
	style[search;fgimg=%s;fgimg_hovered=%s]
	style[clear;fgimg=%s;fgimg_hovered=%s]
	style[prev_page;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
	style[next_page;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
	style[prev_recipe;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
	style[next_recipe;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
	style[prev_usage;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
	style[next_usage;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]
]],
PNG.selected, PNG.selected,
PNG.search, PNG.search_hover,
PNG.clear, PNG.clear_hover,
PNG.prev, PNG.prev_hover, PNG.prev_hover,
PNG.next, PNG.next_hover, PNG.next_hover,
PNG.prev, PNG.prev_hover, PNG.prev_hover,
PNG.next, PNG.next_hover, PNG.next_hover,
PNG.prev, PNG.prev_hover, PNG.prev_hover,
PNG.next, PNG.next_hover, PNG.next_hover)

local function get_lang_code(name)
	local info = get_player_info(name)
	return info and info.lang_code
end

local function outdated(name)
	local fs = fmt([[
		size[6.6,1.3]
		image[0,0;1,1;%s]
		label[1,0;%s]
		button_exit[2.8,0.8;1,1;;OK]
	]],
	PNG.book,
	"Your Minetest client is outdated.\n" ..
	"Get the latest version on minetest.net to use the Crafting Guide.")

	return show_formspec(name, "craftguide", fs)
end

local function mul_elem(elem, n)
	local fstr, elems = "", {}

	for i = 1, n do
		fstr = fstr .. "%s"
		elems[i] = elem
	end

	return fmt(fstr, unpack(elems))
end

craftguide.group_stereotypes = {
	dye = "dye:white",
	wool = "wool:white",
	wood = "default:wood",
	tree = "default:tree",
	sand = "default:sand",
	glass = "default:glass",
	stick = "default:stick",
	stone = "default:stone",
	leaves = "default:leaves",
	coal = "default:coal_lump",
	vessel = "vessels:glass_bottle",
	flower = "flowers:dandelion_yellow",
	water_bucket = "bucket:bucket_water",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local group_names = {
	dye = S"Any dye",
	coal = S"Any coal",
	sand = S"Any sand",
	tree = S"Any tree",
	wool = S"Any wool",
	glass = S"Any glass",
	stick = S"Any stick",
	stone = S"Any stone",
	carpet = S"Any carpet",
	flower = S"Any flower",
	leaves = S"Any leaves",
	vessel = S"Any vessel",
	wood = S"Any wood planks",
	mushroom = S"Any mushroom",

	["color_red,flower"] = S"Any red flower",
	["color_blue,flower"] = S"Any blue flower",
	["color_black,flower"] = S"Any black flower",
	["color_white,flower"] = S"Any white flower",
	["color_green,flower"] = S"Any green flower",
	["color_orange,flower"] = S"Any orange flower",
	["color_yellow,flower"] = S"Any yellow flower",
	["color_violet,flower"] = S"Any violet flower",

	["color_red,dye"] = S"Any red dye",
	["color_blue,dye"] = S"Any blue dye",
	["color_grey,dye"] = S"Any grey dye",
	["color_pink,dye"] = S"Any pink dye",
	["color_cyan,dye"] = S"Any cyan dye",
	["color_black,dye"] = S"Any black dye",
	["color_white,dye"] = S"Any white dye",
	["color_brown,dye"] = S"Any brown dye",
	["color_green,dye"] = S"Any green dye",
	["color_orange,dye"] = S"Any orange dye",
	["color_yellow,dye"] = S"Any yellow dye",
	["color_violet,dye"] = S"Any violet dye",
	["color_magenta,dye"] = S"Any magenta dye",
	["color_dark_grey,dye"] = S"Any dark grey dye",
	["color_dark_green,dye"] = S"Any dark green dye",
}

local function err(str)
	return log("error", str)
end

local function msg(name, str)
	return chat_send(name, fmt("[craftguide] %s", str))
end

local function is_str(x)
	return type(x) == "string"
end

local function true_str(str)
	return is_str(str) and str ~= ""
end

local function is_table(x)
	return type(x) == "table"
end

local function is_func(x)
	return type(x) == "function"
end

local function is_group(item)
	return sub(item, 1, 6) == "group:"
end

local function clean_name(item)
	if sub(item, 1, 1) == ":" then
		item = sub(item, 2)
	end

	return item
end

local function array_diff(t1, t2)
	local hash = {}

	for i = 1, #t1 do
		local v = t1[i]
		hash[v] = true
	end

	for i = 1, #t2 do
		local v = t2[i]
		hash[v] = nil
	end

	local diff, c = {}, 0

	for i = 1, #t1 do
		local v = t1[i]
		if hash[v] then
			c = c + 1
			diff[c] = v
		end
	end

	return diff
end

local function table_eq(T1, T2)
	local avoid_loops = {}

	local function recurse(t1, t2)
		if type(t1) ~= type(t2) then return end

		if not is_table(t1) then
			return t1 == t2
		end

		if avoid_loops[t1] then
			return avoid_loops[t1] == t2
		end

		avoid_loops[t1] = t2
		local t2k, t2kv = {}, {}

		for k in pairs(t2) do
			if is_table(k) then
				insert(t2kv, k)
			end

			t2k[k] = true
		end

		for k1, v1 in pairs(t1) do
			local v2 = t2[k1]
			if type(k1) == "table" then
				local ok
				for i = 1, #t2kv do
					local tk = t2kv[i]
					if table_eq(k1, tk) and recurse(v1, t2[tk]) then
						remove(t2kv, i)
						t2k[tk] = nil
						ok = true
						break
					end
				end

				if not ok then return end
			else
				if v2 == nil then return end
				t2k[k1] = nil
				if not recurse(v1, v2) then return end
			end
		end

		if next(t2k) then return end
		return true
	end

	return recurse(T1, T2)
end

local function table_merge(t1, t2, hash)
	t1 = t1 or {}
	t2 = t2 or {}

	if hash then
		for k, v in pairs(t2) do
			t1[k] = v
		end
	else
		local c = #t1

		for i = 1, #t2 do
			c = c + 1
			t1[c] = t2[i]
		end
	end

	return t1
end

local function table_replace(t, val, new)
	for k, v in pairs(t) do
		if v == val then
			t[k] = new
		end
	end
end

local craft_types = {}

function craftguide.register_craft_type(name, def)
	if not true_str(name) then
		return err "craftguide.register_craft_type(): name missing"
	end

	if not is_str(def.description) then
		def.description = ""
	end

	if not is_str(def.icon) then
		def.icon = ""
	end

	craft_types[name] = def
end

function craftguide.register_craft(def)
	local width, c = 0, 0

	if true_str(def.url) then
		if not http then
			return err(fmt([[craftguide.register_craft(): Unable to reach %s.
				No HTTP support for this mod: add it to the `secure.http_mods` or
				`secure.trusted_mods` setting.]], def.url))
		end

		http.fetch({url = def.url}, function(result)
			if result.succeeded then
				local t = parse_json(result.data)
				if is_table(t) then
					return craftguide.register_craft(t)
				end
			end
		end)

		return
	end

	if not is_table(def) or not next(def) then
		return err "craftguide.register_craft(): craft definition missing"
	end

	if #def > 1 then
		for _, v in pairs(def) do
			craftguide.register_craft(v)
		end
		return
	end

	if def.result then
		def.output = def.result -- Backward compatibility
		def.result = nil
	end

	if not true_str(def.output) then
		return err "craftguide.register_craft(): output missing"
	end

	if not is_table(def.items) then
		def.items = {}
	end

	if def.grid then
		if not is_table(def.grid) then
			def.grid = {}
		end

		if not is_table(def.key) then
			def.key = {}
		end

		local cp = copy(def.grid)
		sort(cp, function(a, b)
			return #a > #b
		end)

		width = #cp[1]

		for i = 1, #def.grid do
			while #def.grid[i] < width do
				def.grid[i] = def.grid[i] .. " "
			end
		end

		for symbol in gmatch(concat(def.grid), ".") do
			c = c + 1
			def.items[c] = def.key[symbol]
		end
	else
		local items, len = def.items, #def.items
		def.items = {}

		for i = 1, len do
			items[i] = items[i]:gsub(",", ", ")
			local rlen = #split(items[i], ",")

			if rlen > width then
				width = rlen
			end
		end

		for i = 1, len do
			while #split(items[i], ",") < width do
				items[i] = items[i] .. ", "
			end
		end

		for name in gmatch(concat(items, ","), "[%s%w_:]+") do
			c = c + 1
			def.items[c] = match(name, "%S+")
		end
	end

	local item = match(def.output, "%S+")
	recipes_cache[item] = recipes_cache[item] or {}

	def.custom = true
	def.width = width
	insert(recipes_cache[item], def)
end

local recipe_filters = {}

function craftguide.add_recipe_filter(name, f)
	if not true_str(name) then
		return err "craftguide.add_recipe_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.add_recipe_filter(): function missing"
	end

	recipe_filters[name] = f
end

function craftguide.set_recipe_filter(name, f)
	if not is_str(name) then
		return err "craftguide.set_recipe_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.set_recipe_filter(): function missing"
	end

	recipe_filters = {[name] = f}
end

function craftguide.remove_recipe_filter(name)
	recipe_filters[name] = nil
end

function craftguide.get_recipe_filters()
	return recipe_filters
end

local function apply_recipe_filters(recipes, player)
	for _, filter in pairs(recipe_filters) do
		recipes = filter(recipes, player)
	end

	return recipes
end

local search_filters = {}

function craftguide.add_search_filter(name, f)
	if not true_str(name) then
		return err "craftguide.add_search_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.add_search_filter(): function missing"
	end

	search_filters[name] = f
end

function craftguide.remove_search_filter(name)
	search_filters[name] = nil
end

function craftguide.get_search_filters()
	return search_filters
end

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if (item_groups[group] or 0) == 0 then return end
	end

	return true
end

local function extract_groups(str)
	if sub(str, 1, 6) == "group:" then
		return split(sub(str, 7), ",")
	end
end

local function get_filtered_items(player, data)
	local items, known, c = {}, 0, 0

	for i = 1, #init_items do
		local item = init_items[i]
		local recipes = recipes_cache[item]
		local usages = usages_cache[item]

		recipes = #apply_recipe_filters(recipes or {}, player)
		usages = #apply_recipe_filters(usages or {}, player)

		if recipes > 0 or usages > 0 then
			c = c + 1
			items[c] = item

			if data then
				known = known + recipes + usages
			end
		end
	end

	if data then
		data.known_recipes = known
	end

	return items
end

local function get_burntime(item)
	return get_craft_result{method = "fuel", items = {item}}.time
end

local function cache_fuel(item)
	local burntime = get_burntime(item)
	if burntime > 0 then
		fuel_cache[item] = {
			type = "fuel",
			items = {item},
			burntime = burntime,
			replacements = replacements.fuel[item],
		}
	end
end

local function show_item(def)
	return def and not (def.groups.not_in_craft_guide == 1 or
		def.groups.not_in_creative_inventory == 1) and
		def.description and def.description ~= ""
end

local function get_usages(recipe)
	local added = {}

	for _, item in pairs(recipe.items) do
		item = reg_aliases[item] or item
		if not added[item] then
			local groups = extract_groups(item)
			if groups then
				for name, def in pairs(reg_items) do
					if not added[name] and show_item(def) and
							item_has_groups(def.groups, groups) then
						local usage = copy(recipe)
						table_replace(usage.items, item, name)
						usages_cache[name] = usages_cache[name] or {}
						insert(usages_cache[name], 1, usage)
						added[name] = true
					end
				end
			elseif show_item(reg_items[item]) then
				usages_cache[item] = usages_cache[item] or {}
				insert(usages_cache[item], 1, recipe)
			end

			added[item] = true
		end
	end
end

local function cache_usages(item)
	local recipes = recipes_cache[item] or {}

	for i = 1, #recipes do
		get_usages(recipes[i])
	end

	if fuel_cache[item] then
		usages_cache[item] = table_merge(usages_cache[item] or {}, {fuel_cache[item]})
	end
end

local function drop_table(name, drop)
	local count_sure = 0
	local drop_items = drop.items or {}
	local max_items = drop.max_items

	for i = 1, #drop_items do
		local di = drop_items[i]
		local valid_rarity = di.rarity and di.rarity > 1

		if di.rarity or not max_items or
				(max_items and not di.rarity and count_sure < max_items) then
			for j = 1, #di.items do
				local dstack = ItemStack(di.items[j])
				local dname  = dstack:get_name()
				local dcount = dstack:get_count()
				local empty  = dstack:is_empty()

				if not empty and (dname ~= name or
						(dname == name and dcount > 1)) then
					local rarity = valid_rarity and di.rarity

					craftguide.register_craft{
						type   = rarity and "digging_chance" or "digging",
						items  = {name},
						output = fmt("%s %u", dname, dcount),
						rarity = rarity,
						tools  = di.tools,
					}
				end
			end
		end

		if not di.rarity then
			count_sure = count_sure + 1
		end
	end
end

local function cache_drops(name, drop)
	if true_str(drop) then
		local dstack = ItemStack(drop)
		local dname  = dstack:get_name()
		local empty  = dstack:is_empty()

		if not empty and dname ~= name then
			craftguide.register_craft{
				type = "digging",
				items = {name},
				output = drop,
			}
		end
	elseif is_table(drop) then
		drop_table(name, drop)
	end
end

local function cache_recipes(item)
	local recipes = get_all_recipes(item)

	if replacements[item] then
		local _recipes = {}

		for k, v in ipairs(recipes or {}) do
			_recipes[#recipes + 1 - k] = v
		end

		local shift = 0
		local size_rpl = maxn(replacements[item])
		local size_rcp = #_recipes

		if size_rpl > size_rcp then
			shift = size_rcp - size_rpl
		end

		for k, v in pairs(replacements[item]) do
			k = k + shift

			if _recipes[k] then
				_recipes[k].replacements = v
			end
		end

		recipes = _recipes
	end

	recipes_cache[item] = recipes
end

local function get_recipes(item, data, player)
	local clean_item = reg_aliases[item] or item
	local recipes = recipes_cache[clean_item]
	local usages = usages_cache[clean_item]

	if recipes then
		recipes = apply_recipe_filters(recipes, player)
	end

	local no_recipes = not recipes or #recipes == 0

	if no_recipes and not usages then
		return
	elseif sfinv_only then
		if usages and no_recipes then
			data.show_usages = true
		elseif recipes and not usages then
			data.show_usages = nil
		end
	end

	if not sfinv_only or (sfinv_only and data.show_usages) then
		usages = apply_recipe_filters(usages, player)
	end

	local no_usages = not usages or #usages == 0

	return not no_recipes and recipes or nil,
	       not no_usages  and usages  or nil
end

local function groups_to_items(groups, get_all)
	if not get_all and #groups == 1 then
		local group = groups[1]
		local stereotype = craftguide.group_stereotypes[group]
		local def = reg_items[stereotype]

		if def and show_item(def) then
			return stereotype
		end
	end

	local names = {}
	for name, def in pairs(reg_items) do
		if show_item(def) and item_has_groups(def.groups, groups) then
			if get_all then
				names[#names + 1] = name
			else
				return name
			end
		end
	end

	return get_all and names or ""
end

local function repairable(tool)
	local def = reg_tools[tool]
	return toolrepair and def and def.groups and def.groups.disable_repair ~= 1
end

local function is_fav(favs, query_item)
	local fav, i
	for j = 1, #favs do
		if favs[j] == query_item then
			fav = true
			i = j
			break
		end
	end

	return fav, i
end

local function weird_desc(str)
	return not true_str(str) or find(str, "[\\]*") or not find(str, "%u")
end

local function toupper(str)
	return str:gsub("%f[%w]%l", upper):gsub("_", " ")
end

local function strip_newline(str)
	return match(str, "[^\n]*")
end

local function strip_prefix(str)
	return match(str, ".*@.*%)(.*)()") or str
end

local function get_desc(item, lang_code)
	if sub(item, 1, 1) == "_" then
		item = sub(item, 2)
	end

	local def = reg_items[item]

	if def then
		local desc = def.description
		if true_str(desc) then
			desc = translate(lang_code, desc)
			desc = desc:trim()
			desc = strip_newline(desc)
			desc = strip_prefix(desc)

			if not find(desc, "%u") then
				desc = toupper(desc)
			end

			return desc

		elseif true_str(item) then
			return toupper(match(item, ":(.*)"))
		end
	end

	return S("Unknown Item (@1)", item)
end

local function get_tooltip(item, info, lang_code)
	local tooltip

	if info.groups then
		sort(info.groups)
		tooltip = group_names[concat(info.groups, ",")]

		if not tooltip then
			local groupstr = {}

			for i = 1, #info.groups do
				insert(groupstr, clr("#ff0", info.groups[i]))
			end

			groupstr = concat(groupstr, ", ")
			tooltip = S("Any item belonging to the group(s): @1", groupstr)
		end
	else
		tooltip = get_desc(item, lang_code)
	end

	local function add(str)
		return fmt("%s\n%s", tooltip, str)
	end

	if info.cooktime then
		tooltip = add(S("Cooking time: @1", clr("#ff0", info.cooktime)))
	end

	if info.burntime then
		tooltip = add(S("Burning time: @1", clr("#ff0", info.burntime)))
	end

	if info.replace then
		for i = 1, #info.replace.items do
			local rpl = match(info.replace.items[i], "%S+")
			local desc = clr("#ff0", get_desc(rpl, lang_code))

			if info.replace.type == "cooking" then
				tooltip = add(S("Replaced by @1 on smelting", desc))
			elseif info.replace.type == "fuel" then
				tooltip = add(S("Replaced by @1 on burning", desc))
			else
				tooltip = add(S("Replaced by @1 on crafting", desc))
			end
		end
	end

	if info.repair then
		tooltip = add(S("Repairable by step of @1", clr("#ff0", toolrepair .. "%")))
	end

	if info.rarity then
		local chance = (1 / max(1, info.rarity)) * 100
		tooltip = add(S("@1 of chance to drop", clr("#ff0", chance .. "%")))
	end

	if info.tools then
		local several = #info.tools > 1
		local names = several and "\n" or ""

		if several then
			for i = 1, #info.tools do
				names = fmt("%s\t\t- %s\n",
					names, clr("#ff0", get_desc(info.tools[i], lang_code)))
			end

			tooltip = add(S("Only drop if using one of these tools: @1",
				sub(names, 1, -2)))
		else
			tooltip = add(S("Only drop if using this tool: @1",
				clr("#ff0", get_desc(info.tools[1], lang_code))))
		end
	end

	return fmt("tooltip[%s;%s]", item, ESC(tooltip))
end

local function get_output_fs(lang_code, fs, rcp, shapeless, right, btn_size, _btn_size, spacing)
	local custom_recipe = craft_types[rcp.type]

	if custom_recipe or shapeless or rcp.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or
			     shapeless and "shapeless" or "furnace"

		if not custom_recipe then
			icon = fmt("craftguide_%s.png^[resize:16x16", icon)
		end

		local pos_x = right + btn_size + 0.1
		local pos_y = YOFFSET + (sfinv_only and 1.55 or -0.45) + spacing

		if sub(icon, 1, 18) == "craftguide_furnace" then
			fs[#fs + 1] = fmt(FMT.animated_image,
				pos_x, pos_y, 0.5, 0.5, PNG.furnace_anim, 8, 180)
		else
			fs[#fs + 1] = fmt(FMT.image, pos_x, pos_y, 0.5, 0.5, icon)
		end

		local tooltip = custom_recipe and custom_recipe.description or
				shapeless and S"Shapeless" or S"Cooking"

		fs[#fs + 1] = fmt(FMT.tooltip, pos_x, pos_y, 0.5, 0.5, ESC(tooltip))
	end

	local arrow_X = right + (_btn_size or ITEM_BTN_SIZE)
	local X = arrow_X + 0.9
	local Y = YOFFSET + (sfinv_only and 2 or 0) + spacing

	fs[#fs + 1] = fmt(FMT.image, arrow_X, Y + 0.2, 0.9, 0.7, PNG.arrow)

	if rcp.type == "fuel" then
		fs[#fs + 1] = fmt(FMT.animated_image, X, Y,
			ITEM_BTN_SIZE, ITEM_BTN_SIZE, PNG.fire_anim, 8, 180)
	else
		local item = rcp.output
		item = clean_name(item)
		local name = match(item, "%S*")

		fs[#fs + 1] = fmt(FMT.image, X, Y,
			ITEM_BTN_SIZE, ITEM_BTN_SIZE, PNG.selected)

		local _name = sfinv_only and name or fmt("_%s", name)

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s;%s]",
			X, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE, item, _name, "")

		local def = reg_items[name]
		local unknown = not def or nil
		local desc = def and def.description
		local weird = name ~= "" and desc and weird_desc(desc) or nil
		local burntime = fuel_cache[name] and fuel_cache[name].burntime

		local infos = {
			unknown  = unknown,
			weird    = weird,
			burntime = burntime,
			repair   = repairable(name),
			rarity   = rcp.rarity,
			tools    = rcp.tools,
		}

		if next(infos) then
			fs[#fs + 1] = get_tooltip(_name, infos, lang_code)
		end

		if infos.burntime then
			fs[#fs + 1] = fmt(FMT.image,
				X + 1, YOFFSET + (sfinv_only and 2 or 0.1) + spacing,
				0.6, 0.4, PNG.arrow)

			fs[#fs + 1] = fmt(FMT.animated_image,
				X + 1.6, YOFFSET + (sfinv_only and 1.85 or 0) + spacing,
				0.6, 0.6, PNG.fire_anim, 8, 180)
		end
	end
end

local function get_grid_fs(lang_code, fs, rcp, spacing)
	local width = rcp.width or 1
	local right, btn_size, _btn_size = 0, ITEM_BTN_SIZE
	local cooktime, shapeless

	if rcp.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 and not rcp.custom then
		shapeless = true
		local n = #rcp.items
		width = (n < 5 and n > 1) and 2 or min(3, max(1, n))
	end

	local rows = ceil(maxn(rcp.items) / width)

	if width > WH_LIMIT or rows > WH_LIMIT then
		fs[#fs + 1] = fmt(FMT.label,
			XOFFSET + (sfinv_only and -1.5 or -1.6),
			YOFFSET + (sfinv_only and 0.5 or spacing),
			ES("Recipe's too big to be displayed (@1x@2)", width, rows))

		return concat(fs)
	end

	local large_recipe = width > 3 or rows > 3

	if large_recipe then
		fs[#fs + 1] = "style_type[item_image_button;border=true]"
	end

	for i = 1, width * rows do
		local item = rcp.items[i] or ""
		item = clean_name(item)
		local name = match(item, "%S*")

		local X = ceil((i - 1) % width - width) + XOFFSET
		local Y = ceil(i / width) + YOFFSET - min(2, rows) + spacing

		if large_recipe then
			btn_size = (width > 3 and 3 / width or 3 / rows) + 0.1
			_btn_size = btn_size
			local xi = (i - 1) % width
			local yi = floor((i - 1) / width)

			X = btn_size * xi + XOFFSET - 2.65 - (xi * 0.15)
			Y = btn_size * yi + spacing + (sfinv_only and 4 or 0) - (yi * 0.1)
		end

		if X > right then
			right = X
		end

		local groups

		if is_group(name) then
			groups = extract_groups(name)
			item = groups_to_items(groups)
		end

		local label = groups and "\nG" or ""
		local replace

		for j = 1, #(rcp.replacements or {}) do
			local replacement = rcp.replacements[j]
			if replacement[1] == name then
				replace = replace or {type = rcp.type, items = {}}

				local added

				for _, v in ipairs(replace.items) do
					if replacement[2] == v then
						added = true
						break
					end
				end

				if not added then
					label = fmt("%s%s\nR", label ~= "" and "\n" or "", label)
					replace.items[#replace.items + 1] = replacement[2]
				end
			end
		end

		Y = Y + (sfinv_only and 2 or 0)

		if not large_recipe then
			fs[#fs + 1] = fmt(FMT.image, X, Y, btn_size, btn_size, PNG.selected)
		end

		local btn_name = ""

		if groups then
			btn_name = fmt("group|%s|%s", groups[1], item)
		elseif item ~= "" then
			btn_name = item
		end

		fs[#fs + 1] = fmt(FMT.item_image_button,
			X, Y, btn_size, btn_size, item, btn_name, label)

		local def = reg_items[name]
		local unknown = not def or nil
		unknown = not groups and unknown or nil
		local desc = def and def.description
		local weird = name ~= "" and desc and weird_desc(desc) or nil
		local burntime = fuel_cache[name] and fuel_cache[name].burntime

		local infos = {
			unknown  = unknown,
			weird    = weird,
			groups   = groups,
			burntime = burntime,
			cooktime = cooktime,
			replace  = replace,
		}

		if next(infos) then
			fs[#fs + 1] = get_tooltip(btn_name, infos, lang_code)
		end
	end

	if large_recipe then
		fs[#fs + 1] = "style_type[item_image_button;border=false]"
	end

	get_output_fs(lang_code, fs, rcp, shapeless, right, btn_size, _btn_size, spacing)
end

local function get_rcp_lbl(lang_code, show_usages, unum, rnum, fs, panel, spacing, rn, is_recipe)
	local lbl

	if (not sfinv_only and is_recipe) or (sfinv_only and not show_usages) then
		lbl = ES("Recipe @1 of @2", rnum, rn)

	elseif not sfinv_only or (sfinv_only and show_usages) then
		lbl = ES("Usage @1 of @2", unum, rn)

	elseif sfinv_only then
		lbl = show_usages and ES("Usage @1 of @2", unum, rn) or
			ES("Recipe @1 of @2", rnum, rn)
	end

	lbl = translate(lang_code, lbl)
	local lbl_len = #lbl:gsub("[\128-\191]", "") -- Count chars, not bytes in UTF-8 strings
	local shift = min(0.9, abs(13 - max(13, lbl_len)) * 0.1)

	fs[#fs + 1] = fmt(FMT.label,
		XOFFSET + (sfinv_only and 2.3 or 1.6) - shift,
		YOFFSET + (sfinv_only and 3.4 or 1.5 + spacing), lbl)

	if rn > 1 then
		local btn_suffix = is_recipe and "recipe" or "usage"
		local prev_name = fmt("prev_%s", btn_suffix)
		local next_name = fmt("next_%s", btn_suffix)
		local x_arrow = XOFFSET + (sfinv_only and 1.7 or 1)
		local y_arrow = YOFFSET + (sfinv_only and 3.3 or 1.4 + spacing)

		fs[#fs + 1] = fmt(mul_elem(FMT.arrow, 2),
			x_arrow - shift, y_arrow, PNG.prev, prev_name, "",
			x_arrow + 1.8,   y_arrow, PNG.next, next_name, "")
	end

	local rcp = is_recipe and panel.rcp[rnum] or panel.rcp[unum]
	get_grid_fs(lang_code, fs, rcp, spacing)
end

local function get_title_fs(query_item, lang_code, favs, fs, spacing)
	local desc = ESC(get_desc(query_item, lang_code))
	desc = #desc > 33 and fmt("%s...", sub(desc, 1, 30)) or desc
	local t_desc = query_item
	t_desc = #t_desc > 40 and fmt("%s...", sub(t_desc, 1, 37)) or t_desc

	fs[#fs + 1] = fmt(FMT.hypertext,
		9.05, spacing - 0.1, 5.85, 1.2,
		fmt("<item name=%s float=right width=64 height=64 rotate=yes>" ..
		    "<big><b>%s</b></big>\n<style color=#7bf font=mono>%s</style>",
			query_item, desc, t_desc))

	local fav = is_fav(favs, query_item)
	local nfavs = #favs

	if nfavs < MAX_FAVS or (nfavs == MAX_FAVS and fav) then
		local fav_marked = fmt("craftguide_fav%s.png", fav and "_off" or "")

		fs[#fs + 1] = fmt(
			"style[fav;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			fmt("craftguide_fav%s.png", fav and "" or "_off"), fav_marked, fav_marked)

		fs[#fs + 1] = fmt(FMT.image_button, 8.25, spacing + 0.15, 0.5, 0.45, "", "fav", "")

		fs[#fs + 1] = fmt("tooltip[fav;%s]",
			fav and ES"Unmark this item" or ES"Mark this item")
	else
		fs[#fs + 1] = fmt(
			"style[fav_no;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			"craftguide_fav_off.png", PNG.nothing, PNG.nothing)

		fs[#fs + 1] = fmt(FMT.image_button,
			8.25, spacing + 0.15, 0.5, 0.45, "", "fav_no", "")

		fs[#fs + 1] = fmt("tooltip[fav_no;%s]",
			ES"Cannot mark this item. Limit of bookmarks reached.")
	end
end

local function get_panels(lang_code, query_item, recipes, usages, show_usages,
			  favs, unum, rnum, fs)

	local _title   = {name = "title", height = 1.2}
	local _favs    = {name = "favs",  height = 1.91}
	local _recipes = {name = "recipes", rcp = recipes, height = 3.5}
	local _usages  = {name = "usages",  rcp = usages,  height = 3.5}
	local panels   = {_title, _recipes, _usages, _favs}

	if sfinv_only then
		panels = {show_usages and _usages or _recipes}
	end

	for idx = 1, #panels do
		local panel, spacing = panels[idx], 0

		if idx > 1 then
			for _idx = idx - 1, 1, -1 do
				spacing = spacing + panels[_idx].height + 0.1
			end
		end

		local rn = panel.rcp and #panel.rcp
		local is_recipe = sfinv_only and not show_usages or panel.name == "recipes"
		local recipe_or_usage = panel.name == "recipes" or panel.name == "usages"

		if rn then
			get_rcp_lbl(lang_code, show_usages, unum, rnum, fs, panel,
				    spacing, rn, is_recipe)
		end

		if sfinv_only then return end

		fs[#fs + 1] = fmt("background9[8.1,%f;6.6,%f;%s;false;%d]",
			-0.2 + spacing, panel.height, PNG.bg_full, 10)

		if recipe_or_usage and not rn then
			local lbl = is_recipe and ES"No recipes" or ES"No usages"

			fs[#fs + 1] = fmt(FMT.hypertext,
				8.29, YOFFSET + spacing + 0.3, 6.8, 1,
				fmt("<center><style size=20><b>%s</b></style></center>",
					translate(lang_code, lbl)))

		elseif panel.name == "title" then
			get_title_fs(query_item, lang_code, favs, fs, spacing)

		elseif panel.name == "favs" then
			fs[#fs + 1] = fmt(FMT.label, 8.3, spacing - 0.15, ES"Bookmarks")

			for i = 1, #favs do
				local item = favs[i]
				local X = 7.85 + (i - 0.5)
				local Y = spacing + 0.4

				if query_item == item then
					fs[#fs + 1] = fmt(FMT.image, X, Y,
						ITEM_BTN_SIZE, ITEM_BTN_SIZE, PNG.selected)
				end

				fs[#fs + 1] = fmt(FMT.item_image_button,
					X, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE, item, item, "")
			end
		end
	end
end

local function make_fs(data)
	local fs = {}

	fs[#fs + 1] = fmt([[
		size[%f,%f]
		no_prepend[]
		bgcolor[#0000]
	]],
	9 + (data.query_item and 6.7 or 0) - 1.2, LINES - 0.3)

	if not sfinv_only then
		fs[#fs + 1] = fmt("background9[-0.15,-0.2;%f,%f;%s;false;%d]",
			9 - 0.9, LINES + 0.4, PNG.bg_full, 10)
	end

	fs[#fs + 1] = styles

	fs[#fs + 1] = fmt([[
		field[0.4,0.2;2.6,1;filter;;%s]
		field_close_on_enter[filter;false]
		box[0,0;2.5,0.6;#bababa25]
	]],
	ESC(data.filter))

	fs[#fs + 1] = fmt(mul_elem(FMT.image_button, 2),
		2.6, -0.06, 0.85, 0.85, "", "search", "",
		3.3, -0.06, 0.85, 0.85, "", "clear", "")

	if sfinv_only then
		fs[#fs + 1] = "container[0.2,0]"
	end

	fs[#fs + 1] = fmt(mul_elem(FMT.image_button, 2),
		5.35, -0.06, 0.85, 0.85, "", "prev_page", "",
		7.1, -0.06, 0.85, 0.85, "", "next_page", "")

	data.pagemax = max(1, ceil(#data.items / IPP))

	fs[#fs + 1] = fmt(FMT.button,
		5.97, -0.06, 1.36, 0.85, "pagenum",
		fmt("%s / %u", clr("#ff0", data.pagenum), data.pagemax))

	if sfinv_only then
		fs[#fs + 1] = "container_end[]"
	end

	if #data.items == 0 then
		local lbl = ES"No item to show"

		if next(recipe_filters) and #init_items > 0 and data.filter == "" then
			lbl = ES"Collect items to reveal more recipes"
		end

		fs[#fs + 1] = fmt(FMT.hypertext,
			0.05, 3, 8.29, 1,
			fmt("<center><style size=20><b>%s</b></style></center>",
				translate(data.lang_code, lbl)))
	end

	local first_item = (data.pagenum - 1) * IPP

	for i = first_item, first_item + IPP - 1 do
		local item = data.items[i + 1]
		if not item then break end

		local X = i % ROWS
		local Y = (i % IPP - X) / ROWS + 1
		X = X - (X * (sfinv_only and 0.12 or 0.14)) - 0.05
		Y = Y - (Y * 0.08) - 0.15

		if data.query_item == item then
			fs[#fs + 1] = fmt(FMT.image, X, Y, 1, 1, PNG.selected)
		end

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s_inv;]",
			X, Y, 1, 1, item, item)
	end

	if (data.recipes and #data.recipes > 0) or (data.usages and #data.usages > 0) then
		get_panels(data.lang_code, data.query_item, data.recipes, data.usages,
			   data.show_usages, data.favs, data.unum, data.rnum, fs)
	end

	return concat(fs)
end

local show_fs = function(player, name)
	local data = pdata[name]
	if sfinv_only then
		sfinv.set_player_inventory_formspec(player)
	else
		show_formspec(name, "craftguide", make_fs(data))
	end
end

craftguide.register_craft_type("digging", {
	description = ES"Digging",
	icon = "craftguide_steelpick.png",
})

craftguide.register_craft_type("digging_chance", {
	description = ES"Digging (by chance)",
	icon = "craftguide_mesepick.png",
})

local function search(data)
	local filter = data.filter

	if searches[filter] then
		data.items = searches[filter]
		return
	end

	local opt = "^(.-)%+([%w_]+)=([%w_,]+)"
	local search_filter = next(search_filters) and match(filter, opt)
	local filters = {}

	if search_filter then
		for filter_name, values in gmatch(filter, sub(opt, 6)) do
			if search_filters[filter_name] then
				values = split(values, ",")
				filters[filter_name] = values
			end
		end
	end

	local filtered_list, c = {}, 0

	for i = 1, #data.items_raw do
		local item = data.items_raw[i]
		local def = reg_items[item]
		local desc = lower(translate(data.lang_code, def and def.description)) or ""
		local search_in = fmt("%s %s", item, desc)
		local to_add

		if search_filter then
			for filter_name, values in pairs(filters) do
				if values then
					local func = search_filters[filter_name]
					to_add = func(item, values) and (search_filter == "" or
						find(search_in, search_filter, 1, true))
				end
			end
		else
			to_add = find(search_in, filter, 1, true)
		end

		if to_add then
			c = c + 1
			filtered_list[c] = item
		end
	end

	if not next(recipe_filters) then
		-- Cache the results only if searched 2 times
		if searches[filter] == nil then
			searches[filter] = false
		else
			searches[filter] = filtered_list
		end
	end

	data.items = filtered_list
end

craftguide.add_search_filter("groups", function(item, groups)
	local def = reg_items[item]
	local has_groups = true

	for i = 1, #groups do
		local group = groups[i]
		if not def.groups[group] then
			has_groups = nil
			break
		end
	end

	return has_groups
end)

--[[	As `core.get_craft_recipe` and `core.get_all_craft_recipes` do not
	return the fuel, replacements and toolrepair recipes, we have to
	override `core.register_craft` and do some reverse engineering.
	See engine's issues #4901, #5745 and #8920.	]]

local old_register_craft = core.register_craft
local rcp_num = {}

core.register_craft = function(def)
	old_register_craft(def)

	if def.type == "toolrepair" then
		toolrepair = def.additional_wear * -100
	end

	local output = def.output or (true_str(def.recipe) and def.recipe) or nil
	if not output then return end
	output = {match(output, "%S+")}

	local groups

	if is_group(output[1]) then
		groups = extract_groups(output[1])
		output = groups_to_items(groups, true)
	end

	for i = 1, #output do
		local item = output[i]
		rcp_num[item] = (rcp_num[item] or 0) + 1

		if def.replacements then
			if def.type == "fuel" then
				replacements.fuel[item] = def.replacements
			else
				replacements[item] = replacements[item] or {}
				replacements[item][rcp_num[item]] = def.replacements
			end
		end
	end
end

local old_clear_craft = core.clear_craft

core.clear_craft = function(def)
	old_clear_craft(def)

	if true_str(def) then
		return -- TODO
	elseif is_table(def) then
		return -- TODO
	end
end

local function resolve_aliases(hash)
	for oldname, newname in pairs(reg_aliases) do
		cache_recipes(oldname)
		local recipes = recipes_cache[oldname]

		if recipes then
			if not recipes_cache[newname] then
				recipes_cache[newname] = {}
			end

			local similar

			for i = 1, #recipes_cache[oldname] do
				local rcp_old = recipes_cache[oldname][i]

				for j = 1, #recipes_cache[newname] do
					local rcp_new = recipes_cache[newname][j]
					rcp_new.type = nil
					rcp_new.method = nil

					if table_eq(rcp_old, rcp_new) then
						similar = true
						break
					end
				end

				if not similar then
					insert(recipes_cache[newname], rcp_old)
				end
			end
		end

		if newname ~= "" and recipes_cache[oldname] and not hash[newname] then
			init_items[#init_items + 1] = newname
		end
	end
end

local function get_init_items()
	local _select, _preselect = {}, {}

	for name, def in pairs(reg_items) do
		if name ~= "" and show_item(def) then
			cache_drops(name, def.drop)

			if not fuel_cache[name] then
				cache_fuel(name)
			end

			if not recipes_cache[name] then
				cache_recipes(name)
			end

			_preselect[name] = true
		end
	end

	for name in pairs(_preselect) do
		cache_usages(name)
	end

	for name in pairs(_preselect) do
		if recipes_cache[name] or usages_cache[name] then
			init_items[#init_items + 1] = name
			_select[name] = true
		end
	end

	resolve_aliases(_select)
	sort(init_items)

	if http and true_str(craftguide.export_url) then
		local post_data = {
			recipes = recipes_cache,
			usages  = usages_cache,
		}

		http.fetch_async{
			url = craftguide.export_url,
			post_data = write_json(post_data),
		}
	end
end

local function init_data(name)
	pdata[name] = {
		filter    = "",
		pagenum   = 1,
		items     = init_items,
		items_raw = init_items,
		favs      = {},
		lang_code = get_lang_code(name),
	}
end

local function reset_data(data)
	data.filter      = ""
	data.pagenum     = 1
	data.rnum        = 1
	data.unum        = 1
	data.query_item  = nil
	data.recipes     = nil
	data.usages      = nil
	data.show_usages = nil
	data.items       = data.items_raw
end

on_mods_loaded(get_init_items)

on_joinplayer(function(player)
	local name = player:get_player_name()
	init_data(name)

	if not pdata[name].lang_code then
		outdated(name)
	end
end)

local function fields(player, _f)
	if _f.quit then return end
	local name = player:get_player_name()
	local data = pdata[name]

	if not _f.key_enter_field then
		sound_play("craftguide_click", {to_player = name, gain = 0.2})
	end

	if _f.clear then
		reset_data(data)

	elseif _f.prev_recipe or _f.next_recipe then
		local num = data.rnum + (_f.prev_recipe and -1 or 1)
		data.rnum = data.recipes[num] and num or (_f.prev_recipe and #data.recipes or 1)

	elseif _f.prev_usage or _f.next_usage then
		local num = data.unum + (_f.prev_usage and -1 or 1)
		data.unum = data.usages[num] and num or (_f.prev_usage and #data.usages or 1)

	elseif _f.key_enter_field == "filter" or _f.search then
		if _f.filter == "" then
			reset_data(data)
			return true, show_fs(player, name)
		end

		local str = lower(_f.filter)
		if data.filter == str then return end

		data.filter = str
		data.pagenum = 1
		search(data)

	elseif _f.prev_page or _f.next_page or _f.pagenum then
		if data.pagemax == 1 then return end
		data.pagenum = data.pagenum - (_f.prev_page and 1 or -1)

		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

	elseif _f.fav then
		local fav, i = is_fav(data.favs, data.query_item)
		local total = #data.favs

		if total < MAX_FAVS and not fav then
			data.favs[total + 1] = data.query_item
		elseif fav then
			remove(data.favs, i)
		end
	else
		local item
		for field in pairs(_f) do
			if find(field, ":") then
				item = field
				break
			end
		end

		if not item then
			return
		elseif sub(item, -4) == "_inv" then
			item = sub(item, 1, -5)
		elseif sub(item, 1, 1) == "_" then
			item = sub(item, 2)
		elseif sub(item, 1, 6) == "group|" then
			item = match(item, "([%w:_]+)$")
		end

		item = reg_aliases[item] or item

		if sfinv_only then
			if item ~= data.query_item then
				data.show_usages = nil
			else
				data.show_usages = not data.show_usages
			end
		elseif item == data.query_item then
			return
		end

		local recipes, usages = get_recipes(item, data, player)
		if not recipes and not usages      then return end
		if data.show_usages and not usages then return end

		data.query_item = item
		data.recipes    = recipes
		data.usages     = usages
		data.rnum       = 1
		data.unum       = 1
	end

	return true, show_fs(player, name)
end

if sfinv_only then
	sfinv.register_page("craftguide:craftguide", {
		title = S"Craft Guide",

		is_in_nav = function(self, player, context)
			local name = player:get_player_name()
			return get_lang_code(name)
		end,

		get = function(self, player, context)
			local name = player:get_player_name()
			local data = pdata[name]

			return sfinv.make_formspec(player, context, make_fs(data))
		end,

		on_enter = function(self, player, context)
			if next(recipe_filters) then
				local name = player:get_player_name()
				local data = pdata[name]

				data.items_raw = get_filtered_items(player)
				search(data)
			end
		end,

		on_player_receive_fields = function(self, player, context, _f)
			fields(player, _f)
		end,
	})
else
	on_receive_fields(function(player, formname, _f)
		if formname == "craftguide" then
			fields(player, _f)
		end
	end)

	local function on_use(user)
		local name = user:get_player_name()
		local data = pdata[name]

		if not data.lang_code then
			return outdated(name)
		end

		if next(recipe_filters) then
			data.items_raw = get_filtered_items(user)
			search(data)
		end

		show_formspec(name, "craftguide", make_fs(data))
	end

	core.register_craftitem("craftguide:book", {
		description = S"Crafting Guide",
		inventory_image = PNG.book,
		wield_image = PNG.book,
		stack_max = 1,
		groups = {book = 1},
		on_use = function(itemstack, user)
			on_use(user)
		end
	})

	core.register_node("craftguide:sign", {
		description = S"Crafting Guide Sign",
		drawtype = "nodebox",
		tiles = {PNG.sign},
		inventory_image = PNG.sign,
		wield_image = PNG.sign,
		paramtype = "light",
		paramtype2 = "wallmounted",
		sunlight_propagates = true,
		groups = {
			choppy = 1,
			attached_node = 1,
			oddly_breakable_by_hand = 1,
			flammable = 3,
		},
		node_box = {
			type = "wallmounted",
			wall_top    = {-0.5, 0.4375, -0.5, 0.5, 0.5, 0.5},
			wall_bottom = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5},
			wall_side   = {-0.5, -0.5, -0.5, -0.4375, 0.5, 0.5}
		},

		on_construct = function(pos)
			local meta = core.get_meta(pos)
			meta:set_string("infotext", "Crafting Guide Sign")
		end,

		on_rightclick = function(pos, node, user, itemstack)
			on_use(user)
		end
	})

	core.register_craft{
		output = "craftguide:book",
		type   = "shapeless",
		recipe = {"default:book"}
	}

	core.register_craft{
		type = "fuel",
		recipe = "craftguide:book",
		burntime = 3
	}

	core.register_craft{
		output = "craftguide:sign",
		type   = "shapeless",
		recipe = {"default:sign_wall_wood"}
	}

	core.register_craft{
		type = "fuel",
		recipe = "craftguide:sign",
		burntime = 10
	}

	if rawget(_G, "sfinv_buttons") then
		sfinv_buttons.register_button("craftguide", {
			title = S"Crafting Guide",
			tooltip = S"Shows a list of available crafting recipes",
			image = PNG.book,
			action = function(player)
				on_use(player)
			end,
		})
	end
end

if progressive_mode then
	local function item_in_inv(item, inv_items)
		local inv_items_size = #inv_items

		if is_group(item) then
			local groups = extract_groups(item)
			for i = 1, inv_items_size do
				local def = reg_items[inv_items[i]]

				if def then
					local item_groups = def.groups
					if item_has_groups(item_groups, groups) then
						return true
					end
				end
			end
		else
			for i = 1, inv_items_size do
				if inv_items[i] == item then
					return true
				end
			end
		end
	end

	local function recipe_in_inv(recipe, inv_items)
		for _, item in pairs(recipe.items) do
			if not item_in_inv(item, inv_items) then return end
		end

		return true
	end

	local function progressive_filter(recipes, player)
		if not recipes then
			return {}
		end

		local name = player:get_player_name()
		local data = pdata[name]

		if #data.inv_items == 0 then
			return {}
		end

		local filtered, c = {}, 0
		for i = 1, #recipes do
			local recipe = recipes[i]
			if recipe_in_inv(recipe, data.inv_items) then
				c = c + 1
				filtered[c] = recipe
			end
		end

		return filtered
	end

	local item_lists = {"main", "craft", "craftpreview"}

	local function get_inv_items(player)
		local inv = player:get_inventory()
		local stacks = {}

		for i = 1, #item_lists do
			local list = inv:get_list(item_lists[i])
			table_merge(stacks, list)
		end

		local inv_items, c = {}, 0

		for i = 1, #stacks do
			local stack = stacks[i]
			if not stack:is_empty() then
				local name = stack:get_name()
				if reg_items[name] then
					c = c + 1
					inv_items[c] = name
				end
			end
		end

		return inv_items
	end

	local function init_hud(player, data)
		data.hud = {
			bg = player:hud_add{
				hud_elem_type = "image",
				position      = {x = 0.78, y = 1},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 370,  y = 112},
				text          = PNG.bg,
				z_index       = 0xDEAD,
			},

			book = player:hud_add{
				hud_elem_type = "image",
				position      = {x = 0.79, y = 1.02},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 4,    y = 4},
				text          = PNG.book,
				z_index       = 0xDEAD,
			},

			text = player:hud_add{
				hud_elem_type = "text",
				position      = {x = 0.84, y = 1.04},
				alignment     = {x = 1,    y = 1},
				number        = 0xffffff,
				text          = "",
				z_index       = 0xDEAD,
			},
		}
	end

	local function show_hud_success(player, data)
		-- It'd better to have an engine function `hud_move` to only need
		-- 2 calls for the notification's back and forth.

		local hud_info_bg = player:hud_get(data.hud.bg)
		local dt = 0.016

		if hud_info_bg.position.y <= 0.9 then
			data.show_hud = false
			data.hud_timer = (data.hud_timer or 0) + dt
		end

		if data.show_hud then
			for _, def in pairs(data.hud) do
				local hud_info = player:hud_get(def)

				player:hud_change(def, "position", {
					x = hud_info.position.x,
					y = hud_info.position.y - (dt / 5)
				})
			end

			player:hud_change(data.hud.text, "text",
				S("@1 new recipe(s) discovered!", data.discovered))

		elseif data.show_hud == false then
			if data.hud_timer >= HUD_TIMER_MAX then
				for _, def in pairs(data.hud) do
					local hud_info = player:hud_get(def)

					player:hud_change(def, "position", {
						x = hud_info.position.x,
						y = hud_info.position.y + (dt / 5)
					})
				end

				if hud_info_bg.position.y >= 1 then
					data.show_hud = nil
					data.hud_timer = nil
				end
			end
		end
	end

	-- Workaround. Need an engine call to detect when the contents of
	-- the player inventory changed, instead.
	local function poll_new_items()
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			local name = player:get_player_name()
			local data = pdata[name]

			local inv_items = get_inv_items(player)
			local diff = array_diff(inv_items, data.inv_items)

			if #diff > 0 then
				data.inv_items = table_merge(diff, data.inv_items)

				local oldknown = data.known_recipes or 0
				local items = get_filtered_items(player, data)

				data.discovered = data.known_recipes - oldknown

				if data.show_hud == nil and data.discovered > 0 then
					data.show_hud = true
				end

				if sfinv_only then
					data.items_raw = items
					search(data)
					sfinv.set_player_inventory_formspec(player)
				end
			end
		end

		after(POLL_FREQ, poll_new_items)
	end

	poll_new_items()

	globalstep(function()
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			local name = player:get_player_name()
			local data = pdata[name]

			if data.show_hud ~= nil and singleplayer then
				show_hud_success(player, data)
			end
		end
	end)

	craftguide.add_recipe_filter("Default progressive filter", progressive_filter)

	on_joinplayer(function(player)
		local name = player:get_player_name()
		local data = pdata[name]

		local meta = player:get_meta()
		data.inv_items = dslz(meta:get_string "inv_items") or {}
		data.known_recipes = dslz(meta:get_string "known_recipes") or 0

		if singleplayer then
			init_hud(player, data)
		end
	end)

	local to_save = {"inv_items", "known_recipes"}

	local function save_meta(player)
		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = pdata[name]

		for i = 1, #to_save do
			local meta_name = to_save[i]
			meta:set_string(meta_name, slz(data[meta_name]))
		end
	end

	on_leaveplayer(save_meta)

	on_shutdown(function()
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			save_meta(player)
		end
	end)
end

on_leaveplayer(function(player)
	local name = player:get_player_name()
	pdata[name] = nil
end)

function craftguide.show(name, item, show_usages)
	if not true_str(name) then
		return err "craftguide.show(): player name missing"
	end

	local data = pdata[name]
	local player = get_player_by_name(name)
	local query_item = data.query_item

	reset_data(data)

	item = reg_items[item] and item or query_item
	local recipes, usages = get_recipes(item, data, player)

	if not recipes and not usages then
		if not recipes_cache[item] and not usages_cache[item] then
			return false, msg(name, fmt("%s: %s",
				S"No recipe or usage for this item",
				get_desc(item, data.lang_code)))
		end

		return false, msg(name, fmt("%s: %s",
			S"You don't know a recipe or usage for this item",
			get_desc(item, data.lang_code)))
	end

	data.query_item = item
	data.recipes    = recipes
	data.usages     = usages

	if sfinv_only then
		data.show_usages = show_usages
	end

	show_fs(player, name)
end

register_command("craft", {
	description = S"Show recipe(s) of the pointed node",
	func = function(name)
		local player = get_player_by_name(name)
		local dir    = player:get_look_dir()
		local ppos   = player:get_pos()
		      ppos.y = ppos.y + 1.625

		local node_name

		for i = 1, 10 do
			local look_at = vec_add(ppos, vec_mul(dir, i))
			local node = core.get_node(look_at)

			if node.name ~= "air" then
				node_name = node.name
				break
			end
		end

		if not node_name then
			return false, msg(name, S"No node pointed")
		end

		return true, craftguide.show(name, node_name)
	end,
})

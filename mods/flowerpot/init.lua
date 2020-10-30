
--[[

  Copyright (C) 2015 - Auke Kok <sofar@foo-projects.org>

  "flowerpot" is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as
  published by the Free Software Foundation; either version 2.1 of
  the license, or (at your option) any later version.

--]]

flowerpot = {}

-- Translation
local S = minetest.get_translator("flowerpot")

-- handle plant removal from flowerpot
local function flowerpot_on_punch(pos, node, puncher, pointed_thing)
	if puncher and not minetest.check_player_privs(puncher, "protection_bypass") then
		local name = puncher:get_player_name()
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return false
		end
	end

	local nodedef = minetest.registered_nodes[node.name]
	local plant = nodedef.flowerpot_plantname
	assert(plant, "unknown plant in flowerpot: " .. node.name)

	minetest.sound_play(nodedef.sounds.dug, {pos = pos})
	minetest.handle_node_drops(pos, {plant}, puncher)
	minetest.swap_node(pos, {name = "flowerpot:empty"})
end

-- handle plant insertion into flowerpot
local function flowerpot_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
	if clicker and not minetest.check_player_privs(clicker, "protection_bypass") then
		local name = clicker:get_player_name()
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return false
		end
	end

	local nodename = itemstack:get_name()
	if not nodename then
		return false
	end

	if nodename:match("grass_1") then
		nodename = nodename:gsub("grass_1", "grass_" .. math.random(5))
	end

	local name = "flowerpot:" .. nodename:gsub(":", "_")
	local def = minetest.registered_nodes[name]
	if not def then
		return itemstack
	end
	minetest.sound_play(def.sounds.place, {pos = pos})
	minetest.swap_node(pos, {name = name})
	if not minetest.settings:get_bool("creative_mode") then
		itemstack:take_item()
	end
	return itemstack
end

local function get_tile(def)
	local tile = def.tiles[1]
	if type (tile) == "table" then
		return tile.name
	end
	return tile
end

function flowerpot.register_node(nodename)
	assert(nodename, "no nodename passed")
	local nodedef = minetest.registered_nodes[nodename]
	if not nodedef then
		minetest.log("error", S("@1 is not a known node, unable to register flowerpot", nodename))
		return false
	end

	local desc = nodedef.description
	local name = nodedef.name:gsub(":", "_")
	local tiles = {}

	if nodedef.drawtype == "plantlike" then
		tiles = {
			{name = "flowerpot.png"},
			{name = get_tile(nodedef)},
			{name = "doors_blank.png"},
		}
	else
		tiles = {
			{name = "flowerpot.png"},
			{name = "doors_blank.png"},
			{name = get_tile(nodedef)},
		}
	end

	local dropname = nodename:gsub("grass_%d", "grass_1")

	minetest.register_node("flowerpot:" .. name, {
		description = S("Flowerpot with @1", desc),
		drawtype = "mesh",
		mesh = "flowerpot.obj",
		tiles = tiles,
		paramtype = "light",
		sunlight_propagates = true,
		collision_box = {
			type = "fixed",
			fixed = {-1/4, -1/2, -1/4, 1/4, -1/8, 1/4},
		},
		selection_box = {
			type = "fixed",
			fixed = {-1/4, -1/2, -1/4, 1/4, 7/16, 1/4},
		},
		sounds = default.node_sound_defaults(),
		groups = {attached_node = 1, oddly_breakable_by_hand = 1, snappy = 3, not_in_creative_inventory = 1},
		flowerpot_plantname = nodename,
		on_dig = function(pos, node, digger)
			minetest.set_node(pos, {name = "flowerpot:empty"})
			local def = minetest.registered_nodes[node.name]
			minetest.add_item(pos, dropname)
		end,
		drop = {
			max_items = 2,
			items = {
				{
					items = {"flowerpot:empty", dropname},
					rarity = 1,
				},
			}
		},
	})
end

-- empty flowerpot
minetest.register_node("flowerpot:empty", {
	description = S("Flowerpot"),
	drawtype = "mesh",
	mesh = "flowerpot.obj",
	inventory_image = "flowerpot_item.png",
	wield_image = "flowerpot_item.png",
	tiles = {
		{name = "flowerpot.png"},
		{name = "doors_blank.png"},
		{name = "doors_blank.png"},
	},
	paramtype = "light",
	sunlight_propagates = true,
	collision_box = {
		type = "fixed",
		fixed = {-1/4, -1/2, -1/4, 1/4, -1/8, 1/4},
	},
	selection_box = {
		type = "fixed",
		fixed = {-1/4, -1/2, -1/4, 1/4, -1/16, 1/4},
	},
	sounds = default.node_sound_defaults(),
	groups = {attached_node = 1, oddly_breakable_by_hand = 3, cracky = 1, dig_immediate = 3},
	on_rightclick = flowerpot_on_rightclick,
})

-- craft
minetest.register_craft({
	output = "flowerpot:empty",
	recipe = {
		{"default:clay_brick", "", "default:clay_brick"},
		{"", "default:clay_brick", ""},
	}
})

for _, node in pairs({
	-- default nodes
	"default:acacia_bush_sapling",
	"default:acacia_bush_stem",
	"default:acacia_sapling",
	"default:aspen_sapling",
	"default:bush_sapling",
	"default:bush_stem",
	"default:cactus",
	"default:emergent_jungle_sapling",
	"default:large_cactus_seedling",
	"default:junglesapling",
	"default:pine_sapling",
	"default:sapling",
	-- flowers nodes
	"flowers:dandelion_white",
	"flowers:dandelion_yellow",
	"flowers:geranium",
	"flowers:mushroom_brown",
	"flowers:mushroom_red",
	"flowers:rose",
	"flowers:tulip",
	"flowers:viola",
	"flowers:chrysanthemum_green",
	"flowers:tulip_black"

}) do
	if minetest.registered_nodes[node] then
		flowerpot.register_node(node)
	end
end

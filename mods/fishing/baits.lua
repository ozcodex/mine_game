

minetest.register_craftitem("fishing:worm", {
	description = "Worm",
    inventory_image = "fishing_worm.png",
    groups = { fishing_bait = 1 },
})

-- Add worm drop to dirt drops
if minetest.registered_nodes["default:dirt"].drop then
	table.insert(minetest.registered_nodes['default:dirt'].drop.items, { rarity = 30, items = {"fishing:worm"} })
else
	minetest.override_item("default:dirt", {
		drop = {
			max_items = 1,
			items = {
				{ 	
					rarity = 30,
			 		items = {"fishing:worm"}
				},
				{
				items = {"default:dirt"}
				}
			}
		}
	})

end


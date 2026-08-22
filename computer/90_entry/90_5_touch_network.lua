function _touchNetwork(zone, x, y)
	if zone.id == "toggle_storage" then
		Config.storages[zone.arg] = not Config.storages[zone.arg]; saveData()
		return true
	elseif zone.id == "toggle_fluid_tank" then
		if Config.fluid_tanks[zone.arg] then Config.fluid_tanks[zone.arg] = nil
		else Config.fluid_tanks[zone.arg] = true end
		saveData()
		return true
	elseif zone.id == "autostock_toggle" then
		Config.autostock_paused = not Config.autostock_paused
		saveData()
		return true
	elseif zone.id == "set_train_box" then
		if Config.train_box == zone.arg then Config.train_box = nil else Config.train_box = zone.arg end
		saveData()
		return true
	elseif zone.id == "set_turtle" then
		if not Config.turtles then Config.turtles = {} end
		if Config.turtles[zone.arg] then
			Config.turtles[zone.arg] = nil
		else
			Config.turtles[zone.arg] = true
		end
		saveData()
		return true
	elseif zone.id == "turtle_remove" then
		if Config.turtles then Config.turtles[zone.arg] = nil end
		saveData()
		return true
	elseif zone.id == "turtle_add" then
		if not Config.turtles then Config.turtles = {} end
		Config.turtles[zone.arg] = true
		saveData()
		return true
	end
	return false
end

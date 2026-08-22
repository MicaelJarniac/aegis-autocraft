function initData()
	local defaults = {
		{ RECIPES_FILE,        "{}"  },
		{ CONFIG_FILE,         textutils.serializeJSON({storages={}, turtles={}, autostock_paused=false}) },
		{ AUTOSTOCK_FILE,      "{}"  },
		{ GROUPS_FILE,         "{}"  },
		{ ALT_RECIPES_FILE,    "{}"  },
		{ MGMT_FILE,           "[]"  },
		{ MACHINE_LABELS_FILE, "{}"  },
		{ CUSTOM_MG_FILE,      "[]"  },
		{ FLUIDS_FILE,         "{}"  },
		{ FLUID_ALTS_FILE,     "{}"  },
	}
	for _, entry in ipairs(defaults) do
		local path, data = entry[1], entry[2]
		if not fs.exists(path) then
			local fh = fs.open(path, "w")
			if fh then fh.write(data); fh.close() end
		end
	end
end

function loadData()
	if fs.exists(RECIPES_FILE) then
		local raw = loadDataFile(RECIPES_FILE) or {}
		if raw.recipes and type(raw.recipes) == "table" then
			Recipes = raw.recipes
			if raw.alt_recipes    and type(raw.alt_recipes)    == "table" then AltRecipes    = raw.alt_recipes    end
			if raw.machine_labels and type(raw.machine_labels) == "table" then MachineLabels = raw.machine_labels end
			local fMigrate = fs.open(RECIPES_FILE, "w")
			if fMigrate then fMigrate.write(textutils.serializeJSON(Recipes)); fMigrate.close() end
		else
			Recipes = raw
		end
	end
	if fs.exists(CONFIG_FILE) then
		Config = loadDataFile(CONFIG_FILE) or {storages={}, train_box=nil, turtles={}, autostock_paused=false}
	end
	if not Config.turtles then Config.turtles = {} end
	if not Config.storages then Config.storages = {} end
	if not Config.fluid_tanks then Config.fluid_tanks = {} end
	if Config.turtle and Config.turtle ~= "" then
		Config.turtles[Config.turtle] = true
		Config.turtle = nil
	end
	if fs.exists(FLUIDS_FILE) then
		FluidRecipes = loadDataFile(FLUIDS_FILE) or {}
	end
	if fs.exists(FLUID_ALTS_FILE) then
		FluidAltRecipes = loadDataFile(FLUID_ALTS_FILE) or {}
	end
	if fs.exists(AUTOSTOCK_FILE) then
		Autostock = loadDataFile(AUTOSTOCK_FILE) or {}
	end
	if fs.exists(GROUPS_FILE) then
		local raw = loadDataFile(GROUPS_FILE) or {}
		ExcludedMachines = {}
		for k, v in pairs(raw) do
			if type(k) == "string" and type(v) == "boolean" then
				ExcludedMachines[k] = v
			end
		end
	end
	if fs.exists(ALT_RECIPES_FILE) then
		AltRecipes = loadDataFile(ALT_RECIPES_FILE) or {}
	end
	if fs.exists(MGMT_FILE) then
		MgmtGroups = loadDataFile(MGMT_FILE) or {}
	end
	if fs.exists(MACHINE_LABELS_FILE) then
		MachineLabels = loadDataFile(MACHINE_LABELS_FILE) or {}
	end
	if fs.exists(CUSTOM_MG_FILE) then
		local raw = loadDataFile(CUSTOM_MG_FILE) or {}
		if type(raw) == "table" then CustomMachineGroups = raw end
	end
end

function syncFluidStubs()
	local itemSrc = {}
	for key, rec in pairs(FluidRecipes) do
		for _, o in ipairs(rec.item_outputs or {}) do
			if not itemSrc[o.name] then itemSrc[o.name] = {count = o.count, key = key, machine = rec.machine_name} end
		end
	end
	for key, alts in pairs(FluidAltRecipes) do
		for _, rec in ipairs(alts) do
			for _, o in ipairs(rec.item_outputs or {}) do
				if not itemSrc[o.name] then itemSrc[o.name] = {count = o.count, key = key, machine = rec.machine_name} end
			end
		end
	end
	for itemName, rec in pairs(Recipes) do
		if type(rec) == "table" and rec.type == "fluid" and not itemSrc[itemName] then
			Recipes[itemName] = nil
		end
	end
	for itemName, src in pairs(itemSrc) do
		local existing = Recipes[itemName]
		if not existing or (type(existing) == "table" and existing.type == "fluid") then
			Recipes[itemName] = {
				type = "fluid",
				fluid_key = src.key,
				machine_name = src.machine,
				output_count = src.count,
				ingredients = {"nil","nil","nil","nil","nil","nil","nil","nil","nil"},
			}
		end
	end
end

function saveData()
	if _fpCache then for k in pairs(_fpCache) do _fpCache[k] = nil end end
	local failNote = nil

	local function writeFile(path, tbl)
		local n = 0
		for _ in pairs(tbl) do n = n + 1 end
		local prev = _savedCounts[path]
		-- DO NOT REMOVE. lost whole recipes db once bcz a table got clobbered
		-- mid-save and we wrote 2 entries over the good file.
		-- if count drops by half we refuse to save
		if prev and prev >= 5 and n < prev * 0.5 then
			failNote = "SAVE BLOCKED: " .. fs.getName(path) .. " " .. prev .. "->" .. n
			return
		end
		local okS, data = pcall(textutils.serializeJSON, tbl)
		if not (okS and type(data) == "string") then
			failNote = "SERIALIZE FAIL: " .. fs.getName(path)
			return
		end
		local tmp = path .. ".new"
		-- write .new, verify size, then swap. never open the real file for write,
		-- crash mid-write leaves it half and boot dies with json parse error
		local function tryWrite()
			local okT = pcall(function()
					local fh = fs.open(tmp, "w")
					if not fh then error("open") end
					fh.write(data)
					fh.close()
				end)
			return okT and fs.exists(tmp) and fs.getSize(tmp) >= #data
		end
		local okW = tryWrite()
		if not okW then
			fs.delete(tmp)
			fs.delete(path .. ".bak")
			okW = tryWrite()
		end
		if not okW then
			fs.delete(tmp)
			failNote = "SAVE FAIL (disk space?): " .. fs.getName(path)
			return
		end
		fs.delete(path)
		fs.move(tmp, path)
		local free = fs.getFreeSpace("/") or 0
		if free > fs.getSize(path) + 4096 then
			fs.delete(path .. ".bak")
			pcall(fs.copy, path, path .. ".bak")
		end
		_savedCounts[path] = n
	end
	local recToSave = {}
	for k, v in pairs(Recipes) do
		if not (type(v) == "table" and v.type == "fluid") then recToSave[k] = v end
	end
	writeFile(RECIPES_FILE, recToSave)
	local cfgToSave = {}
	for k, v in pairs(Config) do cfgToSave[k] = v end
	cfgToSave.github_token = nil
	cfgToSave.github_repo  = nil
	writeFile(CONFIG_FILE, cfgToSave)
	writeFile(AUTOSTOCK_FILE,      Autostock)
	writeFile(GROUPS_FILE,         ExcludedMachines)
	writeFile(ALT_RECIPES_FILE,    AltRecipes)
	writeFile(MGMT_FILE,           MgmtGroups)
	writeFile(MACHINE_LABELS_FILE, MachineLabels)
	writeFile(CUSTOM_MG_FILE,      CustomMachineGroups)
	writeFile(FLUIDS_FILE,         FluidRecipes)
	writeFile(FLUID_ALTS_FILE,     FluidAltRecipes)
	if failNote then
		uiMessage = failNote
		if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
		uiMsgTimer = os.startTimer(6)
	end
end


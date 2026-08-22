function fluidKey(fluidName) return "f:" .. fluidName end

function fluidNameOf(key)
	if type(key) == "string" and key:sub(1, 2) == "f:" then return key:sub(3) end
	return key
end

function primaryKey(recipe)
	if recipe.outputs and recipe.outputs[1] then return fluidKey(recipe.outputs[1].name) end
	if recipe.item_outputs and recipe.item_outputs[1] then return "i:" .. recipe.item_outputs[1].name end
	return nil
end

function findFluidItemProd(itemName)
	for _, rec in pairs(Fluids.all()) do
		for _, o in ipairs(rec.item_outputs or {}) do
			if o.name == itemName then return rec, o.count end
		end
	end
	for _, alts in pairs(Fluids.allAlts()) do
		for _, rec in ipairs(alts) do
			for _, o in ipairs(rec.item_outputs or {}) do
				if o.name == itemName then return rec, o.count end
			end
		end
	end
	return nil
end

function getFluid()
	local inventory  = {}
	local tankCount  = 0
	local totalMb    = 0
	local tankDetails = {}
	local names = {}
	for tankName, isEnabled in pairs(Config.fluid_tanks or {}) do
		if isEnabled and not SYSTEM_SIDES[tankName] then names[#names + 1] = tankName end
	end
	local scanned = scanPeriph(names, "tanks")
	for _, nm in ipairs(names) do
		local e = scanned[nm]
		if e then
			tankCount = tankCount + 1
			if e.data then
				for _, t in pairs(e.data) do
					if t and t.name and t.amount and t.amount > 0 then
						local k = fluidKey(t.name)
						inventory[k] = (inventory[k] or 0) + t.amount
						totalMb = totalMb + t.amount
						table.insert(tankDetails, {periph = nm, fluid = t.name, amount = t.amount})
					end
				end
			end
		end
	end
	return inventory, tankCount, totalMb, tankDetails
end

function getFluidCached()
	local now = os.clock()
	if _flInvCache and (now - _flInvCacheT) < 6 then return _flInvCache end
	_flInvCache = (getFluid())
	_flInvCacheT = now
	return _flInvCache
end

function getTankStats()
	local now = os.clock()
	if _tankStatsCache and (now - _tankStatsT) < 6 then
		return _tankStatsCache.free, _tankStatsCache.total
	end
	local total, free = 0, 0
	local names = {}
	for tankName, en in pairs(Config.fluid_tanks or {}) do
		if en and not SYSTEM_SIDES[tankName] then names[#names + 1] = tankName end
	end
	local scanned = scanPeriph(names, "tanks")
	for _, nm in ipairs(names) do
		local e = scanned[nm]
		if e then
			total = total + 1
			local hasFluid = false
			if e.data then
				for _, t in pairs(e.data) do
					if t and t.amount and t.amount > 0 then hasFluid = true; break end
				end
			end
			if not hasFluid then free = free + 1 end
		end
	end
	_tankStatsCache = {free = free, total = total}
	_tankStatsT = now
	return free, total
end

function fluidTankList()
	local out = {}
	for name, en in pairs(Config.fluid_tanks or {}) do
		if en and not SYSTEM_SIDES[name] then out[#out + 1] = name end
	end
	return out
end

function tankContents(periphName)
	local res = {}
	local t = peripheral.wrap(periphName)
	if not (t and t.tanks) then return res end
	local ok, list = pcall(t.tanks)
	if ok and list then
		for _, e in pairs(list) do
			if e and e.name and e.amount and e.amount > 0 then
				res[e.name] = (res[e.name] or 0) + e.amount
			end
		end
	end
	return res
end


function optTanks()
	local excluded = {}
	for _, g in ipairs(MgmtGroups) do
		if g.output and g.output ~= "" and g.output ~= "STORAGE" then
			excluded[g.output] = true
		end
	end

	local byFluid = {}
	for tankName, isEnabled in pairs(Config.fluid_tanks or {}) do
		if isEnabled and not SYSTEM_SIDES[tankName] and not excluded[tankName] then
			local t = peripheral.wrap(tankName)
			if t and t.tanks and t.pushFluid then
				for fname, amt in pairs(tankContents(tankName)) do
					if amt > 0 then
						byFluid[fname] = byFluid[fname] or {}
						byFluid[fname][#byFluid[fname] + 1] = {periph = tankName, amount = amt}
					end
				end
			end
		end
	end

	for fluidName, tlist in pairs(byFluid) do
		if #tlist > 1 then
			table.sort(tlist, function(a, b) return a.amount > b.amount end)
			local target = 1
			for i = 2, #tlist do
				local srcName = tlist[i].periph
				local srcP = peripheral.wrap(srcName)
				if srcP and srcP.pushFluid then
					local guard = 0
					while target < i and guard < 128 do
						guard = guard + 1
						local ok, n = pcall(srcP.pushFluid, tlist[target].periph, 1000000000, fluidName)
						local moved = (ok and type(n) == "number") and n or 0
						local rem = (tankContents(srcName))[fluidName] or 0
						if rem <= 0 then break end
						if moved <= 0 then target = target + 1 end
					end
				end
			end
		end
	end
end

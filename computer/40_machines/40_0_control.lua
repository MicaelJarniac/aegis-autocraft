function tanksWFluid(fluidName)
	local out = {}
	local names = fluidTankList()
	local scanned = scanPeriph(names, "tanks")
	for _, name in ipairs(names) do
		local e = scanned[name]
		if e and e.data then
			local amt = 0
			for _, t in pairs(e.data) do
				if t and t.name == fluidName and t.amount then amt = amt + t.amount end
			end
			if amt > 0 then out[#out + 1] = {periph = name, amount = amt} end
		end
	end
	table.sort(out, function(a, b) return a.amount > b.amount end)
	return out
end

function pushFluidToMach(machineName, fluidName, amount)
	local moved = 0
	-- pushFluid returns partial fills, some mods cap per call.
	-- hammer same tank until it stops moving, THEN next source.
	-- single call = fluid stuck in source
	for _, src in ipairs(tanksWFluid(fluidName)) do
		if moved >= amount then break end
		local t = peripheral.wrap(src.periph)
		if t and t.pushFluid then
			while moved < amount do
				local ok, m = pcall(t.pushFluid, machineName, amount - moved, fluidName)
				if ok and type(m) == "number" and m > 0 then moved = moved + m
				else break end
			end
		end
	end
	if moved > 0 then resetStock() end
	return moved
end

function tankRes()
	local res = {}
	for _, g in ipairs(MgmtGroups or {}) do
		local isFluid = g.fluid
		if isFluid == nil then
			isFluid = (g.input and Config.fluid_tanks and Config.fluid_tanks[g.input])
			or (g.output and Config.fluid_tanks and Config.fluid_tanks[g.output]) or false
		end
		if isFluid then
			for _, periph in ipairs({g.output, g.input}) do
				if periph and periph ~= "" and periph ~= "STORAGE"
				and Config.fluid_tanks and Config.fluid_tanks[periph] then
					for _, rule in ipairs(g.rules or {}) do
						if rule.item and rule.item ~= "" then
							res[periph] = res[periph] or {}
							res[periph][rule.item] = true
						end
					end
				end
			end
		end
	end
	return res
end

function drainFluid(machineName, fluidName, limit)
	local moved = 0
	local machine = peripheral.wrap(machineName)
	local reserved = tankRes()

	local function allowed(tname)
		local r = reserved[tname]
		return (not r) or r[fluidName]
	end
	local ordered = {}
	local seen = {}
	local resvFirst = {}
	for tname, fl in pairs(reserved) do
		if fl[fluidName] and Config.fluid_tanks and Config.fluid_tanks[tname] then resvFirst[#resvFirst + 1] = tname end
	end
	table.sort(resvFirst)
	for _, name in ipairs(resvFirst) do
		if not seen[name] then ordered[#ordered + 1] = name; seen[name] = true end
	end
	for _, t in ipairs(tanksWFluid(fluidName)) do
		if not seen[t.periph] and allowed(t.periph) then ordered[#ordered + 1] = t.periph; seen[t.periph] = true end
	end
	local rest = {}
	for _, name in ipairs(fluidTankList()) do
		if not seen[name] and allowed(name) then rest[#rest + 1] = name end
	end
	table.sort(rest)
	for _, name in ipairs(rest) do ordered[#ordered + 1] = name end

	local function srcHas()
		if not (machine and machine.tanks) then return false end
		local ok, list = pcall(machine.tanks)
		if not (ok and list) then return false end
		for _, e in pairs(list) do
			if e and e.name == fluidName and (e.amount or 0) > 1 then return true end
		end
		return false
	end
	for _, periphName in ipairs(ordered) do
		if moved >= limit then break end
		if machine and machine.pushFluid then
			for _ = 1, 128 do
				if moved >= limit then break end
				local ok, m = pcall(machine.pushFluid, periphName, limit - moved, fluidName)
				if not (ok and type(m) == "number" and m > 0) then break end
				moved = moved + m
			end
		end
		if moved < limit then
			local dst = peripheral.wrap(periphName)
			if dst and dst.pullFluid then
				for _ = 1, 128 do
					if moved >= limit then break end
					local ok, m = pcall(dst.pullFluid, machineName, limit - moved, fluidName)
					if not (ok and type(m) == "number" and m > 0) then break end
					moved = moved + m
				end
			end
		end
		if moved < limit and not srcHas() then
			if moved > 0 then resetStock() end
			return moved
		end
	end
	if moved > 0 then resetStock() end
	return moved
end

function pushStoList()
	local out = {}
	for sName, en in pairs(Config.storages or {}) do
		if en and not SYSTEM_SIDES[sName] then out[#out + 1] = sName end
	end
	table.sort(out)
	return out
end

-- end-of-craft cleanup. any machine we touched (Craft.usedMachines) gets
-- fully drained back to sto, items and fluids. otherwise leftovers pile up
-- and jam the next unrelated craft
function sweepMachines()
	local stoNames = pushStoList()
	for mName in pairs(Craft.usedMachines or {}) do
		local m = peripheral.wrap(mName)
		if m then
			if m.list and m.pushItems then
				local ok, items = pcall(m.list)
				if ok and items then
					for slot, it in pairs(items) do
						if it and it.count and it.count > 0 then
							local left = it.count
							for _, sName in ipairs(packOrder(it.name, stoNames)) do
								if left <= 0 then break end
								local okP, mv = pcall(m.pushItems, sName, slot, left)
								if okP and type(mv) == "number" and mv > 0 then
									left = left - mv; packRemember(it.name, sName)
								elseif okP and (not mv or mv == 0) then
									packForget(it.name, sName)
								end
							end
						end
					end
				end
			end
			if m.tanks then
				local okT, tl = pcall(m.tanks)
				if okT and tl then
					for _, tk in pairs(tl) do
						if tk and tk.name and tk.amount and tk.amount > 0 then
							drainFluid(mName, tk.name, tk.amount)
						end
					end
				end
			end
		end
	end
	Craft.usedMachines = {}
end

function machFluidSnap(machine)
	local res = {}
	local ok, list = pcall(machine.tanks)
	if ok and list then
		for _, e in pairs(list) do
			if e and e.name and e.amount and e.amount > 0 then
				res[e.name] = (res[e.name] or 0) + e.amount
			end
		end
	end
	return res
end

function sameFluidMap(a, b)
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k, v in pairs(b) do if a[k] ~= v then return false end end
	return true
end

function machItemSnap(machineName)
	local res = {}
	local m = peripheral.wrap(machineName)
	if not (m and m.list) then return res end
	local ok, items = pcall(m.list)
	if ok and items then
		for _, it in pairs(items) do
			if it and it.name and it.count and it.count > 0 then
				res[it.name] = (res[it.name] or 0) + it.count
			end
		end
	end
	return res
end

function waitFluidStable(machine, machineName, timeoutTot, cancellable, onTick)

	local function combo()
		local res = {}
		for k, v in pairs(machFluidSnap(machine)) do res["f:" .. k] = v end
		for k, v in pairs(machItemSnap(machineName)) do res["i:" .. k] = v end
		return res
	end
	local prevC = combo()
	local stableCount, sawChange, elapsed = 0, false, 0
	while true do
		if onTick then onTick() end
		if cancellable then
			sleepCancel(0.5)
			if Craft.cancelled then return machFluidSnap(machine), true end
		else
			sleep(0.5)
		end
		elapsed = elapsed + 0.5
		local curC = combo()
		if sameFluidMap(prevC, curC) then
			stableCount = stableCount + 1
		else
			sawChange = true
			stableCount = 0
		end
		prevC = curC
		if sawChange and stableCount >= 3 then break end
		if not cancellable and elapsed >= timeoutTot then break end
	end
	return machFluidSnap(machine), false
end

function drainMachItems(machineName)
	local m = peripheral.wrap(machineName)
	if not (m and m.list and m.pushItems) then return end
	local ok, items = pcall(m.list)
	if not (ok and items) then return end
	local stoNames = pushStoList()
	for slot, item in pairs(items) do
		if item and item.count and item.count > 0 then
			local left = item.count
			for _, sName in ipairs(packOrder(item.name, stoNames)) do
				if left <= 0 then break end
				local okP, mv = pcall(m.pushItems, sName, slot, left)
				if okP and type(mv) == "number" and mv > 0 then
					left = left - mv; packRemember(item.name, sName)
				elseif okP and (not mv or mv == 0) then
					packForget(item.name, sName)
				end
			end
		end
	end
end

function barrelToMach(machineName)
	local counts = {}
	if not Config.train_box or Config.train_box == "" then return counts end
	local box = peripheral.wrap(Config.train_box)
	if not (box and box.list and box.pushItems and box.getItemDetail) then return counts end
	local centerSlots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
	for _, slot in ipairs(centerSlots) do
		local ok, item = pcall(box.getItemDetail, slot)
		if ok and item and item.name and item.count and item.count > 0 then
			counts[item.name] = (counts[item.name] or 0) + item.count
			pcall(box.pushItems, machineName, slot, item.count)
		end
	end
	return counts
end

function pushItemsToMach(machineName, itemName, count)
	return pushFromStore(itemName, count, machineName) or 0
end


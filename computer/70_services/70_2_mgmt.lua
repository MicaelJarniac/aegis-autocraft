function mgmtMvSlot(srcName, srcSlot, destName, amount)
	local srcP = peripheral.wrap(srcName)
	if srcP and srcP.pushItems then
		local ok, mv = pcall(srcP.pushItems, destName, srcSlot, amount)
		if ok and mv and mv > 0 then return mv end
	end
	local dstP = peripheral.wrap(destName)
	if dstP and dstP.pullItems then
		local ok2, mv2 = pcall(dstP.pullItems, srcName, srcSlot, amount)
		if ok2 and mv2 and mv2 > 0 then return mv2 end
	end
	return 0
end

function isFluidPeri(name)
	if not name or name == "" or name == "STORAGE" then return false end
	if Config.fluid_tanks and Config.fluid_tanks[name] then return true end
	local w = peripheral.wrap(name)
	if w and w.tanks and not w.list then return true end
	return false
end

function isFluid(g)
	if g.fluid ~= nil then return g.fluid end
	return isFluidPeri(g.input) or isFluidPeri(g.output)
end

function mgmtMvFluid(srcName, destName, fluidName, amount)
	if not amount or amount <= 0 then return 0 end
	local srcP = peripheral.wrap(srcName)
	if srcP and srcP.pushFluid then
		local ok, mv = pcall(srcP.pushFluid, destName, amount, fluidName)
		if ok and type(mv) == "number" and mv > 0 then return mv end
	end
	local dstP = peripheral.wrap(destName)
	if dstP and dstP.pullFluid then
		local ok2, mv2 = pcall(dstP.pullFluid, srcName, amount, fluidName)
		if ok2 and type(mv2) == "number" and mv2 > 0 then return mv2 end
	end
	return 0
end

function mgmtFSnap()
	local snap = {}
	for k, v in pairs(getFluid()) do
		snap[fluidNameOf(k)] = v
	end
	return snap
end

function runFluidGroup(group)
	local moved = 0
	local inputIsStg  = (not group.input  or group.input  == "" or group.input  == "STORAGE")
	local outputIsStg = (not group.output or group.output == "" or group.output == "STORAGE")
	if inputIsStg and outputIsStg then return 0 end
	local fsnap = mgmtFSnap()
	local netTanks = fluidTankList()
	if group.drain and not inputIsStg then
		for fname, amt in pairs(tankContents(group.input)) do
			local toMove = amt
			if outputIsStg then
				for _, tname in ipairs(netTanks) do
					if toMove <= 0 then break end
					if tname ~= group.input then
						local mv = mgmtMvFluid(group.input, tname, fname, toMove)
						if mv > 0 then toMove = toMove - mv; moved = moved + mv end
					end
				end
			else
				local mv = mgmtMvFluid(group.input, group.output, fname, toMove)
				if mv > 0 then moved = moved + mv end
			end
		end
	end
	for _, rule in ipairs(group.rules or {}) do
		local curInOutput = 0
		if outputIsStg then
			curInOutput = fsnap[rule.item] or 0
		else
			curInOutput = (tankContents(group.output))[rule.item] or 0
		end
		local condOk = true
		if rule.condition and rule.condition.item and rule.condition.item ~= "" then
			local condCount = fsnap[rule.condition.item] or 0
			local condVal   = rule.condition.value or 1
			local condOp    = rule.condition.op or "<"
			if condOp == "<" then condOk = condCount < condVal
			elseif condOp == ">" then condOk = condCount > condVal
			elseif condOp == "=" then condOk = condCount == condVal
			end
		end
		if condOk and curInOutput < rule.amount then
			local needed = rule.amount - curInOutput
			if inputIsStg then
				for _, src in ipairs(tanksWFluid(rule.item)) do
					if needed <= 0 then break end
					if src.periph ~= group.output then
						local mv = mgmtMvFluid(src.periph, group.output, rule.item, needed)
						if mv > 0 then
							needed = needed - mv
							moved  = moved + mv
							fsnap[rule.item] = math.max(0, (fsnap[rule.item] or 0) - mv)
						end
					end
				end
			elseif outputIsStg then
				for _, tname in ipairs(netTanks) do
					if needed <= 0 then break end
					if tname ~= group.input then
						local mv = mgmtMvFluid(group.input, tname, rule.item, needed)
						if mv > 0 then
							needed = needed - mv
							moved  = moved + mv
							fsnap[rule.item] = (fsnap[rule.item] or 0) + mv
						end
					end
				end
			else
				local mv = mgmtMvFluid(group.input, group.output, rule.item, needed)
				if mv > 0 then needed = needed - mv; moved = moved + mv end
			end
		end
	end
	return moved
end

function mgmtIOList(group, isInput)
	local lst = isInput and group.inputs or group.outputs
	if type(lst) == "table" and #lst > 0 then return lst end
	local s = isInput and group.input or group.output
	if not s or s == "" or s == "STORAGE" then return { "STORAGE" } end
	return { s }
end

function listIsStorage(lst)
	return (#lst == 0) or (lst[1] == "STORAGE")
end

function mgmtIODisp(group, isInput)
	local lst = mgmtIOList(group, isInput)
	if listIsStorage(lst) then return "STORAGE" end
	local d = getMachName(lst[1]) or lst[1]
	if #lst > 1 then d = d .. " +" .. (#lst - 1) end
	return d
end

function mgmtCntItem(srcNames, itemName)
	local total = 0
	for _, nm in ipairs(srcNames) do
		local p = peripheral.wrap(nm)
		if p and p.list then
			local ok, items = pcall(p.list)
			if ok and items then
				for _, si in pairs(items) do
					if si and si.name == itemName then total = total + si.count end
				end
			end
		end
	end
	return total
end

function mgmtMvFrom(srcName, dest, itemName, amount, storageList)
	if amount <= 0 then return 0 end
	local p = peripheral.wrap(srcName)
	if not (p and p.list) then return 0 end
	local ok, items = pcall(p.list)
	if not (ok and items) then return 0 end
	local moved = 0
	for sl, si in pairs(items) do
		if moved >= amount then break end
		if si and si.name == itemName then
			local want = math.min(amount - moved, si.count)
			if dest == "STORAGE" then
				for _, sn in ipairs(storageList) do
					if want <= 0 then break end
					local mv = mgmtMvSlot(srcName, sl, sn, want)
					if mv > 0 then moved = moved + mv; want = want - mv end
				end
			else
				local mv = mgmtMvSlot(srcName, sl, dest, want)
				if mv > 0 then moved = moved + mv end
			end
		end
	end
	return moved
end

function mgmtDrawEven(inputs, dest, itemName, amount, storageList, rr)
	local moved = 0
	local n = #inputs
	if n == 0 or amount <= 0 then return 0 end
	while moved < amount do
		local cycleMoved = 0
		local chunk = math.max(1, math.ceil((amount - moved) / n))
		for _ = 1, n do
			if moved >= amount then break end
			rr.i = (rr.i % n) + 1
			local mv = mgmtMvFrom(inputs[rr.i], dest, itemName,
				math.min(amount - moved, chunk), storageList)
			if mv > 0 then moved = moved + mv; cycleMoved = cycleMoved + mv end
		end
		if cycleMoved == 0 then break end
	end
	return moved
end

function runItemGroup(group, stockSnap, storageList)
	local moved   = 0
	local inputs  = mgmtIOList(group, true)
	local outputs = mgmtIOList(group, false)
	local inStg   = listIsStorage(inputs)
	local outStg  = listIsStorage(outputs)
	if inStg and outStg then return 0 end
	local srcSet = inStg and storageList or inputs
	if group.drain and not inStg then
		local rr = { i = 0 }
		for _, nm in ipairs(inputs) do
			local p = peripheral.wrap(nm)
			if p and p.list then
				local okD, slots = pcall(p.list)
				if okD and slots then
					for sl, si in pairs(slots) do
						if si and si.count > 0 then
							local toMove = si.count
							if outStg then
								for _, sn in ipairs(storageList) do
									if toMove <= 0 then break end
									local mv = mgmtMvSlot(nm, sl, sn, toMove)
									if mv > 0 then
										toMove = toMove - mv; moved = moved + mv
										stockSnap[si.name] = (stockSnap[si.name] or 0) + mv
									end
								end
							else
								local cnt = #outputs
								while toMove > 0 do
									local before = toMove
									for _ = 1, cnt do
										if toMove <= 0 then break end
										rr.i = (rr.i % cnt) + 1
										local mv = mgmtMvSlot(nm, sl, outputs[rr.i], toMove)
										if mv > 0 then toMove = toMove - mv; moved = moved + mv end
									end
									if toMove == before then break end
								end
							end
						end
					end
				end
			end
		end
	end
	for _, rule in ipairs(group.rules or {}) do
		local condOk = true
		if rule.condition and rule.condition.item and rule.condition.item ~= "" then
			local condCount = stockSnap[rule.condition.item] or 0
			local condVal   = rule.condition.value or 1
			local condOp    = rule.condition.op or "<"
			if condOp == "<" then condOk = condCount < condVal
			elseif condOp == ">" then condOk = condCount > condVal
			elseif condOp == "=" then condOk = condCount == condVal end
		end
		if condOk then
			local targets = {}
			if outStg then
				local cur = stockSnap[rule.item] or 0
				targets[1] = { dest = "STORAGE", cur = cur, def = math.max(0, rule.amount - cur) }
			else
				for _, oN in ipairs(outputs) do
					local cur = mgmtCntItem({ oN }, rule.item)
					targets[#targets + 1] = { dest = oN, cur = cur, def = math.max(0, rule.amount - cur) }
				end
			end
			local sumDef = 0
			for _, t in ipairs(targets) do sumDef = sumDef + t.def end
			if sumDef > 0 then
				local avail  = inStg and (stockSnap[rule.item] or 0) or mgmtCntItem(inputs, rule.item)
				local toDist = math.min(avail, sumDef)
				for _ = 1, toDist do
					local pick, lvl
					for ti, t in ipairs(targets) do
						if t.def > 0 and (not pick or t.cur < lvl) then pick = ti; lvl = t.cur end
					end
					if not pick then break end
					targets[pick].cur   = targets[pick].cur + 1
					targets[pick].def   = targets[pick].def - 1
					targets[pick].alloc = (targets[pick].alloc or 0) + 1
				end
				local rr = { i = 0 }
				for _, t in ipairs(targets) do
					local alloc = t.alloc or 0
					if alloc > 0 then
						local mv = mgmtDrawEven(srcSet, t.dest, rule.item, alloc, storageList, rr)
						if mv > 0 then
							moved = moved + mv
							if inStg and not outStg then
								stockSnap[rule.item] = math.max(0, (stockSnap[rule.item] or 0) - mv)
							elseif outStg and not inStg then
								stockSnap[rule.item] = (stockSnap[rule.item] or 0) + mv
							end
						end
					end
				end
			end
		end
	end
	return moved
end

function runMgmtTransfers()
	local totalMoved = 0
	if sysStatus ~= "IDLE" then
		mgmtSyncInfo = "paused (craft)"
		return totalMoved
	end
	if #MgmtGroups == 0 then
		mgmtSyncInfo = "no groups"
		return totalMoved
	end
	local stockSnap = getInv()
	local storageList = {}
	for sName, isEnabled in pairs(Config.storages) do
		if isEnabled and not SYSTEM_SIDES[sName] then
			table.insert(storageList, sName)
		end
	end
	if #storageList == 0 then
		mgmtSyncInfo = "no storage"
		return totalMoved
	end
	for _, group in ipairs(MgmtGroups) do
		if sysStatus ~= "IDLE" then break end
		if group.paused then goto mgmt_continue end
		if group.provider then goto mgmt_continue end
		if isFluid(group) then
			totalMoved = totalMoved + runFluidGroup(group)
			goto mgmt_continue
		end
		totalMoved = totalMoved + runItemGroup(group, stockSnap, storageList)
		::mgmt_continue::
	end
	if totalMoved > 0 then
		mgmtSyncInfo = "moved: " .. totalMoved
		resetStock()
	else
		mgmtSyncInfo = "ok (0 moved)"
	end
	return totalMoved
end


function providerSrc()
	local out, seen = {}, {}
	for _, g in ipairs(MgmtGroups or {}) do
		if g.provider and not g.paused then
			for _, src in ipairs(mgmtIOList(g, true)) do
				if src and src ~= "" and src ~= "STORAGE"
				and not Config.storages[src]
				and not (Config.fluid_tanks and Config.fluid_tanks[src])
				and not seen[src] then
					seen[src] = true
					out[#out + 1] = src
				end
			end
		end
	end
	return out
end

mgmtItemSrch       = ""
mgmtSearchOn = false
mgmtPage             = 1
mgmtPopup            = nil
custGrpPopup         = nil
mgmtSyncInfo         = ""
mgmtTicks        = 0
mgmtActBtn        = nil
syncFlashTime    = nil

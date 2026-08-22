function planFluid(recipe, targetName, amount)
	if not recipe then return false, nil, {"No recipe"} end
	local perOp, isItemTarget = nil, false
	for _, o in ipairs(recipe.outputs or {}) do
		if o.name == targetName then perOp = o.amount; break end
	end
	if not perOp then
		for _, o in ipairs(recipe.item_outputs or {}) do
			if o.name == targetName then perOp = o.count; isItemTarget = true; break end
		end
	end
	if not perOp or perOp <= 0 then return false, nil, {"Bad recipe output amount"} end
	local ops = math.ceil(amount / perOp)
	local inv = getFluid()
	local errLines = {}
	for _, inp in ipairs(recipe.inputs or {}) do
		local need = ops * inp.amount
		local have = inv[fluidKey(inp.name)] or 0
		if have < need then
			local sn = shortName(inp.name)
			table.insert(errLines, string.format("Need %d mB %s, have %d", need, sn, have))
		end
	end
	if recipe.item_inputs and #recipe.item_inputs > 0 then
		local stk = getInv()
		for _, it in ipairs(recipe.item_inputs) do
			local need = ops * it.count
			local have = stk[it.name] or 0
			if have < need then
				local sn = shortName(it.name)
				table.insert(errLines, string.format("Need %dx %s, have %d", need, sn, have))
			end
		end
	end
	if #errLines > 0 then return false, nil, errLines end
	return true, {recipe = recipe, ops = ops, perOp = perOp, target = targetName, isItem = isItemTarget}, nil
end

function checkOutStore(recipe)
	local emptyCount = 0
	local held = {}
	for _, name in ipairs(fluidTankList()) do
		local c = tankContents(name)
		if next(c) == nil then emptyCount = emptyCount + 1
		else for fn in pairs(c) do held[fn] = true end end
	end
	local newOuts = {}
	for _, o in ipairs(recipe.outputs or {}) do
		if not held[o.name] then newOuts[#newOuts + 1] = o.name end
	end
	-- subtract fluidTankClaims. other in-flight crafts already booked this many
	-- empty tanks. dont double-book or two crafts race same tank and one wedges
	if #newOuts > emptyCount - (fluidTankClaims or 0) then
		local sn = newOuts[1] and ((newOuts[1]):match(":(.+)$") or newOuts[1]) or "?"
		return false, {
			"No free [TNK] tank for output: " .. sn,
			"Mark an empty tank with [TNK] in NETWORK.",
		}
	end
	return true, nil, #newOuts
end

function fluidCraftInner(plan)
	local recipe = plan.recipe
	local baseMachine = recipe.machine_name
	local splitOut = nil
	if recipe.output_device and recipe.output_device ~= "" then
		if peripheral.wrap(recipe.output_device) then
			splitOut = recipe.output_device
		else
			return false, {"Output device not found: " .. tostring(recipe.output_device)}, 0
		end
	end
	local itemInDev = nil
	if recipe.item_input_device and recipe.item_input_device ~= "" then
		if peripheral.wrap(recipe.item_input_device) then
			itemInDev = recipe.item_input_device
		else
			return false, {"Item input device not found: " .. tostring(recipe.item_input_device)}, 0
		end
	end
	local fluidInDev = nil
	if recipe.fluid_input_device and recipe.fluid_input_device ~= "" then
		if peripheral.wrap(recipe.fluid_input_device) then
			fluidInDev = recipe.fluid_input_device
		else
			return false, {"Fluid input device not found: " .. tostring(recipe.fluid_input_device)}, 0
		end
	end
	local itemOutDev = nil
	if recipe.item_output_device and recipe.item_output_device ~= "" then
		if peripheral.wrap(recipe.item_output_device) then
			itemOutDev = recipe.item_output_device
		else
			return false, {"Item output device not found: " .. tostring(recipe.item_output_device)}, 0
		end
	end
	local pool = {}
	if splitOut or itemInDev or fluidInDev or itemOutDev then
		local pp = peripheral.wrap(baseMachine)
		if pp and pp.tanks and pp.pushFluid and pp.pullFluid then pool = {baseMachine} end
	else
		for _, pmName in ipairs(getMachPool(baseMachine)) do
			local pp = peripheral.wrap(pmName)
			if pp and pp.tanks and pp.pushFluid and pp.pullFluid then
				pool[#pool + 1] = pmName
			end
		end
	end
	if #pool == 0 then
		return false, {"Machine missing fluid methods: " .. tostring(baseMachine)}, 0
	end
	for _, pmName in ipairs(pool) do Craft.usedMachines[pmName] = true end
	if splitOut   then Craft.usedMachines[splitOut]   = true end
	if itemInDev  then Craft.usedMachines[itemInDev]  = true end
	if fluidInDev then Craft.usedMachines[fluidInDev] = true end
	if itemOutDev then Craft.usedMachines[itemOutDev] = true end
	local inFluidSet, inItemSet = {}, {}
	for _, inp in ipairs(recipe.inputs or {}) do inFluidSet[inp.name] = true end
	for _, it in ipairs(recipe.item_inputs or {}) do inItemSet[it.name] = true end
	local targetName = plan.label
	local targetIsItem = false
	for _, o in ipairs(recipe.item_outputs or {}) do
		if o.name == targetName then targetIsItem = true; break end
	end
	local itemMaxStack = {}
	for _, it in ipairs(recipe.item_inputs or {}) do
		local maxS = 64
		for sName, en in pairs(Config.storages or {}) do
			if en and not SYSTEM_SIDES[sName] then
				local sto = peripheral.wrap(sName)
				if sto and sto.list and sto.getItemDetail then
					local okL, lst = pcall(sto.list)
					if okL and lst then
						local found = false
						for slotI, itemI in pairs(lst) do
							if itemI and itemI.name == it.name then
								local okD, det = pcall(sto.getItemDetail, slotI)
								if okD and det and det.maxCount and det.maxCount > 0 then maxS = det.maxCount end
								found = true
								break
							end
						end
						if found then break end
					end
				end
			end
		end
		itemMaxStack[it.name] = maxS
	end
	local label = plan.label or baseMachine or "fluid"
	fluidStepNum = fluidStepNum + 1
	if fluidStepNum > fluidStepTotal then fluidStepTotal = fluidStepNum end
	fluidSubLabel = label
	local totalOps = plan.ops
	local produced = 0
	local dbgEnt = fluidInlineByCo[lockOwnerId()]
	local dbgBaseline
	if dbgEnt then
		if targetIsItem then dbgBaseline = (getInvCached()[targetName] or 0)
		else                 dbgBaseline = (getFluidCached()[fluidKey(targetName)] or 0) end
	end

	local function pushBatch(mName, wantOps)
		local accepted = wantOps
		for _, it in ipairs(recipe.item_inputs or {}) do
			local maxS = itemMaxStack[it.name] or 64
			if maxS >= it.count then
				local maxOpsItem = math.floor(maxS / it.count)
				if maxOpsItem < accepted then accepted = maxOpsItem end
			elseif accepted > 1 then
				accepted = 1
			end
		end
		for _, inp in ipairs(recipe.inputs or {}) do
			local avail = 0
			for _, src in ipairs(tanksWFluid(inp.name)) do avail = avail + (src.amount or 0) end
			local opsForInp = math.floor(avail / inp.amount)
			if opsForInp < accepted then accepted = opsForInp end
		end
		if accepted < 1 then return 0 end
		local fDev = fluidInDev or mName
		local fPer = peripheral.wrap(fDev)
		if fPer and #(recipe.inputs or {}) > 0 then
			local seqPour = (splitOut ~= nil or itemInDev ~= nil or fluidInDev ~= nil or itemOutDev ~= nil)
			and #(recipe.inputs or {}) > 1
			local preF = machFluidSnap(fPer)
			for fi, inp in ipairs(recipe.inputs or {}) do
				if seqPour and fi > 1 then
					local prevName = recipe.inputs[fi - 1].name
					local waitC = 0
					while waitC < 40 do
						local snapW = machFluidSnap(fPer)
						if (snapW[prevName] or 0) <= 0 then break end
						sleepCancel(0.5)
						if Craft.cancelled then return 0 end
						waitC = waitC + 1
					end
					preF = machFluidSnap(fPer)
				end
				local have   = preF[inp.name] or 0
				local curOps = math.floor(have / inp.amount)
				local needed = (curOps + accepted) * inp.amount - have
				local moved  = 0
				if needed > 0 then moved = pushFluidToMach(fDev, inp.name, needed) end
				local newOps = math.floor((have + moved) / inp.amount) - curOps
				if newOps < accepted then accepted = math.max(0, newOps) end
			end
			if accepted < 1 then return 0 end
		end
		local iDev = itemInDev or mName
		local preI = {}
		if #(recipe.item_inputs or {}) > 0 then
			local iPer = peripheral.wrap(iDev)
			if iPer and iPer.list then
				local okI, its = pcall(iPer.list)
				if okI and its then
					for _, it2 in pairs(its) do
						if it2 and inItemSet[it2.name] then
							preI[it2.name] = (preI[it2.name] or 0) + (it2.count or 0)
						end
					end
				end
			end
		end
		for _, it in ipairs(recipe.item_inputs or {}) do
			local have   = preI[it.name] or 0
			local curOps = math.floor(have / it.count)
			local needed = (curOps + accepted) * it.count - have
			local moved  = 0
			if needed > 0 then moved = pushItemsToMach(iDev, it.name, needed) or 0 end
			local newOps = math.floor((have + moved) / it.count) - curOps
			if newOps < accepted then accepted = math.max(0, newOps) end
		end
		return accepted
	end

	local function drainMach(e)
		local targetMoved = 0
		local anyOutput = false
		local devs = { e.drain, e.name, itemOutDev }
		for _ = 1, 8 do
			local passMoved = 0
			local seenF = {}
			for _, dn in ipairs(devs) do
				if dn and not seenF[dn] then
					seenF[dn] = true
					local isDedicatedOut = (splitOut ~= nil and dn == splitOut)
					local machine = peripheral.wrap(dn)
					if machine and machine.tanks then
						local snap = machFluidSnap(machine)
						for fname, amt in pairs(snap) do
							if amt > 1 and (isDedicatedOut or not inFluidSet[fname]) then
								local moved = drainFluid(dn, fname, 1000000)
								if moved and moved > 0 then
									passMoved = passMoved + moved; anyOutput = true
									if (not targetIsItem) and fname == targetName then targetMoved = targetMoved + moved end
								end
							end
						end
					end
				end
			end
			local seenI = {}
			for _, dn in ipairs(devs) do
				if dn and not seenI[dn] then
					seenI[dn] = true
					local isDedicatedItem = (itemOutDev ~= nil and dn == itemOutDev and dn ~= itemInDev)
					local m = peripheral.wrap(dn)
					if m and m.list and m.pushItems then
						local ok, items = pcall(m.list)
						if ok and items then
							for slot, item in pairs(items) do
								if item and item.count and item.count > 0 and (isDedicatedItem or not inItemSet[item.name]) then
									local left = item.count
									for sName, en in pairs(Config.storages or {}) do
										if left <= 0 then break end
										if en and not SYSTEM_SIDES[sName] then
											local okP, mv = pcall(m.pushItems, sName, slot, left)
											if okP and type(mv) == "number" and mv > 0 then left = left - mv end
										end
									end
									local mvd = item.count - left
									if mvd > 0 then
										passMoved = passMoved + mvd; anyOutput = true
										if targetIsItem and item.name == targetName then targetMoved = targetMoved + mvd end
									end
								end
							end
						end
					end
				end
			end
			if passMoved == 0 then break end
		end
		return targetMoved, anyOutput
	end

	local function finalDrain(mName)
		local machine = peripheral.wrap(mName)
		for pass = 1, 5 do
			local snap = machFluidSnap(machine)
			local itemSnap = machItemSnap(mName)
			if next(snap) == nil and next(itemSnap) == nil then break end
			for fname in pairs(snap) do drainFluid(mName, fname, 1000000) end
			drainMachItems(mName)
		end
	end

	local function availableOps()
		if #(recipe.inputs or {}) == 0 then return nil end
		local minOps = nil
		for _, inp in ipairs(recipe.inputs) do
			local avail = 0
			for _, src in ipairs(tanksWFluid(inp.name)) do avail = avail + (src.amount or 0) end
			local opsForInp = math.floor(avail / inp.amount)
			if minOps == nil or opsForInp < minOps then minOps = opsForInp end
		end
		return minOps
	end
	local poolSize = #pool
	local base  = math.floor(totalOps / poolSize)
	local extra = totalOps % poolSize
	local machineData = {}
	for idx, mName in ipairs(pool) do
		local assigned = base + ((idx <= extra) and 1 or 0)
		if assigned > 0 then
			machineData[#machineData + 1] = {
				name        = mName,
				drain       = splitOut or mName,
				remainOps   = assigned,
				batchTarget = 0,
				batchDone   = 0,
				idle        = 0,
				starve      = 0,
				startedOut  = false,
				finished    = false,
			}
		end
	end

	local function finalDrainE(e)
		local seen = {}
		for _, d in ipairs({e.name, e.drain, itemInDev, fluidInDev, itemOutDev}) do
			if d and not seen[d] then seen[d] = true; finalDrain(d) end
		end
	end
	for _, e in ipairs(machineData) do finalDrainE(e) end
	local totalExp = totalOps * plan.perOp
	local maxWait = math.max(400, totalOps * 30)
	local waited  = 0

	local function allFinished()
		for _, e in ipairs(machineData) do
			if not e.finished then return false end
		end
		return true
	end
	-- machine died mid-batch (silent 15s or 12 loads refused). rescue its
	-- remainOps onto still-alive siblings, else pool silently loses ops
	-- and finishes with produced < totalExp. see chromium electrolyzer log:
	-- one machine stalled at 45/48, other never picked up the 79 orphaned ops.
	local function redistOps(dead)
		if (dead.remainOps or 0) <= 0 then return end
		local alive = {}
		for _, m in ipairs(machineData) do
			if m ~= dead and not m.finished then alive[#alive + 1] = m end
		end
		if #alive == 0 then return end
		local per   = math.floor(dead.remainOps / #alive)
		local extra = dead.remainOps - per * #alive
		for i, m in ipairs(alive) do
			m.remainOps = m.remainOps + per + ((i <= extra) and 1 or 0)
		end
		dead.remainOps = 0
	end
	while (not allFinished()) and produced < totalExp and waited < maxWait do
		sleepCancel(0.5)
		if Craft.cancelled then
			for _, e in ipairs(machineData) do finalDrainE(e) end
			resetStock()
			failReason("fluid.cancel_loop label=" .. tostring(label))
			return false, {"Cancelled by user."}, produced
		end
		waited = waited + 1
		local refillNeed = {}
		for _, e in ipairs(machineData) do
			if not e.finished then
				local moved, hadOut = drainMach(e)
				if moved > 0 then
					produced = produced + moved
					e.batchDone = e.batchDone + moved
					if dbgEnt then
						local sto = (dbgBaseline or 0) + produced
						if targetIsItem then
							dbgPush(Craft.jobId, dbgEnt.ctx.subId, dbgEnt.node, targetName,
								moved, produced, totalExp, sto, 0, e.name)
						else
							dbgFluidPush(Craft.jobId, dbgEnt.ctx.subId, dbgEnt.node, targetName,
								moved, produced, totalExp, sto, 0, e.name)
						end
					end
				end
				if hadOut then
					e.startedOut = true
					if e.idle > (e.maxGap or 0) then e.maxGap = e.idle end
					e.idle = 0
				else
					e.idle = e.idle + 1
				end
				-- adaptive quiet: fast machines still fold at 15s, but slow recipe
				-- that legitimately drops one item every 12s wont get killed
				-- just because 30 ticks passed. mirrors machine-engine.
				local quietNeed = math.max(30, (e.maxGap or 0) * 2 + 4)
				if e.batchDone >= e.batchTarget and not hadOut then
					if e.remainOps > 0 then
						refillNeed[#refillNeed + 1] = e
					else
						e.finished = true
					end
				elseif e.startedOut and e.idle >= quietNeed then
					e.finished = true
					redistOps(e)
				end
			end
		end
		if #refillNeed > 0 then
			local avail = availableOps()
			local share
			if avail == nil then
				share = nil
			else
				share = math.max(1, math.floor(avail / #refillNeed))
			end
			for _, e in ipairs(refillNeed) do
				local want = e.remainOps
				if share and share < want then want = share end
				if want < 1 then want = 1 end
				local acc = pushBatch(e.name, want)
				if acc > 0 then
					e.batchTarget = e.batchTarget + acc * plan.perOp
					e.remainOps   = e.remainOps - acc
					e.startedOut  = false
					e.idle        = 0
					e.starve      = 0
				else
					e.starve = e.starve + 1
					if e.starve >= 12 then
						e.finished = true
						redistOps(e)
					else
						sleepCancel(1)
					end
				end
			end
		end
		if drawFluidProg then
			local doneOpsNow = math.min(totalOps, math.floor(produced / math.max(1, plan.perOp)))
			local activeW = 0
			for _, e in ipairs(machineData) do if not e.finished then activeW = activeW + 1 end end
			drawFluidProg(label, doneOpsNow, totalOps, activeW)
		end
	end
	for _, e in ipairs(machineData) do finalDrainE(e) end
	resetStock()
	if produced <= 0 and totalOps > 0 then
		failReason(string.format("fluid.no_produce label=%s mach=%s ops=%d",
			tostring(label), tostring(baseMachine), totalOps))
		return false, {"Could not push inputs to " .. tostring(baseMachine)}, produced
	end
	if Craft.depth == 0 and (stageDone or 0) < (stageTotal or 0) then
		stageDone = (stageDone or 0) + 1
	end
	return true, nil, produced
end


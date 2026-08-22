-- engine.lua was a 2k line monster. split into turtle/machine/scheduler.
-- old blob is in src copy folder at repo root if something subtle broke

function _turtleCraftLoop(ctx, node, turtleCtx)
	local turtlePool     = turtleCtx.turtlePool
	local turtleSlots    = turtleCtx.turtleSlots
	local sortedStore = turtleCtx.sortedStore
	local provSrc        = turtleCtx.provSrc
	local firstStore   = turtleCtx.firstStore
	local myCleanup      = turtleCtx.myCleanup
	local assignments    = turtleCtx.assignments
	local step           = turtleCtx.step
	local totalDone      = turtleCtx.totalDone
	local totalNeed    = turtleCtx.totalNeed
	local turtleStall    = turtleCtx.turtleStall
	local helpers        = turtleCtx.helpers
	local plan, i        = turtleCtx.plan, turtleCtx.i
	local desc           = turtleCtx.desc

	-- transient dips (autostock racing, parallel jobs eating stock, first batch
	-- push tripped by slow network) shouldnt murder a 500-item craft. bounded
	-- retries with re-scan, then hard fail. lost a 3h craft to one dry batch
	local dryStreak, feasRetries = 0, 0

	while totalDone < totalNeed do
		if Craft.cancelled then
			cleanupCraftMachines(sortedStore, myCleanup)
			failReason("turtle.cancel")
			return false
		end
		helpers.drawProgress(i, #plan, desc, totalDone, totalNeed, step.item, #turtlePool)

		local active = {}
		for _, asgn in ipairs(assignments) do
			if asgn.remaining > 0 then table.insert(active, asgn) end
		end
		if #active == 0 then break end

		for _, asgn in ipairs(active) do helpers.clearGrid(asgn.name) end

		local ingNeed = {}
		for idx = 1, 9 do
			local ing = step.ingredients[idx]
			if ing and ing ~= "nil" then ingNeed[ing] = (ingNeed[ing] or 0) + 1 end
		end

		local tStock = {}
		local srcByName = {}
		for ing in pairs(ingNeed) do
			tStock[ing] = 0
			srcByName[ing] = srcByName[ing] or {}
			local alts = Groups.altsOf(ing)
			if alts then
				for _, alt in ipairs(alts) do
					tStock[alt] = tStock[alt] or 0
					srcByName[alt] = srcByName[alt] or {}
				end
			end
		end

		local tScanList = {}
		for _, s in ipairs(sortedStore) do tScanList[#tScanList + 1] = s end
		for _, s in ipairs(provSrc)        do tScanList[#tScanList + 1] = s end
		for _, stoName in ipairs(tScanList) do
			local sto = peripheral.wrap(stoName)
			if sto and sto.list and sto.pushItems then
				local okL, lst = pcall(sto.list)
				if okL and lst then
					for slot, it in pairs(lst) do
						if it and tStock[it.name] ~= nil and (it.count or 0) > 0 then
							tStock[it.name] = tStock[it.name] + it.count
							local arr = srcByName[it.name]
							arr[#arr + 1] = {sto = sto, slot = slot, count = it.count}
						end
					end
				end
			end
		end

		-- learn per-grid-slot cap for each ingredient. non-stackables (fire starter,
		-- diesel engine ing) hold 1 per slot, so batch>1 pushes 1 item, turtle crafts
		-- 1, we over-decrement remaining and finish thinking we made the rest.
		-- cache per craft (maxCount doesnt change), probe from first live source.
		maxStackCache = maxStackCache or {}
		local ingMaxStack = {}
		for name, arr in pairs(srcByName) do
			local m = maxStackCache[name]
			if not m and arr[1] then
				local okD, det = pcall(arr[1].sto.getItemDetail, arr[1].slot)
				if okD and det and det.maxCount and det.maxCount > 0 then
					m = det.maxCount
				end
			end
			if m then
				maxStackCache[name] = m
				ingMaxStack[name] = m
			end
		end

		local feasibleOps = nil
		for ing, need in pairs(ingNeed) do
			if not helpers.isTool(ing) then
				local f = math.floor(groupAvail(ing, tStock) / need)
				if feasibleOps == nil or f < feasibleOps then feasibleOps = f end
			end
		end
		feasibleOps = feasibleOps or 0

		local chosenType   = {}
		local constCap = nil
		for ing, need in pairs(ingNeed) do
			if not helpers.isTool(ing) then
				local best, bestCnt = ing, tStock[ing] or 0
				local alts = Groups.altsOf(ing)
				if alts then
					for _, alt in ipairs(alts) do
						local c = tStock[alt] or 0
						if c > bestCnt then best, bestCnt = alt, c end
					end
				end
				chosenType[ing] = best
				local cap = math.floor(bestCnt / need)
				if constCap == nil or cap < constCap then constCap = cap end
			end
		end
		constCap = constCap or 0

		if feasibleOps <= 0 then
			resetStock()
			local absTarget = (turtleCtx.baselineStore or 0) + totalNeed * (step.output_count or 1)
			if groupAvail(step.item, getInvCached()) >= absTarget then
				break
			end
			if feasRetries < 5 then
				feasRetries = feasRetries + 1
				dbgWrite(string.format("j=%d s=%d turtle.retry idx=%d item=%s reason=feasible try=%d done=%d/%d",
					Craft.jobId or 0, ctx.subId or 0, node.idx or 0,
					shortName(step.item), feasRetries, totalDone, totalNeed))
				sleepCancel(1.0)
				goto continue_iter
			end
			local itemShort = shortName(step.item)
			craftErrTitle = "! NEED"
			local remaining = totalNeed - totalDone
			local parts = {}
			for ing, perOp in pairs(ingNeed) do
				local short = perOp * remaining - groupAvail(ing, tStock)
				if short > 0 then parts[#parts + 1] = string.format("%dx %s", short, shortName(ing)) end
			end
			local lines = {"Can't make " .. itemShort}
			appendMissing(lines, parts)
			craftErrLines = lines
			cleanupCraftMachines(sortedStore, myCleanup)
			failReason("turtle.no_feasible_ops item=" .. tostring(shortName(step.item)))
			return false
		end
		feasRetries = 0

		-- do-block so locals below dont leak into ::continue_iter::
		-- (lua goto refuses to jump past locals still in scope at the label)
		do
		local toolMissing = nil
		for ing in pairs(ingNeed) do
			if helpers.isTool(ing) and (tStock[ing] or 0) < 1 then toolMissing = ing; break end
		end
		if toolMissing then
			releaseTokens(node.tokens)
			local okTool, toolErr = ensureItem(toolMissing, 1)
			while not Craft.cancelled and not ctx.failed do
				if acquireTokens(node.tokens) then break end
				sleepYield(0.2, ctx)
			end
			if Craft.cancelled or ctx.failed then
				cleanupCraftMachines(sortedStore, myCleanup)
				failReason(Craft.cancelled and "turtle.cancel_tool" or "turtle.ctx_failed_tool")
				return false
			end
			if not okTool then
				craftErrTitle = "! NEED TOOL"
				craftErrLines = toolErr or {"Can't make tool: " .. (shortName(toolMissing))}
				cleanupCraftMachines(sortedStore, myCleanup)
				failReason("turtle.tool_missing tool=" .. tostring(shortName(toolMissing)))
				return false
			end
		else

			helpers.pushDirect = function(ing, amount, turtleName, targetSlot)
				local feeds = { ing }
				local alts = Groups.altsOf(ing)
				if alts then
					for _, alt in ipairs(alts) do
						if alt ~= ing then feeds[#feeds + 1] = alt end
					end
				end
				local moved = 0
				for _, name in ipairs(feeds) do
					local srcs = srcByName[name]
					if srcs then
						for _, s in ipairs(srcs) do
							if moved >= amount then break end
							if s.count > 0 then
								local okD, det = pcall(s.sto.getItemDetail, s.slot)
								if okD and det and det.name == name and (det.count or 0) > 0 then
									local want = math.min(amount - moved, det.count)
									local okP, mv = pcall(s.sto.pushItems, turtleName, s.slot, want, targetSlot)
									if okP and mv and mv > 0 then
										moved = moved + mv
										s.count = s.count - mv
									end
								else
									s.count = 0
								end
							end
						end
					end
				end
				return moved
			end

			helpers.pushExact = function(name, amount, turtleName, targetSlot)
				local srcs = srcByName[name]
				if not srcs then return 0 end
				local moved = 0
				for _, s in ipairs(srcs) do
					if moved >= amount then break end
					if s.count > 0 then
						local okD, det = pcall(s.sto.getItemDetail, s.slot)
						if okD and det and det.name == name and (det.count or 0) > 0 then
							local want = math.min(amount - moved, det.count)
							local okP, mv = pcall(s.sto.pushItems, turtleName, s.slot, want, targetSlot)
							if okP and mv and mv > 0 then
								moved = moved + mv
								s.count = s.count - mv
							end
						else
							s.count = 0
						end
					end
				end
				return moved
			end

			local turtlePerOp = step.output_count or 1
			local outMax = helpers.lookupMax()
			local slotCap
			if outMax then
				slotCap = math.floor(outMax / math.max(1, turtlePerOp))
			else
				slotCap = math.floor(7 / math.max(1, turtlePerOp))
			end
			if slotCap < 1 then slotCap = 1 end

			local useConsistent = constCap >= 1
			local feasLeft = feasibleOps
			local round = {}
			for _, asgn in ipairs(active) do
				if feasLeft <= 0 then break end
				local batchSize = math.min(slotCap, asgn.remaining, feasLeft)
				if useConsistent and batchSize > constCap then batchSize = constCap end
				for ing in pairs(ingNeed) do
					if not helpers.isTool(ing) then
						local nm = useConsistent and (chosenType[ing] or ing) or ing
						local m = ingMaxStack[nm]
						if m and batchSize > m then batchSize = m end
					end
				end
				if batchSize > 0 and helpers.clearGrid(asgn.name) then
					asgn.curBatch = batchSize
					feasLeft = feasLeft - batchSize
					for idx = 1, 9 do
						local ing = step.ingredients[idx]
						if ing and ing ~= "nil" then
							if helpers.isTool(ing) then
								helpers.pushExact(ing, 1, asgn.name, turtleSlots[idx])
							elseif useConsistent then
								helpers.pushExact(chosenType[ing] or ing, batchSize, asgn.name, turtleSlots[idx])
							else
								helpers.pushDirect(ing, batchSize, asgn.name, turtleSlots[idx])
							end
						end
					end
					round[#round + 1] = asgn
				end
			end
			active = round

			if #active == 0 then
				turtleStall = turtleStall + 1
				if turtleStall > 30 then
					local itemShort = shortName(step.item)
					craftErrTitle = "! TURTLE GRID BLOCKED"
					craftErrLines = {
						"Can't clear turtle grid for " .. itemShort,
						"Residue stuck (item storage full?).",
						"Free up storage space and retry.",
					}
					cleanupCraftMachines(sortedStore, myCleanup)
					failReason("turtle.grid_blocked item=" .. tostring(shortName(step.item)))
					return false
				end
				sleepCancel(0.3)
			else
				turtleStall = 0
			end

			local craftResults  = {}
			local craftTasks    = {}
			local numDone = 0
			local batchTotal    = #active
			for ci, asgn in ipairs(active) do
				local tName = asgn.name
				local ri    = ci
				craftTasks[#craftTasks + 1] = function()
					local crafted = false
					local so = peripheral.wrap(firstStore)
					for _ = 1, 120 do
						sleepCancel(0.05)
						if Craft.cancelled then break end
						if so and so.pullItems then
							local s, res = pcall(so.pullItems, tName, 16, 64)
							if s and res and res > 0 then crafted = true; break end
						end
					end
					if crafted then
						if so and so.pullItems then
							for slot = 1, 15 do pcall(so.pullItems, tName, slot, 64) end
						end
					end
					craftResults[ri] = crafted
					numDone = numDone + 1
				end
			end
			-- extra cancel watcher inside waitForAll. turtle steps run for minutes
			-- and cancel tap needs to land NOW not after. ugly but works
			craftTasks[#craftTasks + 1] = function()
				while numDone < batchTotal and not Craft.cancelled do
					local t = os.startTimer(0.05)
					while true do
						local ev, a, b, c = os.pullEvent()
						if ev == "timer" and a == t then break end
						if ev == "monitor_touch" and craftCancelY
						and c == craftCancelY and b >= craftCancelX1 and b <= craftCancelX2 then
							Craft.cancelled = true
							os.cancelTimer(t)
							break
						end
					end
				end
			end
			parallel.waitForAll(table.unpack(craftTasks))

			local anyOk, lastFailName = false, nil
			for ci, asgn in ipairs(active) do
				if craftResults[ci] then
					anyOk = true
					local batch = (asgn.curBatch or 1)
					asgn.remaining = asgn.remaining - batch
					totalDone = totalDone + batch
					local produced = batch * (step.output_count or 1)
					local sto = (turtleCtx.baselineStore or 0) + totalDone * (step.output_count or 1)
					dbgPush(Craft.jobId, ctx.subId, node.idx, step.item,
						produced, totalDone * (step.output_count or 1),
						totalNeed * (step.output_count or 1), sto, 0, asgn.name)
				else
					lastFailName = asgn.name
				end
			end

			if anyOk then
				dryStreak = 0
			elseif lastFailName then
				dryStreak = dryStreak + 1
				dbgWrite(string.format("j=%d s=%d turtle.retry idx=%d item=%s reason=dry try=%d turtle=%s done=%d/%d",
					Craft.jobId or 0, ctx.subId or 0, node.idx or 0,
					shortName(step.item), dryStreak, tostring(lastFailName), totalDone, totalNeed))
				if dryStreak >= 3 then
					cleanupCraftMachines(sortedStore, myCleanup)
					failReason(string.format("turtle.batch_no_output item=%s turtle=%s done=%d/%d",
						tostring(shortName(step.item)), tostring(lastFailName), totalDone, totalNeed))
					return false
				end
				sleepCancel(1.0)
			end

			helpers.drawProgress(i, #plan, desc, totalDone, totalNeed, step.item, #turtlePool)
		end
		end
		::continue_iter::
	end
	turtleCtx.totalDone   = totalDone
	turtleCtx.turtleStall = turtleStall
	return true
end

function _buildTurtlePool(step)
	local pool = {}
	for tName, enabled in pairs(Config.turtles or {}) do
		if enabled then
			local tp = peripheral.wrap(tName)
			if tp then table.insert(pool, tName) end
		end
	end
	table.sort(pool)
	if #pool == 0 then
		if step.machine_name and step.machine_name ~= "" then
			pool = {step.machine_name}
		else
			local itemShort = shortName(step.item)
			craftErrTitle = "! NO TURTLE ASSIGNED"
			craftErrLines = {
				"No turtle available",
				"Required for: " .. itemShort,
				"Assign a turtle in NETWORK tab.",
			}
			return nil
		end
	end
	if step.tools and next(step.tools) and #pool > 1 then
		pool = { pool[1] }
	end
	return pool
end

function _execStepTurtle(step, ctx, node, state)
	local sortedStore = state.sortedStore
	local provSrc        = state.provSrc
	local firstStore   = state.firstStore
	local myCleanup      = state.myCleanup
	local helpers        = state.helpers
	local plan, i        = state.plan, state.i
	local w, h           = state.w, state.h
	local finalGoal  = state.finalGoal
	local nodeTopup      = state.nodeTopup
	local desc           = state.desc

	local turtleSlots = {1, 2, 3, 5, 6, 7, 9, 10, 11}
	local turtlePool = _buildTurtlePool(step)
	if not turtlePool then failReason("turtle.pool_missing item=" .. tostring(shortName(step.item))); return false end

	myCleanup = {}
	for _, tName in ipairs(turtlePool) do
		table.insert(myCleanup, {name = tName, pullNames = nil})
		Craft.usedMachines[tName] = true
	end

	if step.count and step.count > 0 and not Craft.cancelled then
		local ingNeed = {}
		for idx = 1, 9 do
			local ing = step.ingredients[idx]
			if ing and ing ~= "nil" then ingNeed[ing] = (ingNeed[ing] or 0) + 1 end
		end
		releaseTokens(node.tokens)
		local ingsOk, ingsErr, missIng = ensureIngs(step, ingNeed)
		if not ingsOk then
			craftErrTitle = "! NEED"
			craftErrLines = ingsErr or {"Can't make " .. shortName(step.item)}
			failReason("turtle.ing_topup_failed item=" .. tostring(shortName(missIng)))
			return false
		end
		while not Craft.cancelled and not ctx.failed do
			if acquireTokens(node.tokens) then break end
			sleepYield(0.2, ctx)
		end
		if Craft.cancelled or ctx.failed then
			failReason(Craft.cancelled and "turtle.cancel_before_run" or "turtle.ctx_failed_before_run")
			return false
		end
	end
	local storageObj = peripheral.wrap(firstStore)

	helpers.slotsDirty = function(tName)
		local tp = peripheral.wrap(tName)
		if not (tp and tp.list) then return nil end
		local ok, its = pcall(tp.list)
		if not (ok and its) then return nil end
		for _, it in pairs(its) do
			if it and (it.count or 0) > 0 then return true end
		end
		return false
	end

	helpers.clearGrid = function(tName)
		local dirty = helpers.slotsDirty(tName)
		if dirty == false then return true end
		if dirty == nil then return blindUnload(tName, sortedStore) end
		for _attempt = 1, 3 do
			for slot = 1, 16 do
				for _, stoName in ipairs(sortedStore) do
					local sto = peripheral.wrap(stoName)
					if sto and sto.pullItems then
						local okp, mv = pcall(sto.pullItems, tName, slot, 64)
						if okp and mv and mv > 0 then break end
					end
				end
			end
			if helpers.slotsDirty(tName) ~= true then return true end
		end
		return false
	end

	for _, tName in ipairs(turtlePool) do helpers.clearGrid(tName) end

	local poolSize = #turtlePool
	local base  = math.floor(step.count / poolSize)
	local extra = step.count % poolSize
	local assignments = {}
	for ai, tName in ipairs(turtlePool) do
		local cnt = base + (ai <= extra and 1 or 0)
		if cnt > 0 then
			table.insert(assignments, {name = tName, remaining = cnt})
		end
	end

	local totalDone   = 0
	local totalNeed = step.count
	local turtleStall = 0
	local outMaxStack = nil

	helpers.lookupMax = function()
		if outMaxStack then return outMaxStack end
		for _, stoName in ipairs(sortedStore) do
			local sto = peripheral.wrap(stoName)
			if sto and sto.list and sto.getItemDetail then
				local okL, lst = pcall(sto.list)
				if okL and lst then
					for slot, it in pairs(lst) do
						if it and it.name == step.item then
							local okD, det = pcall(sto.getItemDetail, slot)
							if okD and det and det.maxCount and det.maxCount > 0 then
								outMaxStack = det.maxCount
								return outMaxStack
							end
						end
					end
				end
			end
		end
		return nil
	end

	local toolSet = step.tools or {}
	helpers.isTool = function(n) return toolSet[n] and true or false end

	local turtleCtx = {
		turtlePool = turtlePool, turtleSlots = turtleSlots,
		sortedStore = sortedStore, provSrc = provSrc,
		firstStore = firstStore, myCleanup = myCleanup,
		assignments = assignments, step = step,
		totalDone = totalDone, totalNeed = totalNeed,
		turtleStall = turtleStall, helpers = helpers,
		plan = plan, i = i, desc = desc,
		baselineStore = (getInvCached()[step.item] or 0),
	}
	if not _turtleCraftLoop(ctx, node, turtleCtx) then return false end
	totalDone   = turtleCtx.totalDone
	turtleStall = turtleCtx.turtleStall

	for _, tName in ipairs(turtlePool) do helpers.clearGrid(tName) end
	state.myCleanup = myCleanup
	return true
end


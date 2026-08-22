-- part of engine split (turtle/machine/scheduler).
-- pre-split snapshot in src copy folder if you need to compare

function _tickMachineEntry(entry, tickCtx)
	if Craft.cancelled then return end
	local sortedStore = tickCtx.sortedStore
	local ingCounts      = tickCtx.ingCounts
	local step           = tickCtx.step
	local helpers        = tickCtx.helpers
	local outPerOp    = tickCtx.outPerOp
	local totalExp  = tickCtx.totalExp
	local waited         = tickCtx.waited
	local totalColl = tickCtx.totalColl
	local nodeTopup      = tickCtx.nodeTopup

	local hasLeftover = false
	local ok, mItems
	if tickCtx.scan and tickCtx.scan[entry.outName] then
		mItems = tickCtx.scan[entry.outName]; ok = true
	else
		ok, mItems = pcall(entry.outPeriph.list)
	end
	if ok and mItems then
		for slot, mItem in pairs(mItems) do
			if mItem and not entry.excluded[mItem.name] then
				local toTake = mItem.count
				local moved = 0
				for _, stoName in ipairs(packOrder(mItem.name, sortedStore)) do
					if moved >= toTake then break end
					local okP, mv = pcall(entry.outPeriph.pushItems, stoName, slot, toTake - moved)
					if okP and mv and mv > 0 then
						moved = moved + mv; packRemember(mItem.name, stoName)
					elseif okP and (not mv or mv == 0) then
						packForget(mItem.name, stoName)
					end
				end
				if moved < toTake then
					for _, stoName in ipairs(sortedStore) do
						if moved >= toTake then break end
						local sto = peripheral.wrap(stoName)
						if sto and sto.pullItems then
							local okQ, mv = pcall(sto.pullItems, entry.outName, slot, toTake - moved)
							if okQ and mv and mv > 0 then moved = moved + mv end
						end
					end
				end
				if moved > 0 then
					local gap = waited - entry.lastCollTick
					if gap > (entry.maxGap or 0) then entry.maxGap = gap end
					entry.lastCollTick  = waited
					entry.hasAny = true
					entry.collectCount     = (entry.collectCount or 0) + 1
					if mItem.name == step.item then
						entry.doneItems = entry.doneItems + moved
						totalColl  = totalColl + moved
						local sto = (tickCtx.baselineStore or 0) + totalColl
						dbgPush(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx, step.item,
							moved, totalColl, totalExp, sto, 0, entry.name)
					end
				end
				if moved < toTake then
					hasLeftover = true
					-- sto full, cant take output. log once per jam,
					-- reset when it clears so next jam gets logged too
					if mItem.name == step.item and not entry._leftoverLogged then
						dbgLeftover(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx,
							entry.name, mItem.name, toTake - moved)
						entry._leftoverLogged = true
					end
				elseif entry._leftoverLogged then
					entry._leftoverLogged = false
				end
			end
		end
	end

	local hasInput = false
	local okIn, inItems
	if tickCtx.scan and tickCtx.scan[entry.name] then
		inItems = tickCtx.scan[entry.name]; okIn = true
	else
		okIn, inItems = pcall(entry.periph.list)
	end
	if okIn and inItems then
		for _, it in pairs(inItems) do
			if it and ingCounts[it.name] then
				local preC = (entry.preSnap and entry.preSnap[it.name]) or 0
				if it.count > preC then hasInput = true; break end
			end
		end
	end

	local runnableOps
	if okIn and inItems then
		local ingTotNow = {}
		for _, it in pairs(inItems) do
			if it and ingCounts[it.name] then
				ingTotNow[it.name] = (ingTotNow[it.name] or 0) + it.count
			end
		end
		for ingName, ingPerOp in pairs(ingCounts) do
			local o = math.floor((ingTotNow[ingName] or 0) / ingPerOp)
			if runnableOps == nil or o < runnableOps then runnableOps = o end
		end
	end
	runnableOps = runnableOps or 0

	local owes = entry.doneItems < entry.pendingItems
	local idleTicks = waited - entry.lastCollTick
	local quietNeed = math.max(4, (entry.maxGap or 0) * 2 + 4)
	if owes then
		if (entry.collectCount or 0) >= 2 then
			quietNeed = math.max(20, quietNeed)
		else
			quietNeed = math.max(120, quietNeed)
		end
	end

	-- dead machine. loaded, input still sitting, nothing ever came out.
	-- one bad cutter wedged copper_bolt for 5min while twin next to it
	-- was already done. mark exhausted and move on
	if entry.remainOps == 0 and not entry.hasAny
	and hasInput and idleTicks >= 200 and not entry.exhausted then
		if not entry._exhaustLogged then
			dbgExhaust(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx, entry.name, 0)
			entry._exhaustLogged = true
		end
		entry.exhausted = true
	end

	if hasInput and runnableOps == 0 and not hasLeftover
	and idleTicks >= math.max(6, quietNeed) then
		local acc = helpers.pushBatch(entry.name, math.max(1, entry.remainOps))
		if acc > 0 then
			entry.remainOps    = math.max(0, entry.remainOps - acc)
			entry.pendingItems = entry.pendingItems + acc * outPerOp
			entry.lastCollTick = waited
			entry.starve = 0
		else
			entry.starve = (entry.starve or 0) + 1
			if entry.starve >= 6 then
				if not entry._exhaustLogged then
					dbgExhaust(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx, entry.name, entry.remainOps or 0)
					entry._exhaustLogged = true
				end
				entry.exhausted = true
			end
		end
	elseif entry.remainOps > 0 then
		if not hasInput and not hasLeftover then
			local acceptedOps = helpers.pushBatch(entry.name, entry.remainOps)
			if acceptedOps > 0 then
				entry.remainOps    = entry.remainOps - acceptedOps
				entry.pendingItems = entry.pendingItems + acceptedOps * outPerOp
				entry.lastCollTick = waited
				entry.starve = 0
				entry.exhausted = false
			elseif not owes or idleTicks >= quietNeed then
				entry.starve = (entry.starve or 0) + 1
				if entry.starve >= 6 then
				if not entry._exhaustLogged then
					dbgExhaust(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx, entry.name, entry.remainOps or 0)
					entry._exhaustLogged = true
				end
				entry.exhausted = true
			end
			end
		end
	elseif not entry.exhausted and entry.hasAny and not hasInput
	and not hasLeftover and idleTicks >= quietNeed then
		local deficit = totalExp - totalColl
		if deficit > 0 then
			local opsNeeded = math.ceil(deficit / outPerOp)
			local accepted  = helpers.pushBatch(entry.name, opsNeeded)
			if accepted > 0 then
				nodeTopup             = true
				entry.pendingItems    = entry.pendingItems + accepted * outPerOp
				entry.lastCollTick = waited
				entry.refillCount     = entry.refillCount + 1
				entry.starve          = 0
			else
				entry.starve = (entry.starve or 0) + 1
				if entry.starve >= 6 then
				if not entry._exhaustLogged then
					dbgExhaust(tickCtx.jobId, tickCtx.subId, tickCtx.nodeIdx, entry.name, entry.remainOps or 0)
					entry._exhaustLogged = true
				end
				entry.exhausted = true
			end
			end
		else
			entry.exhausted = true
		end
	end

	tickCtx.totalColl = totalColl
	tickCtx.nodeTopup      = nodeTopup
end

function _flushMachines(flushCtx)
	local machineData    = flushCtx.machineData
	local sortedStore = flushCtx.sortedStore
	local ingCounts      = flushCtx.ingCounts
	local step           = flushCtx.step
	local helpers        = flushCtx.helpers
	local outPerOp    = flushCtx.outPerOp
	local totalExp  = flushCtx.totalExp
	local waited         = flushCtx.waited
	local totalColl = flushCtx.totalColl
	local continueOuter  = flushCtx.continueOuter

	local flushSilence    = 0
	local flushMaxSilence = 2
	repeat
		if Craft.cancelled then break end
		local hadOutput = false
		for _, entry in ipairs(machineData) do
			if Craft.cancelled then break end
			local sp = entry.outPeriph
			if sp and sp.list and sp.pushItems then
				local sok, curItems = pcall(sp.list)
				if sok and curItems then
					local flushLeftover = false
					for slot, curItem in pairs(curItems) do
						if curItem and not ingCounts[curItem.name] then
							local preCount = (entry.preSnap and entry.preSnap[curItem.name]) or 0
							local toPull   = curItem.count - preCount
							if toPull > 0 then
								local pulled = 0
								for _, stoName in ipairs(packOrder(curItem.name, sortedStore)) do
									if pulled >= toPull then break end
									local sm, mm = pcall(sp.pushItems, stoName, slot, toPull - pulled)
									if sm and mm and mm > 0 then
										pulled = pulled + mm; packRemember(curItem.name, stoName)
									elseif sm and (not mm or mm == 0) then
										packForget(curItem.name, stoName)
									end
								end
								if pulled > 0 then
									hadOutput = true
									if curItem.name == step.item then
										entry.doneItems = entry.doneItems + pulled
										totalColl  = totalColl  + pulled
										local sto = (flushCtx.baselineStore or 0) + totalColl
										dbgPush(flushCtx.jobId, flushCtx.subId, flushCtx.nodeIdx, step.item,
											pulled, totalColl, totalExp, sto, 0, entry.name)
									end
								end
								if pulled < toPull then flushLeftover = true end
							end
						end
					end
					entry._flushLeftover = flushLeftover
				end
			end

			helpers.drawProgress(flushCtx.i or 0, flushCtx.plan and #flushCtx.plan or 0, flushCtx.desc or "", totalColl, totalExp, step.item, #machineData)
			if entry.remainOps > 0 and not entry._flushLeftover
			and totalColl < totalExp then
				local nextOps     = entry.remainOps
				local acceptedOps = helpers.pushBatch(entry.name, nextOps)
				if acceptedOps > 0 then
					entry.remainOps        = nextOps - acceptedOps
					entry.pendingItems     = entry.pendingItems + acceptedOps * outPerOp
					entry.exhausted        = false
					entry.hasAny = false
					entry.lastCollTick  = waited
					continueOuter = true
				end
			end
		end
		local flushNeed = flushMaxSilence

		-- how many empty ticks before we call it done.
		-- 120 (~60s) first time, 20 after we saw output at least once.
		-- maxGap*2+4 for slow ones
		if totalColl < totalExp then
			for _, entry in ipairs(machineData) do
				if entry.doneItems < entry.pendingItems then
					local floorQ = ((entry.collectCount or 0) >= 2) and 20 or 120
					local q = math.max(floorQ, (entry.maxGap or 0) * 2 + 4)
					if q > flushNeed then flushNeed = q end
				end
			end
		end
		if hadOutput then
			flushSilence = 0
		else
			flushSilence = flushSilence + 1
		end
		if flushSilence < flushNeed and not Craft.cancelled then
			sleepCancel(0.5)
		end
	until flushSilence >= flushNeed or Craft.cancelled

	flushCtx.totalColl = totalColl
	flushCtx.continueOuter  = continueOuter
end

function _machineCraftLoop(step, ctx, node, machCtx)
	local activePool     = machCtx.activePool
	local splitOutName   = machCtx.splitOutName
	local splitOutPer = machCtx.splitOutPer
	local myCleanup      = machCtx.myCleanup
	local sortedStore = machCtx.sortedStore
	local ingCounts      = machCtx.ingCounts
	local totalOps       = machCtx.totalOps
	local outPerOp    = machCtx.outPerOp
	local totalExp  = machCtx.totalExp
	local poolSize       = machCtx.poolSize
	local base           = machCtx.base
	local extra          = machCtx.extra
	local helpers        = machCtx.helpers
	local plan, i        = machCtx.plan, machCtx.i
	local desc           = machCtx.desc
	local nodeTopup      = machCtx.nodeTopup
	local machineData    = machCtx.machineData

	local totalColl = 0
	local maxWait = math.max(600, math.min(3600, totalOps * 12))
	local waited  = 0
	local continueOuter = true
	local absTarget = (machCtx.baselineStore or 0) + totalExp

	while continueOuter do
		continueOuter = false
		for _, e in ipairs(machineData) do e.exhausted = false end
		while totalColl < totalExp and waited < maxWait do
			if groupAvail(step.item, getInvCached()) >= absTarget then break end
			sleepCancel(0.5)
			if Craft.cancelled then
				cleanupCraftMachines(sortedStore, myCleanup)
				failReason("machine.cancel_loop")
				return false
			end
			waited = waited + 1
			helpers.drawProgress(i, #plan, desc, totalColl, totalExp, step.item, #machineData)

			-- one batched list() per tick for all input+output periphs in the pool.
			-- 3-depot pool used to do 6 sequential peripheral calls, 2-3s on laggy
			-- server. scanPeriph runs them in parallel = one yield not six
			local scan = nil
			if #machineData > 1 then
				local names, seen = {}, {}
				for _, e in ipairs(machineData) do
					if not seen[e.name] then seen[e.name] = true; names[#names+1] = e.name end
					if e.outName and not seen[e.outName] then
						seen[e.outName] = true; names[#names+1] = e.outName
					end
				end
				local raw = scanPeriph(names, "list")
				scan = {}
				for n, rec in pairs(raw) do
					if rec and rec.data then scan[n] = rec.data end
				end
			end

			local tickCtx = {
				sortedStore = sortedStore, ingCounts = ingCounts,
				step = step, helpers = helpers, outPerOp = outPerOp, totalExp = totalExp,
				waited = waited, totalColl = totalColl, nodeTopup = nodeTopup,
				myCleanup = myCleanup, scan = scan,
				jobId = machCtx.jobId, subId = machCtx.subId, nodeIdx = machCtx.nodeIdx,
				baselineStore = machCtx.baselineStore,
			}
			for _, entry in ipairs(machineData) do
				if Craft.cancelled then break end
				_tickMachineEntry(entry, tickCtx)
			end
			totalColl = tickCtx.totalColl
			nodeTopup      = tickCtx.nodeTopup

			helpers.drawProgress(i, #plan, desc, totalColl, totalExp, step.item, #machineData)
			local allExhausted = true
			for _, entry in ipairs(machineData) do
				if not entry.exhausted then allExhausted = false; break end
			end
			if allExhausted then break end
		end

		local flushCtx = {
			machineData = machineData, sortedStore = sortedStore,
			ingCounts = ingCounts, step = step, helpers = helpers,
			outPerOp = outPerOp, totalExp = totalExp,
			waited = waited, totalColl = totalColl,
			continueOuter = continueOuter,
			i = i, plan = plan, desc = desc,
			jobId = machCtx.jobId, subId = machCtx.subId, nodeIdx = machCtx.nodeIdx,
			baselineStore = machCtx.baselineStore,
		}
		_flushMachines(flushCtx)
		totalColl = flushCtx.totalColl
		continueOuter  = flushCtx.continueOuter
	end

	if not Craft.cancelled then
		cleanupCraftMachines(sortedStore, myCleanup)
		resetStock()
	end
	if totalColl == 0 then
		resetStock()
		failReason(string.format("machine.zero_output item=%s pool=%d waited=%d/%d",
			tostring(shortName(step.item)), #machineData, waited, maxWait))
		return false
	end
	if totalColl < totalExp then
		resetStock()
		if groupAvail(step.item, getInvCached()) >= absTarget then
			machCtx.nodeTopup = nodeTopup
			return true
		end
		failReason(string.format("machine.partial_output item=%s got=%d/%d",
			tostring(shortName(step.item)), totalColl, totalExp))
		return false
	end
	machCtx.nodeTopup = nodeTopup
	return true
end

function _preUnloadMachines(preunloadCtx)
	local activePool     = preunloadCtx.activePool
	local splitOutName   = preunloadCtx.splitOutName
	local sortedStore = preunloadCtx.sortedStore
	local step           = preunloadCtx.step
	local totalOps       = preunloadCtx.totalOps
	local poolSize       = preunloadCtx.poolSize
	local base           = preunloadCtx.base
	local extra          = preunloadCtx.extra

	local preUnload = {}
	local inList = {}
	for _, mName in ipairs(activePool) do table.insert(preUnload, mName); inList[mName] = true end
	if splitOutName then table.insert(preUnload, splitOutName); inList[splitOutName] = true end

	local dirtyDrop = {}
	for _, mName in ipairs(preUnload) do
		if Craft.cancelled then break end
		local mPeriph = peripheral.wrap(mName)
		local drained = {}
		if mPeriph and mPeriph.list then
			for _pass = 1, 3 do
				local sPre, preItems = pcall(mPeriph.list)
				if not (sPre and preItems) then break end
				local anyPre = false
				for slotPre, itemPre in pairs(preItems) do
					if itemPre and itemPre.name and itemPre.count and itemPre.count > 0 then
						anyPre = true
						local leftPre = itemPre.count
						local startedWith = leftPre
						if mPeriph.pushItems then
							for _, stoName in ipairs(packOrder(itemPre.name, sortedStore)) do
								if leftPre <= 0 then break end
								local okP, mvP = pcall(mPeriph.pushItems, stoName, slotPre, leftPre)
								if okP and mvP and mvP > 0 then
									leftPre = leftPre - mvP; packRemember(itemPre.name, stoName)
								elseif okP and (not mvP or mvP == 0) then
									packForget(itemPre.name, stoName)
								end
							end
						end
						if leftPre > 0 then
							for _, stoName in ipairs(packOrder(itemPre.name, sortedStore)) do
								if leftPre <= 0 then break end
								local sto = peripheral.wrap(stoName)
								if sto and sto.pullItems then
									local okQ, mvQ = pcall(sto.pullItems, mName, slotPre, leftPre)
									if okQ and mvQ and mvQ > 0 then
										leftPre = leftPre - mvQ; packRemember(itemPre.name, stoName)
									elseif okQ and (not mvQ or mvQ == 0) then
										packForget(itemPre.name, stoName)
									end
								end
							end
						end
						local moved = startedWith - leftPre
						if moved > 0 then
							drained[itemPre.name] = (drained[itemPre.name] or 0) + moved
						end
					end
				end
				if not anyPre then break end
				sleepCancel(0.2)
			end
			local sChk, chkItems = pcall(mPeriph.list)
			if sChk and chkItems then
				for _, ci in pairs(chkItems) do
					if ci and ci.name == step.item and (ci.count or 0) > 0 then
						dirtyDrop[mName] = true
					end
				end
			end
			if next(drained) or dirtyDrop[mName] then
				dbgPreunload(preunloadCtx.jobId, preunloadCtx.subId, preunloadCtx.nodeIdx,
					mName, drained, dirtyDrop[mName])
			end
		end
		if mPeriph and mPeriph.tanks then
			local okT, tl = pcall(mPeriph.tanks)
			if okT and tl then
				for _, tk in pairs(tl) do
					if tk and tk.name and tk.amount and tk.amount > 0 then
						drainFluid(mName, tk.name, tk.amount)
					end
				end
			end
		end
	end

	if next(dirtyDrop) and not splitOutName then
		local dropped = {}
		for mName in pairs(dirtyDrop) do dropped[#dropped + 1] = mName end
		local np = {}
		for _, mName in ipairs(activePool) do
			if not dirtyDrop[mName] then np[#np + 1] = mName end
		end
		if #np > 0 then
			dbgPool(preunloadCtx.jobId, preunloadCtx.subId, preunloadCtx.nodeIdx, "shrink",
				string.format("item=%s from=%d to=%d dropped=%s reason=dirty_output",
					tostring(shortName(step.item)), #activePool, #np, table.concat(dropped, ",")))
			activePool = np
			poolSize = #activePool
			base  = math.floor(totalOps / poolSize)
			extra = totalOps % poolSize
		end
	end

	preunloadCtx.activePool = activePool
	preunloadCtx.poolSize   = poolSize
	preunloadCtx.base       = base
	preunloadCtx.extra      = extra
end

function _pushBatch(mName, opsCount, ing)
	if Craft.cancelled then return 0 end
	local counts, maxStack = ing.counts, ing.maxStack
	local slot             = ing.slot
	local srcStore      = ing.srcStore
	local srcProviders     = ing.srcProviders

	local machHas = {}
	do
		local pm = peripheral.wrap(mName)
		if pm and pm.list then
			local okM, its = pcall(pm.list)
			if okM and its then
				for _, it in pairs(its) do
					if it and counts[it.name] then
						machHas[it.name] = (machHas[it.name] or 0) + (it.count or 0)
					end
				end
			end
		end
	end

	for ingName, ingPerOp in pairs(counts) do
		local maxS = maxStack[ingName] or 64
		local curOps = math.floor((machHas[ingName] or 0) / ingPerOp)
		local addable
		if maxS >= ingPerOp then
			addable = math.floor(maxS / ingPerOp) - curOps
		else
			addable = (curOps > 0) and 0 or 1
		end
		if addable < opsCount then opsCount = addable end
	end

	local invCached = getInvCached()
	local stockCnt = {}
	for ingName in pairs(counts) do
		stockCnt[ingName] = invCached[ingName] or 0
		local alts = Groups.altsOf(ingName)
		if alts then for _, alt in ipairs(alts) do stockCnt[alt] = invCached[alt] or 0 end end
	end
	for ingName, ingPerOp in pairs(counts) do
		local feasOps = math.floor(groupAvail(ingName, stockCnt) / ingPerOp)
		if feasOps < opsCount then opsCount = feasOps end
	end
	if opsCount <= 0 then return 0 end

	local accepted = opsCount
	for ingName, ingPerOp in pairs(counts) do
		local have   = machHas[ingName] or 0
		local curOps = math.floor(have / ingPerOp)
		local needed = (curOps + opsCount) * ingPerOp - have
		local moved  = 0
		if needed > 0 then
			if ingPerOp <= (maxStack[ingName] or 64) then
				moved = pushFromStore(ingName, needed, mName, slot[ingName], ing.prescan)
			end
			if moved < needed then
				moved = moved + pushFromStore(ingName, needed - moved, mName, nil, ing.prescan)
			end
		end
		local newOps = math.floor((have + moved) / ingPerOp) - curOps
		if newOps < accepted then accepted = newOps end
	end
	return accepted
end

function _resolveActivePool(step)
	local activePool = {}
	for _, mName in ipairs(getMachPool(step.machine_name)) do
		local p = peripheral.wrap(mName)
		if p and p.list and p.pushItems then
			table.insert(activePool, mName)
		end
	end
	local splitOutName, splitOutPer = nil, nil
	if step.output_device and step.output_device ~= "" then
		splitOutName   = step.output_device
		splitOutPer = peripheral.wrap(splitOutName)
		if not (splitOutPer and splitOutPer.list) then
			craftErrTitle = "! MACHINE NOT FOUND"
			craftErrLines = {
				"Output device not found: " .. getMachName(splitOutName),
				"Required for: " .. (shortName(step.item)),
				"Reconnect device or re-learn recipe.",
			}
			craftErrEdit = { [2] = step.item }
			return nil
		end
		activePool = {}
		local pIn = peripheral.wrap(step.machine_name)
		if pIn and pIn.list and pIn.pushItems then
			activePool = {step.machine_name}
		end
	end
	if #activePool == 0 then
		local mDisplay = getMachName and getMachName(step.machine_name or "?") or (step.machine_name or "?")
		local itemShort = shortName(step.item)
		craftErrTitle = "! MACHINE NOT FOUND"
		craftErrLines = {
			"Machine not found: " .. mDisplay,
			"Required for: " .. itemShort,
			"Use [E] in RECIPES to reassign machine.",
		}
		craftErrEdit = { [2] = step.item }
		return nil
	end
	return activePool, splitOutName, splitOutPer
end

function _tallyIngredients(step)
	local counts, slot = {}, {}
	local slotN = 0
	for i = 1, #step.ingredients do
		local ing = step.ingredients[i]
		if ing and ing ~= "nil" then
			counts[ing] = (counts[ing] or 0) + 1
			if not slot[ing] then
				slotN = slotN + 1
				slot[ing] = slotN
			end
		end
	end
	return counts, slot
end

-- maxCount for an item never changes, so cache it for whole craft.
-- packIndex tells us WHICH chest holds each item, so we probe one chest
-- instead of scanning all. old path did sequential list() over every
-- storage on every node -- 200 chests * ~100ms = 20s of dead air per node.
function _scanMaxStacks(counts, storages)
	maxStackCache = maxStackCache or {}
	local out = {}
	local misses = {}
	for ingName in pairs(counts) do
		local c = maxStackCache[ingName]
		if c then out[ingName] = c else misses[#misses + 1] = ingName end
	end
	if #misses == 0 then return out end
	local function probe(stoName, ingName)
		local sto = peripheral.wrap(stoName)
		if not (sto and sto.list and sto.getItemDetail) then return nil end
		local okL, lst = pcall(sto.list)
		if not (okL and lst) then return nil end
		for slotI, itemI in pairs(lst) do
			if itemI and itemI.name == ingName then
				local okD, det = pcall(sto.getItemDetail, slotI)
				if okD and det and det.maxCount and det.maxCount > 0 then
					return det.maxCount
				end
				return 64
			end
		end
		return nil
	end
	for _, ingName in ipairs(misses) do
		local maxS
		local hinted = craftPackIndex and craftPackIndex[ingName]
		if hinted then
			for stoName in pairs(hinted) do
				maxS = probe(stoName, ingName)
				if maxS then break end
			end
		end
		if not maxS then
			for _, stoName in ipairs(storages) do
				if not (hinted and hinted[stoName]) then
					maxS = probe(stoName, ingName)
					if maxS then break end
				end
			end
		end
		maxS = maxS or 64
		out[ingName] = maxS
		maxStackCache[ingName] = maxS
	end
	return out
end

function _execStepMachine(step, ctx, node, state)
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

	local activePool, splitOutName, splitOutPer = _resolveActivePool(step)
	if not activePool then failReason("machine.pool_missing item=" .. tostring(shortName(step.item))); return false end
	local ingCounts, ingSlot = _tallyIngredients(step)

	local phaseT = {}
	local tPhaseStart = os.clock()
	if step.count and step.count > 0 and not Craft.cancelled then
		releaseTokens(node.tokens)
		local tEnsure = os.clock()
		local ingsOk, ingsErr, missIng = ensureIngs(step, ingCounts)
		phaseT.ensure = os.clock() - tEnsure
		if not ingsOk then
			craftErrTitle = "! NEED"
			craftErrLines = ingsErr or {"Can't make " .. shortName(step.item)}
			failReason("machine.ing_topup_failed item=" .. tostring(shortName(missIng)))
			return false
		end
		local tTokens = os.clock()
		local waitedFirstFail = false
		while not Craft.cancelled and not ctx.failed do
			if acquireTokens(node.tokens) then break end
			if not waitedFirstFail then
				dbgTokens(Craft.jobId, ctx.subId, node.idx, "wait", node.tokens, 0)
				waitedFirstFail = true
			end
			sleepYield(0.2, ctx)
		end
		phaseT.tokens = os.clock() - tTokens
		if waitedFirstFail and not Craft.cancelled and not ctx.failed then
			dbgTokens(Craft.jobId, ctx.subId, node.idx, "grab", node.tokens, phaseT.tokens)
		end
		if Craft.cancelled or ctx.failed then
			failReason(Craft.cancelled and "machine.cancel_before_run" or "machine.ctx_failed_before_run")
			return false
		end
	end

	local ingPullNames = {}
	for ingName in pairs(ingCounts) do ingPullNames[ingName] = true end
	ingPullNames[step.item] = true

	myCleanup = {}
	for _, mName in ipairs(activePool) do
		table.insert(myCleanup, {name = mName, pullNames = ingPullNames})
	end
	if splitOutName then
		table.insert(myCleanup, {name = splitOutName, pullNames = ingPullNames})
	end
	for _, mNameU in ipairs(activePool) do Craft.usedMachines[mNameU] = true end
	if splitOutName then Craft.usedMachines[splitOutName] = true end

	local totalOps      = step.count
	local outPerOp   = step.output_count or 1
	local totalExp = totalOps * outPerOp
	local poolSize      = #activePool

	do
		local invSnap = getInvCached()
		local maxTotal = totalOps
		for ingName, ingPerOp in pairs(ingCounts) do
			local available = groupAvail(ingName, invSnap)
			local ingCap = math.floor(available / ingPerOp)
			if ingCap < maxTotal then maxTotal = ingCap end
		end
		if maxTotal < totalOps then totalOps = math.max(0, maxTotal) end
	end
	local base  = math.floor(totalOps / poolSize)
	local extra = totalOps % poolSize
	do
		local opsPer = {}
		for bIdx = 1, poolSize do
			opsPer[bIdx] = tostring(base + ((bIdx <= extra) and 1 or 0))
		end
		dbgPool(Craft.jobId, ctx.subId, node.idx, "assign",
			string.format("item=%s pool=%s ops=%s split=%s",
				tostring(shortName(step.item)), table.concat(activePool, ","),
				table.concat(opsPer, ","), tostring(splitOutName or "-")))
	end
	helpers.drawProgress(i, #plan, desc, 0, totalExp, step.item, #activePool)
	local ingMaxStack = _scanMaxStacks(ingCounts, sortedStore)

	local ingCtx = {
		counts       = ingCounts,
		maxStack     = ingMaxStack,
		slot         = ingSlot,
		srcStore  = sortedStore,
		srcProviders = provSrc,
	}
	helpers.pushBatch = function(mName, opsCount)
		local accepted = _pushBatch(mName, opsCount, ingCtx)
		if accepted < opsCount then
			local shorts = {}
			local invSnap = getInvCached()
			for ingName in pairs(ingCounts) do
				local avail = groupAvail(ingName, invSnap)
				shorts[#shorts+1] = string.format("%s=%d", tostring(shortName(ingName)), avail)
			end
			dbgLoad(Craft.jobId, ctx.subId, node.idx, mName, opsCount, accepted,
				"stock=" .. table.concat(shorts, ","))
		else
			dbgLoad(Craft.jobId, ctx.subId, node.idx, mName, opsCount, accepted)
		end
		return accepted
	end

	local preunloadCtx = {
		activePool = activePool, splitOutName = splitOutName,
		sortedStore = sortedStore, step = step,
		totalOps = totalOps, poolSize = poolSize, base = base, extra = extra,
		jobId = Craft.jobId, subId = ctx.subId, nodeIdx = node.idx,
	}
	local tPre = os.clock()
	_preUnloadMachines(preunloadCtx)
	phaseT.preunload = os.clock() - tPre
	activePool = preunloadCtx.activePool
	poolSize   = preunloadCtx.poolSize
	base       = preunloadCtx.base
	extra      = preunloadCtx.extra

	local machineData = {}
	local snapNames = {}
	local snapSeen = {}
	for bIdx = 1, poolSize do
		local mName = activePool[bIdx]
		local cName = splitOutName or mName
		if not snapSeen[cName] then snapSeen[cName] = true; snapNames[#snapNames + 1] = cName end
	end
	local tScan = os.clock()
	local preSnaps = scanPeriph(snapNames, "list")
	phaseT.scan = os.clock() - tScan

	local setupTasks = {}
	for bIdx = 1, poolSize do
		local assignedOps = base + (bIdx <= extra and 1 or 0)
		if assignedOps > 0 then
			local mName = activePool[bIdx]
			setupTasks[#setupTasks + 1] = function()
				local mPeriph = peripheral.wrap(mName)
				if not mPeriph then return end
				local collectPeriph = splitOutPer or mPeriph
				local collectName   = splitOutName   or mName
				local excluded = {}
				local preSnap  = {}
				local snap = preSnaps[collectName]
				if snap and snap.data then
					for _, si in pairs(snap.data) do
						if si and si.name ~= step.item then
							excluded[si.name] = true
							preSnap[si.name] = (preSnap[si.name] or 0) + si.count
						end
					end
				end
				for ingName in pairs(ingCounts) do excluded[ingName] = true end
				local acceptedOps = helpers.pushBatch(mName, assignedOps)
				machineData[#machineData + 1] = {
					periph            = mPeriph,
					outPeriph         = collectPeriph,
					name              = mName,
					outName           = collectName,
					excluded          = excluded,
					preSnap           = preSnap,
					remainOps         = assignedOps - acceptedOps,
					pendingItems      = acceptedOps * outPerOp,
					doneItems         = 0,
					lastCollTick   = 0,
					exhausted         = false,
					hasAny  = false,
					collectCount      = 0,
					refillCount       = 0,
				}
			end
		end
	end
	-- one shared sto scan for whole pool setup instead of each depot
	-- scanning all vaults on its own. verifiedPush rereads every slot before
	-- pushing anyway, so if sibling grabbed the stack we just skip that entry.
	-- shaves 12-27s off a 3-machine pool startup
	local tSetup = os.clock()
	if #setupTasks > 1 then
		ingCtx.prescan = scanPeriph(scanStorage(), "list")
	end
	if #setupTasks > 0 then parallel.waitForAll(table.unpack(setupTasks)) end
	ingCtx.prescan = nil
	phaseT.setup = os.clock() - tSetup
	dbgPhase(Craft.jobId, ctx.subId, node.idx, step.item, phaseT)

	local baselineStore = (getInvCached()[step.item] or 0)
	local machCtx = {
		activePool = activePool, splitOutName = splitOutName, splitOutPer = splitOutPer,
		myCleanup = myCleanup, sortedStore = sortedStore,
		ingCounts = ingCounts, machineData = nil,
		totalOps = totalOps, outPerOp = outPerOp, totalExp = totalExp,
		poolSize = poolSize, base = base, extra = extra,
		helpers = helpers, plan = plan, i = i, desc = desc, step = step,
		nodeTopup = nodeTopup,
		jobId = Craft.jobId, subId = ctx.subId, nodeIdx = node.idx,
		baselineStore = baselineStore,
	}
	machCtx.machineData = machineData
	if not _machineCraftLoop(step, ctx, node, machCtx) then return false end
	nodeTopup = machCtx.nodeTopup

	state.myCleanup = myCleanup
	state.nodeTopup = nodeTopup
	return true
end


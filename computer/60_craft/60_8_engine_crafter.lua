-- create mechanical crafter step. one op per cycle: crafters hold 1 item each.
-- cycle = lock, drain out, verify grid empty + stock covers EVERY cell, load,
-- unlock + pulse, wait for the result in the output inv, drain it to vaults.
-- stock is checked before the first push bcz a half-loaded grid cant be
-- unloaded by the computer (insert-only inventory).

local function crafterFail(title, lines, reason)
	craftErrTitle = title
	craftErrLines = lines
	failReason(reason)
	pcall(crafterSetLock, true)
	return false
end

-- pick a real item per cell (exact first, then item-group alts) from one scan.
-- nil + short list when stock cant cover the whole grid
local function crafterAlloc(ings, scanNames)
	local prescan = scanPeriph(scanNames, "list")
	local avail = {}
	for _, n in ipairs(scanNames) do
		local e = prescan[n]
		if e and e.data then
			for _, it in pairs(e.data) do
				if it then avail[it.name] = (avail[it.name] or 0) + (it.count or 0) end
			end
		end
	end
	local pick, short = {}, {}
	for idx, ing in ipairs(ings) do
		if ing ~= "nil" then
			local cands = { ing }
			for _, a in ipairs(Groups.altsOf(ing) or {}) do
				if a ~= ing then cands[#cands + 1] = a end
			end
			for _, c in ipairs(cands) do
				if (avail[c] or 0) > 0 then
					avail[c] = avail[c] - 1
					pick[idx] = c
					break
				end
			end
			if not pick[idx] then short[ing] = (short[ing] or 0) + 1 end
		end
	end
	if next(short) then return nil, short end
	return pick, prescan
end

-- waits for the product. stable = same listing twice in a row
local function crafterAwaitOut(want, target)
	local t, prevSig, stable = 0, nil, 0
	while t < CRAFTER_TIMEOUT do
		sleepCancel(0.5)
		t = t + 0.5
		if Craft.cancelled then return false end
		local sig, have = {}, 0
		for _, it in pairs(crafterOutList()) do
			if it then
				sig[#sig + 1] = it.name .. "=" .. (it.count or 0)
				if it.name == target then have = have + (it.count or 0) end
			end
		end
		table.sort(sig)
		local s = table.concat(sig, ",")
		if s == prevSig then stable = stable + 1 else stable = 0 end
		prevSig = s
		if have >= want and stable >= 1 then return true end
	end
	return false
end

function _execStepCrafter(step, ctx, node, state)
	local sortedStore = state.sortedStore
	local helpers     = state.helpers
	local plan, i     = state.plan, state.i
	local desc        = state.desc
	local ings  = step.ingredients or {}
	local cells = step.grid_cells or {}
	local itemShort = shortName(step.item)
	state.myCleanup = {}

	if #ings == 0 or #ings ~= #cells then
		return crafterFail("! CRAFTER RECIPE BROKEN", {
			"Recipe for " .. itemShort .. " has no cell map.",
			"Re-learn it in +RECIPES > CRAFTER.",
		}, "crafter.bad_recipe item=" .. tostring(itemShort))
	end
	local okR, why = crafterReady(cells)
	if not okR then
		return crafterFail("! CRAFTER NOT READY", {
			"Required for: " .. itemShort, tostring(why),
			"Check grid/relay/output in +RECIPES > CRAFTER.",
		}, "crafter.not_ready " .. tostring(why))
	end
	local c = crafterCfg()
	Craft.usedMachines[c.out] = true

	local ingNeed = {}
	for _, ing in ipairs(ings) do
		if ing ~= "nil" then ingNeed[ing] = (ingNeed[ing] or 0) + 1 end
	end
	releaseTokens(node.tokens)
	local okI, errI, missIng = ensureIngs(step, ingNeed)
	if not okI then
		craftErrTitle = "! NEED"
		craftErrLines = errI or {"Can't make " .. itemShort}
		failReason("crafter.ing_topup_failed item=" .. tostring(shortName(missIng)))
		return false
	end
	while not Craft.cancelled and not ctx.failed do
		if acquireTokens(node.tokens) then break end
		sleepYield(0.2, ctx)
	end
	if Craft.cancelled or ctx.failed then
		failReason(Craft.cancelled and "crafter.cancel_before_run" or "crafter.ctx_failed_before_run")
		return false
	end

	local perOp     = step.output_count or 1
	local totalNeed = step.count or 0
	local totalDone = 0
	local dry = 0
	local scanNames = scanStorage()

	while totalDone < totalNeed do
		if Craft.cancelled then failReason("crafter.cancel"); pcall(crafterSetLock, true); return false end
		helpers.drawProgress(i, #plan, desc, totalDone, totalNeed, step.item, 1)

		local okL, lockErr = crafterSetLock(true)
		if not okL then
			return crafterFail("! CRAFTER CLUTCH", {tostring(lockErr)}, "crafter.lock " .. tostring(lockErr))
		end
		-- residue from a late craft / cancel belongs in the vaults, not in the count
		crafterDrainOut(sortedStore)

		local cur, rErr = crafterReadCells()
		if not cur then
			return crafterFail("! CRAFTER GRID", {tostring(rErr)}, "crafter.read " .. tostring(rErr))
		end
		local dirty = {}
		for idx, v in ipairs(cur) do
			if v ~= "nil" then dirty[#dirty + 1] = shortName(v) .. "@" .. idx end
		end
		if #dirty > 0 then
			return crafterFail("! CRAFTER GRID NOT EMPTY", {
				"Crafters still hold items and the",
				"computer can't pull them out:",
				table.concat(dirty, ", "):sub(1, 60),
				"Empty them by hand and retry.",
			}, "crafter.grid_dirty n=" .. #dirty)
		end

		local pick, extra = crafterAlloc(ings, scanNames)
		if not pick then
			local parts = {}
			for ing, n in pairs(extra) do
				bridgeStage(ing, n * (totalNeed - totalDone))
				parts[#parts + 1] = string.format("%dx %s", n, shortName(ing))
			end
			dry = dry + 1
			if dry >= 3 then
				local lines = {"Can't load grid for " .. itemShort}
				appendMissing(lines, parts)
				return crafterFail("! NEED", lines, "crafter.no_stock item=" .. tostring(itemShort))
			end
			resetStock()
			sleepCancel(1.0)
		else
			local loaded = {}
			for idx = 1, #c.cells do loaded[idx] = "nil" end
			-- pick is sparse (empty cells skipped), so walk by cell index
			for k = 1, #ings do
				local ing = pick[k]
				local cell = cells[k]
				if ing then
					local mv = pushFromStore(ing, 1, cell, 1, extra)
					if (mv or 0) < 1 then
						-- one more try on a fresh scan, slot may have shifted under us
						mv = pushFromStore(ing, 1, cell, 1)
					end
					if (mv or 0) < 1 then
						return crafterFail("! CRAFTER LOAD FAILED", {
							"Couldn't insert " .. shortName(ing),
							"into " .. getMachName(cell) .. " (covered/busy?).",
							"Grid is part-loaded and LOCKED.",
							"Empty it by hand before retrying.",
						}, "crafter.load_failed cell=" .. tostring(cell))
					end
					loaded[crafterCellIdx(cell)] = ing
				end
			end
			dbgLoad(Craft.jobId, ctx.subId, node.idx, CRAFTER_MACHINE, 0, 0, "grid")

			local started, sErr = crafterStart(loaded)
			if Craft.cancelled then failReason("crafter.cancel"); return false end
			if not started then
				local lines = {"Grid loaded for " .. itemShort .. " but it never began."}
				if sErr then
					lines[#lines + 1] = tostring(sErr)
				else
					lines[#lines + 1] = "Empty cells need a PULSE relay or slot covers."
				end
				lines[#lines + 1] = "Items are still in the crafters."
				return crafterFail("! CRAFTER DIDN'T START", lines, "crafter.no_start item=" .. tostring(itemShort))
			end

			if not crafterAwaitOut(perOp, step.item) then
				if Craft.cancelled then failReason("crafter.cancel"); return false end
				local got = crafterDrainOut(sortedStore)
				local lines = {
					"No " .. itemShort .. " after " .. CRAFTER_TIMEOUT .. "s.",
					"Wrong recipe/layout: create drops the",
					"items at the crafters. Check the floor.",
				}
				if next(got) then lines[#lines + 1] = "Got something else instead (in vaults)." end
				return crafterFail("! CRAFTER NO OUTPUT", lines, "crafter.no_output item=" .. tostring(itemShort))
			end

			local got = crafterDrainOut(sortedStore)
			local made = got[step.item] or 0
			local ops = math.max(1, math.floor(made / perOp))
			if ops > totalNeed - totalDone then ops = totalNeed - totalDone end
			totalDone = totalDone + ops
			dry = 0
			dbgPush(Craft.jobId, ctx.subId, node.idx, step.item, made,
				totalDone * perOp, totalNeed * perOp, 0, 0, CRAFTER_MACHINE)
		end
	end
	-- park locked so whatever the next thing is (player, other craft) starts clean
	pcall(crafterSetLock, true)
	helpers.drawProgress(i, #plan, desc, totalDone, totalNeed, step.item, 1)
	return true
end

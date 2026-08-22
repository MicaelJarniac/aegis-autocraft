function timedRead(timeout, initial)
	local buf = initial or ""
	if buf ~= "" then term.write(buf) end
	local timer = os.startTimer(timeout)
	while true do
		local ev, a = os.pullEvent()
		if ev == "char" then
			if timer then os.cancelTimer(timer); timer = nil end
			buf = buf .. a
			term.write(a)
		elseif ev == "key" then
			if a == keys.enter or a == keys.numPadEnter then
				if timer then os.cancelTimer(timer) end
				return buf
			elseif a == keys.backspace and #buf > 0 then
				buf = buf:sub(1, -2)
				local cx, cy = term.getCursorPos()
				term.setCursorPos(cx - 1, cy)
				term.write(" ")
				term.setCursorPos(cx - 1, cy)
			end
		elseif ev == "timer" and a == timer then
			return nil
		end
	end
end

-- three buckets: chests that already stack this item, chests with any free
-- slot, then the rest. with 200+ vaults the third bucket used to eat setup time.
function packOrder(name, storages)
	local hints = craftPackIndex and craftPackIndex[name]
	local free  = craftPackFree
	if not hints and not free then return storages end
	local first, mid, tail = {}, {}, {}
	for _, s in ipairs(storages) do
		if hints and hints[s] then first[#first + 1] = s
		elseif free and free[s] then mid[#mid + 1] = s
		else tail[#tail + 1] = s end
	end
	for _, s in ipairs(mid)  do first[#first + 1] = s end
	for _, s in ipairs(tail) do first[#first + 1] = s end
	return first
end

function packRemember(name, chest)
	if not craftPackIndex then return end
	craftPackIndex[name] = craftPackIndex[name] or {}
	craftPackIndex[name][chest] = true
	-- chest accepted something, so treat it as having room again
	if craftPackFree then craftPackFree[chest] = true end
end

-- pushItems returned 0 = no partial stack AND no empty slot for THIS item.
-- since any empty slot fits any item, means no empty slot at all.
function packForget(name, chest)
	if craftPackIndex and craftPackIndex[name] then craftPackIndex[name][chest] = nil end
	if craftPackFree then craftPackFree[chest] = nil end
end

function findFreeSpace(names)
	for _, stoName in ipairs(names) do
		local sto = peripheral.wrap(stoName)
		if sto and sto.pullItems and sto.list and sto.size then
			local okS, sz = pcall(sto.size)
			local okL, lst = pcall(sto.list)
			if okS and okL and sz and lst then
				local used = 0
				for _ in pairs(lst) do used = used + 1 end
				if sz - used >= 16 then return sto end
			end
		end
	end
	return nil
end

function blindUnload(tName, names)
	local sto = findFreeSpace(names)
	if not sto then return false end
	for slot = 1, 16 do pcall(sto.pullItems, tName, slot, 64) end
	return true
end

function cleanupCraftMachines(activeStore, list)
	local cleanList = list or Craft.cleanMachines
	local stuckMachines = {}
	local stuckSeen     = {}
	for _, entry in ipairs(cleanList) do
		if entry and entry.name then
			local p = peripheral.wrap(entry.name)
			local anyStuck = false
			if p and p.list then
				local s, items = pcall(p.list)
				if s and items then
					for slot, item in pairs(items) do
						if item then
							if entry.pullNames == nil or entry.pullNames[item.name] then
								local remaining = item.count
								if p.pushItems then
									for _, stoName in ipairs(activeStore) do
										if remaining <= 0 then break end
										local ok, mv = pcall(p.pushItems, stoName, slot, remaining)
										if ok and mv and mv > 0 then remaining = remaining - mv end
									end
								end
								if remaining > 0 then
									for _, stoName in ipairs(activeStore) do
										if remaining <= 0 then break end
										local sto = peripheral.wrap(stoName)
										if sto and sto.pullItems then
											local ok2, mv2 = pcall(sto.pullItems, entry.name, slot, remaining)
											if ok2 and mv2 and mv2 > 0 then remaining = remaining - mv2 end
										end
									end
								end
								if remaining > 0 then anyStuck = true end
							end
						end
					end
				end
			else
				if not blindUnload(entry.name, activeStore) then
					anyStuck = true
				end
			end
			if anyStuck and not stuckSeen[entry.name] then
				stuckSeen[entry.name] = true
				table.insert(stuckMachines, entry.name)
			end
		end
	end
	if not list then Craft.cleanMachines = {} end
	if #stuckMachines > 0 then
		local shortNames = {}
		for _, n in ipairs(stuckMachines) do
			local disp = n
			if getMachName then disp = getMachName(n) end
			table.insert(shortNames, disp)
		end
		uiMessage = "CANCEL: stuck in " .. table.concat(shortNames, ", ")
		if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
		uiMsgTimer = os.startTimer(4)
	end
end

drawFluidProg = function(subLabel, current, total, workers)
	local co = lockOwnerId()
	local ent = fluidInlineByCo[co]
	if ent then
		local short = shortName(tostring(subLabel))
		local line = {
			desc = short .. " (fluid)", done = current or 0, total = total or 0,
			machines = workers or 0, topup = false,
		}
		ent.ctx.active[ent.node] = line
		if displayCtx and displayCtx ~= ent.ctx then
			displayCtx.active["FLUIDNEST:" .. tostring(co)] = line
		end
		return
	end
	if drawUI then drawUI(true) end
	local w, h = monitor.getSize()
	local pW, pH = 46, 10
	local title = Craft.failed and " MANUFACTURING FAILED " or " MANUFACTURING ACTIVE "
	local style = Craft.failed and "danger" or "warn"
	local pX, pY = UI.popup(pW, pH, w, h, title, style)
	local stepStr = string.format("Step %d/%d", fluidStepNum, math.max(fluidStepNum, fluidStepTotal))
	drawText(pX + 2, pY + 2, stepStr, colors.white, colors.gray)
	local fStr = "[FLUID]"
	drawText(pX + pW - #fStr - 2, pY + 2, fStr, colors.cyan, colors.gray)
	if workers and workers > 1 then
		local wStr = "[" .. workers .. "x parallel] "
		drawText(pX + pW - #fStr - 2 - #wStr, pY + 2, wStr, colors.cyan, colors.gray)
	end
	local subShort = (shortName(tostring(subLabel)))
	local subStr = ("Sub-task: " .. total .. " ops " .. subShort):sub(1, pW - 4)
	drawText(pX + 2, pY + 3, subStr, colors.lightGray, colors.gray)
	local goal = fluidGoalLabel ~= "" and fluidGoalLabel or subLabel
	local cleanGoal = (shortName(tostring(goal))):upper()
	local itemStr = (">> " .. cleanGoal .. " <<"):sub(1, pW - 4)
	drawText(pX + math.floor((pW - #itemStr) / 2), pY + 5, itemStr, colors.yellow, colors.gray)
	local progStr = string.format("Progress: %d / %d", current, total)
	drawText(pX + math.floor((pW - #progStr) / 2), pY + 7, progStr, colors.lime, colors.gray)
	local barWidth = math.min(28, pW - 14)
	local barX = pX + math.floor((pW - barWidth) / 2)
	drawProgBar(barX, pY + 8, barWidth, current, total, colors.gray)
	local cancelStr = " [ CANCEL ] "
	local cancelBtnX = pX + math.floor((pW - #cancelStr) / 2)
	local cancelBtnY = pY + pH - 1
	drawText(cancelBtnX, cancelBtnY, cancelStr, colors.white, colors.red)
	craftCancelY  = cancelBtnY
	craftCancelX1 = cancelBtnX
	craftCancelX2 = cancelBtnX + #cancelStr - 1
	_bufFlush()
end

drawFluidCancel = function()
	local sw, sh = monitor.getSize()
	local cancStr = " [ CANCEL SCAN ] "
	local cancX = math.floor((sw - #cancStr) / 2) + 1
	drawText(2, sh - 3, fluidScanStatus, colors.yellow, colors.black)
	drawText(cancX, sh - 1, cancStr, colors.white, colors.red)
	craftCancelY  = sh - 1
	craftCancelX1 = cancX
	craftCancelX2 = cancX + #cancStr - 1
	_bufFlush()
end

function findFluidProd(fluidName)
	local p = fluidProducers(fluidName)[1]
	if p then return p.recipe, p.perOp end
	return nil
end

function countFluidSteps(fluidName, amount, simStock, visited)
	local have = simStock[fluidName] or 0
	if have >= amount then simStock[fluidName] = have - amount; return 0 end
	local shortfall = amount - have
	simStock[fluidName] = 0
	if visited[fluidName] then return 0 end
	local recipe, perOp = findFluidProd(fluidName)
	if not recipe or not perOp or perOp <= 0 then return 0 end
	local ops = math.ceil(shortfall / perOp)
	visited[fluidName] = true
	local cnt = 0
	for _, inp in ipairs(recipe.inputs or {}) do
		cnt = cnt + countFluidSteps(inp.name, ops * inp.amount, simStock, visited)
	end
	visited[fluidName] = nil
	simStock[fluidName] = (simStock[fluidName] or 0) + (ops * perOp - shortfall)
	return cnt + 1
end

function countTopSteps(recipe, targetName, amount)
	local perOp = nil
	for _, o in ipairs(recipe.outputs or {}) do if o.name == targetName then perOp = o.amount; break end end
	if not perOp then for _, o in ipairs(recipe.item_outputs or {}) do if o.name == targetName then perOp = o.count; break end end end
	if not perOp or perOp <= 0 then return 1 end
	local ops = math.ceil(amount / perOp)
	local simStock = {}
	for k, v in pairs(getFluid()) do simStock[fluidNameOf(k)] = v end
	local cnt = 0
	local visited = {}
	for _, inp in ipairs(recipe.inputs or {}) do
		cnt = cnt + countFluidSteps(inp.name, ops * inp.amount, simStock, visited)
	end
	return cnt + 1
end

function estimateStages(plan)
	local n = 0
	for _, step in ipairs(plan) do
		if step.count and step.count > 0 then
			if step.fluid_craft then
				n = n + countTopSteps(step.fluidRecipe, step.item, step.fluidAmount)
			else
				n = n + 1
			end
		end
	end
	return n
end
FLUID_MAX_CAP = 100000

fluidProducers = function(fluidName)
	local cached = _fpCache[fluidName]
	if cached then return cached end
	local out = {}
	local fk = fluidKey(fluidName)

	local function tryAdd(rec, key, own, isPrimary, altIdx)
		if type(rec) ~= "table" then return end
		for _, o in ipairs(rec.outputs or {}) do
			if o.name == fluidName and o.amount and o.amount > 0 then
				out[#out + 1] = {recipe = rec, perOp = o.amount, key = key,
					own = own, isPrimary = isPrimary, altIdx = altIdx}
				return
			end
		end
	end
	tryAdd(Fluids.find(fk), fk, true, true, nil)
	for i, alt in ipairs(Fluids.altsOf(fk) or {}) do tryAdd(alt, fk, true, false, i) end
	for key, rec in pairs(Fluids.all()) do
		if key ~= fk then tryAdd(rec, key, false, false, nil) end
	end
	for key, alts in pairs(Fluids.allAlts()) do
		if key ~= fk then
			for _, alt in ipairs(alts) do tryAdd(alt, key, false, false, nil) end
		end
	end
	_fpCache[fluidName] = out
	return out
end

function removeFluidRef(rec)
	for key, r in pairs(Fluids.all()) do
		if r == rec then
			local alts = Fluids.altsOf(key)
			if alts and alts[1] then
				Fluids.set(key, table.remove(alts, 1))
				if #alts == 0 then Fluids.setAlts(key, nil) end
			else
				Fluids.remove(key)
			end
			return
		end
	end
	for key, alts in pairs(Fluids.allAlts()) do
		for i, r in ipairs(alts) do
			if r == rec then
				table.remove(alts, i)
				if #alts == 0 then Fluids.setAlts(key, nil) end
				return
			end
		end
	end
end

_mfcMemo, _mfcStock, _mfcIStock = {}, nil, nil

function fluidMaxOps(recipe, fstock, istock, visited)
	local maxOps = math.huge
	local tainted = false
	for _, inp in ipairs(recipe.inputs or {}) do
		local avail, t = maxFluid(inp.name, fstock, istock, visited)
		if t then tainted = true end
		local possible = (inp.amount and inp.amount > 0) and math.floor(avail / inp.amount) or 0
		if possible < maxOps then maxOps = possible end
	end
	for _, it in ipairs(recipe.item_inputs or {}) do
		local possible = (it.count and it.count > 0) and math.floor((istock[it.name] or 0) / it.count) or 0
		if possible < maxOps then maxOps = possible end
	end
	if maxOps == math.huge then maxOps = FLUID_MAX_CAP end
	return maxOps, tainted
end

maxFluid = function(fluidName, fstock, istock, visited)
	if _mfcStock ~= fstock or _mfcIStock ~= istock then
		_mfcMemo = {}; _mfcStock = fstock; _mfcIStock = istock
	end
	local have = fstock[fluidName] or 0
	calcNodes = calcNodes + 1
	if calcBudget > 0 and calcNodes > calcBudget then return have, true end
	if calcNodes % 1024 == 0 then sleep(0) end
	if visited[fluidName] then return have, true end
	local cached = _mfcMemo[fluidName]
	if cached ~= nil then return cached, false end
	local prods = fluidProducers(fluidName)
	if #prods == 0 then _mfcMemo[fluidName] = have; return have, false end
	visited[fluidName] = true
	local best = 0
	local tainted = false
	for _, pr in ipairs(prods) do
		local ops, t = fluidMaxOps(pr.recipe, fstock, istock, visited)
		if t then tainted = true end
		local produced = ops * pr.perOp
		if produced > best then best = produced end
	end
	visited[fluidName] = nil
	local result = math.min(have + best, have + FLUID_MAX_CAP)
	if not tainted then _mfcMemo[fluidName] = result end
	return result, tainted
end

simFluidConsume = function(fluidName, amountMb, stock, missing, fvisited, itemVisited)
	calcNodes = calcNodes + 1
	if calcBudget > 0 and calcNodes > calcBudget then return end
	if calcNodes % 1024 == 0 then sleep(0) end
	if not amountMb or amountMb <= 0 then return end
	if not stock.__fl then
		stock.__fl = true
		for k, v in pairs(getFluidCached()) do
			if stock[k] == nil then stock[k] = v end
		end
	end
	local key = fluidKey(fluidName)
	local have = stock[key] or 0
	if have >= amountMb then stock[key] = have - amountMb; return end
	local shortfall = amountMb - have
	stock[key] = 0
	if fvisited[fluidName] then
		missing[key] = (missing[key] or 0) + shortfall
		return
	end
	local prods = fluidProducers(fluidName)
	if #prods == 0 then
		missing[key] = (missing[key] or 0) + shortfall
		return
	end
	fvisited[fluidName] = true

	local function consumeVia(p, st, miss)
		local fops = math.ceil(shortfall / p.perOp)
		for _, inp in ipairs(p.recipe.inputs or {}) do
			simFluidConsume(inp.name, inp.amount * fops, st, miss, fvisited, itemVisited)
		end
		for _, it in ipairs(p.recipe.item_inputs or {}) do
			calcCraft(it.name, it.count * fops, st, miss, {}, {}, itemVisited or {}, false)
		end
	end
	local usedP
	if #prods == 1 then
		consumeVia(prods[1], stock, missing)
		usedP = prods[1]
	else
		for _, p in ipairs(prods) do
			local stCopy = {}
			for k, v in pairs(stock) do stCopy[k] = v end
			local missCopy = {}
			consumeVia(p, stCopy, missCopy)
			if next(missCopy) == nil then
				for k, v in pairs(stCopy) do stock[k] = v end
				usedP = p
				break
			end
		end
		if not usedP then
			consumeVia(prods[1], stock, missing)
			usedP = prods[1]
		end
	end
	fvisited[fluidName] = nil
	local fops = math.ceil(shortfall / usedP.perOp)
	local surplus = fops * usedP.perOp - shortfall
	if surplus > 0 then stock[key] = (stock[key] or 0) + surplus end
	creditByprods(usedP.recipe, fops, stock, nil, fluidName)
end
ITEM_MAX_CAP = 999
_micMemo, _micStock = {}, nil

function maxItem(itemName, istock, fstock, visited)
	if _micStock ~= istock then _micMemo = {}; _micStock = istock end
	visited = visited or {}
	local have = groupAvail(itemName, istock)
	calcNodes = calcNodes + 1
	if calcBudget > 0 and calcNodes > calcBudget then return have, true end
	if visited[itemName] then return have, true end
	local cached = _micMemo[itemName]
	if cached ~= nil then return cached, false end
	local recs = {}
	local main = Recipe.find(itemName)
	if main then recs[#recs + 1] = main end
	for _, a in ipairs(Recipe.altsOf(itemName) or {}) do recs[#recs + 1] = a end
	if #recs == 0 then _micMemo[itemName] = have; return have, false end
	visited[itemName] = true
	local best, tainted = 0, false
	for _, rec in ipairs(recs) do
		local produced = 0
		if rec.type == "fluid" then
			local frec, fperOp = findFluidItemProd(itemName)
			if frec and fperOp and fperOp > 0 then
				local ops, t = fluidMaxOps(frec, fstock or {}, istock, {})
				if t then tainted = true end
				produced = (ops or 0) * fperOp
			end
		else
			local ings = {}
			for i = 1, #(rec.ingredients or {}) do
				local ing = rec.ingredients[i]
				if ing and ing ~= "nil" then ings[ing] = (ings[ing] or 0) + 1 end
			end
			local opc = rec.output_count or 1
			local maxOps = math.huge
			for ing, per in pairs(ings) do
				local av, t = maxItem(ing, istock, fstock, visited)
				if t then tainted = true end
				local p = math.floor(av / per)
				if p < maxOps then maxOps = p end
			end
			if maxOps == math.huge then maxOps = 0 end
			produced = maxOps * opc
		end
		if produced > best then best = produced end
	end
	visited[itemName] = nil
	local result = math.min(have + best, have + ITEM_MAX_CAP)
	if not tainted then _micMemo[itemName] = result end
	return result, tainted
end

function scanFluidsNow()
	fluidScanResults = {}
	local fstock = {}
	for k, v in pairs(getFluid()) do fstock[fluidNameOf(k)] = v end
	local istock = getInv()
	local seen = {}

	local function scanRec(rec)
		for _, o in ipairs(rec.outputs or {}) do
			if not seen[o.name] then
				seen[o.name] = true
				local total = maxFluid(o.name, fstock, istock, {})
				fluidScanResults[o.name] = math.min(9999, math.max(0, total - (fstock[o.name] or 0)))
				sleep(0)
			end
		end
	end
	for _, rec in pairs(Fluids.all()) do scanRec(rec) end
	for _, alts in pairs(Fluids.allAlts()) do
		for _, rec in ipairs(alts) do scanRec(rec) end
	end
end

ensureItem = function(itemName, count)
	if Craft.cancelled then return false, {"Cancelled by user."} end

	local function curHave()
		local stk = getInvCached()
		local h = stk[itemName] or 0
		local alts = Groups.altsOf(itemName)
		if alts then
			for _, alt in ipairs(alts) do h = h + (stk[alt] or 0) end
		end
		return h
	end
	local have = curHave()
	if have >= count then return true, nil end
	resetStock()
	have = curHave()
	if have >= count then return true, nil end
	-- HARD CAP. 6 tiers covers everything real. deeper = infinite loop from
	-- a circular recipe or a mod that lied about outputs. DO NOT REMOVE.
	-- per-coroutine bcz parallel workers sharing one global counter tripped
	-- this cap on 8 concurrent depth-1 calls and cascaded failures.
	local co = lockOwnerId()
	local myDepth = ensureDepthByCo[co] or 0
	if myDepth >= 6 then
		return false, {"Recursion too deep: " .. (shortName(itemName))}
	end
	ensureDepthByCo[co] = myDepth + 1
	Craft.depth = Craft.depth + 1
	local attempts = 0
	local lastMissing = nil
	-- max 12 loops or you just spin. subcrafts finishing mid-loop can
	-- produce ingredients we needed. after 12, give up
	while have < count and not Craft.cancelled do
		attempts = attempts + 1
		if attempts > 12 then break end
		local plan, miss = planProd(itemName, count, true)
		lastMissing = miss
		if not (plan and #plan > 0) then break end
		local before = have
		runCraft(plan)
		have = curHave()
		if have <= before then break end
	end
	Craft.depth = Craft.depth - 1
	ensureDepthByCo[co] = myDepth
	if ensureDepthByCo[co] == 0 then ensureDepthByCo[co] = nil end
	if have < count then
		local sn = shortName(itemName)
		local lines = {string.format("Need %dx %s (have %d)", count, sn, have)}
		if lastMissing and next(lastMissing) then
			local parts = {}
			for mName, mCnt in pairs(lastMissing) do
				if not (mName == itemName) then
					parts[#parts + 1] = string.format("%dx %s", mCnt, shortName(mName))
				end
			end
			table.sort(parts)
			if #parts > 0 then
				local shown = {}
				for i = 1, math.min(3, #parts) do shown[i] = parts[i] end
				local msg = "Need: " .. table.concat(shown, ", ")
				if #parts > 3 then msg = msg .. " +" .. (#parts - 3) end
				table.insert(lines, msg)
			end
		end
		return false, lines
	end
	return true, nil
end

function ensureInputs(recipe, ops)
	for _, it in ipairs(recipe.item_inputs or {}) do
		local ok, err = ensureItem(it.name, ops * it.count)
		if not ok then return false, err end
	end
	return true, nil
end

function ensureIngs(step, ingsMap)
	for ing, perOp in pairs(ingsMap) do
		local wantN = (step.tools and step.tools[ing]) and 1 or (perOp * (step.count or 0))
		local ok, err = ensureItem(ing, wantN)
		if not ok then return false, err, ing end
	end
	return true
end

function fluidRecShortIn(recipe, ops)
	local parts = {}
	local fInv = getFluid()
	for _, inp in ipairs(recipe.inputs or {}) do
		local need = ops * inp.amount
		local have = fInv[fluidKey(inp.name)] or 0
		if have < need then parts[#parts + 1] = string.format("%d mB %s", need - have, shortName(inp.name)) end
	end
	local iInv = getInv()
	for _, it in ipairs(recipe.item_inputs or {}) do
		local need = ops * it.count
		local have = iInv[it.name] or 0
		local alts = Groups.altsOf(it.name)
		if alts then for _, alt in ipairs(alts) do have = have + (iInv[alt] or 0) end end
		if have < need then parts[#parts + 1] = string.format("%dx %s", need - have, shortName(it.name)) end
	end
	return parts
end

function appendMissing(lines, parts)
	if parts and #parts > 0 then
		table.sort(parts)
		local shown = {}
		for i = 1, math.min(3, #parts) do shown[i] = parts[i] end
		local msg = "Need: " .. table.concat(shown, ", ")
		if #parts > 3 then msg = msg .. " +" .. (#parts - 3) end
		table.insert(lines, msg)
	end
	return lines
end

ensureFluid = function(fluidName, amount, visited)
	if Craft.cancelled then return false, {"Cancelled by user."} end
	local have = (getFluidCached())[fluidKey(fluidName)] or 0
	if have >= amount then return true, nil end
	resetStock()
	have = (getFluidCached())[fluidKey(fluidName)] or 0
	if have >= amount then return true, nil end
	if visited[fluidName] then
		local sn = shortName(fluidName)
		return false, {"Recursion cycle on " .. sn}
	end
	local prods = fluidProducers(fluidName)
	if #prods == 0 then
		local sn = shortName(fluidName)
		return false, {string.format("Need %d mB %s, have %d (no recipe)", amount, sn, have)}
	end
	visited[fluidName] = true
	local attempts = 0
	while have < amount do
		if Craft.cancelled then visited[fluidName] = nil; return false, {"Cancelled by user."} end
		attempts = attempts + 1
		if attempts > 8 then
			visited[fluidName] = nil
			local sn = shortName(fluidName)
			local lines = {string.format("Need %d mB %s, made only %d", amount, sn, have)}
			local p0 = prods[1]
			if p0 then appendMissing(lines, fluidRecShortIn(p0.recipe, math.ceil((amount - have) / p0.perOp))) end
			return false, lines
		end
		local shortfall = amount - have
		local fstock = {}
		for k, v in pairs(getFluidCached()) do fstock[fluidNameOf(k)] = v end
		local istock = getInvCached()
		local chosen, chosenOps
		for _, p in ipairs(prods) do
			local ops = math.ceil(shortfall / p.perOp)
			if fluidMaxOps(p.recipe, fstock, istock, {}) >= ops then
				chosen = p; chosenOps = ops; break
			end
		end
		if not chosen then chosen = prods[1]; chosenOps = math.ceil(shortfall / prods[1].perOp) end
		local recipe, ops = chosen.recipe, chosenOps
		for _, inp in ipairs(recipe.inputs or {}) do
			local ok, err = ensureFluid(inp.name, ops * inp.amount, visited)
			if not ok then visited[fluidName] = nil; return false, err end
		end
		local okItems, itemErr = ensureInputs(recipe, ops)
		if not okItems then visited[fluidName] = nil; return false, itemErr end
		local okRun, errRun = runFluidCraft({recipe = recipe, ops = ops, perOp = chosen.perOp, label = fluidName})
		if not okRun then visited[fluidName] = nil; return false, errRun end
		resetStock()
		local newHave = (getFluid())[fluidKey(fluidName)] or 0
		if newHave <= have then
			visited[fluidName] = nil
			local sn = shortName(fluidName)
			local lines = {string.format("Need %d mB %s, stuck at %d", amount, sn, newHave)}
			appendMissing(lines, fluidRecShortIn(recipe, ops))
			return false, lines
		end
		have = newHave
	end
	visited[fluidName] = nil
	return true, nil
end

function produceFluid(recipe, targetName, amount)
	if Craft.cancelled then return false, {"Cancelled by user."}, 0 end
	local prods = fluidProducers(targetName)
	if #prods > 1 then
		local fstock = {}
		for k, v in pairs(getFluidCached()) do fstock[fluidNameOf(k)] = v end
		local istock = getInvCached()
		for _, p in ipairs(prods) do
			local ops = math.ceil(amount / p.perOp)
			if fluidMaxOps(p.recipe, fstock, istock, {}) >= ops then
				recipe = p.recipe; break
			end
		end
	end
	local perOp = nil
	for _, o in ipairs(recipe.outputs or {}) do
		if o.name == targetName then perOp = o.amount; break end
	end
	if not perOp then
		for _, o in ipairs(recipe.item_outputs or {}) do
			if o.name == targetName then perOp = o.count; break end
		end
	end
	if not perOp or perOp <= 0 then return false, {"Bad recipe output amount"}, 0 end
	local ops = math.ceil(amount / perOp)
	local visited = {}
	for _, inp in ipairs(recipe.inputs or {}) do
		local ok, err = ensureFluid(inp.name, ops * inp.amount, visited)
		if not ok then return false, err, 0 end
	end
	local okItems, itemErr = ensureInputs(recipe, ops)
	if not okItems then return false, itemErr, 0 end
	return runFluidCraft({recipe = recipe, ops = ops, perOp = perOp, label = targetName})
end

function fluidCraft(recipe, targetName, amount)
	local isItem = false
	for _, o in ipairs(recipe.item_outputs or {}) do
		if o.name == targetName then isItem = true; break end
	end
	fluidGoalLabel = targetName
	fluidStepNum = 0
	fluidStepTotal = countTopSteps(recipe, targetName, amount)
	sysStatus = "AUTO_CRAFT"
	fluidCraftMsg = "Crafting..."
	Craft.cancelled = false
	Craft.locks = {}; fluidTankClaims = 0; _fluidBusy = false; fluidInlineByCo = {}
	drawUI()
	local okRun, runErr, produced = produceFluid(recipe, targetName, amount)
	sysStatus = "IDLE"
	fluidCraftMsg = ""
	Craft.cancelled = false
	if okRun then
		local prod = {{name = targetName, amount = produced, unit = isItem and "x" or "mB"}}
		craftDonePopup = {outputs = prod, timer = os.startTimer(10)}
	else
		craftErrTitle = "! CANNOT CRAFT"
		craftErrLines = runErr or {"Unknown error"}
	end
	return okRun, produced, isItem
end

function fluidCraftFlow(recipe, targetName)
	local isItemTarget = false
	for _, o in ipairs(recipe.item_outputs or {}) do
		if o.name == targetName then isItemTarget = true; break end
	end
	fluidRecipePicker = nil
	fluidKeepName = nil
	fluidCraftMode = {recipe = recipe, target = targetName, isItem = isItemTarget}
	itemToCraft = targetName
	craftQuantity = isItemTarget and 1 or 1000
	isRequestMode = false
	isSettingKeep = false
	qtyOrigTab = "RECIPES"
	pickerCapped = false
	pickerCraftable = 0
	pickerMaxSet = false
	if Config.autoMaxCalc ~= false then pickerMax() end
	curTab = "QUANTITY_PICKER"
end

function pickerMax()
	pickerCraftable = 0
	pickerCapped = false
	if fluidCraftMode and fluidCraftMode.recipe then
		local recipe       = fluidCraftMode.recipe
		local targetName   = fluidCraftMode.target
		local isItemTarget = fluidCraftMode.isItem
		local fstock = {}
		for k, v in pairs(getFluid()) do fstock[fluidNameOf(k)] = v end
		local istock = getInv()
		local perOp = 1
		if isItemTarget then
			for _, o in ipairs(recipe.item_outputs or {}) do if o.name == targetName then perOp = o.count; break end end
		else
			for _, o in ipairs(recipe.outputs or {}) do if o.name == targetName then perOp = o.amount; break end end
		end
		local ops = fluidMaxOps(recipe, fstock, istock, {})
		pickerCraftable = math.min(FLUID_MAX_CAP, ops * (perOp > 0 and perOp or 1))
	else
		local target = itemToCraft
		local snap = getInv()
		local snapCraft = {}
		for k, v in pairs(snap) do snapCraft[k] = v end
		snapCraft[target] = 0
		local alts = Groups.altsOf(target)
		if alts then
			for _, alt in ipairs(alts) do snapCraft[alt] = 0 end
		end
		local cs = recipesScan[target]
		if cs and type(cs.maxCraftable) == "number" and not next(cs.missing or {}) then
			pickerCraftable = cs.maxCraftable
		else
			pickerCraftable = maxCraft(target, snapCraft)
		end
	end
	pickerMaxSet = true
end


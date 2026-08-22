-- grab the FIRST wireless modem. wired modems are also 'modem' peripherals
-- but rednet wont broadcast on them. isWireless() is only reliable filter
function openRemote()
	for _, nm in ipairs(peripheral.getNames()) do
		if peripheral.getType(nm) == "modem" then
			local m = peripheral.wrap(nm)
			if m and m.isWireless and m.isWireless() then
				rednet.open(nm)
				return true
			end
		end
	end
	return false
end

function runQueueAll()
	if #Craft.queue == 0 then return end
	sysStatus = "MANUAL_CRAFT"
	local qi = 1
	-- reset cancel PER entry not once at top. user cancels item N,
	-- we still try N+1 without making them click start again
	while qi <= #Craft.queue do
		Craft.cancelled = false
		resetErr()
		local qe = Craft.queue[qi]
		local okQ, reason = queueRunOne(qe)
		craftResultId = (craftResultId or 0) + 1
		if okQ then
			lastResult = { ok = true, name = qe.name, made = lastCraftMade or qe.qty }
			table.remove(Craft.queue, qi)
		else
			lastResult = { ok = false, name = qe.name, err = (reason and reason[1]) or "craft failed", stage = stageDone or 0, total = stageTotal or 0 }
			qe.failed = reason
			qi = qi + 1
		end
		if Craft.cancelled then break end
		drawUI()
	end
	sysStatus = "IDLE"
	resetErr()
end

function buildRemote()
	local snap = { cmd = "remote_snap", busy = sysStatus ~= "IDLE", keepPaused = Config.autostock_paused == true, epoch = stockEpoch or 0 }
	local q = {}
	for i = 1, #Craft.queue do
		q[i] = { name = Craft.queue[i].name, count = Craft.queue[i].qty }
	end
	snap.queue = q
	local ctx = displayCtx
	if ctx and (ctx.total or 0) > 0 and not ctx.done then
		local sDone = stageDone or 0
		local sTotal = math.max(stageTotal or 0, sDone, 1)
		snap.job = { name = ctx.finalGoal or "?", done = sDone, total = sTotal, pct = math.floor(sDone / sTotal * 100) }
	elseif sysStatus ~= "IDLE" then
		if fluidGoalLabel and fluidGoalLabel ~= "" then
			local sn = fluidStepNum or 0
			local st = math.max(fluidStepNum or 0, fluidStepTotal or 0, 1)
			snap.job = { name = fluidGoalLabel, done = sn, total = st, pct = math.floor(sn / st * 100) }
		else
			local sDone = stageDone or 0
			local sTotal = math.max(stageTotal or 0, sDone, 1)
			snap.job = { name = "crafting", done = sDone, total = sTotal, pct = math.floor(sDone / sTotal * 100) }
		end
	end
	if snap.busy then snap.note = "crafting" elseif #q > 0 then snap.note = #q .. " queued" else snap.note = "" end
	snap.resultId = craftResultId or 0
	snap.result = lastResult
	return snap
end

function remoteSearch(q)
	local out = { cmd = "remote_found", results = {} }
	if type(q) ~= "string" or q == "" then return out end
	local ql = q:lower()
	local names = {}
	for itemName in pairs(Recipe.all()) do
		local sn = shortName(itemName)
		if sn:lower():find(ql, 1, true) then names[#names + 1] = itemName end
	end
	table.sort(names)
	local inv = getInvCached()
	local n = 0
	for i = 1, #names do
		if n >= 50 then break end
		n = n + 1
		out.results[n] = { name = names[i], have = groupAvail(names[i], inv) }
	end
	local fset = {}
	for _, rec in pairs(Fluids.all()) do
		for _, o in ipairs(rec.outputs or {}) do fset[o.name] = true end
	end
	for _, alts in pairs(Fluids.allAlts()) do
		for _, a in ipairs(alts) do
			for _, o in ipairs(a.outputs or {}) do fset[o.name] = true end
		end
	end
	local fnames = {}
	for fn in pairs(fset) do
		local sn = shortName(fn)
		if sn:lower():find(ql, 1, true) then fnames[#fnames + 1] = fn end
	end
	table.sort(fnames)
	local finv = getFluidCached()
	for i = 1, #fnames do
		if n >= 80 then break end
		n = n + 1
		out.results[n] = { name = fnames[i], fl = true, have = (finv and finv[fluidKey(fnames[i])]) or 0 }
	end
	return out
end

function remoteMax(name)
	if type(name) ~= "string" then return 0 end
	if Recipe.find(name) then
		local snap = getInvCached()
		local snapCraft = {}
		for k, v in pairs(snap) do snapCraft[k] = v end
		snapCraft[name] = 0
		local alts = Groups.altsOf(name)
		if alts then
			for _, alt in ipairs(alts) do snapCraft[alt] = 0 end
		end
		local cs = recipesScan[name]
		if cs and type(cs.maxCraftable) == "number" and not next(cs.missing or {}) then return cs.maxCraftable end
		return maxCraft(name, snapCraft)
	end
	local prod = fluidProducers(name)
	if prod and prod[1] and prod[1].recipe then
		local recipe = prod[1].recipe
		local fstock = {}
		for k, v in pairs(getFluidCached()) do fstock[fluidNameOf(k)] = v end
		local istock = getInvCached()
		local perOp = 0
		for _, o in ipairs(recipe.outputs or {}) do if o.name == name then perOp = o.amount break end end
		if perOp <= 0 then
			for _, o in ipairs(recipe.item_outputs or {}) do if o.name == name then perOp = o.count break end end
		end
		local ops = fluidMaxOps(recipe, fstock, istock, {})
		return math.min(FLUID_MAX_CAP, ops * (perOp > 0 and perOp or 1))
	end
	return 0
end

-- rednet is just a transport. old cmd names stay so existing pocket client keeps working.
-- new callers use {cmd="rpc", method="craft.start", args={...}, rid=N}
-- and hit the same functions local scripts do
function handleRemote(sid, msg)
	local cmd = msg.cmd
	if cmd == "rpc" then
		local ok, r1, r2 = pcall(aegis.rpc, msg.method, msg.args)
		local reply = { cmd = "rpcr", rid = msg.rid }
		if not ok then
			reply.ok = false; reply.err = tostring(r1)
		elseif r1 == nil and type(r2) == "string" then
			reply.ok = false; reply.err = r2
		else
			reply.ok = true; reply.result = r1
		end
		rednet.send(sid, reply, REMOTE_PROTOCOL)
	elseif cmd == "remote_pull" then
		rednet.send(sid, aegis.jobs.status(), REMOTE_PROTOCOL)
	elseif cmd == "remote_search" then
		rednet.send(sid, remoteSearch(msg.q), REMOTE_PROTOCOL)
	elseif cmd == "remote_max" then
		local mhave = 0
		if type(msg.name) == "string" then
			if Recipe.find(msg.name) then mhave = aegis.storage.count(msg.name)
			else mhave = (aegis.fluids.inventory()[fluidKey(msg.name)]) or 0 end
		end
		rednet.send(sid, { cmd = "remote_maxr", name = msg.name, max = aegis.craft.max(msg.name), have = mhave }, REMOTE_PROTOCOL)
	elseif cmd == "remote_craft" then
		if type(msg.name) == "string" then
			aegis.craft.start(msg.name, msg.count, { run = msg.now and true or false })
		end
		rednet.send(sid, aegis.jobs.status(), REMOTE_PROTOCOL)
	elseif cmd == "remote_do" then
		if msg.id == "cancel" then aegis.jobs.cancel()
		elseif msg.id == "runall" then remoteRunFlag = true
		elseif msg.id == "keep_on" then Config.autostock_paused = false; saveData()
		elseif msg.id == "keep_off" then Config.autostock_paused = true; saveData()
		elseif msg.id == "keep_run" then remoteKeepRun = true
		elseif msg.id == "qdel" then aegis.jobs.cancel(msg.arg)
		end
		rednet.send(sid, aegis.jobs.status(), REMOTE_PROTOCOL)
	end
end


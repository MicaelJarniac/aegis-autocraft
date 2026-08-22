function scanPeriph(names, method, withSize)
	local out = {}
	if #names == 0 then return out end
	while _batchScanBusy do sleep(0.05) end
	_batchScanBusy = true
	local i = 1
	while i <= #names do
		local hi = math.min(i + 63, #names)
		local tasks = {}
		for j = i, hi do
			local nm = names[j]
			tasks[#tasks + 1] = function()
				local p = peripheral.wrap(nm)
				if p and p[method] then
					local e = {}
					local ok, res = pcall(p[method])
					if ok then e.data = res end
					if withSize and p.size then
						local ok2, sz = pcall(p.size)
						if ok2 then e.size = sz end
					end
					out[nm] = e
				end
			end
		end
		local okAll, errAll = pcall(parallel.waitForAll, table.unpack(tasks))
		if not okAll then
			_batchScanBusy = false
			error(errAll, 0)
		end
		i = hi + 1
	end
	_batchScanBusy = false
	return out
end

function getInv()
	local inventory = {}
	local totalItems, vaultsCnt = 0, 0
	local totalSlots, usedSlots = 0, 0
	local names = {}
	for storageName, isEnabled in pairs(Config.storages) do
		if isEnabled and not SYSTEM_SIDES[storageName] then names[#names + 1] = storageName end
	end
	local scanned = scanPeriph(names, "list", true)
	for _, nm in ipairs(names) do
		local e = scanned[nm]
		if e then
			vaultsCnt = vaultsCnt + 1
			if e.size then totalSlots = totalSlots + e.size end
			if e.data then
				for _, item in pairs(e.data) do
					if item then
						inventory[item.name] = (inventory[item.name] or 0) + item.count
						totalItems = totalItems + item.count
						usedSlots  = usedSlots + 1
					end
				end
			end
		end
	end
	local provNames = providerSrc()
	local pScan = scanPeriph(provNames, "list")
	for _, nm in ipairs(provNames) do
		local e = pScan[nm]
		if e and e.data then
			for _, item in pairs(e.data) do
				if item then inventory[item.name] = (inventory[item.name] or 0) + item.count end
			end
		end
	end
	local freeSlots = totalSlots - usedSlots
	return inventory, totalItems, vaultsCnt, freeSlots, totalSlots
end
_flInvCache, _flInvCacheT = nil, -100
_tankStatsCache, _tankStatsT = nil, -100
_stInvCache, _stInvCacheT = nil, -100

function resetStock()
	_flInvCacheT = -100
	_tankStatsT = -100
	_stInvCacheT = -100
	stockEpoch = (stockEpoch or 0) + 1
end

-- 4s cache. long enough so ui redraws dont rescan every vault each frame,
-- short enough that keep/autostock still sees fresh stock.
-- moves = resetStock()
function getInvCached()
	local now = os.clock()
	if _stInvCache and (now - _stInvCacheT) < 4 then
		local c = _stInvCache
		return c[1], c[2], c[3], c[4], c[5]
	end
	local a, b, cc, d, e = getInv()
	_stInvCache = {a, b, cc, d, e}
	_stInvCacheT = now
	return a, b, cc, d, e
end


function optStore()
	local names = {}
	for storageName, isEnabled in pairs(Config.storages) do
		if isEnabled and not SYSTEM_SIDES[storageName] then names[#names + 1] = storageName end
	end
	if #names == 0 then return end

	local packTasks = {}
	for _, sName in ipairs(names) do
		local nm = sName
		packTasks[#packTasks + 1] = function()
			local sto = peripheral.wrap(nm)
			if not (sto and sto.list and sto.pushItems) then return end
			local ok, items = pcall(sto.list)
			if not (ok and items) then return end
			local byName = {}
			for slot, item in pairs(items) do
				if item then
					byName[item.name] = byName[item.name] or {}
					byName[item.name][#byName[item.name] + 1] = slot
				end
			end
			for _, slots in pairs(byName) do
				if #slots > 1 then
					table.sort(slots)
					local target = 1
					for i = 2, #slots do
						local ok2, n = pcall(sto.pushItems, nm, slots[i], 64, slots[target])
						local moved = (ok2 and n) or 0
						if moved == 0 and target < i - 1 then
							target = target + 1
							pcall(sto.pushItems, nm, slots[i], 64, slots[target])
						end
					end
				end
			end
		end
	end
	parallel.waitForAll(table.unpack(packTasks))

	-- cross-chest grouping. one shared scan, per item pick a primary (chest
	-- that already holds most of it) and push everything else into it. jobs
	-- keyed by SOURCE chest so no two writers race the same slot. writes INTO
	-- a primary from different sources are fine, pushItems is atomic per call.
	local scanned = scanPeriph(names, "list")
	local perItem = {}
	for _, sName in ipairs(names) do
		local e = scanned[sName]
		if e and e.data then
			local sto = peripheral.wrap(sName)
			if sto and sto.pushItems then
				for slot, item in pairs(e.data) do
					if item and (item.count or 0) > 0 then
						perItem[item.name] = perItem[item.name] or {}
						perItem[item.name][#perItem[item.name] + 1] = {sName=sName, sto=sto, slot=slot, count=item.count}
					end
				end
			end
		end
	end

	local movesBySrc = {}
	for name, locs in pairs(perItem) do
		local totBy = {}
		for _, l in ipairs(locs) do totBy[l.sName] = (totBy[l.sName] or 0) + l.count end
		local uniq = 0
		for _ in pairs(totBy) do uniq = uniq + 1 end
		if uniq > 1 then
			local best, bestCnt = nil, -1
			for c, cnt in pairs(totBy) do
				if cnt > bestCnt then best, bestCnt = c, cnt end
			end
			for _, l in ipairs(locs) do
				if l.sName ~= best then
					movesBySrc[l.sName] = movesBySrc[l.sName] or {}
					local q = movesBySrc[l.sName]
					q[#q + 1] = {name=name, sto=l.sto, slot=l.slot, dst=best}
				end
			end
		end
	end

	local mergeTasks = {}
	for _, moves in pairs(movesBySrc) do
		local list = moves
		mergeTasks[#mergeTasks + 1] = function()
			for _, m in ipairs(list) do
				-- re-verify slot before push. scan is fresh but other coroutines
				-- (autostock, keep, live crafts) may already grabbed the stack.
				local okD, det = pcall(m.sto.getItemDetail, m.slot)
				if okD and det and det.name == m.name and (det.count or 0) > 0 then
					pcall(m.sto.pushItems, m.dst, m.slot, det.count)
				end
			end
		end
	end
	if #mergeTasks > 0 then
		parallel.waitForAll(table.unpack(mergeTasks))
	end

	resetStock()
end

-- cached for the whole craft. pushFromStore hits this on every push,
-- and the answer only changes when the user edits storages/mgmt groups,
-- which cant happen mid-craft. scheduler seeds craftScan at start.
function scanStorage()
	if craftScan then return craftScan end
	local names, seen = {}, {}
	for storageName, isEnabled in pairs(Config.storages) do
		if isEnabled and not SYSTEM_SIDES[storageName] and not seen[storageName] then
			seen[storageName] = true; names[#names + 1] = storageName
		end
	end
	for _, pName in ipairs(providerSrc()) do
		if not seen[pName] then seen[pName] = true; names[#names + 1] = pName end
	end
	return names
end

pushFromStore = function(itemName, amountNeeded, targetMach, targetSlot, prescan)
	if Craft.cancelled then return 0 end
	local moved = 0

	local alts = Groups.altsOf(itemName)
	local altItems = {}
	if alts then
		for _, altName in ipairs(alts) do
			if altName ~= itemName then altItems[altName] = true end
		end
	end
	local hasAlts = next(altItems) ~= nil

	local exactSlots = {}
	local altSlots   = {}
	local scanNames = scanStorage()

	-- prescan lets the caller share ONE storage scan across concurrent coroutines
	-- (e.g. 3 depots loading in the same setup burst).
	-- verifiedPush below re-reads each slot right before push, so a slot that
	-- shifted after prescan just falls through, no wrong items pushed.
	local scanned = prescan or scanPeriph(scanNames, "list")
	for _, stoName in ipairs(scanNames) do
		local e = scanned[stoName]
		if e and e.data then
			local storage = peripheral.wrap(stoName)
			if storage and storage.pushItems then
				for slot, item in pairs(e.data) do
					if item then
						if item.name == itemName then
							table.insert(exactSlots, {storage=storage, stoName=stoName, slot=slot, count=item.count, name=item.name})
						elseif hasAlts and altItems[item.name] then
							table.insert(altSlots,   {storage=storage, stoName=stoName, slot=slot, count=item.count, name=item.name})
						end
					end
				end
			end
		end
	end

	-- re-check the slot right before push. inv scan can be seconds stale,
	-- another coroutine may have grabbed the stack.
	-- push a stale entry = move whatever landed there = wrong item to the machine
	local function verifiedPush(entry)
		local okD, det = pcall(entry.storage.getItemDetail, entry.slot)
		if not (okD and det and det.name == entry.name and (det.count or 0) > 0) then
			entry.count = 0
			return
		end
		local toMove = math.min(amountNeeded - moved, det.count)
		local ok, mv = pcall(entry.storage.pushItems, targetMach, entry.slot, toMove, targetSlot)
		if ok and mv then moved = moved + mv end
		-- pinned slot refused a live source = wrong item or full. bail so caller
		-- picks next target instead of hammering all 55 sources into a dead slot.
		-- t.box delivery used to burn 10s+ per stuck slot with a big log stack
		if targetSlot and (mv or 0) == 0 then return "reject" end
	end

	for _, entry in ipairs(exactSlots) do
		if Craft.cancelled or moved >= amountNeeded then break end
		if verifiedPush(entry) == "reject" then break end
	end
	for _, entry in ipairs(altSlots) do
		if Craft.cancelled or moved >= amountNeeded then break end
		if verifiedPush(entry) == "reject" then break end
	end

	if moved < amountNeeded and targetMach then
		local mPeriph = peripheral.wrap(targetMach)
		if mPeriph and mPeriph.pullItems then
			local mSize = 9
			if mPeriph.size then
				local okSz, sz = pcall(mPeriph.size)
				if okSz and type(sz) == "number" then mSize = sz end
			end

			local function pullReverse(entries)
				for _, entry in ipairs(entries) do
					if moved >= amountNeeded then break end
					local okD, det = pcall(entry.storage.getItemDetail, entry.slot)
					if not (okD and det and det.name == entry.name and (det.count or 0) > 0) then
						entry.count = 0
					elseif targetSlot then
						local ok3, mv3 = pcall(mPeriph.pullItems, entry.stoName, entry.slot, amountNeeded - moved, targetSlot)
						if ok3 and type(mv3) == "number" and mv3 > 0 then
							moved = moved + mv3
						else
							return
						end
					else
						for mSlot = mSize, 1, -1 do
							if moved >= amountNeeded then break end
							local ok3, mv3 = pcall(mPeriph.pullItems, entry.stoName, entry.slot, amountNeeded - moved, mSlot)
							if ok3 and type(mv3) == "number" and mv3 > 0 then
								moved = moved + mv3
								break
							end
						end
					end
				end
			end

			if not Craft.cancelled then pullReverse(exactSlots) end
			if not Craft.cancelled then pullReverse(altSlots)   end
		end
	end

	if moved > 0 then resetStock() end
	return moved
end

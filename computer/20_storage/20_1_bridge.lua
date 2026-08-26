-- ME / RS bridge as a PROVIDER source. no list/pushItems on these, so they
-- cant go through the slot scan at all. we only export FROM them, importItem
-- is never called anywhere on purpose.
--
-- api names are AP 0.7.61, NOT the wiki: getItems/exportItem. exportItem takes
-- a side or a peripheral name and answers 0 plus a status string on a miss.

function isBridge(name)
	if not name or name == "" or name == "STORAGE" then return false end
	local p = peripheral.wrap(name)
	if not p then return false end
	return p.getItems ~= nil and p.exportItem ~= nil
end

function bridgeSrc()
	local out = {}
	for _, nm in ipairs(providerSrc()) do
		if isBridge(nm) then out[#out + 1] = nm end
	end
	return out
end

function bridgeStock()
	local out = {}
	for _, nm in ipairs(bridgeSrc()) do
		local b = peripheral.wrap(nm)
		if b then
			local ok, items = pcall(b.getItems)
			if ok and type(items) == "table" then
				for _, it in pairs(items) do
					if it and it.name then
						out[it.name] = (out[it.name] or 0) + (it.count or it.amount or 0)
					end
				end
			end
		end
	end
	return out
end

function bridgeExport(itemName, amount, dstName)
	if not dstName or amount <= 0 then return 0 end
	local moved = 0
	for _, nm in ipairs(bridgeSrc()) do
		if moved >= amount then break end
		local b = peripheral.wrap(nm)
		if b then
			local ok, mv, err = pcall(b.exportItem, {name = itemName, count = amount - moved}, dstName)
			if ok and type(mv) == "number" then moved = moved + mv end
			if not ok then err = mv end
			if err then
				dbgWrite(string.format("bridge.export %s -> %s : %s", shortName(itemName), tostring(dstName), tostring(err)))
			end
		end
	end
	if moved > 0 then resetStock() end
	return moved
end

-- park items in a real vault first. slot-pinned pushes (turtle grid, machine
-- input slots) need a source with slots and the bridge has none
function bridgeStage(itemName, amount)
	if amount <= 0 or #bridgeSrc() == 0 then return nil, 0 end
	for sName, isEnabled in pairs(Config.storages) do
		if isEnabled and not SYSTEM_SIDES[sName] then
			local mv = bridgeExport(itemName, amount, sName)
			if mv > 0 then return sName, mv end
		end
	end
	return nil, 0
end

function bridgeFeed(itemName, amount, dstName, dstSlot)
	if amount <= 0 or #bridgeSrc() == 0 then return 0 end
	if not dstSlot then return bridgeExport(itemName, amount, dstName) end
	local vault, staged = bridgeStage(itemName, amount)
	local sto = vault and peripheral.wrap(vault)
	if not sto then return 0 end
	local ok, items = pcall(sto.list)
	if not (ok and items) then return 0 end
	local moved = 0
	for slot, it in pairs(items) do
		if moved >= staged then break end
		if it and it.name == itemName then
			local ok2, mv = pcall(sto.pushItems, dstName, slot, staged - moved, dstSlot)
			if ok2 and mv then moved = moved + mv end
			if (mv or 0) == 0 then break end
		end
	end
	if moved > 0 then resetStock() end
	return moved
end

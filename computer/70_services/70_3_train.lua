function deliverTrain(itemName, amount)
	if not Config.train_box or Config.train_box == "" then return 0 end
	-- one scan for the whole delivery. else every safe-slot rescans every vault
	-- and a 3.5k-log chest turns 50-item request into seconds of dead calls
	local prescan = scanPeriph(scanStorage(), "list")
	local moved = 0
	-- skip the corner slots. physical shulker clips through them when
	-- it detaches from the rail. drop there = item lost to the void
	for _, targetSlot in ipairs(TRAINBOX_SAFE_SLOTS) do
		if moved >= amount then break end
		local got = pushFromStore(itemName, amount - moved, Config.train_box, targetSlot, prescan)
		moved = moved + got
	end
	return moved
end

function pullTrainAll()
	if not Config.train_box or Config.train_box == "" then return 0 end
	local box = peripheral.wrap(Config.train_box)
	if not box or not box.list or not box.pushItems then return 0 end
	local sortedStore = {}
	for sName, enabled in pairs(Config.storages) do
		if enabled then
			local p = peripheral.wrap(sName)
			if p and p.list and p.pullItems then table.insert(sortedStore, sName) end
		end
	end
	table.sort(sortedStore)
	if #sortedStore == 0 then return 0 end
	local totalMoved = 0
	local ok, items = pcall(box.list)
	if not ok or not items then return 0 end
	for slot, item in pairs(items) do
		if item then
			local remaining = item.count
			for _, stoName in ipairs(sortedStore) do
				if remaining <= 0 then break end
				local mv_ok, mv = pcall(box.pushItems, stoName, slot, remaining)
				if mv_ok and mv and mv > 0 then remaining = remaining - mv; totalMoved = totalMoved + mv end
			end
		end
	end
	return totalMoved
end


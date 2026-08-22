function runFluidScan(inputs, machineName, outputDevice, itemInputDevice, fluidInputDev, itemOutputDev)
	local machine = peripheral.wrap(machineName)
	if not (machine and machine.tanks and machine.pushFluid and machine.pullFluid) then
		return false, nil, {"Machine missing fluid methods:", machineName}
	end

	local fluidOutName = (outputDevice and outputDevice ~= "") and outputDevice or machineName
	local fluidOutObj  = (fluidOutName ~= machineName) and peripheral.wrap(fluidOutName) or machine
	if not fluidOutObj then return false, nil, {"Fluid output device offline:", fluidOutName} end

	local itemInName  = (itemInputDevice  and itemInputDevice  ~= "") and itemInputDevice  or machineName
	if itemInName  ~= machineName and not peripheral.wrap(itemInName)  then return false, nil, {"Item input device offline:",  itemInName}  end
	local fluidInName = (fluidInputDev and fluidInputDev ~= "") and fluidInputDev or machineName
	if fluidInName ~= machineName and not peripheral.wrap(fluidInName) then return false, nil, {"Fluid input device offline:", fluidInName} end
	local itemOutName = (itemOutputDev and itemOutputDev ~= "") and itemOutputDev or fluidOutName
	if itemOutName ~= machineName and not peripheral.wrap(itemOutName) then return false, nil, {"Item output device offline:", itemOutName} end

	local errLines = {}
	local inv = getFluid()
	for _, inp in ipairs(inputs) do
		local have = inv[fluidKey(inp.name)] or 0
		if have < inp.amount then
			table.insert(errLines, string.format("Need %d mB %s, have %d", inp.amount, inp.name, have))
		end
	end
	if #errLines > 0 then return false, nil, errLines end

	local before = machFluidSnap(fluidOutObj)
	local itemsBefore = machItemSnap(itemOutName)

	for _, inp in ipairs(inputs) do
		local m = pushFluidToMach(fluidInName, inp.name, inp.amount)
		if m < inp.amount then
			table.insert(errLines, string.format("Only pushed %d/%d mB %s", m, inp.amount, inp.name))
		end
	end

	local itemCounts = barrelToMach(itemInName)
	local inputSet = {}
	for _, inp in ipairs(inputs) do inputSet[inp.name] = true end
	local inputItemSet = {}
	for iname in pairs(itemCounts) do inputItemSet[iname] = true end

	local function drainAll()
		for fname in pairs(machFluidSnap(fluidOutObj)) do drainFluid(fluidOutName, fname, 1000000) end
		for fname in pairs(machFluidSnap(machine)) do
			if not inputSet[fname] then drainFluid(machineName, fname, 1000000) end
		end
		drainMachItems(machineName)
		if itemOutName ~= machineName then drainMachItems(itemOutName) end
		if itemInName  ~= machineName then drainMachItems(itemInName)  end
	end

	local outputs = {}
	local itemOutputs = {}
	local cancelled = false
	local separateOut = (fluidOutName ~= machineName) or (itemOutName ~= machineName)

	if separateOut then
		local fAgg, iAgg = {}, {}
		local quiet, sawAny = 0, false
		while true do
			if drawFluidCancel then drawFluidCancel() end
			sleepCancel(0.5)
			if Craft.cancelled then cancelled = true; break end
			local moved = false
			for fname, amt in pairs(machFluidSnap(fluidOutObj)) do
				if not inputSet[fname] and amt > 0 then
					local mv = drainFluid(fluidOutName, fname, 1000000)
					if mv and mv > 0 then fAgg[fname] = (fAgg[fname] or 0) + mv; moved = true; sawAny = true end
				end
			end
			local hadItems = false
			for iname, cnt in pairs(machItemSnap(itemOutName)) do
				if not inputItemSet[iname] and cnt > 0 then
					iAgg[iname] = (iAgg[iname] or 0) + cnt; moved = true; sawAny = true; hadItems = true
				end
			end
			if hadItems then drainMachItems(itemOutName) end
			-- 3s of silence after first output = done.
			-- sawAny gate is critical, some machines take 20+ sec to spit first drop
			if moved then quiet = 0 else quiet = quiet + 1 end
			if sawAny and quiet >= 6 then break end
		end
		for fname, amt in pairs(fAgg) do if amt > 0 then outputs[#outputs + 1] = {kind = "fluid", name = fname, amount = amt} end end
		for iname, cnt in pairs(iAgg) do if cnt > 0 then itemOutputs[#itemOutputs + 1] = {kind = "item", name = iname, count = cnt} end end
	else
		local after
		after, cancelled = waitFluidStable(fluidOutObj, fluidOutName, 0, true, drawFluidCancel)
		if not cancelled then
			for fname, amt in pairs(after) do
				if not inputSet[fname] then
					local net = amt - (before[fname] or 0)
					if net > 0 then outputs[#outputs + 1] = {kind = "fluid", name = fname, amount = net} end
				end
			end
			for iname, cnt in pairs(machItemSnap(itemOutName)) do
				if not inputItemSet[iname] then
					local net = cnt - (itemsBefore[iname] or 0)
					if net > 0 then itemOutputs[#itemOutputs + 1] = {kind = "item", name = iname, count = net} end
				end
			end
		end
	end

	local function drainFluidIn()
		if fluidInName ~= machineName then
			for fname in pairs(machFluidSnap(peripheral.wrap(fluidInName))) do drainFluid(fluidInName, fname, 1000000) end
		end
	end

	if cancelled then
		drainAll(); drainFluidIn(); sleep(0.3); drainAll(); drainFluidIn()
		return false, nil, {"Scan cancelled by user."}
	end

	table.sort(outputs,     function(a, b) return a.amount > b.amount end)
	table.sort(itemOutputs, function(a, b) return a.count  > b.count  end)
	-- double drain with 0.3s pause. create needs a tick to refill output tank
	-- from its buffer after drain 1. one drain leaves ~5% behind, two = clean
	drainAll(); drainFluidIn(); sleep(0.3); drainAll(); drainFluidIn()

	if #outputs == 0 and #itemOutputs == 0 then
		table.insert(errLines, "No output detected (fluid or item).")
		return false, nil, errLines
	end

	if Config.train_box and Config.train_box ~= "" then
		for _, io2 in ipairs(itemOutputs) do
			pushFromStore(io2.name, io2.count, Config.train_box)
		end
	end

	local recipeInputs = {}
	for _, inp in ipairs(inputs) do
		recipeInputs[#recipeInputs + 1] = {kind = "fluid", name = inp.name, amount = inp.amount}
	end
	local itemInputs = {}
	for iname, cnt in pairs(itemCounts) do
		itemInputs[#itemInputs + 1] = {kind = "item", name = iname, count = cnt}
	end

	return true, {
		machine_name       = machineName,
		output_device      = (outputDevice     and outputDevice     ~= "") and outputDevice     or nil,
		item_input_device  = (itemInputDevice  and itemInputDevice  ~= "") and itemInputDevice  or nil,
		fluid_input_device = (fluidInputDev and fluidInputDev ~= "") and fluidInputDev or nil,
		item_output_device = (itemOutputDev and itemOutputDev ~= "") and itemOutputDev or nil,
		inputs        = recipeInputs,
		item_inputs   = itemInputs,
		outputs       = outputs,
		item_outputs  = itemOutputs,
	}, nil
end

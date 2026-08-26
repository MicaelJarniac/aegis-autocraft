TRAINBOX_CRAFT_SLOTS = {[4]=true,[5]=true,[6]=true,[13]=true,[14]=true,[15]=true,[22]=true,[23]=true,[24]=true}
TRAINBOX_SAFE_SLOTS  = {}
for s = 1, 27 do if not TRAINBOX_CRAFT_SLOTS[s] then table.insert(TRAINBOX_SAFE_SLOTS, s) end end

function clearFluidDevs()
	learnOut = nil; fluidOutPick = false
	learnItemIn = nil; fluidItemInPick = false
	learnFluidIn = nil; fluidInPick = false
	learnItemOut = nil; itemOutPick = false
end

function drawFluidLearn(w, h, touchZones)
	local sumY = 12
	if #learnInputs > 0 then
		local parts = {}
		for _, inp in ipairs(learnInputs) do
			local sn = shortName(inp.name)
			parts[#parts + 1] = string.format("%s:%dmB", sn, inp.amount)
		end
		drawText(2, sumY, "Inputs: " .. table.concat(parts, "  "), colors.lime, colors.black)
	else
		drawText(2, sumY, "Inputs: (none yet)", colors.gray, colors.black)
	end
	if fluidLearnStage == "PICK_INPUT" then
		local hdr = "SELECT INPUT FLUIDS (optional - items read from barrel)"
		drawText(2, 13, hdr, colors.gray, colors.black)
		local selAmt = {}
		for _, inp in ipairs(learnInputs) do selAmt[inp.name] = inp.amount end
		local inv = getFluid()
		local avail = {}
		for fk, amt in pairs(inv) do
			avail[#avail + 1] = {name = fluidNameOf(fk), mb = amt}
		end
		table.sort(avail, function(a, b) return a.name < b.name end)
		if #avail == 0 then
			local noF = "No fluids in [TNK] tanks."
			drawText(math.floor((w - #noF) / 2) + 1, 16, noF, colors.gray)
		else
			local listY = 15
			local cols = 3
			local maxRows = h - listY - 4
			if maxRows < 1 then maxRows = 1 end
			local perPage = cols * maxRows
			local totalP = math.max(1, math.ceil(#avail / perPage))
			if fluidLearnPage > totalP then fluidLearnPage = totalP end
			if fluidLearnPage < 1 then fluidLearnPage = 1 end
			local sIdx = (fluidLearnPage - 1) * perPage + 1
			local eIdx = math.min(sIdx + perPage - 1, #avail)
			local colW = math.floor(w / cols)
			for ci = 1, cols - 1 do
				for ry = 0, maxRows - 1 do
					drawText(ci * colW, listY + ry, "|", colors.gray, colors.black)
				end
			end
			for fi = sIdx, eIdx do
				local li = fi - sIdx
				local col = math.floor(li / maxRows)
				local row = li % maxRows
				local rowY = listY + row
				local colX = col * colW + 1
				local f = avail[fi]
				local short = shortName(f.name)
				if fluidWaitInput == f.name then
					local lbl = short
					local maxName = colW - 5
					if #lbl > maxName then lbl = lbl:sub(1, maxName) end
					drawText(colX, rowY, "--", colors.yellow, colors.black)
					drawText(colX + 2, rowY, lbl, colors.yellow, colors.black)
					drawText(colX + 2 + #lbl, rowY, "--", colors.yellow, colors.black)
				elseif selAmt[f.name] then
					local lbl = short .. " " .. selAmt[f.name]
					local maxName = colW - 5
					if #lbl > maxName then lbl = lbl:sub(1, maxName) end
					drawText(colX, rowY, "--", colors.lime, colors.gray)
					drawText(colX + 2, rowY, lbl, colors.white, colors.gray)
					drawText(colX + 2 + #lbl, rowY, "--", colors.lime, colors.gray)
				else
					local lbl = short
					if #lbl > colW - 2 then lbl = lbl:sub(1, colW - 2) end
					drawText(colX, rowY, lbl, colors.lightGray, colors.black)
				end
				table.insert(touchZones, {id="fluid_pick_input", arg=f.name, x1=colX, x2=colX+colW-2, y=rowY})
			end
			if totalP > 1 then
				local navY = h - 3
				local pS = string.format("[PREV] %d/%d [NEXT]", fluidLearnPage, totalP)
				local navX = math.floor((w - #pS) / 2) + 1
				drawText(navX, navY, pS, colors.white, colors.black)
				table.insert(touchZones, {id="fluid_learn_prev", x1=navX, x2=navX+5, y=navY})
				table.insert(touchZones, {id="fluid_learn_next", x1=navX+#pS-6, x2=navX+#pS-1, y=navY})
			end
		end
		do
			local doneStr = " [ DONE ] "
			local doneX = math.floor((w - #doneStr) / 2) + 1
			drawText(doneX, h - 1, doneStr, colors.black, colors.lime)
			table.insert(touchZones, {id="fluid_learn_done_inputs", x1=doneX, x2=doneX+#doneStr-1, y=h-1})
		end
	elseif fluidLearnStage == "PICK_MACHINE" then
		local hdr = "SELECT MACHINE"
		drawText(2, 13, hdr, colors.gray, colors.black)
		local machines = listMachines()
		table.sort(machines, _cmpByDisplay)
		local listY = 15
		local cols = 3
		local maxRows = h - listY - 4
		if maxRows < 1 then maxRows = 1 end
		local perPage = cols * maxRows
		local totalP = math.max(1, math.ceil(#machines / perPage))
		if fluidLearnPage > totalP then fluidLearnPage = totalP end
		if fluidLearnPage < 1 then fluidLearnPage = 1 end
		local sIdx = (fluidLearnPage - 1) * perPage + 1
		local eIdx = math.min(sIdx + perPage - 1, #machines)
		local colW = math.floor(w / cols)
		for ci = 1, cols - 1 do
			for ry = 0, maxRows - 1 do
				drawText(ci * colW, listY + ry, "|", colors.gray, colors.black)
			end
		end
		for mi = sIdx, eIdx do
			local li = mi - sIdx
			local col = math.floor(li / maxRows)
			local row = li % maxRows
			local rowY = listY + row
			local colX = col * colW + 1
			local m = machines[mi]
			local isSel = (learnMach == m)
			local rroles = {}
			if learnItemIn  == m then rroles[#rroles + 1] = "II" end
			if learnFluidIn == m then rroles[#rroles + 1] = "FI" end
			if learnItemOut == m then rroles[#rroles + 1] = "IO" end
			if learnOut  == m then rroles[#rroles + 1] = "FO" end
			local rtag, rcol
			if #rroles == 1 then
				rtag = rroles[1] .. ":"
				rcol = (rroles[1] == "II" and colors.cyan)
				or (rroles[1] == "FI" and colors.lightBlue)
				or (rroles[1] == "IO" and colors.orange)
				or colors.lime
			elseif #rroles > 1 then
				rtag = table.concat(rroles, "/") .. ":"
				rcol = colors.magenta
			end
			if rtag then
				local nm = (isSel and ">" or "") .. (getMachName(m) or m)
				local maxName = colW - #rtag - 1
				if #nm > maxName then nm = nm:sub(1, maxName) end
				drawText(colX, rowY, rtag, colors.black, rcol)
				drawText(colX + #rtag, rowY, nm, colors.white, colors.gray)
			else
				local label = (isSel and "> " or "") .. (getMachName(m) or m)
				if #label > colW - 1 then label = label:sub(1, colW - 1) end
				drawText(colX, rowY, label, isSel and colors.white or colors.lightGray, isSel and colors.gray or colors.black)
			end
			table.insert(touchZones, {id="fluid_pick_machine", arg=m, x1=colX, x2=colX+colW-2, y=rowY})
		end
		if totalP > 1 then
			local navY = h - 3
			local pS = string.format("[PREV] %d/%d [NEXT]", fluidLearnPage, totalP)
			local navX = math.floor((w - #pS) / 2) + 1
			drawText(navX, navY, pS, colors.white, colors.black)
			table.insert(touchZones, {id="fluid_learn_prev", x1=navX, x2=navX+5, y=navY})
			table.insert(touchZones, {id="fluid_learn_next", x1=navX+#pS-6, x2=navX+#pS-1, y=navY})
		end
		if fluidScanStatus ~= "" then
			drawText(2, h - 3, fluidScanStatus, colors.yellow, colors.black)
			local cancStr = " [ CANCEL SCAN ] "
			local cancX = math.floor((w - #cancStr) / 2) + 1
			drawText(cancX, h - 1, cancStr, colors.white, colors.red)
			craftCancelY  = h - 1
			craftCancelX1 = cancX
			craftCancelX2 = cancX + #cancStr - 1
		elseif learnMach then
			local backS  = " BACK "
			local scanS  = " SCAN "
			local flOutS = " FL/OUT "
			local itOutS = " IT/OUT "
			local flInS  = " FL/INP "
			local itInS  = " IT/INP "
			local g = 1
			local rowW = #flOutS + g + #backS + g + #scanS + g + #itOutS
			local flOutX = math.floor((w - rowW) / 2) + 1
			local backX  = flOutX + #flOutS + g
			local scanX  = backX + #backS + g
			local itOutX = scanX + #scanS + g

			local function devCol(pick, set)
				if pick then return colors.black, colors.yellow
				elseif set then return colors.black, colors.lime
				else return colors.white, colors.gray end
			end
			local af, ab = devCol(fluidInPick, learnFluidIn ~= nil)
			drawText(flOutX, h-2, flInS, af, ab)
			table.insert(touchZones, {id="fluid_fluidin_toggle", x1=flOutX, x2=flOutX+#flInS-1, y=h-2})
			local bf, bb = devCol(fluidItemInPick, learnItemIn ~= nil)
			drawText(itOutX, h-2, itInS, bf, bb)
			table.insert(touchZones, {id="fluid_iteminput_toggle", x1=itOutX, x2=itOutX+#itInS-1, y=h-2})
			local cf, cb = devCol(fluidOutPick, learnOut ~= nil)
			drawText(flOutX, h-1, flOutS, cf, cb)
			table.insert(touchZones, {id="fluid_pull_toggle", x1=flOutX, x2=flOutX+#flOutS-1, y=h-1})
			local df, db = devCol(itemOutPick, learnItemOut ~= nil)
			drawText(itOutX, h-1, itOutS, df, db)
			table.insert(touchZones, {id="fluid_itemout_toggle", x1=itOutX, x2=itOutX+#itOutS-1, y=h-1})
			drawText(backX, h-1, backS, colors.white, colors.gray)
			table.insert(touchZones, {id="fluid_learn_back_inputs", x1=backX, x2=backX+#backS-1, y=h-1})
			drawText(scanX, h-1, scanS, colors.black, colors.lime)
			table.insert(touchZones, {id="fluid_learn_scan", x1=scanX, x2=scanX+#scanS-1, y=h-1})
		else
			local backS = " BACK "
			local sX = math.floor((w - #backS) / 2) + 1
			drawText(sX, h-1, backS, colors.white, colors.gray)
			table.insert(touchZones, {id="fluid_learn_back_inputs", x1=sX, x2=sX+#backS-1, y=h-1})
		end
	end
end

function runMachineSearch()
	if not Config.train_box or Config.train_box == "" then
		return "ERR: Assign Train Box in NETWORK!"
	end
	local trainBox = peripheral.wrap(Config.train_box)
	if not trainBox or not trainBox.getItemDetail then
		return "ERR: Train box offline!"
	end
	local barrelCenter = {4, 5, 6, 13, 14, 15, 22, 23, 24}
	local ingredients = {}
	local ingCnts = {}
	local hasItems = false
	local sampleItemName = "Unknown Item"
	for i = 1, 9 do
		local sourceSlot = barrelCenter[i]
		local success, item = pcall(function() return trainBox.getItemDetail(sourceSlot) end)
		if success and item then
			ingredients[i] = item.name
			ingCnts[i] = item.count or 1
			hasItems = true
			sampleItemName = item.name
		else
			ingredients[i] = "nil"
			ingCnts[i] = 0
		end
	end
	if not hasItems then return "ERR: Grid empty!" end
	learnedResult = nil
	learnedOutputs = nil
	learnedTools = {}
	if selCraftType == "turtle" then
		learnedIngs = ingredients
	else
		local flatIng = {}
		for i = 1, 9 do
			if ingredients[i] ~= "nil" then
				local cnt = ingCnts[i] or 1
				for _ = 1, cnt do
					flatIng[#flatIng + 1] = ingredients[i]
				end
			end
		end
		if #flatIng == 0 then flatIng[1] = "nil" end
		learnedIngs = flatIng
	end

	local function drawTest(stageDesc, curProg, maxProgress)
		local w, h = monitor.getSize()
		local pW, pH = math.min(w - 6, 56), 11
		local pX, pY = UI.popup(pW, pH, w, h, " RECIPE INTERACTIVE LEARNING ", "warn")
		UI.text(pX + 1, pY + 1, string.rep("-", pW - 2), UI.C.soft, UI.C.rowBg)
		local sName = shortName(sampleItemName)
		drawText(pX + 2, pY + 3, ("Testing: " .. sName):sub(1, pW - 4), colors.yellow, colors.gray)
		drawText(pX + 2, pY + 5, ("STATUS: " .. stageDesc):sub(1, pW - 4), colors.lightGray, colors.gray)
		if maxProgress and maxProgress > 0 then
			drawProgBar(pX + 2, pY + 7, pW - 10, curProg, maxProgress, colors.gray)
		end
		local cancStr = " [ CANCEL ] "
		local cancX = pX + math.floor((pW - #cancStr) / 2)
		drawText(cancX, pY + pH - 2, cancStr, colors.white, colors.red)
		craftCancelY  = pY + pH - 2
		craftCancelX1 = cancX
		craftCancelX2 = cancX + #cancStr - 1
		_bufFlush()
	end
	Craft.cancelled = false

	local function dumpToBarrel(p, pName)
		if not p then return end
		local ok, items = pcall(p.list)
		if ok and items then
			for slot, it in pairs(items) do
				if it then
					local moved = 0
					if p.pushItems then
						local o, m = pcall(p.pushItems, Config.train_box, slot, 64)
						if o and type(m) == "number" then moved = m end
					end
					if moved <= 0 and pName then
						pcall(trainBox.pullItems, pName, slot, 64)
					end
				end
			end
		end
	end
	if selCraftType == "turtle" then
		local firstTurtle = nil
		local tSorted = {}
		for tName, enabled in pairs(Config.turtles or {}) do
			if enabled then tSorted[#tSorted + 1] = tName end
		end
		table.sort(tSorted)
		for _, tName in ipairs(tSorted) do
			if peripheral.wrap(tName) then firstTurtle = tName; break end
		end
		if not firstTurtle then
			if #tSorted > 0 then return "ERR: Turtle offline: " .. tSorted[1] end
			return "ERR: Assign Turtle!"
		end
		learnedMach = firstTurtle
		learnedType = "turtle"
		learnedOut = nil
		drawTest("Clearing worker grid...", 1, 4)
		local turtleSlots = {1, 2, 3, 5, 6, 7, 9, 10, 11}
		for slot = 1, 16 do pcall(function() trainBox.pullItems(firstTurtle, slot, 64) end) end
		drawTest("Pushing test ingredients...", 2, 4)
		local pushedAny = false
		for i = 1, 9 do
			if ingredients[i] ~= "nil" then
				local okP, mvP = pcall(function() return trainBox.pushItems(firstTurtle, barrelCenter[i], 1, turtleSlots[i]) end)
				if okP and type(mvP) == "number" and mvP > 0 then pushedAny = true end
			end
		end
		if not pushedAny then
			dumpToBarrel(peripheral.wrap(firstTurtle), firstTurtle)
			return "ERR: Cannot push items to " .. firstTurtle
		end
		drawTest("Awaiting turtle processing...", 3, 4)
		while true do
			drawTest("Awaiting turtle (cancel to abort)...")
			sleepCancel(0.4)
			if Craft.cancelled then
				for slot = 1, 16 do pcall(function() trainBox.pullItems(firstTurtle, slot, 64) end) end
				craftCancelY = nil
				learnState = "IDLE"
				return "Learning cancelled."
			end
			local moved = 0
			local targetSlot = nil
			for _, bSlot in ipairs(TRAINBOX_SAFE_SLOTS) do
				local ok, mv = pcall(function() return trainBox.pullItems(firstTurtle, 16, 64, bSlot) end)
				if ok and mv and mv > 0 then
					moved = mv
					targetSlot = bSlot
					break
				end
			end
			if moved > 0 and targetSlot then
				learnedResult = trainBox.getItemDetail(targetSlot)
				break
			end
		end
		for _, tslot in ipairs({1, 2, 3, 5, 6, 7, 9, 10, 11}) do
			for _, bSlot in ipairs(TRAINBOX_SAFE_SLOTS) do
				local okE, detE = pcall(function() return trainBox.getItemDetail(bSlot) end)
				if not (okE and detE) then
					local ok, mv = pcall(function() return trainBox.pullItems(firstTurtle, tslot, 64, bSlot) end)
					if ok and mv and mv > 0 then
						local okD, det = pcall(function() return trainBox.getItemDetail(bSlot) end)
						if okD and det and det.name then learnedTools[det.name] = true end
					end
					break
				end
			end
		end
		drawTest("Analyzing output data...")
	else
		learnedMach = selCraftType
		learnedType = "machine"
		learnedOut = nil
		if selOut and selOut ~= selCraftType then
			learnedOut = selOut
		end
		local machObj = peripheral.wrap(learnedMach)
		if not machObj or not machObj.list then return "ERR: Machine offline!" end
		local outputObj = machObj
		if learnedOut then
			local oo = peripheral.wrap(learnedOut)
			if not oo or not oo.list then return "ERR: Output device offline!" end
			outputObj = oo
		end
		drawTest("Scanning machine state...", 1, 3)
		local learnExcluded = {}
		local sPre, preItems = pcall(machObj.list)
		if sPre and preItems then
			for _, preItem in pairs(preItems) do
				if preItem then learnExcluded[preItem.name] = true end
			end
		end
		if learnedOut then
			local sPreO, preItemsO = pcall(outputObj.list)
			if sPreO and preItemsO then
				for _, preItem in pairs(preItemsO) do
					if preItem then learnExcluded[preItem.name] = true end
				end
			end
		end
		local learnMachSize = 9
		if machObj.size then
			local okSz, sz = pcall(machObj.size)
			if okSz and type(sz) == "number" then learnMachSize = sz end
		end
		for i = 1, 9 do
			if ingredients[i] ~= "nil" then
				learnExcluded[ingredients[i]] = true
				local fromSlot = barrelCenter[i]
				local needCount = ingCnts[i] or 1
				local pushed = false
				if machObj.pullItems then
					for mSlot = learnMachSize, 1, -1 do
						local ok1, mv1 = pcall(machObj.pullItems, Config.train_box, fromSlot, needCount, mSlot)
						if ok1 and type(mv1) == "number" and mv1 > 0 then
							pushed = true
							break
						end
					end
				end
				if not pushed then
					pcall(trainBox.pushItems, learnedMach, fromSlot, needCount)
				end
			end
		end
		local prevSig, stableCount = nil, 0
		while true do
			drawTest("Waiting for output (cancel to abort)...")
			sleepCancel(0.5)
			if Craft.cancelled then break end
			local present = false
			local sig = {}
			local sList, mList = pcall(outputObj.list)
			if sList and mList then
				for _, mItem in pairs(mList) do
					if mItem and not learnExcluded[mItem.name] then
						present = true
						sig[#sig + 1] = mItem.name .. "=" .. (mItem.count or 0)
					end
				end
			end
			if present then
				table.sort(sig)
				local s = table.concat(sig, ",")
				if s == prevSig then stableCount = stableCount + 1 else stableCount = 0 end
				prevSig = s
				if stableCount >= 2 then break end
			end
		end
		if Craft.cancelled then
			dumpToBarrel(machObj, learnedMach)
			if outputObj ~= machObj then dumpToBarrel(outputObj, learnedOut) end
			craftCancelY = nil
			learnState = "IDLE"
			return "Learning cancelled."
		end
		drawTest("Collecting outputs...")
		local outAgg = {}
		local sFin, mFin = pcall(outputObj.list)
		if sFin and mFin then
			for slot, mItem in pairs(mFin) do
				if mItem and not learnExcluded[mItem.name] then
					outAgg[mItem.name] = (outAgg[mItem.name] or 0) + (mItem.count or 0)
					for _, bSlot in ipairs(TRAINBOX_SAFE_SLOTS) do
						local ok2, mv2 = pcall(function() return outputObj.pushItems(Config.train_box, slot, mItem.count, bSlot) end)
						if ok2 and mv2 and mv2 > 0 then break end
					end
				end
			end
		end
		learnedOutputs = {}
		for nm, cnt in pairs(outAgg) do learnedOutputs[#learnedOutputs + 1] = {name = nm, count = cnt} end
		table.sort(learnedOutputs, function(a, b)
				if a.count ~= b.count then return a.count > b.count end
				return a.name < b.name
			end)
		if learnedOutputs[1] then
			learnedResult = {name = learnedOutputs[1].name, count = learnedOutputs[1].count}
		end
	end
	craftCancelY = nil
	if learnedResult then
		learnState = "AWAITING_DECISION"
		local hItem = learnedResult.name
		for hi = #craftHistory, 1, -1 do
			if craftHistory[hi].item == hItem then table.remove(craftHistory, hi) end
		end
		table.insert(craftHistory, 1, {item = hItem, qty = learnedResult.count or 1})
		if #craftHistory > 30 then table.remove(craftHistory) end
		return "Success! Confirm entry."
	else
		learnState = "IDLE"
		return "ERR: Process failed!"
	end
end


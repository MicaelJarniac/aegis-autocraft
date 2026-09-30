-- crafter teach flow. player locks the grid, puts the recipe into the crafters
-- by hand, hits SCAN. we read every cell, unlock + pulse, catch the result in
-- the crafter output inv and hand it to T.BOX (or vaults when no T.BOX).
learnedGridCells = nil

local function crafterLearnPopup(stage)
	local w, h = monitor.getSize()
	local pW, pH = math.min(w - 6, 56), 9
	local pX, pY = UI.popup(pW, pH, w, h, " CRAFTER LEARNING ", "warn")
	drawText(pX + 2, pY + 3, ("STATUS: " .. stage):sub(1, pW - 4), colors.lightGray, colors.gray)
	local cancStr = " [ CANCEL ] "
	local cancX = pX + math.floor((pW - #cancStr) / 2)
	drawText(cancX, pY + pH - 2, cancStr, colors.white, colors.red)
	craftCancelY  = pY + pH - 2
	craftCancelX1 = cancX
	craftCancelX2 = cancX + #cancStr - 1
	_bufFlush()
end

local function toTrainOrVault(got)
	local c = crafterCfg()
	local o = peripheral.wrap(c.out)
	if not (o and o.pushItems) then return end
	for slot, it in pairs(crafterOutList()) do
		if it then
			local moved = 0
			if Config.train_box and Config.train_box ~= "" then
				for _, bSlot in ipairs(TRAINBOX_SAFE_SLOTS) do
					local ok, mv = pcall(o.pushItems, Config.train_box, slot, it.count, bSlot)
					if ok and type(mv) == "number" then moved = moved + mv end
					if moved >= it.count then break end
				end
			end
			if moved < it.count then
				for _, s in ipairs(pushStoList()) do
					local ok, mv = pcall(o.pushItems, s, slot, it.count - moved)
					if ok and type(mv) == "number" then moved = moved + mv end
					if moved >= it.count then break end
				end
			end
		end
	end
	resetStock()
end

function runCrafterSearch()
	local ok, why = crafterReady()
	if not ok then return "ERR: crafter " .. tostring(why) end
	local ings, rErr = crafterReadCells()
	if not ings then return "ERR: " .. tostring(rErr) end
	local any = false
	for _, v in ipairs(ings) do if v ~= "nil" then any = true; break end end
	if not any then return "ERR: Crafter grid empty!" end

	Craft.cancelled = false
	learnedResult, learnedOutputs, learnedTools = nil, nil, {}
	crafterLearnPopup("Clearing crafter output...")
	-- leftovers in the output inv would be read as the result
	crafterDrainOut(pushStoList())
	if next(crafterOutList()) then
		return "ERR: crafter output not empty (vaults full?)"
	end

	crafterLearnPopup("Starting crafters...")
	local started, sErr = crafterStart(ings)
	if Craft.cancelled then
		pcall(crafterSetLock, true); craftCancelY = nil
		return "Learning cancelled."
	end
	if not started then
		pcall(crafterSetLock, true); craftCancelY = nil
		if sErr then return "ERR: " .. tostring(sErr) end
		return "ERR: crafters didn't start (empty cells need PULSE)"
	end

	local t, prevSig, stable, agg = 0, nil, 0, nil
	while t < CRAFTER_TIMEOUT do
		crafterLearnPopup(string.format("Waiting for result... %ds", math.floor(t)))
		sleepCancel(0.5)
		t = t + 0.5
		if Craft.cancelled then break end
		local cur, sig = {}, {}
		for _, it in pairs(crafterOutList()) do
			if it then
				cur[it.name] = (cur[it.name] or 0) + (it.count or 0)
				sig[#sig + 1] = it.name .. "=" .. (it.count or 0)
			end
		end
		table.sort(sig)
		local s = table.concat(sig, ",")
		if s ~= "" and s == prevSig then stable = stable + 1 else stable = 0 end
		prevSig = s
		if stable >= 2 then agg = cur; break end
	end
	craftCancelY = nil
	if Craft.cancelled then
		-- dont relock mid-craft, the chain would freeze holding the items
		return "Learning cancelled. Result lands in crafter output."
	end
	if not agg then
		pcall(crafterSetLock, true)
		return "ERR: no result (invalid recipe? items dropped at crafters)"
	end

	local name, cnt = crafterPickResult(agg)
	toTrainOrVault(agg)
	pcall(crafterSetLock, true)

	learnedIngs      = ings
	learnedGridCells = {}
	for i, n in ipairs(crafterCfg().cells) do learnedGridCells[i] = n end
	learnedType   = "crafter"
	learnedMach   = CRAFTER_MACHINE
	learnedOut    = nil
	learnedResult = {name = name, count = cnt}
	learnState    = "AWAITING_DECISION"
	for hi = #craftHistory, 1, -1 do
		if craftHistory[hi].item == name then table.remove(craftHistory, hi) end
	end
	table.insert(craftHistory, 1, {item = name, qty = cnt or 1})
	if #craftHistory > 30 then table.remove(craftHistory) end
	return "Success! Confirm entry."
end

function drawCrafterLearn(w, h, touchZones)
	local c = crafterCfg()
	local y = 13
	local nOn = 0
	for _, n in ipairs(c.cells) do if peripheral.wrap(n) then nOn = nOn + 1 end end
	local found = #detectCrafters()
	local gridCol = (#c.cells > 0 and nOn == #c.cells) and UI.C.accent or UI.C.danger
	UI.text(2, y, string.format("Grid:   %d crafters registered (%d online, %d on network)",
		#c.cells, nOn, found), gridCol)
	UI.btnR(touchZones, w - 1, y, " [DETECT GRID] ", found ~= #c.cells and "warn" or "mute", "crafter_detect")

	local function devLine(yy, label, name, side)
		local on = name and peripheral.wrap(name)
		local txt = name and (getMachName(name) .. (side and (" @" .. side) or "")) or "<not set - tag in NETWORK>"
		UI.text(2, yy, label, UI.C.muted)
		UI.text(10, yy, txt:sub(1, w - 12), name and (on and UI.C.fg or UI.C.danger) or UI.C.danger)
	end
	devLine(y + 1, "Clutch:", c.clutch, c.clutch_side)
	devLine(y + 2, "Pulse:",  c.pulse,  c.pulse_side)
	if not c.pulse then UI.text(10, y + 2, "<optional - needed for recipes with empty cells>", UI.C.muted) end
	devLine(y + 3, "Output:", c.out)

	local lk = crafterLocked()
	local lkS, lkStyle = " [ NO RELAY ] ", "mute"
	if lk == true then lkS, lkStyle = " [ LOCKED - place recipe ] ", "warn"
	elseif lk == false then lkS, lkStyle = " [ RUNNING - tap to LOCK ] ", "ok" end
	UI.btn(touchZones, math.floor((w - #lkS) / 2) + 1, y + 5, lkS, lkStyle, "crafter_lock_toggle")

	UI.textC(y + 7, w, "LOCK, place the recipe into the crafters, then SCAN.", UI.C.muted)
	UI.textC(y + 8, w, "Crafter inputs must NOT be wrench-connected.", UI.C.soft)
end

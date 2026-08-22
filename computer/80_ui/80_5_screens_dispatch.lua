function drawHeader(w, stockInv)
	local si, totalCount, vaultsCnt, freeSlots, totalSlots
	local tFree, tTotal
	if curTab == "QUANTITY_PICKER" then
		if not pickerHdr then
			local pi, pc, pv, pf, ps = getInvCached()
			local ptf, ptt = getTankStats()
			pickerHdr = {inv = pi, count = pc, vaults = pv, free = pf, slots = ps, tFree = ptf, tTotal = ptt, fluidInv = getFluid()}
		end
		local snap = pickerHdr
		si, totalCount, vaultsCnt, freeSlots, totalSlots = snap.inv, snap.count, snap.vaults, snap.free, snap.slots
		tFree, tTotal = snap.tFree, snap.tTotal
	else
		pickerHdr = nil
		si, totalCount, vaultsCnt, freeSlots, totalSlots = getInvCached()
		tFree, tTotal = getTankStats()
	end
	stockInv = si
	local totalTypes = 0 for _ in pairs(Recipe.all()) do totalTypes = totalTypes + 1 end
	local freeColor = colors.gray
	if totalSlots > 0 then
		local pct = freeSlots / totalSlots
		if pct < 0.1 then freeColor = colors.red
		elseif pct < 0.25 then freeColor = colors.orange
		else freeColor = colors.lime
		end
	end
	local freeVal = string.format("%d/%d", freeSlots, totalSlots)
	local freeX = math.max(1, math.floor((w - #freeVal) / 2) + 1)
	drawText(freeX, 3, freeVal, freeColor, colors.black)
	local statStr
	if tTotal > 0 then
		statStr = string.format("Tank: %d/%d | Vaults: %d | Types: %d | Total: %d", tFree, tTotal, vaultsCnt, totalTypes, totalCount)
	else
		statStr = string.format("Vaults: %d | Types: %d | Total: %d", vaultsCnt, totalTypes, totalCount)
	end
	local statX = math.max(1, math.floor((w - #statStr) / 2) + 1)
	drawText(statX, 4, statStr, colors.gray, colors.black)
	return stockInv
end


-- deferFlush=true = popup driver draws on top and flushes itself.
-- flushing base frame first made the monitor briefly show a popup-less
-- frame between the two flushes = single-tick flicker.
drawUI = function(deferFlush)
	local w, h = monitor.getSize()
	_bufInit(w, h)
	local popupRect = nil
	local popupZoneS = 1
	do
		local logoX = math.max(1, math.floor((w - 25) / 2) + 1)
		UI.text(logoX,      2, ">>[ ",             UI.C.accent)
		UI.text(logoX + 4,  2, "A . E . G . I . S", UI.C.fg)
		UI.text(logoX + 21, 2, " ]<<",             UI.C.accent)
	end
	local stockInv
	stockInv = drawHeader(w, stockInv)
	UI.rule(5, w)
	local tabY = 6
	local touchZones = {}
	local displayTab = (curTab == "QUANTITY_PICKER") and qtyOrigTab or curTab
	do
		local nextX = 2
		for _, tab in ipairs({"RECIPES","STOCK","LOGISTIC","KEEP","+RECIPES","GROUPS","NETWORK","SERVICE"}) do
			nextX = drawTabBtn(nextX, tabY, tab, displayTab, touchZones)
		end
	end
	UI.rule(tabY + 2, w)
	if Config.autostock_paused then
		UI.text(2, h - 1, "[AUTOSTOCK PAUSED]", UI.C.fg, UI.C.danger)
	else
		if asItem ~= "" then
			local asName = shortName(asItem)
			UI.text(2, h - 1, ("[AS> " .. asName .. "]"):sub(1, math.floor(w / 2) - 2), UI.C.accent)
		end
		local sMap = {
			IDLE         = {"[SYS IDLE]",           UI.C.muted},
			MANUAL_CRAFT = {"[MANUAL CRAFTING...]", UI.C.hi},
			AUTO_CRAFT   = {"[AUTOCRAFT ACTIVE]",   UI.C.accent},
		}
		local st = sMap[sysStatus] or sMap.IDLE
		if Craft.failed then st = {"[CRAFT FAIL - WINDING DOWN]", UI.C.danger} end
		UI.text(w - #st[1] - 1, h - 1, st[1], st[2])
	end
	if displayTab == "RECIPES" then
		drawRecTab(w, h, stockInv, touchZones)
	elseif displayTab == "ALT_VIEW" then
		drawAltTab(w, h, touchZones)
	elseif displayTab == "KEEP" then
		drawKeepTab(w, h, stockInv, touchZones)
	elseif displayTab == "STOCK" then
		drawStockTab(w, h, stockInv, touchZones)
	elseif displayTab == "+RECIPES" then
		drawPlusTab(w, h, touchZones)
	elseif displayTab == "GROUPS" then
		popupRect = drawGroupsTab(w, h, touchZones, popupRect)
	elseif displayTab == "NETWORK" then
		drawNetTab(w, h, touchZones)
	elseif displayTab == "SERVICE" then
		drawGitTab(w, h, touchZones)
	elseif displayTab == "LOGISTIC" then
		drawLogTab(w, h, touchZones)
		if mgmtPopup then
			local pW = math.min(w - 4, 58)
			local pX = math.floor((w - pW) / 2) + 1
			if mgmtPopup.mode == "edit" then
				local step = mgmtPopup.step or "main"
				if step == "main" then
					popupRect, popupZoneS = drawMgmtEdit(w, h, touchZones, popupRect, popupZoneS)
				elseif step == "input_select" then
					popupRect, popupZoneS = drawMgmtInputSel(w, h, touchZones, popupRect, popupZoneS)
				elseif step == "item_select" then
					popupRect, popupZoneS = _drawMgmtItemPicker(w, h, touchZones)
				elseif step == "output_select" then
					popupRect, popupZoneS = drawMgmtOutSel(w, h, touchZones, popupRect, popupZoneS)
				end
			elseif mgmtPopup.mode == "view_input" then
				local grp2 = MgmtGroups[mgmtPopup.groupIdx]
				if grp2 then
					popupRect, popupZoneS = drawMgmtInput(w, grp2, h, touchZones, popupRect, popupZoneS)
				end
			end
		end
	end
	if curTab == "QUANTITY_PICKER" then
		popupRect = drawQtyPicker(w, h, stockInv, touchZones, popupRect)
	elseif queueEditPopup then
		popupRect = _diQueuePopup(w, h, touchZones, popupRect)
	elseif historyPopup then
		popupRect = drawHistory(w, h, stockInv, touchZones, popupRect)
	elseif craftDonePopup then
		popupRect = drawCraftDone(w, h, touchZones, popupRect)
	elseif recipeEditPop then
		popupRect = drawRecipeEdit(w, h, touchZones, popupRect)
	elseif fluidSaveConfirm then
		popupRect = drawFluidSave(w, h, touchZones, popupRect)
	elseif fluidRecipePicker then
		popupRect = drawFluidPicker(w, h, touchZones, popupRect)
	elseif machInfoPopup then
		local pW, pH = math.min(w - 4, 50), 7
		local pX, pY, rect = UI.popup(pW, pH, w, h, " MACHINE NOT FOUND ", "warn")
		popupRect = rect
		local sName = shortName(machInfoPopup.item)
		local mDisp = getMachName(machInfoPopup.machineName or "?")
		UI.text(pX + 2, pY + 2, ("Recipe:  " .. sName):sub(1, pW - 4), UI.C.fg, UI.C.rowBg)
		UI.text(pX + 2, pY + 3, ("Machine: " .. mDisp):sub(1, pW - 4), UI.C.warn, UI.C.rowBg)
		UI.text(pX + 2, pY + 4, "Not connected to the network.", UI.C.soft, UI.C.rowBg)
		UI.btnP(touchZones, pX + math.floor((pW - 11) / 2), pY + pH - 1, " [ CLOSE ] ", "mute", "close_machine_info")
	elseif craftInfoPop then
		local data = recipesScan[craftInfoPop.item]
		if not data then
			craftInfoPop = nil
		else
			popupRect = drawCraftInfo(w, h, touchZones, popupRect, data)
		end
	elseif fluidCraftInfo then
		popupRect = drawFluidInfo(w, h, touchZones, popupRect)
	elseif #craftErrLines > 0 then
		local panelTop = math.max(9, h - #craftErrLines)
		local hdr = craftErrTitle or "! NOT ENOUGH RESOURCES"
		if hdr == "! NEED" then
			_bufClearLine(panelTop, colors.yellow)
			UI.text(2, panelTop, hdr:sub(1, w - 2), UI.C.bg, UI.C.hi)
		else
			_bufClearLine(panelTop, colors.red)
			UI.text(2, panelTop, hdr:sub(1, w - 2), UI.C.fg, UI.C.danger)
		end
		for li, line in ipairs(craftErrLines) do
			local ly = panelTop + li
			if ly <= h then
				_bufClearLine(ly, colors.gray)
				local editItem = (craftErrTitle == "! MACHINE NOT FOUND") and craftErrEdit[li]
				if editItem and Recipe.find(editItem) then
					UI.text(2, ly, line:sub(1, w - 9), UI.C.fg, UI.C.rowBg)
					UI.btnP(touchZones, w - 6, ly, " [E] ", "warn", "error_edit_machine", editItem)
				else
					UI.text(2, ly, line:sub(1, w - 2), UI.C.fg, UI.C.rowBg)
				end
			end
		end
	end
	if popupRect then
		if popupZoneS and popupZoneS > 1 then
			local filtered = {}
			for i = popupZoneS, #touchZones do
				table.insert(filtered, touchZones[i])
			end
			touchZones = filtered
		end
		for shieldY = popupRect.y1, popupRect.y2 do
			table.insert(touchZones, {id="popup_bg", x1=popupRect.x1, x2=popupRect.x2, y=shieldY})
		end
	end
	for bgRow = 1, h do
		table.insert(touchZones, {id="bg_click", x1=1, x2=w, y=bgRow})
	end
	if not deferFlush then _bufFlush() end
	return touchZones
end


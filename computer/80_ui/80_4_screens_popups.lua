function drawCondRow(pX, pW, ry, rule, ri, touchZones)
	local cond = rule.condition
	_bufFillRect(pX + 1, ry, pW - 2, 1, colors.lightGray)
	if not (cond and cond.item and cond.item ~= "") then
		drawText(pX + 2, ry, "[+IF]", colors.gray, colors.lightGray)
		drawText(pX + 8, ry, "add condition", colors.gray, colors.lightGray)
		UI.zone(touchZones, "mgmt_rule_if_add", ri, pX + 2, ry, 5)
		return
	end
	local opStr = "[" .. (cond.op or "<") .. "]"
	local cVal  = tostring(cond.value or 1)
	local delX  = pX + pW - 7
	local typX  = delX - 5
	local plusX = typX - 5
	local valX  = plusX - #cVal
	local minX  = valX - 5
	local opX   = minX - #opStr - 2
	local nameX = pX + 5
	drawText(pX + 2, ry, "IF ", colors.orange, colors.lightGray)
	drawText(nameX, ry, shortName(cond.item):sub(1, math.max(0, opX - nameX)), colors.lime, colors.lightGray)
	drawText(opX,   ry, " " .. opStr .. " ", colors.black, colors.yellow)
	drawText(minX,  ry, " [-] ", colors.white, colors.lightGray)
	drawText(valX,  ry, cVal, colors.yellow, colors.lightGray)
	drawText(plusX, ry, " [+] ", colors.white, colors.lightGray)
	drawText(typX,  ry, " [#] ", colors.black, colors.orange)
	drawText(delX,  ry, " [X] ", colors.white, colors.red)
	UI.zone(touchZones, "mgmt_rule_if_item", ri,        nameX, ry, opX - nameX)
	UI.zone(touchZones, "mgmt_rule_if_op",   ri,        opX,   ry, #opStr + 2)
	UI.zone(touchZones, "mgmt_rule_if_adj",  {ri, -1},  minX,  ry, 5)
	UI.zone(touchZones, "mgmt_rule_if_adj",  {ri,  1},  plusX, ry, 5)
	UI.zone(touchZones, "mgmt_rule_if_type", ri,        typX,  ry, 5)
	UI.zone(touchZones, "mgmt_rule_if_del",  ri,        delX,  ry, 5)
end


function _drawGitPopup(w, h, touchZones, ctx)
	local pW     = math.min(56, w - 4)
	local maxVis = math.min(ctx.maxV, math.max(1, h - 17 + (ctx.extraHdr == 2 and 1 or 0)))
	local totLP  = math.max(1, math.ceil(#ctx.list / maxVis))
	local page   = ctx.page
	if page > totLP then page = totLP end
	local hasNav = totLP > 1
	local pH = math.min(ctx.extraHdr + maxVis + (hasNav and 1 or 0) + 1, h - 10)
	local pX, pY = UI.popup(pW, pH, w, h, ctx.hdr, ctx.hdrStyle, 9)
	local listY = pY + 2
	if ctx.newRow then
		local isNew = (ctx.sel == 0)
		drawText(pX + 2, listY, (isNew and "> " or "  ") .. ctx.newRow,
			isNew and colors.black or colors.lime, isNew and colors.lime or colors.gray)
		UI.zoneP(touchZones, ctx.selectId, 0, pX + 2, listY, pW - 4)
		listY = listY + 1
	end
	local iStart = (page - 1) * maxVis + 1
	local iEnd   = math.min(iStart + maxVis - 1, #ctx.list)
	for i = iStart, iEnd do
		local isSel = (i == ctx.sel)
		local selBg = ctx.selStyle == "warn" and colors.orange or colors.lime
		drawText(pX + 2, listY, ((isSel and "> " or "  ") .. ctx.list[i].name):sub(1, pW - 4),
			isSel and colors.black or colors.white, isSel and selBg or colors.gray)
		UI.zoneP(touchZones, ctx.selectId, i, pX + 2, listY, pW - 4)
		listY = listY + 1
	end
	if hasNav then
		UI.miniPager(touchZones, pY + pH - 2, pX + math.floor(pW / 2), page, totLP, ctx.prevId, ctx.nextId, true)
	end
	local btnY = pY + pH - 1
	UI.btnP(touchZones, pX + 2, btnY, ctx.confirmS, "ok", ctx.confirmId)
	UI.btnP(touchZones, pX + pW - #ctx.cancelS - 2, btnY, ctx.cancelS, "mute", ctx.cancelId)
	return page
end


function drawRecipeEdit(w, h, touchZones, popupRect)
	local rec
	if recipeEditPop.fluid then
		rec = recipeEditPop.fluidRecipeRef
	elseif recipeEditPop.altIdx then
		local alts = Recipe.altsOf(recipeEditPop.item)
		rec = alts and alts[recipeEditPop.altIdx]
	else
		rec = Recipe.find(recipeEditPop.item)
	end
	if not rec then
		recipeEditPop = nil
		return popupRect
	end
	local sName = shortName(recipeEditPop.fluid or recipeEditPop.item)
	local allM = {}
	for tName, enabled in pairs(Config.turtles or {}) do
		if enabled then allM[#allM + 1] = tName end
	end
	table.sort(allM)
	local mList = listMachines()
	table.sort(mList, _cmpByDisplay)
	for _, m in ipairs(mList) do allM[#allM + 1] = m end
	local pW = math.min(w - 10, 76)
	local pH = math.min(h - 4, 19)
	local cols = 3
	local cw = math.floor((pW - 2) / cols)
	local maxRows = pH - 7
	local perPage = cols * maxRows
	local pages = math.max(1, math.ceil(#allM / perPage))
	local page  = recipeEditPop.page or 1
	if page > pages then page = pages; recipeEditPop.page = page end
	local pX, pY, rect = UI.popup(pW, pH, w, h, " EDIT RECIPE: " .. sName:upper():sub(1, pW - 16) .. " ", "warn")
	popupRect = rect
	local curM = rec.machine_name or "?"
	UI.text(pX + 2, pY + 2, "Current: " .. getMachName(curM), UI.C.fg, UI.C.rowBg)
	if recipeEditPop.confirmGlobal then
		local n = 0
		if recipeEditPop.isItemScope then
			local iRec = Recipe.find(recipeEditPop.item)
			if iRec and iRec.machine_name == curM then n = n + 1 end
			for _, alt in ipairs(Recipe.altsOf(recipeEditPop.item) or {}) do
				if alt.machine_name == curM then n = n + 1 end
			end
		else
			for _, rData in pairs(Recipe.all()) do
				if rData.machine_name == curM then n = n + 1 end
			end
		end
		local scopeLbl = recipeEditPop.isItemScope and "This item only:" or "Replace ALL:"
		local newDisp  = getMachName(recipeEditPop.selected or curM)
		UI.text(pX + 2, pY + 4, scopeLbl .. " " .. getMachName(curM), UI.C.hi, UI.C.rowBg)
		UI.text(pX + 2, pY + 5, "       -> " .. newDisp, UI.C.accent, UI.C.rowBg)
		UI.text(pX + 2, pY + 6, "Affects " .. n .. " recipes!", UI.C.danger, UI.C.rowBg)
		local cfmStr, cnlStr = " [ CONFIRM REPLACE ALL ] ", " [ CANCEL ] "
		UI.btnP(touchZones, pX + math.floor((pW - #cfmStr) / 2), pY + pH - 3, cfmStr, "danger", "recipe_edit_confirm_global")
		UI.btnP(touchZones, pX + math.floor((pW - #cnlStr) / 2), pY + pH - 1, cnlStr, "mute", "close_recipe_edit")
		return popupRect
	end
	UI.text(pX + 2, pY + 3, "Select machine:", UI.C.soft, UI.C.rowBg)
	local listTop = pY + 4
	for ci = 1, cols - 1 do
		local sepX = pX + 1 + ci * cw
		for ry = 0, maxRows - 1 do
			UI.text(sepX, listTop + ry, "|", UI.C.soft, UI.C.rowBg)
		end
	end
	local mStart = (page - 1) * perPage + 1
	local mEnd   = math.min(mStart + perPage - 1, #allM)
	for i = mStart, mEnd do
		local li = i - mStart
		local cellX = pX + 2 + math.floor(li / maxRows) * cw
		local cellY = listTop + (li % maxRows)
		local nm    = allM[i]
		local disp  = getMachName(nm)
		local isSel = (nm == recipeEditPop.selected)
		local isCur = (nm == curM)
		if #disp > cw - 2 then disp = disp:sub(1, cw - 2) end
		drawText(cellX, cellY, disp,
			isSel and colors.black or (isCur and colors.lime or colors.white),
			isSel and colors.lime or colors.gray)
		UI.zoneP(touchZones, "recipe_edit_select", nm, cellX, cellY, cw - 1)
	end
	local navY = pY + pH - 2
	drawText(pX + 2, navY, " < ", page > 1 and colors.white or colors.lightGray, colors.gray)
	drawText(pX + pW - 5, navY, " > ", page < pages and colors.white or colors.lightGray, colors.gray)
	if page > 1     then UI.zoneP(touchZones, "recipe_edit_prev", nil, pX + 2, navY, 3) end
	if page < pages then UI.zoneP(touchZones, "recipe_edit_next", nil, pX + pW - 5, navY, 3) end
	local btnY = pY + pH - 1
	UI.btnP(touchZones, pX + 2, btnY, " [APPLY] ", "ok", "recipe_edit_apply")
	if not recipeEditPop.fluid then
		UI.btnP(touchZones, pX + 12, btnY, " [REPLACE ALL] ", "warn", "recipe_edit_global")
	end
	UI.btnP(touchZones, pX + pW - 12, btnY, " [CANCEL] ", "mute", "close_recipe_edit")
	return popupRect
end


function drawQtyPicker(w, h, stockInv, touchZones, popupRect)
	craftDonePopup = nil
	resetErr()
	craftInfoPop = nil
	recipeEditPop = nil
	local pW, pH = 54, 10
	local headerText, hdrStyle
	if queueEditIdx           then headerText, hdrStyle = " EDIT QUEUE AMOUNT ", "cool"
	elseif fluidCraftMode     then headerText, hdrStyle = " FLUID PRODUCTION ORDER ", "cool"
	elseif isRequestMode      then headerText, hdrStyle = " REQUEST TO TRAIN BOX ", "cool"
	elseif altOutEdit         then headerText, hdrStyle = " OUTPUT COUNT ", "cool"
	elseif isSettingKeep then headerText, hdrStyle = " KEEP: THRESHOLD -> TARGET ", "warn"
	else                           headerText, hdrStyle = " PRODUCTION INTERACTIVE ORDER ", "ok" end
	local pX, pY, rect = UI.popup(pW, pH, w, h, headerText, hdrStyle)
	popupRect = rect
	local nameLabel = "Item: "
	if fluidCraftMode then nameLabel = fluidCraftMode.isItem and "Item: " or "Fluid: " end
	if fluidKeepName then nameLabel = "Fluid: " end
	local pickName = fluidKeepName and (fluidKeepName:match("([^:]+)$") or fluidKeepName)
	or (shortName(itemToCraft))
	if not altOutEdit then
		drawText(pX + 2, pY + 2, nameLabel .. pickName, colors.white, colors.gray)
	end
	local exactStock = isRequestMode and reqMaxQty or (stockInv and (stockInv[itemToCraft] or 0) or 0)
	local curStock      = exactStock
	local stockColor    = colors.cyan
	if exactStock == 0 and stockInv then
		local alts = Groups.altsOf(itemToCraft)
		if alts then
			local altTotal = 0
			for _, altName in ipairs(alts) do
				if altName ~= itemToCraft then
					altTotal = altTotal + (stockInv[altName] or 0)
				end
			end
			if altTotal > 0 then
				curStock   = altTotal
				stockColor = colors.yellow
			end
		end
	end
	local unitSuf = ""
	if fluidCraftMode then
		unitSuf = fluidCraftMode.isItem and "x" or " mB"
		if fluidCraftMode.isItem then
			curStock = stockInv and (stockInv[itemToCraft] or 0) or 0
		else
			local fInv = (pickerHdr and pickerHdr.fluidInv) or getFluid()
			curStock = fInv[fluidKey(itemToCraft)] or 0
		end
		stockColor = colors.cyan
	elseif fluidKeepName then
		unitSuf = " mB"
		local fInv = (pickerHdr and pickerHdr.fluidInv) or getFluid()
		curStock = fInv[itemToCraft] or 0
		stockColor = colors.cyan
	end
	if isSettingKeep then
		drawText(pX + 2 + #(nameLabel .. pickName) + 2, pY + 2,
			"Stock: " .. curStock .. unitSuf, stockColor, colors.gray)
		local thrSel = (keepField == "threshold")
		local tgtSel = (keepField ~= "threshold")
		local thrStr = " THRESHOLD: " .. keepThr .. unitSuf .. " "
		local tgtStr = " TARGET: " .. keepTgt .. unitSuf .. " "
		drawText(pX + 2, pY + 3, thrStr, thrSel and colors.black or colors.white, thrSel and colors.lime or colors.gray)
		table.insert(touchZones, 1, {id="keep_field", arg="threshold", x1=pX+2, x2=pX+2+#thrStr-1, y=pY+3})
		local tgtX = pX + 2 + #thrStr + 2
		drawText(tgtX, pY + 3, tgtStr, tgtSel and colors.black or colors.white, tgtSel and colors.lime or colors.gray)
		table.insert(touchZones, 1, {id="keep_field", arg="target", x1=tgtX, x2=tgtX+#tgtStr-1, y=pY+3})
	elseif altOutEdit then
		local aoPart = "Output per craft: " .. craftQuantity
		drawText(pX + math.floor((pW - #aoPart) / 2), pY + 2, aoPart, colors.lime, colors.gray)
	else
		local amtPart = "Amount: " .. craftQuantity .. unitSuf
		local stPart  = "  Stock: " .. curStock .. unitSuf
		drawText(pX + 2,            pY + 3, amtPart, colors.lime, colors.gray)
		drawText(pX + 2 + #amtPart, pY + 3, stPart,  stockColor, colors.gray)
		if not isRequestMode then
			local mxLabel = "  Max: "
			local mxX = pX + 2 + #amtPart + #stPart
			drawText(mxX, pY + 3, mxLabel, colors.lime, colors.gray)
			local valX = mxX + #mxLabel
			local mxVal, mxColor
			if not pickerMaxSet then
				mxVal = "?"
				mxColor = colors.yellow
			else
				if fluidCraftMode then
					mxVal = pickerCraftable >= FLUID_MAX_CAP and ">100000" or (tostring(pickerCraftable) .. unitSuf)
				else
					mxVal = pickerCraftable >= ITEM_MAX_CAP and ">999" or tostring(pickerCraftable)
				end
				mxColor = pickerCraftable > 0 and colors.lime or colors.red
			end
			UI.text(valX, pY + 3, mxVal, mxColor, colors.gray)
			UI.zoneP(touchZones, "qty_calc_max", nil, valX, pY + 3, #mxVal)
			local autoOn = (Config.autoMaxCalc ~= false)
			UI.btnP(touchZones, pX + pW - 9, pY + 3, autoOn and " [AUT] " or " [MAN] ", autoOn and "ok" or "warn", "qty_toggle_automax")
		end
	end
	local addRow = pY + 4
	local subRow = pY + 5
	local btnRow = pY + 8
	local maxStr = " [MAX] "
	local typStr = " [123] "
	local rightBtnX = pX + pW - #maxStr - 2
	local addVals = {1, 8, 16, 32, 64}
	local subVals = {-1, -8, -16, -32, -64}
	local qeEdit = queueEditIdx and Craft.queue[queueEditIdx]
	if (fluidCraftMode and not fluidCraftMode.isItem) or fluidKeepName
	or (qeEdit and qeEdit.kind == "fluid" and not qeEdit.isItem) then
		addVals = {100, 1000, 5000, 10000}
		subVals = {-100, -1000, -5000, -10000}
	end
	local qX = pX + 2
	for _, val in ipairs(addVals) do
		local str = " [+" .. val .. "] "
		UI.btnP(touchZones, qX, addRow, str, "mute", "qty_adj", val)
		qX = qX + #str + 1
	end
	if not isSettingKeep and not altOutEdit then
		UI.btnP(touchZones, rightBtnX, addRow, maxStr, "ok", "qty_max")
	end
	qX = pX + 2
	for _, val in ipairs(subVals) do
		local str = " [" .. val .. "] "
		UI.btnP(touchZones, qX, subRow, str, "mute", "qty_adj", val)
		qX = qX + #str + 1
	end
	UI.btnP(touchZones, rightBtnX, subRow, typStr, "cool", "qty_type")
	if qtyTypeAct then
		local opW, opH = 30, 5
		local opX = pX + math.floor((pW - opW) / 2)
		local opY = pY + math.floor((pH - opH) / 2)
		_bufFillRect(opX, opY, opW, opH, colors.gray)
		local ohdr = " ENTER QUANTITY "
		UI.text(opX + math.floor((opW - #ohdr) / 2), opY, ohdr, UI.C.bg, UI.C.info)
		local oHint = "Type number in terminal"
		UI.text(opX + math.floor((opW - #oHint) / 2), opY + 2, oHint, UI.C.soft, UI.C.rowBg)
		local oCur = "Current: " .. tostring(craftQuantity)
		UI.text(opX + math.floor((opW - #oCur) / 2), opY + 3, oCur, UI.C.accent, UI.C.rowBg)
	end
	local cfmStr, cnlStr = " [ CONFIRM ] ", " [ CANCEL ] "
	UI.btnP(touchZones, pX + 2, btnRow, cfmStr, "ok", "qty_confirm")
	UI.btnP(touchZones, pX + pW - #cnlStr - 2, btnRow, cnlStr, "mute", "qty_cancel")
	if not isRequestMode and not isSettingKeep and not fluidKeepName and not queueEditIdx and not altOutEdit then
		UI.btnP(touchZones, pX + 2 + #cfmStr + 1, btnRow, " [+QUEUE] ", "cool", "qty_add_queue")
	end
	return popupRect
end


function drawHistory(w, h, stockInv, touchZones, popupRect)
	local hasBox = Config.train_box and Config.train_box ~= ""
	local pW = math.min(w - 4, 82)
	local perPage = math.max(4, h - 18)
	local totEnt = #craftHistory
	local pages = math.max(1, math.ceil(totEnt / perPage))
	if (historyPopup.page or 1) > pages then historyPopup.page = 1 end
	local hPage = historyPopup.page or 1
	local pH = perPage + 5
	local pX, pY, rect = UI.popup(pW, pH, w, h, " CRAFT HISTORY ", "warn", 9)
	popupRect = rect
	UI.btnP(touchZones, pX + pW - 9, pY, " [SCAN] ", "ok", "history_scan")
	local reqX    = pX + pW - 7
	local stkEnd  = reqX - 2
	local craftX  = stkEnd - 10
	local maxEnd  = craftX - 2
	local fInv    = getFluidCached()
	local maxCache = historyPopup.maxCache or {}
	local iStart = (hPage - 1) * perPage + 1
	local iEnd   = math.min(iStart + perPage - 1, totEnt)
	local listY  = pY + 2
	for i = iStart, iEnd do
		local e     = craftHistory[i]
		local stock = e.fluid and (fInv[fluidKey(e.item)] or 0)
		              or (stockInv and (stockInv[e.item] or 0) or 0)
		local maxC  = maxCache[(e.fluid and "f:" or "") .. e.item]
		local maxDisp = (maxC == nil and "?") or (maxC >= 100 and ">99") or tostring(maxC)
		local stkStr = tostring(stock); if #stkStr > 3 then stkStr = "+++" end
		local qtyStr = "x" .. tostring(e.qty)
		local qtyX   = maxEnd - 3 - #qtyStr
		local rowBg  = zebraBg(i)
		_bufFillRect(pX + 1, listY, pW - 2, 1, rowBg)
		UI.text(pX + 2, listY, shortName(e.item):sub(1, math.max(0, qtyX - pX - 2)), UI.C.fg, rowBg)
		UI.text(qtyX, listY, qtyStr, (rowBg == colors.lightGray) and colors.black or colors.lightGray, rowBg)
		UI.text(maxEnd - #maxDisp + 1, listY, maxDisp, UI.C.accent, rowBg)
		UI.btnP(touchZones, craftX, listY, "[CRAFT]", "soft", e.fluid and "history_craft_fluid" or "history_craft", e.item)
		UI.text(stkEnd - #stkStr + 1, listY, stkStr, UI.C.info, rowBg)
		if not e.fluid then
			UI.text(reqX, listY, "[REQ]", UI.C.bg, hasBox and UI.C.info or UI.C.rowBg)
			if hasBox then UI.zoneP(touchZones, "history_req", e.item, reqX, listY, 5) end
		end
		listY = listY + 1
	end
	if totEnt == 0 then
		UI.text(pX + math.floor((pW - 14) / 2), listY + 1, "No crafts yet.", UI.C.soft, UI.C.rowBg)
	end
	local navY = pY + pH - 1
	UI.text(pX + 1, navY - 1, string.rep("-", pW - 2), UI.C.soft, UI.C.rowBg)
	if pages > 1 then
		local prevS, nextS = "[ PREV ]", "[ NEXT ]"
		local pgS = " PAGE " .. hPage .. " OF " .. pages .. " "
		local navX  = pX + math.floor((pW - (#prevS + #pgS + #nextS + 2)) / 2)
		UI.btnP(touchZones, navX, navY, prevS, "mute", "history_prev")
		UI.text(navX + #prevS + 1, navY, pgS, UI.C.accent, UI.C.rowBg)
		UI.btnP(touchZones, navX + #prevS + #pgS + 2, navY, nextS, "mute", "history_next")
	else
		local clsNav = " [ CLOSE ] "
		UI.btnP(touchZones, pX + math.floor((pW - #clsNav) / 2), navY, clsNav, "mute", "close_history")
	end
	return popupRect
end


function _diQueuePopup(w, h, touchZones, popupRect)
	local total = #Craft.queue
	local maxRows = math.max(4, h - 18)
	if queueScroll > math.max(0, total - maxRows) then queueScroll = math.max(0, total - maxRows) end
	if queueScroll < 0 then queueScroll = 0 end
	local shown = math.min(total, maxRows)
	local errActive = queueErrIdx and Craft.queue[queueErrIdx] and Craft.queue[queueErrIdx].failed
	local pW = math.min(w - 4, 72)
	local pH = math.max(shown, 1) + (errActive and 8 or 4)
	local pX, pY, rect = UI.popup(pW, pH, w, h, " CRAFT QUEUE (" .. total .. ") ", "ok", 9)
	popupRect = rect
	local xDel = pX + pW - 7
	local xEd, xDn, xUp = xDel - 7, xDel - 11, xDel - 15
	local xTop = xUp - 6
	local xCr  = xTop - 8
	if total == 0 then
		UI.text(pX + 2, pY + 2, "Queue empty. Use [+QUEUE] in order popup.", UI.C.soft, UI.C.rowBg)
	end
	for ri = 1, shown do
		local qi = queueScroll + ri
		local qe = Craft.queue[qi]
		local rowY = pY + 1 + ri
		local nm = shortName(qe.name)
		local unit = (qe.kind == "fluid" and not qe.isItem) and " mB" or "x"
		local label = string.format("%d. %s  %d%s", qi, nm, qe.qty, unit)
		local nameW = xCr - (pX + 2) - (qe.failed and 5 or 2)
		UI.text(pX + 2, rowY, label:sub(1, nameW), qe.failed and UI.C.warn or UI.C.fg, UI.C.rowBg)
		if qe.failed then UI.btnP(touchZones, xCr - 4, rowY, "[!]", "danger", "queue_err", qi) end
		UI.btnP(touchZones, xCr, rowY, "[CRAFT]", "soft", "queue_craft", qi)
		local topStyle = (qi > 1) and "mute" or "soft"
		UI.btnP(touchZones, xTop, rowY, "[TOP]", topStyle, "queue_top", qi)
		UI.btnP(touchZones, xUp, rowY, "[^]", topStyle, "queue_up", qi)
		UI.btnP(touchZones, xDn, rowY, "[v]", (qi < total) and "mute" or "soft", "queue_dn", qi)
		UI.btnP(touchZones, xEd, rowY, "[EDIT]", "mute", "queue_edit", qi)
		UI.btnP(touchZones, xDel, rowY, "[DEL]", "danger", "queue_del", qi)
	end
	if errActive then
		local fl = Craft.queue[queueErrIdx].failed
		local errY = pY + shown + 2
		UI.text(pX + 2, errY, ("FAIL #" .. queueErrIdx .. ":"):sub(1, pW - 4), UI.C.danger, UI.C.rowBg)
		for li = 1, math.min(2, #fl) do
			UI.text(pX + 4, errY + li, tostring(fl[li]):sub(1, pW - 6), UI.C.fg, UI.C.rowBg)
		end
	end
	local btnY = pY + pH - 1
	local runStr, clsStr = " [ RUN ALL ] ", " [ CLOSE ] "
	UI.btnP(touchZones, pX + 2, btnY, runStr, (total > 0) and "ok" or "mute", "queue_runall")
	UI.btnP(touchZones, pX + pW - #clsStr - 2, btnY, clsStr, "mute", "queue_close")
	if total > maxRows then
		local pgX = pX + math.floor(pW / 2) - 4
		UI.btnP(touchZones, pgX, btnY, " < ", "soft", "queue_scroll", -maxRows)
		UI.btnP(touchZones, pgX + 5, btnY, " > ", "soft", "queue_scroll", maxRows)
	end
	return popupRect
end


function drawMgmtEdit(w, h, touchZones, popupRect, popupZoneS)
	local pW = math.min(w - 4, 58)
	local rules = mgmtPopup.rules or {}
	local inIsStg = (#(mgmtPopup.inputs or {}) == 0)
	local hdrLines = 7 + (inIsStg and 0 or 2)
	local ftrLines = 3
	local maxPH = h - 2
	local rulesN = math.max(1, #rules)
	local pH = math.min(maxPH, hdrLines + rulesN * 3 + ftrLines)
	local perPage = math.max(1, math.floor((pH - hdrLines - ftrLines) / 3))
	local pages = math.max(1, math.ceil(#rules / perPage))
	if not mgmtPopup.rulesPage or mgmtPopup.rulesPage < 1 then mgmtPopup.rulesPage = 1 end
	if mgmtPopup.rulesPage > pages then mgmtPopup.rulesPage = pages end
	local rulesPage = mgmtPopup.rulesPage
	local rStart = (rulesPage - 1) * perPage + 1
	local rEnd   = math.min(rStart + perPage - 1, #rules)
	popupZoneS = #touchZones + 1
	local pX, pY, rect = UI.popup(pW, pH, w, h, mgmtPopup.groupIdx and " EDIT GROUP " or " NEW GROUP ", "cool")
	popupRect = rect
	local nmDisp = mgmtPopup.name ~= "" and mgmtPopup.name or "(tap to set)"
	UI.text(pX + 1, pY + 2, (" Name: [ " .. nmDisp .. " ]"):sub(1, pW - 2), UI.C.fg, UI.C.rowBg)
	UI.zone(touchZones, "mgmt_edit_name", nil, pX + 1, pY + 2, pW - 2)
	local inDisp = mgmtIODisp({inputs=mgmtPopup.inputs}, true)
	UI.text(pX + 1, pY + 3, (" Input:  " .. inDisp):sub(1, pW - 13), inIsStg and UI.C.accent or UI.C.fg, UI.C.rowBg)
	UI.btnR(touchZones, pX + pW - 2, pY + 3, " [CHANGE] ", "warn", "mgmt_pick_input")
	local outIsStg = (#(mgmtPopup.outputs or {}) == 0)
	local outDisp = mgmtIODisp({outputs=mgmtPopup.outputs}, false)
	UI.text(pX + 1, pY + 4, (" Output: " .. outDisp):sub(1, pW - 13), outIsStg and UI.C.accent or UI.C.info, UI.C.rowBg)
	UI.btnR(touchZones, pX + pW - 2, pY + 4, " [CHANGE] ", "warn", "mgmt_pick_output")
	UI.text(pX + 1, pY + 5, string.rep("-", pW - 2), UI.C.soft, UI.C.rowBg)
	UI.text(pX + 1, pY + 6, mgmtPopup.fluid and " RULES (keep mB in output):" or " RULES (input->output):", UI.C.hi, UI.C.rowBg)
	UI.btnR(touchZones, pX + pW - 2, pY + 6, " [+ADD] ", "ok", "mgmt_pick_item")
	local ry = pY + 7
	if not inIsStg then
		local drainOn = mgmtPopup.drain or false
		local drainLbl = (drainOn and " [EMPTY ALL]  ON  " or " [EMPTY ALL]  OFF "):sub(1, pW - 2)
		drawText(pX + 1, ry, drainLbl, drainOn and colors.black or colors.lightGray, drainOn and colors.lime or colors.gray)
		UI.zone(touchZones, "mgmt_toggle_drain", nil, pX + 1, ry, pW - 2)
		ry = ry + 1
		local provOn = mgmtPopup.provider or false
		local provSuf = " (pull-only src) "
		for _, nm in ipairs(mgmtPopup.inputs or {}) do
			if isBridge(nm) then provSuf = " (ME/RS pull-only) "; break end
		end
		drawText(pX + 1, ry, (provOn and " [PROVIDER] ON" .. provSuf or " [PROVIDER] OFF"):sub(1, pW - 2),
			provOn and colors.black or colors.lightGray, provOn and colors.orange or colors.gray)
		UI.zone(touchZones, "mgmt_toggle_provider", nil, pX + 1, ry, pW - 2)
		ry = ry + 1
	end
	if #rules == 0 then
		UI.text(pX + 2, ry, "(none)", UI.C.soft, UI.C.rowBg)
		ry = ry + 1
	else
		for ri = rStart, rEnd do
			local rule = rules[ri]
			local rn = (shortName(rule.item))
			local amt = tostring(rule.amount)
			local ctrlX = pX + pW - (5 + #amt + 5 + 5 + 5) - 2
			UI.text(pX + 2, ry, rn:sub(1, ctrlX - pX - 3), UI.C.fg, UI.C.rowBg)
			UI.btn(touchZones, ctrlX, ry, " [-] ", "mute", "mgmt_rule_adj", {ri, -1})
			UI.text(ctrlX + 5, ry, amt, UI.C.hi, UI.C.rowBg)
			UI.btn(touchZones, ctrlX + 5 + #amt, ry, " [+] ", "mute", "mgmt_rule_adj", {ri, 1})
			UI.btn(touchZones, ctrlX + 5 + #amt + 5, ry, " [#] ", "warn", "mgmt_rule_type", ri)
			UI.btn(touchZones, ctrlX + 5 + #amt + 10, ry, " [X] ", "danger", "mgmt_rule_del", ri)
			ry = ry + 1
			UI.text(pX + 1, ry, string.rep("-", pW - 2), UI.C.soft, UI.C.rowBg)
			ry = ry + 1
			drawCondRow(pX, pW, ry, rule, ri, touchZones)
			ry = ry + 1
		end
	end
	local footY = pY + pH - 2
	if pages > 1 then
		local pagerY = footY - 1
		local prevS, nextS = " < PREV ", " NEXT > "
		local pgStr = string.format("Page %d/%d", rulesPage, pages)
		UI.text(pX + 2, pagerY, prevS, rulesPage > 1 and UI.C.fg or UI.C.muted, UI.C.rowBg)
		UI.text(pX + math.floor((pW - #pgStr) / 2), pagerY, pgStr, UI.C.soft, UI.C.rowBg)
		UI.text(pX + pW - #nextS - 2, pagerY, nextS, rulesPage < pages and UI.C.fg or UI.C.muted, UI.C.rowBg)
		if rulesPage > 1 then UI.zone(touchZones, "mgmt_rules_prev", nil, pX + 2, pagerY, #prevS) end
		if rulesPage < pages then UI.zone(touchZones, "mgmt_rules_next", nil, pX + pW - #nextS - 2, pagerY, #nextS) end
	end
	UI.btn(touchZones, pX + 2, footY + 1, " [SAVE] ", "ok", "mgmt_save")
	UI.btnR(touchZones, pX + pW - 2, footY + 1, " [CANCEL] ", "mute", "mgmt_cancel")
	return popupRect, popupZoneS
end


function _drawMgmtPeriPicker(w, h, touchZones, ctx)
	local allPeri = {"STORAGE"}
	local tmp = {}
	for _, pn in ipairs(peripheral.getNames()) do
		if not SYSTEM_SIDES[pn] and pn ~= MONITOR_SIDE and pn ~= Config.train_box then table.insert(tmp, pn) end
	end
	table.sort(tmp, _cmpByDisplay)
	for _, v in ipairs(tmp) do table.insert(allPeri, v) end
	local pW = math.min(w - 10, 70)
	local pX = math.floor((w - pW) / 2) + 1
	local pH = math.min(h - 4, 16)
	local pY = math.floor((h - pH) / 2) + 1
	local cols, colW = 3, math.floor((pW - 2) / 3)
	local listTop = pY + 2
	local maxRows = pH - 5
	local perPage = cols * maxRows
	local page  = mgmtPopup[ctx.pageKey] or 1
	local total = math.max(1, math.ceil(#allPeri / perPage))
	if page > total then page = total; mgmtPopup[ctx.pageKey] = page end
	local st = (page - 1) * perPage + 1
	local en = math.min(st + perPage - 1, #allPeri)
	local zoneStart = #touchZones + 1
	local hdrStyleName = ctx.hdrColor == colors.orange and "warn" or "cool"
	local _, _, rect = UI.popup(pW, pH, w, h, ctx.hdr, hdrStyleName)
	for ci = 1, cols - 1 do
		local sepX = pX + 1 + ci * colW
		for ry = 0, maxRows - 1 do UI.text(sepX, listTop + ry, "|", UI.C.soft, UI.C.rowBg) end
	end
	local sel = mgmtPopup[ctx.listKey] or {}
	local selSet = {}
	for _, nm in ipairs(sel) do selSet[nm] = true end
	local stgSel = (#sel == 0)
	for pi = st, en do
		local localIdx = pi - st
		local cellX = pX + 2 + math.floor(localIdx / maxRows) * colW
		local cellY = listTop + (localIdx % maxRows)
		local pn = allPeri[pi]
		local isStg = (pn == "STORAGE")
		local isSel = (isStg and stgSel) or (not isStg and selSet[pn] == true)
		local disp = isStg and pn or getMachName(pn)
		if #disp > colW - 2 then disp = disp:sub(1, colW - 2) end
		drawText(cellX, cellY, disp,
			(isSel or isStg) and colors.black or colors.white,
			isSel and colors.cyan or (isStg and colors.lime or colors.gray))
		UI.zone(touchZones, ctx.setId, pn, cellX, cellY, colW - 1)
	end
	local navY = pY + pH - 2
	drawText(pX + 2, navY, " < ", page > 1 and colors.white or colors.gray, colors.gray)
	drawText(pX + pW - 5, navY, " > ", page < total and colors.white or colors.gray, colors.gray)
	if page > 1 then UI.zone(touchZones, ctx.prevId, nil, pX + 2, navY, 3) end
	if page < total then UI.zone(touchZones, ctx.nextId, nil, pX + pW - 5, navY, 3) end
	UI.btn(touchZones, pX + math.floor((pW - 8) / 2), pY + pH - 1, " [DONE] ", "ok", ctx.doneId)
	return rect, zoneStart
end


function _drawMgmtItemPicker(w, h, touchZones)
	local inIsStg = (mgmtPopup.condRuleIdx ~= nil) or (#(mgmtPopup.inputs or {}) == 0)
	local items = {}

	local function push(name, count) items[#items + 1] = {name = name, count = count} end
	if mgmtPopup.fluid then
		local src = inIsStg and mgmtFSnap() or tankContents(mgmtPopup.input)
		for n, c in pairs(src) do push(n, c) end
	elseif inIsStg then
		for n, c in pairs(getInvCached()) do push(n, c) end
	else
		local by = {}
		for _, inNm in ipairs(mgmtPopup.inputs or {}) do
			local p = peripheral.wrap(inNm)
			if p and p.list then
				local ok, lst = pcall(p.list)
				if ok and lst then
					for _, it in pairs(lst) do if it then by[it.name] = (by[it.name] or 0) + it.count end end
				end
			elseif p and p.getItems then
				local ok, lst = pcall(p.getItems)
				if ok and lst then
					for _, it in pairs(lst) do if it and it.name then by[it.name] = (by[it.name] or 0) + (it.count or 0) end end
				end
			end
		end
		for n, c in pairs(by) do push(n, c) end
	end
	table.sort(items, function(a, b) return a.name < b.name end)
	local srch = mgmtItemSrch:lower()
	local filt = {}
	for _, it in ipairs(items) do
		if srch == "" or it.name:lower():find(srch, 1, true) then filt[#filt + 1] = it end
	end
	local pW = math.min(w - 10, 70)
	local pX = math.floor((w - pW) / 2) + 1
	local pH = math.min(h - 4, 18)
	local pY = math.floor((h - pH) / 2) + 1
	local cols, colW = 3, math.floor((pW - 2) / 3)
	local listTop = pY + 3
	local maxRows = pH - 6
	local perPage = cols * maxRows
	local page  = mgmtPopup.itemPage or 1
	local total = math.max(1, math.ceil(#filt / perPage))
	if page > total then page = total; mgmtPopup.itemPage = page end
	local st = (page - 1) * perPage + 1
	local en = math.min(st + perPage - 1, #filt)
	local zoneStart = #touchZones + 1
	local inpShort = inIsStg and "STORAGE" or getMachName(mgmtPopup.input)
	local hdr
	if mgmtPopup.condRuleIdx then
		hdr = mgmtPopup.fluid and " PICK CONDITION FLUID " or " PICK CONDITION ITEM "
	else
		hdr = (mgmtPopup.fluid and " ADD FLUID FROM: " or " ADD ITEM FROM: ") .. inpShort:upper():sub(1, pW - 20) .. " "
	end
	local _, _, rect = UI.popup(pW, pH, w, h, hdr, "ok")
	local searchRow = pY + 1
	local srchDisp  = (mgmtItemSrch == "") and "<type item name...>" or mgmtItemSrch
	local srchFull  = "FIND: [ " .. srchDisp .. " ]"
	local srchX     = pX + math.floor((pW - #srchFull) / 2)
	UI.text(srchX, searchRow, "FIND: ", UI.C.soft, UI.C.rowBg)
	drawText(srchX + 6, searchRow, "[ " .. srchDisp .. " ]",
		mgmtSearchOn and colors.black or (mgmtItemSrch == "" and colors.gray or colors.white),
		mgmtSearchOn and colors.white or colors.lightGray)
	UI.zone(touchZones, "mgmt_search_focus", nil, srchX, searchRow, #srchFull)
	if mgmtItemSrch ~= "" then
		UI.btn(touchZones, srchX + #srchFull + 1, searchRow, " [X] ", "danger", "mgmt_search_clear")
	end
	for ci = 1, cols - 1 do
		local sepX = pX + 1 + ci * colW
		for ry = 0, maxRows - 1 do UI.text(sepX, listTop + ry, "|", UI.C.soft, UI.C.rowBg) end
	end
	if #filt == 0 then
		UI.text(pX + 2, listTop + 1, srch ~= "" and "(no matches)" or "(input empty or unavailable)", UI.C.soft, UI.C.rowBg)
	else
		for ii = st, en do
			local localIdx = ii - st
			local cellX = pX + 2 + math.floor(localIdx / maxRows) * colW
			local cellY = listTop + (localIdx % maxRows)
			local itm = filt[ii]
			local cntS = tostring(itm.count)
			local nameMax = colW - 2 - #cntS - 1
			local iShort = (shortName(itm.name)):sub(1, nameMax)
			local hasRule = false
			if not mgmtPopup.condRuleIdx then
				for _, r in ipairs(mgmtPopup.rules or {}) do
					if r.item == itm.name then hasRule = true; break end
				end
			end
			UI.text(cellX, cellY, iShort, hasRule and UI.C.warn or UI.C.fg, UI.C.rowBg)
			UI.text(cellX + colW - 2 - #cntS, cellY, cntS, UI.C.info, UI.C.rowBg)
			if not hasRule then UI.zone(touchZones, "mgmt_add_rule", itm.name, cellX, cellY, colW - 1) end
		end
	end
	local navY = pY + pH - 2
	drawText(pX + 2, navY, " < ", page > 1 and colors.white or colors.lightGray, colors.gray)
	drawText(pX + pW - 5, navY, " > ", page < total and colors.white or colors.lightGray, colors.gray)
	if page > 1 then UI.zone(touchZones, "mgmt_item_prev", nil, pX + 2, navY, 3) end
	if page < total then UI.zone(touchZones, "mgmt_item_next", nil, pX + pW - 5, navY, 3) end
	UI.btn(touchZones, pX + math.floor((pW - 10) / 2), pY + pH - 1, " [CANCEL] ", "mute", "mgmt_item_cancel")
	return rect, zoneStart
end


function drawMgmtInputSel(w, h, touchZones)
	return _drawMgmtPeriPicker(w, h, touchZones,
		{pageKey="periPage", listKey="inputs", hdr=" SELECT INPUTS (tap to toggle) ", hdrColor=colors.orange,
			setId="mgmt_set_input", prevId="mgmt_peri_prev", nextId="mgmt_peri_next", doneId="mgmt_peri_cancel"})
end


function drawMgmtOutSel(w, h, touchZones)
	return _drawMgmtPeriPicker(w, h, touchZones,
		{pageKey="outPeriPage", listKey="outputs", hdr=" SELECT OUTPUTS (tap to toggle) ", hdrColor=colors.cyan,
			setId="mgmt_set_output", prevId="mgmt_outperi_prev", nextId="mgmt_outperi_next", doneId="mgmt_outperi_cancel"})
end


function drawFluidPicker(w, h, touchZones, popupRect)
	resetErr()
	local fp = fluidRecipePicker
	local sName = shortName(fp.fluid)
	local rows = fp.producers
	local pW = math.min(w - 4, 76)
	local pH = math.min(#rows + 6, h - 4)
	local pX, pY, rect = UI.popup(pW, pH, w, h, " RECIPE PRIORITY: " .. sName:upper() .. " ", "ok")
	popupRect = rect
	UI.text(pX + 2, pY + 1, "[*]=make primary  [X]=delete  top=tried first", UI.C.muted, UI.C.rowBg)
	local awaiting = (fluidWaitCraft == fp.fluid)
	local delX  = pX + pW - 5
	local crfX  = delX - 8
	local starX = crfX - 4
	local descW = starX - pX - 3
	local lineY = pY + 3
	for idx, p in ipairs(rows) do
		if lineY >= pY + pH - 1 then break end
		local mDisp = getMachName(p.recipe.machine_name) or p.recipe.machine_name or "?"
		local ins, outs = {}, {}
		for _, inp in ipairs(p.recipe.inputs or {}) do
			ins[#ins + 1] = string.format("%s %d", shortName(inp.name), inp.amount)
		end
		for _, it in ipairs(p.recipe.item_inputs or {}) do
			ins[#ins + 1] = string.format("%dx %s", it.count, shortName(it.name))
		end
		for _, o in ipairs(p.recipe.outputs or {}) do
			outs[#outs + 1] = string.format("%s %d", shortName(o.name), o.amount)
		end
		for _, o in ipairs(p.recipe.item_outputs or {}) do
			outs[#outs + 1] = string.format("%dx %s", o.count, shortName(o.name))
		end
		local rank = p.isPrimary and "[PRIMARY] " or (p.own and ("[#" .. idx .. "] ") or "[~] ")
		local desc = rank .. string.format("%s: %s -> %s", mDisp, table.concat(ins, " + "), table.concat(outs, " + "))
		UI.text(pX + 2, lineY, desc:sub(1, math.max(1, descW)), p.isPrimary and UI.C.hi or UI.C.fg, UI.C.rowBg)
		if p.own and not p.isPrimary then UI.btnP(touchZones, starX, lineY, "[*]", "cool", "fluid_make_primary", idx) end
		if awaiting then
			UI.text(crfX - 1, lineY, "-", UI.C.accent, UI.C.rowBg)
			UI.text(crfX + 7, lineY, "-", UI.C.accent, UI.C.rowBg)
		end
		UI.btnP(touchZones, crfX, lineY, "[CRAFT]", awaiting and "hi" or "ok", "fluid_pick_recipe", idx)
		if p.own then UI.btnP(touchZones, delX, lineY, "[X]", "danger", "fluid_picker_delete", idx) end
		lineY = lineY + 1
	end
	local clsStr = " [ CLOSE ] "
	UI.btnP(touchZones, pX + math.floor((pW - #clsStr) / 2), pY + pH - 1, clsStr, "mute", "fluid_picker_close")
	return popupRect
end


function drawCraftInfo(w, h, touchZones, popupRect, data)
	local sName = shortName(craftInfoPop.item)
	local lines = {}
	local blocked = {}
	for bItem in pairs(data.blocked or {}) do
		table.insert(blocked, bItem)
	end
	table.sort(blocked)
	if #blocked > 0 then
		for _, bn in ipairs(blocked) do
			local bs = shortName(bn)
			table.insert(lines, {text = bs .. ":", color = colors.red})
			local details = data.blockedInfo and data.blockedInfo[bn]
			if details and details.missing and next(details.missing) then
				local mList = {}
				for mItem, mCount in pairs(details.missing) do
					table.insert(mList, {name = shortName(mItem), count = mCount})
				end
				table.sort(mList, function(a, b) return a.name < b.name end)
				for _, m in ipairs(mList) do
					table.insert(lines, {text = "  " .. m.name .. "  x" .. m.count, color = colors.white})
				end
			end
			table.insert(lines, {text = "", color = colors.gray})
		end
	else
		local mList = {}
		for mItem, mCount in pairs(data.missing or {}) do
			table.insert(mList, {name = shortName(mItem), count = mCount})
		end
		table.sort(mList, function(a, b) return a.name < b.name end)
		for _, m in ipairs(mList) do
			table.insert(lines, {text = m.name .. "  x" .. m.count, color = colors.white})
		end
	end
	if #lines == 0 then
		table.insert(lines, {text = "Craftable from stock (no shortage).", color = colors.lime})
	end
	local pW = 44
	local pH = math.min(#lines + 5, h - 8)
	local pX, pY, rect = UI.popup(pW, pH, w, h, " ANALYSIS: " .. sName:upper():sub(1, pW - 13) .. " ", "danger")
	popupRect = rect
	local lineY = pY + 2
	for _, line in ipairs(lines) do
		if lineY >= pY + pH - 2 then break end
		if line.text ~= "" then UI.text(pX + 2, lineY, line.text:sub(1, pW - 4), line.color, UI.C.rowBg) end
		lineY = lineY + 1
	end
	UI.btnP(touchZones, pX + math.floor((pW - 11) / 2), pY + pH - 1, " [ CLOSE ] ", "mute", "close_craft_info")
	return popupRect
end


function drawCraftDone(w, h, touchZones, popupRect)
	resetErr()
	craftInfoPop = nil
	recipeEditPop = nil
	local popup = craftDonePopup
	local outs = popup.outputs
	local bodyLines = outs and #outs or 1
	local pW = 40
	local pH = math.max(7, bodyLines + 5)
	local pX, pY, rect = UI.popup(pW, pH, w, h, popup.learned and " RECIPE LEARNED " or " CRAFT COMPLETE ", "ok", 9)
	popupRect = rect
	local clsStr = " [CLOSE] "
	local btnY = pY + pH - 2
	if outs then
		UI.text(pX + 2, pY + 2, "Output:", UI.C.fg, UI.C.rowBg)
		local ly = pY + 3
		for _, o in ipairs(outs) do
			local on = shortName(o.name)
			local txt = (o.unit == "x") and (on .. ": " .. o.amount .. "x") or (on .. ": " .. o.amount .. " mB")
			UI.text(pX + 4, ly, txt:sub(1, pW - 6), UI.C.accent, UI.C.rowBg)
			ly = ly + 1
		end
	elseif popup.isFluid then
		local sName = shortName(popup.item)
		UI.text(pX + 2, pY + 2, ("Fluid: " .. sName):sub(1, pW - 4), UI.C.fg, UI.C.rowBg)
		UI.text(pX + 2, pY + 3, "Made: " .. popup.count .. " mB", UI.C.accent, UI.C.rowBg)
	else
		local sName = shortName(popup.item)
		UI.text(pX + 2, pY + 2, ("Item: " .. sName):sub(1, pW - 4), UI.C.fg, UI.C.rowBg)
		UI.text(pX + 2, pY + 3, "Stock: " .. popup.count .. " pcs.", UI.C.accent, UI.C.rowBg)
		UI.btnP(touchZones, pX + 2, btnY, " [REQUEST] ", "cool", "popup_request")
	end
	UI.btnP(touchZones, pX + pW - #clsStr - 2, btnY, clsStr, "soft", "popup_close")
	return popupRect
end


function drawFluidSave(w, h, touchZones, popupRect)
	resetErr()
	local sc = fluidSaveConfirm
	local rec = sc.recipe
	local inParts = {}
	for _, inp in ipairs(rec.inputs or {}) do
		inParts[#inParts + 1] = (shortName(inp.name)) .. " " .. inp.amount
	end
	for _, it in ipairs(rec.item_inputs or {}) do
		inParts[#inParts + 1] = it.count .. "x " .. (shortName(it.name))
	end
	local outParts = {}
	for _, o in ipairs(rec.outputs or {}) do
		outParts[#outParts + 1] = (shortName(o.name)) .. " " .. o.amount .. "mB"
	end
	for _, o in ipairs(rec.item_outputs or {}) do
		outParts[#outParts + 1] = o.count .. "x " .. (shortName(o.name))
	end
	local pW = math.min(w - 6, 64)
	local pH = 9
	local pX, pY, rect = UI.popup(pW, pH, w, h, " SAVE LEARNED RECIPE? ", "ok")
	popupRect = rect
	local mDisp = getMachName(rec.machine_name) or rec.machine_name or "?"
	UI.text(pX + 2, pY + 2, ("Machine: " .. mDisp):sub(1, pW - 4), UI.C.fg, UI.C.rowBg)
	UI.text(pX + 2, pY + 3, ("In:  " .. table.concat(inParts, " + ")):sub(1, pW - 4), UI.C.soft, UI.C.rowBg)
	UI.text(pX + 2, pY + 4, ("Out: " .. table.concat(outParts, " + ")):sub(1, pW - 4), UI.C.info, UI.C.rowBg)
	UI.text(pX + 2, pY + 5, (sc.asAlt and "Will be saved as ALT (priority recipe exists)" or "Will be saved as PRIMARY"):sub(1, pW - 4),
		sc.asAlt and UI.C.warn or UI.C.accent, UI.C.rowBg)
	UI.btnP(touchZones, pX + 2, pY + pH - 1, " [ SAVE ] ", "ok", "fluid_save_yes")
	UI.btnR(touchZones, pX + pW - 3, pY + pH - 1, " [ DISCARD ] ", "danger", "fluid_save_no")
	return popupRect
end


function drawFluidInfo(w, h, touchZones, popupRect)
	local sName = shortName(fluidCraftInfo.name)
	local mList = {}
	for mKey, mAmt in pairs(fluidCraftInfo.missing or {}) do
		if mKey ~= "__fl" and type(mAmt) == "number" and mAmt > 0 then
			local isFl = (type(mKey) == "string" and mKey:sub(1, 2) == "f:")
			local nm = isFl and fluidNameOf(mKey) or mKey
			nm = shortName(nm)
			mList[#mList + 1] = {name = nm, amt = mAmt, isFl = isFl}
		end
	end
	table.sort(mList, function(a, b) return a.name < b.name end)
	local lines = {}
	for _, m in ipairs(mList) do
		local suf = m.isFl and (" x" .. m.amt .. " mB") or ("  x" .. m.amt)
		lines[#lines + 1] = {text = m.name .. suf, color = m.isFl and colors.cyan or colors.white}
	end
	if #lines == 0 then
		lines[#lines + 1] = {text = "Craftable from stock (no shortage).", color = colors.lime}
	end
	local pW = 44
	local pH = math.min(#lines + 5, h - 8)
	local pX, pY, rect = UI.popup(pW, pH, w, h, " MISSING: " .. sName:upper():sub(1, pW - 12) .. " ", "danger")
	popupRect = rect
	local lineY = pY + 2
	for _, line in ipairs(lines) do
		if lineY >= pY + pH - 2 then break end
		UI.text(pX + 2, lineY, line.text:sub(1, pW - 4), line.color, UI.C.rowBg)
		lineY = lineY + 1
	end
	UI.btnP(touchZones, pX + math.floor((pW - 11) / 2), pY + pH - 1, " [ CLOSE ] ", "mute", "close_fluid_info")
	return popupRect
end


function drawMgmtInput(w, grp, h, touchZones, popupRect, popupZoneS)
	local pW = math.min(w - 4, 58)
	local inIsStg  = (not grp.input  or grp.input  == "" or grp.input  == "STORAGE")
	local outIsStg = (not grp.output or grp.output == "" or grp.output == "STORAGE")
	local vitems = {}
	for _, rule in ipairs(grp.rules or {}) do
		table.insert(vitems, {name=rule.item, amount=rule.amount, condition=rule.condition})
	end
	table.sort(vitems, function(a,b) return a.name < b.name end)
	local isFluid = isFluid(grp)
	local snap = isFluid and mgmtFSnap() or getInvCached()
	local inputCounts = {}
	if inIsStg then
		for _, vi in ipairs(vitems) do
			inputCounts[vi.name] = snap[vi.name] or 0
		end
	elseif isFluid then
		inputCounts = tankContents(grp.input)
	else
		local inP = peripheral.wrap(grp.input)
		if inP and inP.list then
			local ok, items = pcall(inP.list)
			if ok and items then
				for _, it in pairs(items) do
					if it then inputCounts[it.name] = (inputCounts[it.name] or 0) + it.count end
				end
			end
		end
	end
	local outCounts = {}
	if outIsStg then
		outCounts = snap
	elseif isFluid then
		outCounts = tankContents(grp.output)
	else
		local outP = peripheral.wrap(grp.output)
		if outP and outP.list then
			local ok, outItems = pcall(outP.list)
			if ok and outItems then
				for _, oi in pairs(outItems) do
					if oi then outCounts[oi.name] = (outCounts[oi.name] or 0) + oi.count end
				end
			end
		end
	end
	local perPage = 5
	local page = mgmtPopup.page or 1
	local pages = math.max(1, math.ceil(#vitems / perPage))
	if page > pages then page = pages; mgmtPopup.page = page end
	local vStart = (page - 1) * perPage + 1
	local vEnd   = math.min(vStart + perPage - 1, #vitems)
	local rN = 0
	for vi = vStart, vEnd do
		rN = rN + 1
		local itm = vitems[vi]
		if itm.condition and itm.condition.item and itm.condition.item ~= "" then
			rN = rN + 1
		end
	end
	if rN == 0 then rN = 1 end
	local pH = math.max(10, math.min(rN + 6, h - 2))
	popupZoneS = #touchZones + 1
	local gName = (grp.name ~= "" and grp.name or "(unnamed)"):upper()
	local pX, pY, rect = UI.popup(pW, pH, w, h, " VIEW: " .. gName:sub(1, pW - 11) .. " ", "warn")
	popupRect = rect
	local C_RULE, C_INPUT, C_OUTPUT = pX + pW - 20, pX + pW - 13, pX + pW - 6
	local nameMax = pW - 23
	local inLbl  = inIsStg  and "STORAGE" or (shortName(grp.input)):sub(1,10)
	local outLbl = outIsStg and "STORAGE" or (shortName(grp.output)):sub(1,10)
	UI.text(pX + 2,   pY + 1, ("In: " .. inLbl .. " -> Out: " .. outLbl):sub(1, nameMax + 1), UI.C.soft, UI.C.rowBg)
	UI.text(C_RULE,   pY + 1, "  RULE", UI.C.hi,     UI.C.rowBg)
	UI.text(C_INPUT,  pY + 1, " INPUT", UI.C.info,   UI.C.rowBg)
	UI.text(C_OUTPUT, pY + 1, "OUTPUT", UI.C.accent, UI.C.rowBg)

	local function numCell(x, y, val, col)
		local s = tostring(val):sub(1, 6)
		UI.text(x + math.max(0, 6 - #s), y, s, col, UI.C.rowBg)
	end
	if #vitems == 0 then
		UI.text(pX + 2, pY + 2, "(no rules defined)", UI.C.soft, UI.C.rowBg)
	else
		local ry = pY + 2
		for vi = vStart, vEnd do
			local itm = vitems[vi]
			UI.text(pX + 2, ry, (shortName(itm.name)):sub(1, nameMax), UI.C.fg, UI.C.rowBg)
			numCell(C_RULE,   ry, itm.amount, UI.C.hi)
			numCell(C_INPUT,  ry, inputCounts[itm.name] or 0, UI.C.info)
			numCell(C_OUTPUT, ry, outCounts[itm.name] or 0, UI.C.accent)
			ry = ry + 1
			local cond = itm.condition
			if cond and cond.item and cond.item ~= "" then
				local cShort = (shortName(cond.item))
				local opStr = cond.op or "<"
				local cVal  = cond.value or 1
				local condStock = snap[cond.item] or 0
				local condMet = (opStr == "<" and condStock < cVal)
				or (opStr == ">" and condStock > cVal)
				or (opStr == "=" and condStock == cVal)
				local ifDetail = "-- IF " .. cShort:sub(1, nameMax - 6) .. " " .. opStr .. " " .. tostring(cVal)
				UI.text(pX + 2, ry, ifDetail:sub(1, nameMax + 2), UI.C.info, UI.C.rowBg)
				numCell(C_OUTPUT, ry, condStock, condMet and UI.C.accent or UI.C.warn)
				ry = ry + 1
			end
		end
	end
	local navY = pY + pH - 3
	if pages > 1 then
		if page > 1 then UI.btn(touchZones, pX + 2, navY, " [<] ", "soft", "mgmt_vinput_prev") end
		local pgStr = page .. "/" .. pages
		UI.text(pX + math.floor((pW - #pgStr) / 2), navY, pgStr, UI.C.soft, UI.C.rowBg)
		if page < pages then UI.btn(touchZones, pX + pW - 7, navY, " [>] ", "soft", "mgmt_vinput_next") end
	end
	UI.btn(touchZones, pX + math.floor((pW - 9) / 2), pY + pH - 1, " [CLOSE] ", "mute", "mgmt_close_view")
	return popupRect, popupZoneS
end


function _touchKeep(zone, x, y)
	if zone.id == "keep_cat" then
		fluidKeepFilter = zone.arg
		curPage = 1
		return true
	elseif zone.id == "force_autostock" then
		if not Config.autostock_paused then
			runAutostock()
		end
		return true
	elseif zone.id == "keep_craft_now" then
		local kItem = zone.arg
		local kSet  = Keep.of(kItem)
		if kSet and kItem:sub(1, 2) == "f:" then
			local fname = fluidNameOf(kItem)
			local cur   = (getFluid())[kItem] or 0
			-- .limit is the old field from pre-v3 keep entries. still around bcz
			-- some users never re-saved after rename. leave it
			local need  = (kSet.target or kSet.limit) - cur
			local kShort = shortName(fname)
			if need > 0 then
				local prods = fluidProducers(fname)
				if prods[1] then
					fluidCraft(prods[1].recipe, fname, need)
				else
					uiMessage = "ERR: no recipe for " .. kShort
					if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
					uiMsgTimer = os.startTimer(3)
				end
			else
				uiMessage = kShort .. " already at target"
				if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
				uiMsgTimer = os.startTimer(3)
			end
		elseif kSet and Recipe.find(kItem) then
			local kInv    = getInv()
			local kStock  = kInv[kItem] or 0
			local kNeeded = (kSet.target or kSet.limit) - kStock
			local kShort  = shortName(kItem)
			if kNeeded > 0 then
				sysStatus = "MANUAL_CRAFT"
				drawUI()
				local kPlan, kMiss, _ = planProd(kItem, kNeeded, true)
				if kPlan and #kPlan > 0 then
					local kTarget = kSet.target or kSet.limit or 1
					local kOk, kErr = pcall(function()
							runCraft(kPlan)
							local kAtt = 0
							while not Craft.cancelled and kAtt < 12 do
								local tNow = groupAvail(kItem, getInv())
								if tNow >= kTarget then break end
								kAtt = kAtt + 1
								resetStock()
								local rP = planProd(kItem, kTarget, true)
								if not (rP and #rP > 0) then break end
								local bK = tNow
								runCraft(rP)
								if groupAvail(kItem, getInv()) <= bK then break end
							end
						end)
					sysStatus = "IDLE"
					if kOk then
						uiMessage = "Crafted: " .. kShort
					else
						uiMessage = "ERR: " .. tostring(kErr):sub(1, 30)
					end
				else
					sysStatus = "IDLE"
					uiMessage = "ERR: no resources for " .. kShort
				end
			else
				uiMessage = kShort .. " already at target"
			end
			if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
			uiMsgTimer = os.startTimer(3)
			scanKeepNow()
		end
		return true
	elseif zone.id == "keep_top" or zone.id == "keep_up" or zone.id == "keep_dn" then
		local fname = zone.arg
		local isFl = (fname:sub(1, 2) == "f:")
		local list = {}
		for iName, s in pairs(Keep.all()) do
			if (iName:sub(1, 2) == "f:") == isFl then
				table.insert(list, {name=iName, order=s.order or 99999})
			end
		end
		table.sort(list, function(a,b) return a.order < b.order end)
		local idx
		for i, e in ipairs(list) do if e.name == fname then idx = i; break end end
		if idx then
			if zone.id == "keep_top" then
				local moved = table.remove(list, idx)
				table.insert(list, 1, moved)
			elseif zone.id == "keep_up" and idx > 1 then
				list[idx], list[idx-1] = list[idx-1], list[idx]
			elseif zone.id == "keep_dn" and idx < #list then
				list[idx], list[idx+1] = list[idx+1], list[idx]
			end
			local slots = {}
			for _, e in ipairs(list) do slots[#slots + 1] = e.order end
			table.sort(slots)
			for i, e in ipairs(list) do
				local ent = Keep.of(e.name)
				if ent then ent.order = slots[i] end
			end
			saveData()
		end
		return true
	elseif zone.id == "toggle_keep_status" then
		local ent = Keep.of(zone.arg)
		if ent then
			ent.paused = not ent.paused
			saveData()
		end
		return true
	elseif zone.id == "remove_keep" then
		Keep.remove(zone.arg)
		local remaining = {}
		for iName, s in pairs(Keep.all()) do
			table.insert(remaining, {name=iName, order=s.order or 99999})
		end
		table.sort(remaining, function(a,b) return a.order < b.order end)
		for ni, ri in ipairs(remaining) do Keep.of(ri.name).order = ni end
		saveData()
		return true
	elseif zone.id == "open_keep_picker" then
		itemToCraft = zone.arg
		fluidCraftMode = nil
		fluidKeepName = nil
		local ex = Keep.of(zone.arg)
		keepThr = (ex and (ex.threshold or ex.limit)) or 64
		keepTgt = (ex and (ex.target or ex.limit)) or (keepThr * 2)
		keepField = "threshold"
		isSettingKeep = true
		isRequestMode = false
		qtyOrigTab = "RECIPES"
		curTab = "QUANTITY_PICKER"
		return true
	elseif zone.id == "keep_edit" then
		itemToCraft = zone.arg
		local ex = Keep.of(zone.arg)
		keepThr = (ex and (ex.threshold or ex.limit)) or 64
		keepTgt = (ex and (ex.target or ex.limit)) or (keepThr * 2)
		keepField = "threshold"
		isSettingKeep = true
		isRequestMode = false
		fluidKeepName = (zone.arg:sub(1, 2) == "f:") and fluidNameOf(zone.arg) or nil
		qtyOrigTab = "KEEP"
		curTab = "QUANTITY_PICKER"
		return true
	elseif zone.id == "keep_field" then
		keepField = zone.arg
		return true
	end
	return false
end

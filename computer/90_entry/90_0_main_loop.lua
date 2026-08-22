local function _handleTouch(param2, param3, touchZones)
	local x, y = param2, param3
	uiMessage = ""
	if uiMsgTimer then os.cancelTimer(uiMsgTimer); uiMsgTimer = nil end
	resetErr()
	pendDelItem = nil
	pendDelFluid = nil
	if idleTimer then os.cancelTimer(idleTimer) end
	idleTimer = os.startTimer(autostockIdle)
	for _, zone in ipairs(touchZones) do
		if zone.id and x >= zone.x1 and x <= zone.x2 and y == zone.y then
			if craftDonePopup and zone.id ~= "popup_close" and zone.id ~= "popup_request" and zone.id ~= "popup_bg" then
				if craftDonePopup.timer then os.cancelTimer(craftDonePopup.timer) end
				craftDonePopup = nil
				break
			end
			if fluidSaveConfirm and zone.id ~= "fluid_save_yes" and zone.id ~= "fluid_save_no" then
				break
			end
			if fluidRecipePicker and zone.id ~= "fluid_pick_recipe" and zone.id ~= "fluid_make_primary"
			and zone.id ~= "fluid_picker_delete" and zone.id ~= "fluid_picker_close" then
				break
			end
			if machInfoPopup and zone.id ~= "close_machine_info" and zone.id ~= "show_machine_info" and zone.id ~= "popup_bg" then
				machInfoPopup = nil
				break
			end
			if craftInfoPop and zone.id ~= "close_craft_info" and zone.id ~= "show_craft_info" and zone.id ~= "popup_bg" then
				craftInfoPop = nil
				break
			end
			if fluidCraftInfo and zone.id ~= "close_fluid_info" and zone.id ~= "show_fluid_info" and zone.id ~= "popup_bg" then
				fluidCraftInfo = nil
				break
			end
			if historyPopup and zone.id ~= "open_history" and zone.id ~= "close_history" and zone.id ~= "history_craft" and zone.id ~= "history_craft_fluid" and zone.id ~= "history_req" and zone.id ~= "history_prev" and zone.id ~= "history_next" and zone.id ~= "history_scan" and zone.id ~= "popup_bg" then
				historyPopup = nil
				break
			end
			if recipeEditPop and zone.id ~= "close_recipe_edit" and zone.id ~= "recipe_edit_select" and zone.id ~= "recipe_edit_apply" and zone.id ~= "recipe_edit_global" and zone.id ~= "recipe_edit_confirm_global" and zone.id ~= "recipe_edit_prev" and zone.id ~= "recipe_edit_next" and zone.id ~= "popup_bg" then
				recipeEditPop = nil
				break
			end
			if curTab == "QUANTITY_PICKER" then
				local isQtyZone = zone.id == "qty_adj" or zone.id == "qty_confirm" or zone.id == "qty_cancel" or zone.id == "qty_max" or zone.id == "qty_type" or zone.id == "keep_field" or zone.id == "popup_bg" or zone.id == "qty_calc_max" or zone.id == "qty_toggle_automax" or zone.id == "qty_add_queue"
				if not isQtyZone then
					isRequestMode = false
					isSettingKeep = false
					altOutEdit = nil
					if queueEditIdx then queueEditIdx = nil; queueEditPopup = true end
					curTab = qtyOrigTab or "RECIPES"
					break
				end
			end
			if queueEditPopup and zone.id == "bg_click" then
				queueEditPopup = false
				queueErrIdx = nil
				break
			end
			if mgmtPopup and zone.id == "bg_click" then
				mgmtPopup = nil
				break
			end
			if custGrpPopup and zone.id == "bg_click" then
				custGrpPopup = nil
				break
			end
			if zone.id == "popup_bg" then break end
			if zone.id == "switch_tab" then
				curTab = zone.arg; curPage = 1
				mgmtPopup = nil
				custGrpPopup = nil
				if zone.arg == "STOCK" then stockFilter = ""; stockModFilter = "All"; stockFilterPage = 1 end
				if zone.arg == "KEEP" then scanKeepNow() end
			elseif zone.id == "set_mod" then
				modFilter = zone.arg; curPage = 1
			elseif zone.id == "mod_prev" then
				modFilterPage = math.max(1, modFilterPage - 1)
			elseif zone.id == "mod_next" then
				modFilterPage = modFilterPage + 1
			elseif _touchRecipes(zone, x, y) then
			elseif _touchFluid(zone, x, y) then
			elseif _touchNetwork(zone, x, y) then
			elseif _touchKeep(zone, x, y) then
			elseif _touchStock(zone, x, y) then
			elseif _touchQty(zone, x, y) then
			elseif _touchAdd(zone, x, y) then
			elseif _touchGit(zone, x, y) then
			elseif _touchMgmt(zone, x, y) then
			end
			break
		end
	end
end

local function mainLoop()
	checkTimer = os.startTimer(6)
	idleTimer   = os.startTimer(autostockIdle)
	local lastTouchX, lastTouchY, lastTouchT = nil, nil, 0
	-- cc monitors are trash and fire double touches for one tap.
	-- turned out to be the wired modem hooked to monitor causing it.
	-- keeping debounce anyway in case some other setup does the same.
	-- 200ms swallows the dupe but leaves real double-clicks alone
	local TOUCH_DEBOUNCE_MS = 200
	while true do
		local touchZones = drawUI()
		term.clear() term.setCursorPos(1,1)
		print("==========================================")
		print(" STATUS: MONITOR DISPLAY ACTIVE ")
		print("==========================================")
		local isSearchTab = (curTab == "RECIPES" or curTab == "STOCK")
		or (curTab == "FLUID" and (fluidSubTab == "FLUID" or fluidSubTab == "FITEM") and not fluidLearnStage and not fluidRecipePicker and not fluidWaitCraft)
		if isSearchTab then
			local sf, label
			if curTab == "RECIPES" then sf, label = srchFilter, "RECIPES"
			elseif curTab == "STOCK" then sf, label = stockFilter, "STOCK"
			else sf, label = fluidSearchFilter, "FLUID" end
			print("")
			print(" [" .. label .. " SEARCH]")
			if sf == "" then
				print(" > _  (type to search)")
			else
				print(" > " .. sf .. "_")
			end
		end
		if remoteRunFlag then
			remoteRunFlag = false
			if sysStatus == "IDLE" and #Craft.queue > 0 then runQueueAll() end
		end
		if remoteKeepRun then
			remoteKeepRun = false
			if sysStatus == "IDLE" and not Config.autostock_paused then runAutostock() end
		end
		local event, param1, param2, param3
		-- drain queue first. programmatic touches (rednet remote, keep_craft_now etc)
		-- run BEFORE whatever the user is poking.
		-- swap-real-for-queued branch below is intentional --
		-- without it a real tap starves out pending remotes forever
		if #pendingTouches > 0 then
			local t = table.remove(pendingTouches, 1)
			event, param1, param2, param3 = t[1], t[2], t[3], t[4]
		else
			event, param1, param2, param3 = os.pullEvent()
			if event == "monitor_touch" and #pendingTouches > 0 then
				local t = table.remove(pendingTouches, 1)
				event, param1, param2, param3 = t[1], t[2], t[3], t[4]
			end
		end
		if event == "monitor_touch" then
			local now = os.epoch("utc")
			if lastTouchX == param2 and lastTouchY == param3 and (now - lastTouchT) < TOUCH_DEBOUNCE_MS then
				event = nil
			else
				lastTouchX, lastTouchY, lastTouchT = param2, param3, now
			end
		end
		if event == "timer" and param1 == checkTimer then
			checkTimer = os.startTimer(6)
		elseif event == "timer" and param1 == uiMsgTimer then
			uiMessage = ""
			uiMsgTimer = nil
		elseif event == "timer" and craftDonePopup and param1 == craftDonePopup.timer then
			craftDonePopup = nil
		elseif event == "timer" and unloadTimer and param1 == unloadTimer then
			unloadActive = false
			unloadTimer = nil
		elseif event == "timer" and optTimer and param1 == optTimer then
			optActive = false
			optTimer = nil
		elseif event == "timer" and scanTimer and param1 == scanTimer then
			scanActive = false
			scanTimer = nil
		elseif event == "timer" and gitStTimer and param1 == gitStTimer then
			gitStatus = ""; gitStColor = colors.gray; gitStTimer = nil
		elseif event == "timer" and param1 == idleTimer then
			if not Config.autostock_paused then
				runAutostock()
			end
			idleTimer = os.startTimer(autostockIdle)
		elseif event == "monitor_touch" then
			_handleTouch(param2, param3, touchZones)
		end
	end
end
REMOTE_PROTOCOL = "aegis_remote"
remoteRunFlag = false
remoteKeepRun = false
stockEpoch = 0
craftResultId = 0
lastCraftMade = 0

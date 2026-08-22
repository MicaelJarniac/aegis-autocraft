function _touchStock(zone, x, y)
	if zone.id == "stock_mod" then
		stockModFilter = zone.arg
		curPage = 1
		return true
	elseif zone.id == "stock_mod_prev" then
		stockFilterPage = math.max(1, stockFilterPage - 1)
		return true
	elseif zone.id == "stock_mod_next" then
		stockFilterPage = stockFilterPage + 1
		return true
	elseif zone.id == "stock_search" then
		stockSearchOn = true
		drawUI()
		term.clear() term.setCursorPos(1,1)
		write("Stock search: ")
		local stInput = timedRead(5)
		stockSearchOn = false
		if stInput ~= nil and stInput ~= "" then stockFilter = stInput end
		curPage = 1
		return true
	elseif zone.id == "stock_clear_search" then
		stockFilter = ""
		curPage = 1
		return true
	elseif zone.id == "pull_from_box" then
		local moved = pullTrainAll()
		if moved > 0 then
			resetStock()
			uiMessage = "Unloaded " .. moved .. " items from train box"
		else
			uiMessage = "Train box is empty or not reachable"
		end
		if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
		uiMsgTimer = os.startTimer(3)
		unloadActive = true
		if unloadTimer then os.cancelTimer(unloadTimer) end
		unloadTimer = os.startTimer(4)
		return true
	elseif zone.id == "stock_optimize" then
		local isTankOpt = (stockModFilter == "TANK")
		uiMessage = isTankOpt and "Optimizing tanks..." or "Optimizing storage..."
		if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
		uiMsgTimer = os.startTimer(1)
		optActive = true
		if optTimer then os.cancelTimer(optTimer) end
		drawUI()
		if isTankOpt then optTanks() else optStore() end
		resetStock()
		uiMessage = isTankOpt and "Tanks optimized!" or "Storage optimized!"
		if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
		uiMsgTimer = os.startTimer(3)
		optTimer = os.startTimer(3)
		return true
	end
	return false
end

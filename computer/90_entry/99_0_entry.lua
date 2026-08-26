local function runMain()
	initData()
	loadData()
	syncFluidStubs()
	openRemote()
	dbgInit()
	if _DEV_MODE and not getmetatable(_G) then
		local seen = {}
		for k in pairs(_G) do seen[k] = true end
		setmetatable(_G, {__newindex = function(t, k, v)
			if not seen[k] then
				seen[k] = true
				local fh = fs.open("dev_globals.log", "a")
				if fh then fh.writeLine(os.clock() .. " " .. tostring(k)); fh.close() end
			end
			rawset(t, k, v)
		end})
	end
	parallel.waitForAny(
		function()
			while true do
				local ev, p1, p2, p3 = os.pullEvent("monitor_touch")
				if sysStatus == "IDLE" then
					pendingTouches[#pendingTouches + 1] = {ev, p1, p2, p3}
					if #pendingTouches > 5 then table.remove(pendingTouches, 1) end
				end
			end
		end,
		function()
			while true do
				local ev, ch = os.pullEvent()
				local noPopup = not custGrpPopup and not mgmtPopup
				and craftInfoPop == nil and machInfoPopup == nil
				and historyPopup == nil and recipeEditPop == nil
				and craftDonePopup == nil and pendDelItem == nil
				local fluidSearchable = curTab == "FLUID" and (fluidSubTab == "FLUID" or fluidSubTab == "FITEM")
				and not fluidLearnStage and not fluidRecipePicker and not fluidWaitCraft
				if ev == "char" and noPopup then
					if curTab == "RECIPES" then
						srchFilter = srchFilter .. ch
						curPage = 1
					elseif curTab == "STOCK" then
						stockFilter = stockFilter .. ch
						curPage = 1
					elseif fluidSearchable then
						fluidSearchFilter = fluidSearchFilter .. ch
						fluidRecipePage = 1
					end
				elseif ev == "key" and noPopup and ch == keys.backspace then
					if curTab == "RECIPES" and #srchFilter > 0 then
						srchFilter = srchFilter:sub(1, -2)
						curPage = 1
					elseif curTab == "STOCK" and #stockFilter > 0 then
						stockFilter = stockFilter:sub(1, -2)
						curPage = 1
					elseif fluidSearchable and #fluidSearchFilter > 0 then
						fluidSearchFilter = fluidSearchFilter:sub(1, -2)
						fluidRecipePage = 1
					end
				end
			end
		end,
		function()
			while true do
				local sid, msg = rednet.receive(REMOTE_PROTOCOL)
				if type(msg) == "table" and msg.cmd then pcall(handleRemote, sid, msg) end
			end
		end,
		mainLoop,
		function()
			while true do
				sleep(10)
				runMgmtTransfers()
			end
		end,
		function()
			while true do
				sleep(5)
				pcall(ntfyPoll)
			end
		end
	)
end
while true do
	local ok, err = pcall(runMain)
	if not ok then
		print("[AUTOCRAFT] Crashed: " .. tostring(err))
		print("[AUTOCRAFT] Restarting in 3s...")
		sleep(3)
	end
end

Keep = {}

function Keep.of(name)
	return Autostock[name]
end

function Keep.put(name, entry)
	Autostock[name] = entry
end

function Keep.remove(name)
	Autostock[name] = nil
end

function Keep.all()
	return Autostock
end

function userIsBusy()
	if curTab == "QUANTITY_PICKER" then return true end
	if mgmtPopup or custGrpPopup or fluidRecipePicker or recipeEditPop
	or craftInfoPop or machInfoPopup or historyPopup or craftDonePopup
	or pendDelItem or pendDelFluid or outPickMode
	or gitExportMode or gitImportMode or fluidLearnStage or fluidWaitCraft then
		return true
	end
	return false
end

function runAutostock()
	if Config.autostock_paused or sysStatus == "MANUAL_CRAFT" then return end
	if userIsBusy() then return end
	local stockInv = getInv()
	local queue = {}
	for itemName, settings in pairs(Keep.all()) do
		table.insert(queue, {
				name      = itemName,
				threshold = settings.threshold or settings.limit or 1,
				target    = settings.target or settings.limit or 1,
				paused    = settings.paused,
				order     = settings.order or 99999,
			})
	end
	table.sort(queue, function(a, b)
			if a.order ~= b.order then return a.order < b.order end
			return a.name < b.name
		end)
	for _, settings in ipairs(queue) do
		local itemName = settings.name
		if settings.paused then
		elseif itemName:sub(1, 2) == "f:" then
			local fname = fluidNameOf(itemName)
			local fprods = fluidProducers(fname)
			if fprods[1] then
				local fcur = (getFluid())[itemName] or 0
				if fcur < settings.threshold then
					local fneed = settings.target - fcur
					if fneed > 0 then
						sysStatus = "AUTO_CRAFT"
						asItem = itemName
						uiMessage = "Autostock fluid: " .. (shortName(fname))
						Craft.locks = {}; fluidTankClaims = 0; _fluidBusy = false; fluidInlineByCo = {}
						pcall(function() produceFluid(fprods[1].recipe, fname, fneed) end)
						sysStatus = "IDLE"
						asItem = ""
						if checkTimer then os.cancelTimer(checkTimer) end
						checkTimer = os.startTimer(2)
						if Craft.cancelled then return end
						stockInv = getInv()
					end
				end
			end
		elseif Recipe.find(itemName) then
			local curCount = stockInv[itemName] or 0
			if curCount < settings.threshold then
				local needed = settings.target - curCount
				local plan, planMiss = nil, nil
				if needed > 0 then
					plan, planMiss = planProd(itemName, needed, false)
				end
				local isPartial = false
				if needed > 0 and (not plan or #plan == 0 or (planMiss and next(planMiss))) then
					plan = nil
					local partialPlan = planProd(itemName, needed, true)
					if partialPlan and #partialPlan > 0 then
						plan = partialPlan
						isPartial = true
					end
				end
				if plan and #plan > 0 then
					sysStatus = "AUTO_CRAFT"
					asItem = itemName
					local shortName = shortName(itemName)
					if isPartial then
						uiMessage = "Partial autostock: " .. shortName
					else
						uiMessage = "Autostocking " .. shortName
					end
					local ok = false
					local craftOk, craftErr = pcall(function()
							ok = runCraft(plan)
							local kAttempts = 0
							while not Craft.cancelled and kAttempts < 12 do
								local totalNow = groupAvail(itemName, getInv())
								if totalNow >= settings.target then break end
								kAttempts = kAttempts + 1
								resetStock()
								local rPlan = planProd(itemName, settings.target, true)
								if not (rPlan and #rPlan > 0) then break end
								local beforeK = totalNow
								runCraft(rPlan)
								if groupAvail(itemName, getInv()) <= beforeK then break end
							end
						end)
					sysStatus = "IDLE"
					asItem = ""
					if checkTimer then os.cancelTimer(checkTimer) end
					checkTimer = os.startTimer(2)
					if not craftOk then
						uiMessage = "ERR: KEEP crashed: " .. tostring(craftErr):sub(1, 40)
						if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
						uiMsgTimer = os.startTimer(5)
					elseif not ok then
						uiMessage = "ERR: KEEP failed for " .. shortName
						if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
						uiMsgTimer = os.startTimer(4)
					else
						uiMessage = "KEEP done: " .. shortName
						if uiMsgTimer then os.cancelTimer(uiMsgTimer) end
						uiMsgTimer = os.startTimer(3)
					end
					if Craft.cancelled then return end
					stockInv = getInv()
				end
			end
		end
	end
end


asItem   = ""
idleTimer              = nil
-- 3 min. less = autostock steals cpu while user still poking around.
-- more = base sits empty too long
autostockIdle      = 180
unloadActive  = false
unloadTimer   = nil
checkTimer    = nil

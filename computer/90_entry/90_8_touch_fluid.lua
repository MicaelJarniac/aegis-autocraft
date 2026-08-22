function _touchFluid(zone, x, y)
	if zone.id == "fluid_subtab" then
		fluidSubTab = zone.arg
		fluidTankPage = 1
		fluidRecipePage = 1
		return true
	elseif zone.id == "fluid_tank_prev" then
		fluidTankPage = math.max(1, fluidTankPage - 1)
		return true
	elseif zone.id == "fluid_tank_next" then
		fluidTankPage = fluidTankPage + 1
		return true
	elseif zone.id == "fluid_recipe_prev" then
		fluidRecipePage = math.max(1, fluidRecipePage - 1)
		return true
	elseif zone.id == "fluid_recipe_next" then
		fluidRecipePage = fluidRecipePage + 1
		return true
	elseif zone.id == "fluid_delete_ask" then
		pendDelFluid = zone.arg
		return true
	elseif zone.id == "fluid_delete_cancel" then
		pendDelFluid = nil
		return true
	elseif zone.id == "fluid_delete_confirm" then
		local prods = fluidProducers(zone.arg)
		if prods[1] then removeFluidRef(prods[1].recipe) end
		pendDelFluid = nil
		syncFluidStubs()
		saveData()
		return true
	elseif zone.id == "open_keep_picker_fluid" then
		local fk = fluidKey(zone.arg)
		if Keep.of(fk) then
			Keep.remove(fk)
			saveData()
		else
			fluidCraftMode = nil
			fluidKeepName = zone.arg
			itemToCraft = fk
			keepThr = 1000
			keepTgt = 2000
			keepField = "threshold"
			isSettingKeep = true
			isRequestMode = false
			qtyOrigTab = "RECIPES"
			curTab = "QUANTITY_PICKER"
		end
		return true
	elseif zone.id == "open_recipe_edit_fluid" then
		local prods = fluidProducers(zone.arg)
		local p = prods[1]
		if p then
			recipeEditPop = {
				fluid = zone.arg, fluidRecipeRef = p.recipe,
				origMachine = p.recipe.machine_name, selected = p.recipe.machine_name,
				confirmGlobal = false, page = 1,
			}
		end
		return true
	elseif zone.id == "fluid_craft" then
		local prods = fluidProducers(zone.arg)
		if prods[1] then fluidCraftFlow(prods[1].recipe, zone.arg) end
		return true
	elseif zone.id == "fluid_alt" then
		altViewFluid = zone.arg
		altViewItem = nil
		curTab = "ALT_VIEW"
		return true
	elseif zone.id == "fluid_pick_recipe" then
		if fluidRecipePicker then
			local p = fluidRecipePicker.producers[zone.arg]
			local fname = fluidRecipePicker.fluid
			if p then fluidCraftFlow(p.recipe, fname) end
		end
		return true
	elseif zone.id == "fluid_make_primary" then
		if fluidRecipePicker then
			local p = fluidRecipePicker.producers[zone.arg]
			if p and p.own and not p.isPrimary and p.altIdx then
				local fk = p.key
				local alts = Fluids.altsOf(fk) or {}
				local chosen = table.remove(alts, p.altIdx)
				local old = Fluids.find(fk)
				Fluids.set(fk, chosen)
				if old then table.insert(alts, 1, old) end
				if #alts == 0 then alts = nil end
				Fluids.setAlts(fk, alts)
				syncFluidStubs()
				saveData()
				fluidRecipePicker.producers = fluidProducers(fluidRecipePicker.fluid)
			end
		end
		return true
	elseif zone.id == "fluid_picker_delete" then
		if fluidRecipePicker then
			local p = fluidRecipePicker.producers[zone.arg]
			if p and p.own then
				local fk = p.key
				if p.isPrimary then
					local alts = Fluids.altsOf(fk)
					if alts and alts[1] then
						Fluids.set(fk, table.remove(alts, 1))
						if #alts == 0 then Fluids.setAlts(fk, nil) end
					else
						Fluids.remove(fk)
					end
				elseif p.altIdx then
					local alts = Fluids.altsOf(fk)
					if alts then
						table.remove(alts, p.altIdx)
						if #alts == 0 then Fluids.setAlts(fk, nil) end
					end
				end
				syncFluidStubs()
				saveData()
				local prods = fluidProducers(fluidRecipePicker.fluid)
				if #prods == 0 then fluidRecipePicker = nil
				else fluidRecipePicker.producers = prods end
			end
		end
		return true
	elseif zone.id == "fluid_picker_close" then
		fluidRecipePicker = nil
		return true
	elseif zone.id == "fluid_save_yes" then
		if fluidSaveConfirm then
			local sc = fluidSaveConfirm
			if sc.asAlt then
				local list = Fluids.altsOf(sc.key) or {}
				table.insert(list, sc.recipe)
				Fluids.setAlts(sc.key, list)
			else
				Fluids.set(sc.key, sc.recipe)
			end
			syncFluidStubs()
			saveData()
			fluidLearnStage = "PICK_INPUT"
			learnInputs = {}
			learnMach = nil
			clearFluidDevs()
			fluidLearnPage = 1
			local prod = {}
			for _, o in ipairs(sc.recipe.outputs or {}) do prod[#prod + 1] = {name = o.name, amount = o.amount, unit = "mB"} end
			for _, o in ipairs(sc.recipe.item_outputs or {}) do prod[#prod + 1] = {name = o.name, amount = o.count, unit = "x"} end
			fluidSaveConfirm = nil
			craftDonePopup = {learned = true, outputs = prod, timer = os.startTimer(10)}
		end
		return true
	elseif zone.id == "fluid_save_no" then
		fluidSaveConfirm = nil
		fluidLearnStage = "PICK_INPUT"
		learnInputs = {}
		learnMach = nil
		clearFluidDevs()
		fluidLearnPage = 1
		return true
	elseif zone.id == "fluid_trigger_search" then
		isSearch = true
		drawUI()
		term.clear() term.setCursorPos(1, 1)
		write("Enter fluid search: ")
		local srInput = timedRead(5)
		isSearch = false
		if srInput ~= nil then fluidSearchFilter = srInput end
		fluidRecipePage = 1
		return true
	elseif zone.id == "fluid_clear_search" then
		fluidSearchFilter = ""
		fluidRecipePage = 1
		return true
	elseif zone.id == "fluid_add" then
		fluidCraftMsg = ""
		fluidLearnStage = "PICK_INPUT"
		learnInputs = {}
		learnMach = nil
		clearFluidDevs()
		fluidLearnPage = 1
		fluidScanStatus = ""
		return true
	elseif zone.id == "fluid_learn_cancel" then
		fluidLearnStage = nil
		learnInputs = {}
		learnMach = nil
		clearFluidDevs()
		fluidLearnPage = 1
		fluidScanStatus = ""
		return true
	elseif zone.id == "fluid_learn_prev" then
		fluidLearnPage = math.max(1, fluidLearnPage - 1)
		return true
	elseif zone.id == "fluid_learn_next" then
		fluidLearnPage = fluidLearnPage + 1
		return true
	elseif zone.id == "fluid_pick_input" then
		local existIdx = nil
		for i, inp in ipairs(learnInputs) do
			if inp.name == zone.arg then existIdx = i; break end
		end
		if existIdx then
			table.remove(learnInputs, existIdx)
		elseif #learnInputs < 5 then
			qtyTypeAct = true
			fluidWaitInput = zone.arg
			drawUI()
			term.clear(); term.setCursorPos(1, 1)
			print("Enter mB for:")
			print(zone.arg)
			write("> ")
			local input = timedRead(30)
			fluidWaitInput = nil
			qtyTypeAct = false
			local num = tonumber(input)
			if num and num > 0 then
				learnInputs[#learnInputs + 1] = {name = zone.arg, amount = math.floor(num)}
			end
		end
		return true
	elseif zone.id == "fluid_learn_done_inputs" then
		fluidLearnStage = "PICK_MACHINE"
		fluidLearnPage = 1
		return true
	elseif zone.id == "fluid_learn_back_inputs" then
		fluidLearnStage = "PICK_INPUT"
		clearFluidDevs()
		fluidLearnPage = 1
		return true
	elseif zone.id == "fluid_pick_machine" then
		if fluidOutPick then
			learnOut = zone.arg; fluidOutPick = false
		elseif fluidItemInPick then
			learnItemIn = zone.arg; fluidItemInPick = false
		elseif fluidInPick then
			learnFluidIn = zone.arg; fluidInPick = false
		elseif itemOutPick then
			learnItemOut = zone.arg; itemOutPick = false
		elseif learnMach == zone.arg then
			learnMach = nil
			clearFluidDevs()
		else
			learnMach = zone.arg
		end
		return true
	elseif zone.id == "fluid_pull_toggle" then
		fluidItemInPick = false; fluidInPick = false; itemOutPick = false
		if fluidOutPick then fluidOutPick = false
		elseif learnOut then learnOut = nil
		else fluidOutPick = true end
		return true
	elseif zone.id == "fluid_iteminput_toggle" then
		fluidOutPick = false; fluidInPick = false; itemOutPick = false
		if fluidItemInPick then fluidItemInPick = false
		elseif learnItemIn then learnItemIn = nil
		else fluidItemInPick = true end
		return true
	elseif zone.id == "fluid_fluidin_toggle" then
		fluidOutPick = false; fluidItemInPick = false; itemOutPick = false
		if fluidInPick then fluidInPick = false
		elseif learnFluidIn then learnFluidIn = nil
		else fluidInPick = true end
		return true
	elseif zone.id == "fluid_itemout_toggle" then
		fluidOutPick = false; fluidItemInPick = false; fluidInPick = false
		if itemOutPick then itemOutPick = false
		elseif learnItemOut then learnItemOut = nil
		else itemOutPick = true end
		return true
	elseif zone.id == "fluid_learn_scan" and learnMach then
		sysStatus = "MANUAL_CRAFT"
		Craft.cancelled = false
		fluidScanStatus = "Scanning: waiting for mix (tap CANCEL to stop)..."
		drawUI()
		local okScan, recipe, errLines = runFluidScan(learnInputs, learnMach, learnOut, learnItemIn, learnFluidIn, learnItemOut)
		sysStatus = "IDLE"
		fluidScanStatus = ""
		Craft.cancelled = false
		craftCancelY = nil
		if okScan and recipe then
			local fk = primaryKey(recipe)
			local asAlt = (Fluids.find(fk) ~= nil)
			fluidSaveConfirm = {recipe = recipe, key = fk, asAlt = asAlt}
		else
			craftErrTitle = "! FLUID SCAN FAILED"
			craftErrLines = errLines or {"Unknown error"}
		end
		return true
	elseif zone.id == "show_fluid_info" then
		local prods = fluidProducers(zone.arg)
		local perOp = (prods[1] and prods[1].perOp) or 1
		local fStock = {}
		for k, v in pairs(getInv()) do fStock[k] = v end
		fStock[fluidKey(zone.arg)] = 0
		local fMiss = {}
		simFluidConsume(zone.arg, perOp, fStock, fMiss, {}, {})
		fluidCraftInfo = {name = zone.arg, missing = fMiss}
		return true
	elseif zone.id == "close_fluid_info" then
		fluidCraftInfo = nil
		return true
	end
	return false
end

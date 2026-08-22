local function toggleMgmtPeri(field, name)
	if not mgmtPopup then return end
	local listKey = field .. "s"
	local lst = mgmtPopup[listKey] or {}
	if name == "STORAGE" then
		lst = {}
	else
		local found
		for i, nm in ipairs(lst) do if nm == name then found = i; break end end
		if found then table.remove(lst, found) else lst[#lst + 1] = name end
	end
	mgmtPopup[listKey] = lst
	mgmtPopup[field]   = lst[1] or "STORAGE"
	mgmtPopup.fluid = isFluidPeri(mgmtPopup.input) or isFluidPeri(mgmtPopup.output)
end

local function closeMgmtPopup()
	if mgmtPopup and mgmtPopup.openerGi and mgmtPopup.openerBtn then
		mgmtActBtn = {gi=mgmtPopup.openerGi, btn=mgmtPopup.openerBtn, t=os.clock()}
	end
	mgmtPopup = nil
end

function _touchMgmt(zone, x, y)
	if zone.id == "mgmt_sync_now" then
		syncFlashTime = os.clock()
		runMgmtTransfers()
		return true
	elseif zone.id == "mgmt_new" then
		mgmtPopup = {
			mode="edit", groupIdx=nil,
			name="", input="STORAGE", output="STORAGE", rules={},
			inputs={}, outputs={},
			drain=false, provider=false,
			step="main", periPage=1, outPeriPage=1, itemPage=1,
		}
		return true
	elseif zone.id == "mgmt_edit" then
		local g = MgmtGroups[zone.arg]
		if g then
			mgmtActBtn = nil
			local rc = {}
			for _, r in ipairs(g.rules or {}) do
				local rcond = nil
				if r.condition then
					rcond = {item=r.condition.item, op=r.condition.op, value=r.condition.value}
				end
				table.insert(rc, {item=r.item, amount=r.amount, condition=rcond})
			end
			local inl, outl = {}, {}
			for _, nm in ipairs(mgmtIOList(g, true))  do if nm ~= "STORAGE" then inl[#inl+1]  = nm end end
			for _, nm in ipairs(mgmtIOList(g, false)) do if nm ~= "STORAGE" then outl[#outl+1] = nm end end
			mgmtPopup = {
				mode="edit", groupIdx=zone.arg,
				name=g.name,
				input  = g.input  or "STORAGE",
				output = g.output or "STORAGE",
				inputs = inl, outputs = outl,
				rules=rc,
				drain  = g.drain  or false,
				provider = g.provider or false,
				fluid  = isFluid(g),
				step="main", periPage=1, outPeriPage=1, itemPage=1,
				openerGi=zone.arg, openerBtn="edit",
			}
		end
		return true
	elseif zone.id == "mgmt_pause" then
		local g = MgmtGroups[zone.arg]
		if g then
			g.paused = not (g.paused or false)
			mgmtActBtn = {gi=zone.arg, btn="pause", t=os.clock()}
			saveData()
		end
		return true
	elseif zone.id == "mgmt_del" then
		mgmtActBtn = nil
		table.remove(MgmtGroups, zone.arg)
		saveData()
		return true
	elseif zone.id == "mgmt_view" then
		local g = MgmtGroups[zone.arg]
		if g then
			mgmtActBtn = nil
			mgmtPopup = {mode="view_input", groupIdx=zone.arg, page=1,
				openerGi=zone.arg, openerBtn="view"}
		end
		return true
	elseif zone.id == "mgmt_list_prev" then
		mgmtPage = math.max(1, mgmtPage - 1)
		return true
	elseif zone.id == "mgmt_list_next" then
		mgmtPage = mgmtPage + 1
		return true
	elseif zone.id == "mgmt_edit_name" then
		if mgmtPopup then
			drawUI()
			term.clear(); term.setCursorPos(1,1)
			write("Group name: ")
			local inp = read()
			if inp and inp ~= "" then mgmtPopup.name = inp end
		end
		return true
	elseif zone.id == "mgmt_rule_type" then
		if mgmtPopup then
			local ri3t = zone.arg
			local rule = mgmtPopup.rules[ri3t]
			if rule then
				drawUI()
				term.clear(); term.setCursorPos(1,1)
				write("Amount for " .. (shortName(rule.item)) .. ": ")
				local inp = read()
				local n = tonumber(inp)
				if n and n >= 1 then rule.amount = math.floor(n) end
			end
		end
		return true
	elseif zone.id == "mgmt_pick_input" then
		if mgmtPopup then mgmtPopup.step = "input_select"; mgmtPopup.periPage = 1 end
		return true
	elseif zone.id == "mgmt_set_input" then
		toggleMgmtPeri("input", zone.arg)
		return true
	elseif zone.id == "mgmt_peri_prev" then
		if mgmtPopup then mgmtPopup.periPage = math.max(1, mgmtPopup.periPage - 1) end
		return true
	elseif zone.id == "mgmt_peri_next" then
		if mgmtPopup then mgmtPopup.periPage = mgmtPopup.periPage + 1 end
		return true
	elseif zone.id == "mgmt_peri_cancel" then
		if mgmtPopup then mgmtPopup.step = "main" end
		return true
	elseif zone.id == "mgmt_pick_output" then
		if mgmtPopup then mgmtPopup.step = "output_select"; mgmtPopup.outPeriPage = 1 end
		return true
	elseif zone.id == "mgmt_set_output" then
		toggleMgmtPeri("output", zone.arg)
		return true
	elseif zone.id == "mgmt_pick_item" then
		if mgmtPopup then
			mgmtPopup.step = "item_select"; mgmtPopup.itemPage = 1
			mgmtItemSrch = ""; mgmtSearchOn = false
		end
		return true
	elseif zone.id == "mgmt_add_rule" then
		if mgmtPopup then
			local condIdx = mgmtPopup.condRuleIdx
			if condIdx then
				local rule = mgmtPopup.rules[condIdx]
				if rule then
					if not rule.condition then rule.condition = {op="<", value=1} end
					rule.condition.item = zone.arg
				end
				mgmtPopup.condRuleIdx = nil
			else
				local exists = false
				for _, r in ipairs(mgmtPopup.rules) do
					if r.item == zone.arg then exists = true; break end
				end
				if not exists then
					table.insert(mgmtPopup.rules, {item=zone.arg, amount=(mgmtPopup.fluid and 1000 or 64)})
				end
			end
			mgmtPopup.step = "main"
		end
		return true
	elseif zone.id == "mgmt_item_prev" then
		if mgmtPopup then mgmtPopup.itemPage = math.max(1, mgmtPopup.itemPage - 1) end
		return true
	elseif zone.id == "mgmt_item_next" then
		if mgmtPopup then mgmtPopup.itemPage = mgmtPopup.itemPage + 1 end
		return true
	elseif zone.id == "mgmt_rules_prev" then
		if mgmtPopup then mgmtPopup.rulesPage = math.max(1, (mgmtPopup.rulesPage or 1) - 1) end
		return true
	elseif zone.id == "mgmt_rules_next" then
		if mgmtPopup then mgmtPopup.rulesPage = (mgmtPopup.rulesPage or 1) + 1 end
		return true
	elseif zone.id == "mgmt_item_cancel" then
		if mgmtPopup then
			mgmtPopup.condRuleIdx = nil
			mgmtPopup.step = "main"
		end
		return true
	elseif zone.id == "mgmt_rule_adj" then
		if mgmtPopup then
			local ri3  = zone.arg[1]
			local delta = zone.arg[2]
			local rule = mgmtPopup.rules[ri3]
			if rule then
				local stepU = mgmtPopup.fluid and 100 or 1
				local capU  = mgmtPopup.fluid and 1000000 or 9999
				rule.amount = math.max(1, math.min(capU, rule.amount + delta * stepU))
			end
		end
		return true
	elseif zone.id == "mgmt_rule_del" then
		if mgmtPopup then table.remove(mgmtPopup.rules, zone.arg) end
		return true
	elseif zone.id == "mgmt_toggle_drain" then
		if mgmtPopup then
			mgmtPopup.drain = not (mgmtPopup.drain or false)
			if mgmtPopup.drain then mgmtPopup.provider = false end
		end
		return true
	elseif zone.id == "mgmt_toggle_provider" then
		if mgmtPopup then
			mgmtPopup.provider = not (mgmtPopup.provider or false)
			if mgmtPopup.provider then mgmtPopup.drain = false end
		end
		return true
	elseif zone.id == "mgmt_rule_if_add" then
		if mgmtPopup then
			local ri = zone.arg
			local rule = mgmtPopup.rules[ri]
			if rule then
				rule.condition = {item = "", op = "<", value = 1}
				mgmtPopup.condRuleIdx = ri
				mgmtPopup.step = "item_select"
				mgmtPopup.itemPage = 1
				mgmtItemSrch = ""
				mgmtSearchOn = false
			end
		end
		return true
	elseif zone.id == "mgmt_rule_if_item" then
		if mgmtPopup then
			mgmtPopup.condRuleIdx = zone.arg
			mgmtPopup.step = "item_select"
			mgmtPopup.itemPage = 1
			mgmtItemSrch = ""
			mgmtSearchOn = false
		end
		return true
	elseif zone.id == "mgmt_rule_if_op" then
		if mgmtPopup then
			local rule = mgmtPopup.rules[zone.arg]
			if rule and rule.condition then
				local ops = {"<", "=", ">"}
				local cur = rule.condition.op or "<"
				for i, op in ipairs(ops) do
					if op == cur then
						rule.condition.op = ops[(i % #ops) + 1]
						break
					end
				end
			end
		end
		return true
	elseif zone.id == "mgmt_rule_if_adj" then
		if mgmtPopup then
			local rule = mgmtPopup.rules[zone.arg[1]]
			if rule and rule.condition then
				local stepC = mgmtPopup.fluid and 100 or 1
				local capC  = mgmtPopup.fluid and 1000000 or 99999
				rule.condition.value = math.max(1, math.min(capC,
						(rule.condition.value or 1) + zone.arg[2] * stepC))
			end
		end
		return true
	elseif zone.id == "mgmt_rule_if_type" then
		if mgmtPopup then
			local rule = mgmtPopup.rules[zone.arg]
			if rule and rule.condition then
				local cName = shortName(rule.condition.item)
				drawUI()
				term.clear(); term.setCursorPos(1,1)
				write("IF value for " .. cName .. ": ")
				local inp = read()
				local n = tonumber(inp)
				if n and n >= 1 then rule.condition.value = math.floor(n) end
			end
		end
		return true
	elseif zone.id == "mgmt_rule_if_del" then
		if mgmtPopup then
			local rule = mgmtPopup.rules[zone.arg]
			if rule then rule.condition = nil end
		end
		return true
	elseif zone.id == "mgmt_outperi_prev" then
		if mgmtPopup then mgmtPopup.outPeriPage = math.max(1, (mgmtPopup.outPeriPage or 1) - 1) end
		return true
	elseif zone.id == "mgmt_outperi_next" then
		if mgmtPopup then mgmtPopup.outPeriPage = (mgmtPopup.outPeriPage or 1) + 1 end
		return true
	elseif zone.id == "mgmt_outperi_cancel" then
		if mgmtPopup then mgmtPopup.step = "main" end
		return true
	elseif zone.id == "mgmt_save" then
		if mgmtPopup then
			if mgmtPopup.name == "" then
				uiMessage = "Enter a group name first!"
				uiMsgTimer = os.startTimer(2)
			else
				local inl  = mgmtPopup.inputs  or {}
				local outl = mgmtPopup.outputs or {}
				local newG = {
					name   = mgmtPopup.name,
					inputs = inl,
					outputs = outl,
					input  = inl[1]  or "STORAGE",
					output = outl[1] or "STORAGE",
					rules  = mgmtPopup.rules  or {},
					drain  = mgmtPopup.drain  or false,
					provider = mgmtPopup.provider or false,
					fluid  = mgmtPopup.fluid or isFluid({input=inl[1] or "STORAGE", output=outl[1] or "STORAGE"}),
					paused = mgmtPopup.groupIdx and (MgmtGroups[mgmtPopup.groupIdx] and MgmtGroups[mgmtPopup.groupIdx].paused or false) or false,
				}
				if mgmtPopup.groupIdx then
					MgmtGroups[mgmtPopup.groupIdx] = newG
				else
					table.insert(MgmtGroups, newG)
				end
				saveData()
				closeMgmtPopup()
			end
		end
		return true
	elseif zone.id == "mgmt_cancel" then
		closeMgmtPopup()
		return true
	elseif zone.id == "mgmt_close_view" then
		closeMgmtPopup()
		return true
	elseif zone.id == "mgmt_vinput_prev" then
		if mgmtPopup then mgmtPopup.page = math.max(1, mgmtPopup.page - 1) end
		return true
	elseif zone.id == "mgmt_vinput_next" then
		if mgmtPopup then mgmtPopup.page = mgmtPopup.page + 1 end
		return true
	elseif zone.id == "mgmt_search_focus" then
		mgmtSearchOn = true
		drawUI()
		term.clear() term.setCursorPos(1,1)
		write("> ")
		local srInput = timedRead(5)
		mgmtSearchOn = false
		if srInput ~= nil then
			mgmtItemSrch = srInput
		end
		if mgmtPopup then mgmtPopup.itemPage = 1 end
		return true
	elseif zone.id == "mgmt_search_clear" then
		mgmtItemSrch = ""
		if mgmtPopup then mgmtPopup.itemPage = 1 end
		return true
	end
	return false
end

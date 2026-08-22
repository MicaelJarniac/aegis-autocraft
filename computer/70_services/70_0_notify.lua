function b64enc(s)
	local r = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i+2); b = b or 0; c = c or 0
		local n = a*65536 + b*256 + c
		r[#r+1] = _B64:sub(math.floor(n/262144)%64+1, math.floor(n/262144)%64+1)
		r[#r+1] = _B64:sub(math.floor(n/4096)%64+1,   math.floor(n/4096)%64+1)
		r[#r+1] = _B64:sub(math.floor(n/64)%64+1,     math.floor(n/64)%64+1)
		r[#r+1] = _B64:sub(n%64+1,                    n%64+1)
	end
	local p = #s % 3
	if p == 1 then r[#r] = "="; r[#r-1] = "=" elseif p == 2 then r[#r] = "=" end
	return table.concat(r)
end

function b64dec(s)
	s = s:gsub("[^A-Za-z0-9+/=]", "")
	local r = {}
	for i = 1, #s, 4 do

		local function v(c) return c == "=" and 0 or (_B64:find(c, 1, true) - 1) end
		local a, b, c, d = v(s:sub(i,i)), v(s:sub(i+1,i+1)), v(s:sub(i+2,i+2)), v(s:sub(i+3,i+3))
		local n = a*262144 + b*4096 + c*64 + d
		r[#r+1] = string.char(math.floor(n/65536)%256)
		if s:sub(i+2,i+2) ~= "=" then r[#r+1] = string.char(math.floor(n/256)%256) end
		if s:sub(i+3,i+3) ~= "=" then r[#r+1] = string.char(n%256) end
	end
	return table.concat(r)
end

function httpGetSync(url, headers)
	local ok, handle = pcall(http.get, url, headers)
	if not ok or not handle then return nil end
	local d = handle.readAll(); handle.close(); return d
end

function ntfyCraftDone(label, qty, isFluid)
	local topic = Config.ntfy_topic
	if not topic or topic == "" then return end
	if not (http and http.request) then return end
	local url = topic:find("://") and topic or ("https://ntfy.sh/" .. topic)
	local short = shortName(label)
	local body
	if qty and qty > 0 then
		body = isFluid and (short .. " " .. qty .. " mB") or (qty .. "x " .. short)
	else
		body = short .. " done"
	end
	-- fire and forget. http.request is async in cc, if we wait for response
	-- and ntfy is down we block the whole loop. no thanks
	pcall(function()
			http.request({url = url, method = "POST", body = body,
					headers = {["Title"] = "AEGIS craft done", ["Tags"] = "white_check_mark"}})
		end)
end

function ntfyCraftFail(label)
	local topic = Config.ntfy_topic
	if not topic or topic == "" then return end
	if not (http and http.request) then return end
	local url = topic:find("://") and topic or ("https://ntfy.sh/" .. topic)
	local short = label and (shortName(label)) or "craft"
	local body  = "INTERRUPTED: " .. short
	local stage = Craft.lastFailStage and shortName(Craft.lastFailStage) or nil
	if stage and stage ~= short then body = body .. "\nstage: " .. stage end
	if Craft.lastFail then
		body = body .. "\nwhy: " .. tostring(Craft.lastFail):sub(1, 200)
	end
	pcall(function()
			http.request({url = url, method = "POST", body = body,
					headers = {["Title"] = "AEGIS craft failed", ["Priority"] = "high", ["Tags"] = "x"}})
		end)
end

function ntfyBaseUrl()
	local topic = Config.ntfy_topic
	if not topic or topic == "" then return nil end
	return topic:find("://") and topic or ("https://ntfy.sh/" .. topic)
end

function ntfyPublish(body, title, tags)
	local url = ntfyBaseUrl()
	if not url then return end
	if not (http and http.request) then return end
	pcall(function()
			http.request({url = url, method = "POST", body = tostring(body),
					headers = {["Title"] = title or "AEGIS", ["Tags"] = tags or "robot"}})
		end)
end

function buildStatus()
	local ctx = displayCtx
	if ctx and (ctx.total or 0) > 0 and not ctx.done then
		local sDone  = stageDone or 0
		local sTotal = math.max(stageTotal or 0, sDone, 1)
		local pct  = math.floor(sDone / sTotal * 100)
		local goal = ctx.finalGoal or "?"
		goal = shortName(goal)
		local lines = { goal .. " " .. pct .. "% (" .. sDone .. "/" .. sTotal .. ")" }
		local n = 0
		for _, a in pairs(ctx.active or {}) do
			if n >= 6 then break end
			lines[#lines + 1] = "- " .. tostring(a.desc or "?") .. " " .. (a.done or 0) .. "/" .. (a.total or 0)
			n = n + 1
		end
		if n == 0 then lines[#lines + 1] = "(scheduling...)" end
		return table.concat(lines, "\n")
	end
	if sysStatus and sysStatus ~= "IDLE" then
		local s = "Busy: " .. tostring(sysStatus)
		if fluidGoalLabel and fluidGoalLabel ~= "" then
			local g = shortName(fluidGoalLabel)
			s = s .. "\n" .. g .. " step " .. (fluidStepNum or 0) .. "/" .. math.max(fluidStepNum or 0, fluidStepTotal or 0)
		end
		return s
	end
	local q = #(Craft.queue or {})
	if q > 0 then return "IDLE. Queue: " .. q .. " waiting." end
	return "IDLE. No active craft."
end

function buildQueueTxt()
	local q = Craft.queue or {}
	if #q == 0 then return "Queue empty." end
	local lines = {}
	for i = 1, math.min(8, #q) do
		local qe = q[i]
		local nm = shortName(qe.name)
		local unit = (qe.kind == "fluid" and not qe.isItem) and " mB" or "x"
		lines[#lines + 1] = i .. ". " .. nm .. " " .. qe.qty .. unit .. (qe.failed and " [FAIL]" or "")
	end
	if #q > 8 then lines[#lines + 1] = "... +" .. (#q - 8) .. " more" end
	return table.concat(lines, "\n")
end

function ntfyPoll()
	if Config.ntfy_cmds == false then return end
	local url = ntfyBaseUrl()
	if not url then return end
	if not (http and http.get) then return end
	local since = ntfyLastId and ("&since=" .. textutils.urlEncode(ntfyLastId)) or "&since=15s"
	local ok, handle = pcall(http.get, url .. "/json?poll=1" .. since)
	if not ok or not handle then return end
	local body = handle.readAll(); handle.close()
	if not body or body == "" then return end
	local want = nil
	for line in body:gmatch("[^\n]+") do
		local okJ, obj = pcall(textutils.unserializeJSON, line)
		if okJ and type(obj) == "table" and obj.event == "message" then
			if obj.id then ntfyLastId = obj.id end
			local title = tostring(obj.title or "")
			if title:sub(1, 5) ~= "AEGIS" then
				local msg = tostring(obj.message or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
				if msg:sub(1, 1) == "/" then msg = msg:sub(2) end
				if msg == "status" or msg == "stat" or msg == "s" then want = "status"
				elseif msg == "queue" or msg == "q" then want = "queue"
				elseif msg == "cancel" or msg == "stop" then want = "cancel" end
			end
		end
	end
	if want == "status" then
		ntfyPublish(buildStatus(), "AEGIS status", "bar_chart")
	elseif want == "queue" then
		ntfyPublish(buildQueueTxt(), "AEGIS queue", "clipboard")
	elseif want == "cancel" then
		Craft.cancelled = true
		ntfyPublish("Cancel requested.", "AEGIS status", "octagonal_sign")
	end
end

function queueRunOne(qe)
	if qe.kind == "fluid" then
		local fOk, fProduced, fIsItem = fluidCraft(qe.recipe, qe.name, qe.qty)
		if fOk then
			ntfyCraftDone(qe.name, fProduced, not fIsItem)
			lastCraftMade = fProduced
			return true
		end
		ntfyCraftFail(qe.name)
		local reason = {}
		for li = 1, math.min(4, #craftErrLines) do reason[li] = craftErrLines[li] end
		if #reason == 0 then reason[1] = "Fluid craft failed" end
		return false, reason
	end
	local preStock = groupAvail(qe.name, getInv())
	Craft.cancelled = false
	local plan, missingRes = planProd(qe.name, qe.qty, true)
	if plan and #plan == 0 and not next(missingRes or {}) then return true end
	if next(missingRes or {}) then
		local reason = {}
		for mName, mCnt in pairs(missingRes) do
			if #reason >= 4 then break end
			reason[#reason + 1] = "Need " .. mCnt .. "x " .. (shortName(mName))
		end
		if #reason == 0 then reason[1] = "Missing components" end
		return false, reason
	end
	local craftOk = false
	if plan and #plan > 0 then
		craftOk = runCraft(plan)
		local tlA = 0
		while not Craft.cancelled and tlA < 12 do
			local totalNow = groupAvail(qe.name, getInv())
			if totalNow >= qe.qty then break end
			tlA = tlA + 1
			local rPlan = planProd(qe.name, qe.qty, true)
			if not (rPlan and #rPlan > 0) then break end
			local beforeTL = totalNow
			if runCraft(rPlan) then craftOk = true end
			if groupAvail(qe.name, getInv()) <= beforeTL then break end
		end
	end
	if craftOk then
		lastCraftMade = math.max(0, groupAvail(qe.name, getInv()) - preStock)
		ntfyCraftDone(qe.name, lastCraftMade, false)
		return true
	end
	ntfyCraftFail(qe.name)
	local reason = {}
	if craftErrTitle then reason[#reason + 1] = craftErrTitle end
	for li = 1, #craftErrLines do
		if #reason >= 4 then break end
		reason[#reason + 1] = tostring(craftErrLines[li])
	end
	for mName, mCnt in pairs(missingRes or {}) do
		if #reason >= 4 then break end
		reason[#reason + 1] = "Need " .. mCnt .. "x " .. (shortName(mName))
	end
	if #reason == 0 then reason[1] = "Craft failed" end
	return false, reason
end


ntfyLastId = nil

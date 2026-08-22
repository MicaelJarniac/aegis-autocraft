local function promptField(activeId, prompt, masked)
	gitActiveBtn = activeId
	drawUI()
	term.clear(); term.setCursorPos(1,1)
	write(prompt)
	local input = masked and read("*") or read()
	gitActiveBtn = ""
	return input
end

local function promptNewExportName()
	local defName = "autocraft_" .. tostring(math.floor(os.epoch("utc") / 1000))
	gitStatus = "Type filename on PC keyboard..."
	gitStColor = colors.yellow
	drawUI()
	term.clear(); term.setCursorPos(1,1)
	print("==========================================")
	print(" GIT EXPORT: NEW FILE                     ")
	print("==========================================")
	print("")
	print("Enter filename (without .json)")
	print("Default: " .. defName)
	print("Press ENTER to use default or empty to cancel.")
	print("")
	write("> ")
	local fname = timedRead(60, defName)
	gitExportMode = false
	gitStatus = ""; gitStColor = colors.gray
	if fname and fname ~= "" then
		fname = fname:gsub("%.json$", "") .. ".json"
		gitExport(fname, nil)
	end
end

function _touchGit(zone, x, y)
	if zone.id == "git_set_repo" then
		local input = promptField("git_set_repo", "GitHub repo (owner/repo): ", true)
		if input and input ~= "" then Config.github_repo = input; saveData() end
		return true
	elseif zone.id == "git_set_token" then
		local input = promptField("git_set_token", "GitHub token (ghp_...): ", true)
		if input and input ~= "" then Config.github_token = input; saveData() end
		return true
	elseif zone.id == "git_set_ntfy" then
		local input = promptField("git_set_ntfy", "ntfy topic or full URL (empty = off): ", false)
		Config.ntfy_topic = (input and input ~= "") and input or nil
		saveData()
		return true
	elseif zone.id == "log_toggle" then
		if Config.debug_log == true then
			Config.debug_log = false
			DBG_LOG_ENABLED = false
			dbgWipe()
			uiMessage = "Debug log OFF (files wiped)"
		else
			Config.debug_log = true
			DBG_LOG_ENABLED = true
			uiMessage = "Debug log ON"
		end
		saveData()
		return true
	elseif zone.id == "git_export" then
		gitActiveBtn = "git_export"
		gitListForExport()
		gitActiveBtn = ""
		return true
	elseif zone.id == "git_export_select" then
		gitExportSel = zone.arg
		if zone.arg == 0 then promptNewExportName() end
		return true
	elseif zone.id == "git_confirm_export" then
		if gitExportSel == 0 then
			promptNewExportName()
		else
			gitExportMode = false
			local file = gitExportList[gitExportSel]
			if file then gitExport(file.name, file.sha) end
		end
		return true
	elseif zone.id == "git_cancel_export" then
		gitExportMode = false
		gitExportList = {}
		gitExportSel = 0
		gitStatus = ""; gitStColor = colors.gray
		return true
	elseif zone.id == "git_import_list" then
		gitActiveBtn = "git_import_list"
		gitListFiles()
		gitActiveBtn = ""
		return true
	elseif zone.id == "git_select_file" then
		gitSelFile = zone.arg
		return true
	elseif zone.id == "git_import_prev" then
		gitImportPage = math.max(1, gitImportPage - 1)
		return true
	elseif zone.id == "git_import_next" then
		gitImportPage = gitImportPage + 1
		return true
	elseif zone.id == "git_export_prev" then
		gitExportPage = math.max(1, gitExportPage - 1)
		return true
	elseif zone.id == "git_export_next" then
		gitExportPage = gitExportPage + 1
		return true
	elseif zone.id == "git_confirm_import" then
		gitImport()
		return true
	elseif zone.id == "git_cancel_import" then
		gitImportMode = false
		gitFileList = {}
		gitStatus = ""
		gitStColor = colors.gray
		return true
	end
	return false
end

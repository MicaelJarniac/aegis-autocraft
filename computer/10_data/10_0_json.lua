function parseJSON(str)
	local result = textutils.unserializeJSON(str)
	if result == textutils.empty_json_array then return {} end
	return result
end

_savedCounts = {}
restoredFromBak = false

function loadDataFile(path)
	if not fs.exists(path) then return nil end
	local fh = fs.open(path, "r")
	if not fh then return nil end
	local raw = fh.readAll() or ""
	fh.close()
	local parsed = parseJSON(raw)
	local bak = path .. ".bak"
	if type(parsed) == "table" and next(parsed) ~= nil then
		local n = 0
		for _ in pairs(parsed) do n = n + 1 end
		_savedCounts[path] = n
		-- 0-byte .bak = corpse from a previous crash. treat as absent
		-- so we write a fresh one instead of trusting garbage
		if fs.exists(bak) and fs.getSize(bak) == 0 then fs.delete(bak) end
		if not fs.exists(bak) then
			local free = fs.getFreeSpace("/") or 0
			if free > #raw + 4096 then
				local bh = fs.open(bak, "w")
				if bh then bh.write(raw); bh.close() end
			end
		end
		return parsed
	end
	-- parse failed but the file has real content.
	-- freeze a .corrupt copy for post-mortem before falling to .bak
	if #raw > 2 and parsed == nil then
		fs.delete(path .. ".corrupt")
		pcall(fs.copy, path, path .. ".corrupt")
	end
	if fs.exists(bak) then
		local bh = fs.open(bak, "r")
		if bh then
			local bp = parseJSON(bh.readAll() or "")
			bh.close()
			if type(bp) == "table" and next(bp) ~= nil then
				local n = 0
				for _ in pairs(bp) do n = n + 1 end
				_savedCounts[path] = n
				restoredFromBak = true
				return bp
			end
		end
	end
	if type(parsed) == "table" then _savedCounts[path] = 0 end
	return parsed
end


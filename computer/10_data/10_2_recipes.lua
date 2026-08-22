function findDup(outName, cand)
	local function sig(r)
		if type(r) ~= "table" or r.type == "fluid" then return nil end
		local parts = {}
		for i = 1, 9 do parts[i] = tostring(r.ingredients and r.ingredients[i] or "nil") end
		if r.type ~= "turtle" then table.sort(parts) end
		return tostring(r.type) .. "|" .. tostring(r.machine_name) .. "|" .. table.concat(parts, ",")
	end

	local target = sig(cand)
	if not target then return false end

	local ex = Recipe.find(outName)
	if ex and sig(ex) == target then return true end
	for _, alt in ipairs(Recipe.altsOf(outName) or {}) do
		if sig(alt) == target then return true end
	end
	return false
end

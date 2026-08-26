local gridSlots = {1, 2, 3, 5, 6, 7, 9, 10, 11}
local LAYOUT_DELAY = 1.5

local function getGridCount()
	local total = 0
	for _, slot in ipairs(gridSlots) do
		total = total + turtle.getItemCount(slot)
	end
	return total
end

local function gridSig()
	local parts = {}
	for _, slot in ipairs(gridSlots) do
		local d = turtle.getItemDetail(slot)
		parts[#parts + 1] = d and (d.name .. "x" .. d.count) or "-"
	end
	return table.concat(parts, "|")
end

local function craftLoop()
	local lastFailSig = nil
	local settled = false
	local seen = 0
	while true do
		turtle.select(16)
		local cnt = getGridCount()
		-- crafting only ever drains the grid, so a count that went UP means the
		-- computer is laying out a new recipe and the settle check runs again
		if cnt == 0 or cnt > seen then settled = false end
		seen = cnt
		if cnt > 0 and turtle.getItemCount(16) == 0 then
			local sig = gridSig()
			if sig == lastFailSig then
				sleep(0.2)
			elseif not settled then
				-- a laggy server pushes the recipe slot by slot. craft only once
				-- the whole grid held still for LAYOUT_DELAY, otherwise we craft
				-- whatever half a layout happens to look like
				sleep(LAYOUT_DELAY)
				settled = (gridSig() == sig)
			elseif turtle.craft() then
				seen = getGridCount()
			else
				lastFailSig = sig
				settled = false
			end
		else
			lastFailSig = nil
			sleep(0.05)
		end
	end
end

while true do
	local ok, err = pcall(craftLoop)
	if not ok then
		print("[TURTLE] Crashed: " .. tostring(err))
		print("[TURTLE] Restarting in 3s...")
		sleep(3)
	end
end

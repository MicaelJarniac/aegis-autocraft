-- create mechanical crafter grid. one grid per computer, every crafter has its
-- own wired modem. cell order = Config.crafter.cells, recipes store one
-- ingredient per cell ("nil" = empty), so a recipe only fits the grid it was
-- learned on.
-- crafter inventory is INSERT ONLY (create calls forbidExtraction). nothing we
-- push in can be pulled back out, so every load checks stock + empty cells first
-- and a failed load leaves the grid locked for the player to empty by hand.
-- clutch relay ON = clutch disengaged = speed 0 = crafters never start.
CRAFTER_MACHINE = "mechanical_crafter"
-- slowest crafter speed (4 rpm) on a 5x5 chain is ~2 min per craft
CRAFTER_TIMEOUT = 180
CRAFTER_START_WAIT = 6
RELAY_SIDES = {"top", "bottom", "left", "right", "front", "back"}
CRAFTER_REMAINDERS = {
	["minecraft:bucket"] = true, ["minecraft:glass_bottle"] = true, ["minecraft:bowl"] = true,
}

function crafterCfg()
	if type(Config.crafter) ~= "table" then Config.crafter = {} end
	if type(Config.crafter.cells) ~= "table" then Config.crafter.cells = {} end
	return Config.crafter
end

function isCrafterPeriph(name)
	if type(name) ~= "string" then return false end
	if name:find("mechanical_crafter", 1, true) then return true end
	local ok, has = pcall(peripheral.hasType, name, "create:mechanical_crafter")
	return ok and has == true
end

function isRelayPeriph(name)
	if type(name) ~= "string" then return false end
	local ok, has = pcall(peripheral.hasType, name, "redstone_relay")
	return ok and has == true
end

-- crafters + the devices tagged for the grid stay out of machine pickers
function isCrafterRole(name)
	if isCrafterPeriph(name) then return true end
	local c = Config.crafter
	if type(c) ~= "table" then return false end
	return name == c.out or name == c.clutch or name == c.pulse
end

local function sufNum(n) return tonumber(n:match("_(%d+)$")) or math.huge end

function detectCrafters()
	local out = {}
	for _, p in ipairs(peripheral.getNames()) do
		if not SYSTEM_SIDES[p] and isCrafterPeriph(p) then out[#out + 1] = p end
	end
	table.sort(out, function(a, b)
		local na, nb = sufNum(a), sufNum(b)
		if na ~= nb then return na < nb end
		return a < b
	end)
	return out
end

function crafterCellIdx(name)
	for i, n in ipairs(crafterCfg().cells) do
		if n == name then return i end
	end
	return nil
end

function crafterSetLock(on)
	local c = crafterCfg()
	if not (c.clutch and c.clutch_side) then return false, "clutch relay not set" end
	local r = peripheral.wrap(c.clutch)
	if not (r and r.setOutput) then return false, "clutch relay offline" end
	local ok = pcall(r.setOutput, c.clutch_side, on and true or false)
	if not ok then return false, "clutch relay error" end
	return true
end

-- true = locked, false = running, nil = no relay
function crafterLocked()
	local c = crafterCfg()
	if not (c.clutch and c.clutch_side) then return nil end
	local r = peripheral.wrap(c.clutch)
	if not (r and r.getOutput) then return nil end
	local ok, v = pcall(r.getOutput, c.clutch_side)
	if not ok then return nil end
	return v and true or false
end

-- crafter starts on a RISING edge. drop low first: after a chunk reload create
-- thinks it was already powered and eats the first high as "no change"
function crafterPulse()
	local c = crafterCfg()
	if not (c.pulse and c.pulse_side) then return false end
	local r = peripheral.wrap(c.pulse)
	if not (r and r.setOutput) then return false end
	pcall(r.setOutput, c.pulse_side, false)
	sleep(0.1)
	pcall(r.setOutput, c.pulse_side, true)
	sleep(0.3)
	pcall(r.setOutput, c.pulse_side, false)
	return true
end

-- false+why when the grid cant be used. why is shown as "machine" in popups.
-- need = recipe.grid_cells, every one of them has to still be in the grid
function crafterReady(need)
	local c = crafterCfg()
	if #c.cells == 0 then return false, "no crafter grid registered" end
	for _, n in ipairs(c.cells) do
		if not peripheral.wrap(n) then return false, n end
	end
	for _, n in ipairs(need or {}) do
		if not crafterCellIdx(n) then return false, n end
	end
	if not (c.clutch and c.clutch_side) then return false, "clutch relay not set" end
	if not peripheral.wrap(c.clutch) then return false, c.clutch end
	if not c.out then return false, "crafter output not set" end
	if not peripheral.wrap(c.out) then return false, c.out end
	return true
end

-- one entry per cell: item name or "nil"
function crafterReadCells()
	local cells = crafterCfg().cells
	local scanned = scanPeriph(cells, "list", true)
	local res = {}
	for i, n in ipairs(cells) do
		local e = scanned[n]
		if not (e and e.data) then return nil, "crafter offline: " .. n end
		-- wrench-linked inputs = every modem sees the whole combined inventory
		if e.size and e.size > 1 then
			return nil, "crafter inputs are linked (wrench) - unlink them"
		end
		local it = e.data[1]
		res[i] = (it and it.name) or "nil"
	end
	return res
end

-- a loaded cell going empty = create began the chain (begin() empties every
-- inventory at once). still full after the wait = never kicked
function crafterWaitStart(loaded, secs)
	local t, repulsed = 0, false
	while t < secs do
		sleepCancel(0.5)
		t = t + 0.5
		if Craft.cancelled then return false end
		local cur = crafterReadCells()
		if cur then
			for idx, ing in ipairs(loaded) do
				if ing ~= "nil" and cur[idx] == "nil" then return true end
			end
		end
		-- first pulse can land before the network spun back up (speed 0 = ignored)
		if not repulsed and t >= 2.5 then
			repulsed = true
			crafterPulse()
		end
	end
	return false
end

-- unlock + kick. returns true once the chain is running
function crafterStart(loaded)
	local ok, err = crafterSetLock(false)
	if not ok then return false, err end
	sleepCancel(0.6)
	crafterPulse()
	return crafterWaitStart(loaded, CRAFTER_START_WAIT)
end

function crafterOutList()
	local c = crafterCfg()
	local o = c.out and peripheral.wrap(c.out)
	if not (o and o.list) then return {} end
	local ok, items = pcall(o.list)
	return (ok and items) or {}
end

-- everything in the output inv -> dst list. returns {name = moved}
function crafterDrainOut(dstNames)
	local c = crafterCfg()
	local got = {}
	local o = c.out and peripheral.wrap(c.out)
	if not (o and o.pushItems) then return got end
	local dsts = {}
	for _, s in ipairs(dstNames) do if s ~= c.out then dsts[#dsts + 1] = s end end
	for slot, it in pairs(crafterOutList()) do
		if it and (it.count or 0) > 0 then
			local left = it.count
			for _, s in ipairs(packOrder(it.name, dsts)) do
				if left <= 0 then break end
				local okP, mv = pcall(o.pushItems, s, slot, left)
				if okP and type(mv) == "number" and mv > 0 then
					left = left - mv
					packRemember(it.name, s)
					got[it.name] = (got[it.name] or 0) + mv
				end
			end
		end
	end
	if next(got) then resetStock() end
	return got
end

-- main product out of a crafter result. leftover containers ride along
function crafterPickResult(agg)
	local best, bestN = nil, -1
	for nm, cnt in pairs(agg) do
		if not CRAFTER_REMAINDERS[nm] and cnt > bestN then best, bestN = nm, cnt end
	end
	if not best then
		for nm, cnt in pairs(agg) do
			if cnt > bestN then best, bestN = nm, cnt end
		end
	end
	return best, bestN
end

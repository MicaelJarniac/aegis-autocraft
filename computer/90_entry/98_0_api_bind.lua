-- everything below just points aegis.* at existing internals.
-- if a wrapper does more than shuffle args it belongs in the module, not here.
-- keep this file dumb on purpose

aegis.storage.count = function(name) return groupAvail(name, getInvCached()) end
aegis.storage.list  = getInvCached

aegis.recipes.get   = Recipe.find
aegis.recipes.list  = Recipe.all
aegis.recipes.alts  = Recipe.altsOf

aegis.fluids.get       = Fluids.find
aegis.fluids.list      = Fluids.all
aegis.fluids.producers = fluidProducers
aegis.fluids.inventory = getFluidCached

aegis.craft.max = remoteMax

function aegis.craft.canMake(name, count)
	return remoteMax(name) >= (tonumber(count) or 1)
end

-- run defaults on. pass {run=false} to just enqueue and let the ui pick it up
function aegis.craft.start(name, count, opts)
	if type(name) ~= "string" then return nil, "bad name" end
	local qty = math.max(1, math.floor(tonumber(count) or 1))
	if Recipe.find(name) then
		Craft.queue[#Craft.queue + 1] = { kind = "item", name = name, qty = qty }
	else
		local prod = fluidProducers(name)
		if not (prod and prod[1] and prod[1].recipe) then
			return nil, "no recipe: " .. name
		end
		Craft.queue[#Craft.queue + 1] = { kind = "fluid", name = name, qty = qty, recipe = prod[1].recipe }
	end
	if not opts or opts.run ~= false then remoteRunFlag = true end
	return #Craft.queue
end

aegis.jobs.status = buildRemote
aegis.jobs.queue  = function() return Craft.queue end

-- no arg = kill the current craft. with idx = just drop that queue entry
function aegis.jobs.cancel(idx)
	if idx == nil then Craft.cancelled = true; return true end
	local qi = tonumber(idx)
	if qi and Craft.queue[qi] then table.remove(Craft.queue, qi); return true end
	return false
end

Fluids = {}

function Fluids.find(fk)
	return FluidRecipes[fk]
end

function Fluids.altsOf(fk)
	return FluidAltRecipes[fk]
end

function Fluids.set(fk, recipe)
	FluidRecipes[fk] = recipe
end

function Fluids.setAlts(fk, alts)
	FluidAltRecipes[fk] = alts
end

function Fluids.remove(fk)
	FluidRecipes[fk] = nil
end

function Fluids.all()
	return FluidRecipes
end

function Fluids.allAlts()
	return FluidAltRecipes
end

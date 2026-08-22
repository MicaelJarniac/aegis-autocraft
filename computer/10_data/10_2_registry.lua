Groups = {}

function Groups.altsOf(itemName)
	local key = ITEM_GROUPS[itemName]
	if not key then return nil end
	return GROUPS[key]
end

Recipe = {}

function Recipe.find(name)
	return Recipes[name]
end

function Recipe.altsOf(name)
	return AltRecipes[name]
end

function Recipe.set(name, r)
	Recipes[name] = r
end

function Recipe.setAlts(name, alts)
	AltRecipes[name] = alts
end

function Recipe.remove(name)
	Recipes[name] = nil
end

function Recipe.all()
	return Recipes
end

function Recipe.allAlts()
	return AltRecipes
end

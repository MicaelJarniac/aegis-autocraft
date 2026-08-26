MONITOR_SIDE = "right"
SYSTEM_SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }

RECIPES_FILE        = "factory_recipes.json"
CONFIG_FILE         = "factory_config.json"
AUTOSTOCK_FILE      = "factory_autostock.json"
GROUPS_FILE         = "factory_groups.json"
ALT_RECIPES_FILE    = "factory_alt_recipes.json"
MGMT_FILE           = "factory_mgmt.json"
MACHINE_LABELS_FILE = "factory_machine_labels.json"
CUSTOM_MG_FILE      = "factory_custom_mg.json"
FLUIDS_FILE         = "factory_fluids.json"
FLUID_ALTS_FILE     = "factory_fluid_alts.json"

Config = {
	storages         = {},
	fluid_tanks      = {},
	train_box        = nil,
	turtles          = {},
	autostock_paused = false,
	github_repo      = "",
	github_token     = "",
}

function shortName(n) return n and (n:match(":(.+)$") or n) end

_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

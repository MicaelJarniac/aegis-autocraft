-- old crap globals waiting to get killed. dont add new stuff here.
-- moved out one domain at a time (Recipe, Fluids, Machines, Groups, Keep done).
-- when this file is empty, delete it
Recipes          = {}
AltRecipes       = {}
FluidRecipes     = {}
FluidAltRecipes  = {}
FluidStock       = {}
Autostock        = {}
ExcludedMachines = {}

MgmtGroups          = {}
MachineLabels       = {}
CustomMachineGroups = {}
ITEM_GROUPS         = {}
GROUPS              = {}

stageDone  = 0
stageTotal = 0

craftCancelY  = nil
craftCancelX1 = 2
craftCancelX2 = 20

fluidTankClaims = 0
_fluidBusy = false
fluidInlineByCo = {}

fluidGoalLabel      = ""
fluidStepNum        = 0
fluidStepTotal      = 1
fluidSubLabel       = ""
fluidCraftMsg       = ""
fluidWaitInput = nil
fluidWaitCraft = nil

uiMessage      = ""
uiMsgTimer     = nil
pendingTouches = {}

displayCtx = nil

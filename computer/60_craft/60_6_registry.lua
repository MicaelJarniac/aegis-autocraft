Craft = {
	cancelled       = false,
	failed          = false,
	lastFailStage   = nil,
	lastFail  = nil,
	depth           = 0,
	locks           = {},
	usedMachines    = {},
	cleanMachines = {},
	queue           = {},
	jobId           = 0,
	jobSrc          = nil,
}

ensureDepthByCo = {}
failReasonByCo  = {}

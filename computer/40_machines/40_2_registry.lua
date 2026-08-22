Machines = {}

function Machines.label(name)
	return MachineLabels[name]
end

function Machines.setLabel(name, lbl)
	MachineLabels[name] = lbl
end

function Machines.excluded(name)
	return ExcludedMachines[name] == true
end

function Machines.exclude(name, on)
	if on then
		ExcludedMachines[name] = true
	else
		ExcludedMachines[name] = nil
	end
end

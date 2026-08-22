monitor = peripheral.wrap(MONITOR_SIDE)
if not monitor then
	monitor = peripheral.find("monitor")
	if monitor then MONITOR_SIDE = peripheral.getName(monitor) end
end
if not monitor then error("Monitor not found on any side") end
monitor.setTextScale(0.5)

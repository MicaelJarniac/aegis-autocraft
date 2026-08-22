aegis = {
	version = "0.1.0",
	storage = {},
	recipes = {},
	craft   = {},
	jobs    = {},
	fluids  = {},
}
function aegis.rpc(path, args)
	local node = aegis
	for part in tostring(path):gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil, "bad path: " .. path end
		node = node[part]
	end
	if type(node) ~= "function" then return nil, "no method: " .. path end
	return node(table.unpack(args or {}))
end

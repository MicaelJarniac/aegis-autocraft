local DIR = "aegis"

if not fs.isDir(DIR) then
	error("A.E.G.I.S: /" .. DIR .. "/ missing. Run the installer.", 0)
end

local files = {}
local function walk(dir)
	for _, entry in ipairs(fs.list(dir)) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			walk(full)
		elseif entry:match("^%d%d_.+%.lua$") then
			files[#files + 1] = full
		end
	end
end
walk(DIR)
-- sort by BASENAME not fullpath. NN_ prefix is what matters.
-- broke this once using full path, spent an hour figuring out why order was wrong
table.sort(files, function(a, b) return fs.getName(a) < fs.getName(b) end)

if #files == 0 then
	error("A.E.G.I.S: no NN_*.lua modules under /" .. DIR .. "/", 0)
end

local buf = {}
for _, f in ipairs(files) do
	local h = fs.open(f, "r")
	buf[#buf + 1] = h.readAll()
	h.close()
end

local chunk, err = load(table.concat(buf, "\n"), "aegis")
if not chunk then error("A.E.G.I.S load error: " .. err, 0) end

chunk()


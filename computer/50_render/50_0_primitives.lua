_COLOR_BLIT = {
	[colors.white]     = "0", [colors.orange]    = "1",
	[colors.magenta]   = "2", [colors.lightBlue] = "3",
	[colors.yellow]    = "4", [colors.lime]       = "5",
	[colors.pink]      = "6", [colors.gray]       = "7",
	[colors.lightGray] = "8", [colors.cyan]       = "9",
	[colors.purple]    = "a", [colors.blue]       = "b",
	[colors.brown]     = "c", [colors.green]      = "d",
	[colors.red]       = "e", [colors.black]      = "f",
}
_fb     = {}
_fbLast = {}
_fbW, _fbH = 0, 0

function _bufInit(w, h)
	_fbW, _fbH = w, h
	_fb = {}
	for y = 1, h do
		local t, f, b = {}, {}, {}
		for x = 1, w do t[x] = " "; f[x] = "0"; b[x] = "f" end
		_fb[y] = {t = t, f = f, b = b}
	end
end

function _bufWrite(x, y, text, fg, bg)
	local row = _fb[y]; if not row then return end
	local fh = _COLOR_BLIT[fg] or "0"
	local bh = _COLOR_BLIT[bg] or "f"
	for i = 1, #text do
		local col = x + i - 1
		if col >= 1 and col <= _fbW then
			row.t[col] = text:sub(i, i)
			row.f[col] = fh
			row.b[col] = bh
		end
	end
end

function _bufClearLine(y, bg)
	_bufWrite(1, y, string.rep(" ", _fbW), colors.white, bg)
end

function _bufFillRect(x, y, rw, rh, bg)
	local row = string.rep(" ", rw)
	for dy = 0, rh - 1 do _bufWrite(x, y + dy, row, colors.white, bg) end
end

function _bufFlush()
	for y = 1, _fbH do
		local row = _fb[y]
		local ts  = table.concat(row.t)
		local fs  = table.concat(row.f)
		local bs  = table.concat(row.b)
		local prev = _fbLast[y]
		if not prev or prev[1] ~= ts or prev[2] ~= fs or prev[3] ~= bs then
			monitor.setCursorPos(1, y)
			monitor.blit(ts, fs, bs)
			_fbLast[y] = {ts, fs, bs}
		end
	end
end

function drawText(x, y, text, fg, bg)
	_bufWrite(x, y, text, fg or colors.white, bg or colors.black)
end

function drawProgBar(x, y, width, current, max, bgColor)
	bgColor = bgColor or colors.black
	local percent = math.min(1, math.max(0, current / max))
	local filledChars = math.floor(percent * (width - 2))
	local emptyChars = (width - 2) - filledChars
	local barStr = "[" .. string.rep("|", filledChars) .. string.rep(".", emptyChars) .. "]"
	drawText(x, y, barStr, colors.lime, bgColor)
	drawText(x + width + 1, y, string.format("%d%%", math.floor(percent * 100)), colors.white, bgColor)
end


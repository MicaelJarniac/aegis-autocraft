UI = {}
UI.C = {
	bg = colors.black, fg = colors.white, muted = colors.gray, soft = colors.lightGray,
	accent = colors.lime, danger = colors.red, warn = colors.orange, info = colors.cyan,
	hi = colors.yellow, rowBg = colors.gray,
}
UI.S = {
	ok     = {fg = colors.black, bg = colors.lime},
	danger = {fg = colors.white, bg = colors.red},
	warn   = {fg = colors.black, bg = colors.orange},
	cool   = {fg = colors.black, bg = colors.cyan},
	mute   = {fg = colors.white, bg = colors.gray},
	soft   = {fg = colors.black, bg = colors.lightGray},
	tabon  = {fg = colors.black, bg = colors.lime},
	taboff = {fg = colors.lightGray, bg = colors.gray},
	hi     = {fg = colors.black, bg = colors.yellow},
	okhi   = {fg = colors.white, bg = colors.lime},
}

function UI.zone(zones, id, arg, x, y, w1)
	zones[#zones + 1] = {id = id, arg = arg, x1 = x, x2 = x + w1 - 1, y = y}
end

function UI.zoneP(zones, id, arg, x, y, w1)
	table.insert(zones, 1, {id = id, arg = arg, x1 = x, x2 = x + w1 - 1, y = y})
end

function UI.btn(zones, x, y, label, style, id, arg)
	local s = UI.S[style] or UI.S.mute
	drawText(x, y, label, s.fg, s.bg)
	UI.zone(zones, id, arg, x, y, #label)
	return x + #label
end

function UI.btnP(zones, x, y, label, style, id, arg)
	local s = UI.S[style] or UI.S.mute
	drawText(x, y, label, s.fg, s.bg)
	UI.zoneP(zones, id, arg, x, y, #label)
	return x + #label
end

function UI.btnR(zones, x2, y, label, style, id, arg)
	local x = x2 - #label + 1
	UI.btn(zones, x, y, label, style, id, arg)
	return x
end

function UI.text(x, y, text, fg, bg)
	drawText(x, y, text, fg or UI.C.fg, bg or UI.C.bg)
end

function UI.textC(y, w, text, fg, bg)
	local x = math.floor((w - #text) / 2) + 1
	drawText(x, y, text, fg or UI.C.fg, bg or UI.C.bg)
end

function UI.rule(y, w, ch, fg)
	drawText(1, y, string.rep(ch or "-", w), fg or UI.C.muted)
end

function UI.popup(pW, pH, w, h, hdr, hdrStyle, minY)
	local pX = math.max(1, math.floor((w - pW) / 2) + 1)
	local pY = math.max(minY or 1, math.floor((h - pH) / 2) + 1)
	_bufFillRect(pX, pY, pW, pH, colors.gray)
	if hdr and hdr ~= "" then
		local s = UI.S[hdrStyle] or UI.S.ok
		drawText(pX + math.floor((pW - #hdr) / 2), pY, hdr, s.fg, s.bg)
	end
	return pX, pY, {x1 = pX, x2 = pX + pW - 1, y1 = pY, y2 = pY + pH - 1}
end

function UI.tabBtn(zones, x, y, label, id, active, arg)
	UI.btn(zones, x, y, label, "mute", id, arg)
	if active then UI.text(x, y + 1, string.rep("-", #label), UI.C.accent) end
	return x + #label
end

function UI.subTabs(zones, y, w, items, active, id)
	local total = 0
	for i, name in ipairs(items) do total = total + #name + 4 + (i > 1 and 2 or 0) end
	local x = math.floor((w - total) / 2) + 1
	for _, name in ipairs(items) do
		local lbl = " [ " .. name .. " ] "
		local isOn = (name == active)
		drawText(x, y, lbl, isOn and UI.C.fg or UI.C.muted, isOn and UI.C.rowBg or UI.C.bg)
		if isOn then drawText(x, y + 1, string.rep("-", #lbl), UI.C.accent, UI.C.bg) end
		UI.zone(zones, id, name, x, y, #lbl)
		x = x + #lbl + 2
	end
end

function UI.miniPager(zones, y, cx, page, total, prevId, nextId, prepend)
	local pgStr = page .. "/" .. total
	local prevS, nextS = " [<] ", " [>] "
	local navW = #prevS + 1 + #pgStr + 1 + #nextS
	local navX = cx - math.floor(navW / 2)
	local canP, canN = page > 1, page < total
	drawText(navX, y, prevS, canP and UI.C.fg or UI.C.muted, UI.C.rowBg)
	drawText(navX + #prevS + 1, y, pgStr, UI.C.accent, UI.C.rowBg)
	drawText(navX + #prevS + 1 + #pgStr + 1, y, nextS, canN and UI.C.fg or UI.C.muted, UI.C.rowBg)
	local add = prepend and UI.zoneP or UI.zone
	if canP then add(zones, prevId, nil, navX, y, #prevS) end
	if canN then add(zones, nextId, nil, navX + #prevS + 1 + #pgStr + 1, y, #nextS) end
end

function UI.pager(zones, y, w, page, total, prevId, nextId)
	UI.rule(y - 1, w)
	local prevStr, nextStr = " [ PREV ] ", " [ NEXT ] "
	local pageStr = string.format(" PAGE %d OF %d ", page, math.max(1, total))
	local startX = math.floor((w - (#prevStr + #pageStr + #nextStr + 4)) / 2)
	local prevFg = page > 1 and UI.C.fg or UI.C.soft
	local nextFg = page < total and UI.C.fg or UI.C.soft
	drawText(startX, y, prevStr, prevFg, UI.C.rowBg)
	drawText(startX + #prevStr + 2, y, pageStr, UI.C.accent, UI.C.bg)
	local nextX = startX + #prevStr + #pageStr + 4
	drawText(nextX, y, nextStr, nextFg, UI.C.rowBg)
	if page > 1 then UI.zone(zones, prevId or "prev_page", nil, startX, y, #prevStr) end
	if page < total then UI.zone(zones, nextId or "next_page", nil, nextX, y, #nextStr) end
end


function zebraBg(idx)    return (idx % 2 == 0) and colors.gray or colors.black end

DBG_LOG_ENABLED = false

DBG_LOG_FILE = "factory_dbg.log"
DBG_LOG_MAX  = 256 * 1024

_dbgJobSeq = 0

function dbgInit()
	DBG_LOG_ENABLED = (Config and Config.debug_log == true) or false
	if not DBG_LOG_ENABLED then return end
	local sz = fs.exists(DBG_LOG_FILE) and (fs.getSize(DBG_LOG_FILE) or 0) or 0
	if sz > DBG_LOG_MAX then
		fs.delete(DBG_LOG_FILE .. ".old")
		fs.move(DBG_LOG_FILE, DBG_LOG_FILE .. ".old")
	end
	local fh = fs.open(DBG_LOG_FILE, "a")
	if fh then
		fh.writeLine(string.format("%.2f ---- boot cid=%d", os.clock(), os.getComputerID()))
		fh.close()
	end
end

function dbgWipe()
	fs.delete(DBG_LOG_FILE)
	fs.delete(DBG_LOG_FILE .. ".old")
end

function dbgWrite(line)
	if not DBG_LOG_ENABLED then return end
	local fh = fs.open(DBG_LOG_FILE, "a")
	if not fh then return end
	fh.writeLine(string.format("%.2f %s", os.clock(), line))
	fh.close()
end

function dbgNextJob(src)
	_dbgJobSeq = _dbgJobSeq + 1
	dbgWrite(string.format("j=%d job.new src=%s", _dbgJobSeq, tostring(src or "?")))
	return _dbgJobSeq
end

local function shortItem(n) return n and (n:match(":(.+)$") or n) or "?" end

function dbgStart(jid, sid, idx, item, count, kind)
	if not DBG_LOG_ENABLED then return end
	dbgWrite(string.format("j=%d s=%d start idx=%d item=%s count=%d kind=%s",
		jid or 0, sid or 0, idx or 0, shortItem(item), count or 0, kind or "?"))
end

function dbgPush(jid, sid, idx, item, added, total, want, storage, reserved, mach)
	if not DBG_LOG_ENABLED then return end
	local line = string.format("j=%d s=%d push idx=%d item=%s add=%d tot=%d/%d sto=%d res=%d",
		jid or 0, sid or 0, idx or 0, shortItem(item),
		added or 0, total or 0, want or 0, storage or 0, reserved or 0)
	if mach then line = line .. " mach=" .. tostring(mach) end
	dbgWrite(line)
end

function dbgFluidPush(jid, sid, idx, fluid, added, total, want, storage, reserved, mach)
	if not DBG_LOG_ENABLED then return end
	local line = string.format("j=%d s=%d push idx=%d fluid=%s add=%d tot=%d/%d sto=%d res=%d",
		jid or 0, sid or 0, idx or 0, shortItem(fluid),
		added or 0, total or 0, want or 0, storage or 0, reserved or 0)
	if mach then line = line .. " mach=" .. tostring(mach) end
	dbgWrite(line)
end

function dbgPool(jid, sid, idx, event, detail)
	if not DBG_LOG_ENABLED then return end
	dbgWrite(string.format("j=%d s=%d pool.%s idx=%d %s",
		jid or 0, sid or 0, tostring(event or "?"), idx or 0, tostring(detail or "")))
end

function dbgLoad(jid, sid, idx, mach, want, got, note)
	if not DBG_LOG_ENABLED then return end
	local line = string.format("j=%d s=%d load idx=%d mach=%s want=%d got=%d",
		jid or 0, sid or 0, idx or 0, tostring(mach), want or 0, got or 0)
	if note then line = line .. " " .. note end
	dbgWrite(line)
end

function dbgExhaust(jid, sid, idx, mach, remainOps)
	if not DBG_LOG_ENABLED then return end
	dbgWrite(string.format("j=%d s=%d exhaust idx=%d mach=%s remainOps=%d",
		jid or 0, sid or 0, idx or 0, tostring(mach), remainOps or 0))
end

function failReason(reason)
	failReasonByCo[lockOwnerId()] = reason
end

function dbgDone(jid, sid, idx, item, produced, ok, err)
	if not DBG_LOG_ENABLED then return end
	local line = string.format("j=%d s=%d done idx=%d item=%s prod=%d ok=%d",
		jid or 0, sid or 0, idx or 0, shortItem(item), produced or 0, ok and 1 or 0)
	if not ok then
		local reason = failReasonByCo[lockOwnerId()]
		local errTxt
		if type(err) == "table" then errTxt = table.concat(err, ";")
		elseif err then                 errTxt = tostring(err)
		elseif reason then              errTxt = reason
		else                            errTxt = tostring(craftErrTitle or "?") .. "|" .. table.concat(craftErrLines or {}, ";") end
		line = line .. " err=" .. errTxt:gsub("%s+", " "):sub(1, 120)
	end
	dbgWrite(line)
	-- dont wipe failReasonByCo here. dbgFail runs AFTER dbgDone in the worker
	-- and needs reason to know who kicked off the cascade. cleared when
	-- worker picks up its next node (see runCraft reset)
end

function dbgFail(jid, sid, idx, item, reason)
	if not DBG_LOG_ENABLED then return end
	dbgWrite(string.format("j=%d s=%d FAIL idx=%d item=%s reason=%s",
		jid or 0, sid or 0, idx or 0, shortItem(item), tostring(reason or "?"):sub(1, 120)))
end

function dbgPreunload(jid, sid, idx, mach, drained, dirty)
	if not DBG_LOG_ENABLED then return end
	local parts = {}
	for name, cnt in pairs(drained or {}) do
		parts[#parts + 1] = shortItem(name) .. "=" .. tostring(cnt)
	end
	local line = string.format("j=%d s=%d preunload idx=%d mach=%s drained=%s",
		jid or 0, sid or 0, idx or 0, tostring(mach),
		(#parts > 0) and table.concat(parts, ",") or "-")
	if dirty then line = line .. " dirty" end
	dbgWrite(line)
end

function dbgPhase(jid, sid, idx, item, timings)
	if not DBG_LOG_ENABLED then return end
	local parts = {}
	for _, k in ipairs({"ensure", "tokens", "preunload", "scan", "setup"}) do
		if timings[k] then parts[#parts + 1] = string.format("%s=%.2fs", k, timings[k]) end
	end
	dbgWrite(string.format("j=%d s=%d phase idx=%d item=%s %s",
		jid or 0, sid or 0, idx or 0, shortItem(item), table.concat(parts, " ")))
end

function dbgTokens(jid, sid, idx, event, toks, waited)
	if not DBG_LOG_ENABLED then return end
	local tstr = "-"
	if toks and #toks > 0 then tstr = table.concat(toks, ",") end
	local line = string.format("j=%d s=%d tokens.%s idx=%d toks=%s",
		jid or 0, sid or 0, tostring(event or "?"), idx or 0, tstr)
	if waited and waited > 0.05 then line = line .. string.format(" waited=%.2fs", waited) end
	dbgWrite(line)
end

function dbgLeftover(jid, sid, idx, mach, item, count)
	if not DBG_LOG_ENABLED then return end
	dbgWrite(string.format("j=%d s=%d leftover idx=%d mach=%s item=%s count=%d",
		jid or 0, sid or 0, idx or 0, tostring(mach), shortItem(item), count or 0))
end

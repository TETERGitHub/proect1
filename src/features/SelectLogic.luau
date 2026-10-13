--!nonstrict
-- features/SelectLogic: pure target-selection rules for Select Aim (no Roblox APIs).
-- It works on TEST targets only: the caller supplies already-projected candidates, the module decides
-- which one is eligible / selected / locked and why a previous target was dropped. It never fires, aims
-- a camera or touches hit registration - it only answers "which test target is selected?".

local Logic = {}

Logic.MODES = { "Crosshair", "Distance", "Manual" }

-- target = { id, name, alive, onScreen, sx, sy, dist, visible(true|false|nil), pos{x,y,z}, vel{x,y,z} }
-- cfg    = { mode, fov, lock, visibilityCheck, centerX, centerY, autoAcquire }
-- state  = { id, manualId, suspended, forceAcquire }

-- eligibility(t, cfg) -> ok, whyNot, screenDistance
function Logic.eligibility(t, cfg)
	if not t.alive then
		return false, "inactive"
	end
	if not t.onScreen then
		return false, "off-screen"
	end
	local dx, dy = t.sx - cfg.centerX, t.sy - cfg.centerY
	local d = math.sqrt(dx * dx + dy * dy)
	if d > cfg.fov then
		return false, "outside-fov", d
	end
	if cfg.visibilityCheck and t.visible == false then
		return false, "hidden", d
	end
	return true, nil, d
end

local function byId(a, b)
	return a.id < b.id
end

-- evaluate(targets, cfg, state) -> result
-- result = { id, status, lost, eligible = {ids}, screenDist }
--   status: "no-targets" | "none" | "suspended" | "selected" | "locked" | "manual-wait"
--   lost:   nil | { id, reason }   reason: "removed" | "inactive" | "off-screen" | "outside-fov" | "hidden"
function Logic.evaluate(targets, cfg, state)
	local result = { id = nil, status = "none", lost = nil, eligible = {}, screenDist = nil }
	local byKey, eligible, screenDist = {}, {}, {}
	for _, t in ipairs(targets) do
		byKey[t.id] = t
		local ok, why, d = Logic.eligibility(t, cfg)
		screenDist[t.id] = d
		t._why = why
		if ok then
			table.insert(eligible, t)
		end
	end
	table.sort(eligible, byId)
	for _, t in ipairs(eligible) do
		table.insert(result.eligible, t.id)
	end
	if #targets == 0 then
		result.status = "no-targets"
		if state.id then
			result.lost = { id = state.id, reason = "removed" }
		end
		return result
	end

	-- is the current target still valid?
	local current = state.id and byKey[state.id]
	local currentOk = false
	if state.id then
		if not current then
			result.lost = { id = state.id, reason = "removed" }
		elseif current._why then
			result.lost = { id = state.id, reason = current._why }
		else
			currentOk = true
		end
	end

	-- Target Lock: keep the current target for as long as it exists and still satisfies the conditions
	if currentOk and cfg.lock and not state.forceAcquire then
		result.id, result.status, result.screenDist = current.id, "locked", screenDist[current.id]
		return result
	end

	local mayAcquire = (cfg.autoAcquire or state.forceAcquire) and (not state.suspended or state.forceAcquire)
	if not mayAcquire then
		if currentOk then
			result.id, result.status, result.screenDist = current.id, "selected", screenDist[current.id]
		else
			result.status = state.suspended and "suspended" or "none"
		end
		return result
	end

	local pick
	if cfg.mode == "Manual" then
		local m = state.manualId and byKey[state.manualId]
		if m and not m._why then
			pick = m
		else
			result.status = "manual-wait"
			if state.manualId and m and m._why and not result.lost then
				result.lost = { id = state.manualId, reason = m._why }
			end
			return result
		end
	elseif cfg.mode == "Distance" then
		for _, t in ipairs(eligible) do
			if not pick or t.dist < pick.dist then
				pick = t
			end
		end
	else -- Crosshair: nearest to the centre of the search area
		for _, t in ipairs(eligible) do
			if not pick or screenDist[t.id] < screenDist[pick.id] then
				pick = t
			end
		end
	end
	if pick then
		result.id, result.status, result.screenDist = pick.id, "selected", screenDist[pick.id]
		if result.lost and result.lost.id == pick.id then
			result.lost = nil
		end
	else
		result.status = "none"
	end
	return result
end

-- cycle(eligibleIds, currentId, direction) -> id | nil     direction: +1 next, -1 previous (wraps)
function Logic.cycle(ids, currentId, direction)
	if #ids == 0 then
		return nil
	end
	local index
	for i, id in ipairs(ids) do
		if id == currentId then
			index = i
		end
	end
	if not index then
		return direction >= 0 and ids[1] or ids[#ids]
	end
	return ids[((index - 1 + direction) % #ids) + 1]
end

-- intercept(origin, pos, vel, speed) -> t | nil   time at which a projectile of constant `speed` fired from
-- `origin` meets a target moving at constant `vel` (smallest positive root), or nil when it cannot.
function Logic.intercept(o, p, v, speed)
	local rx, ry, rz = p.x - o.x, p.y - o.y, p.z - o.z
	local a = v.x * v.x + v.y * v.y + v.z * v.z - speed * speed
	local b = 2 * (rx * v.x + ry * v.y + rz * v.z)
	local c = rx * rx + ry * ry + rz * rz
	if math.abs(a) < 1e-9 then
		if math.abs(b) < 1e-9 then
			return nil
		end
		local t = -c / b
		return t > 0 and t or nil
	end
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local sq = math.sqrt(disc)
	local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
	local best
	for _, t in ipairs({ t1, t2 }) do
		if t > 1e-9 and (not best or t < best) then
			best = t
		end
	end
	return best
end

-- predict(origin, pos, vel, speed, leadMax) -> {x,y,z}, leadTime
-- Lead time is the intercept time, capped at leadMax; a static target returns its own position.
function Logic.predict(o, p, v, speed, leadMax)
	local speed2 = v.x * v.x + v.y * v.y + v.z * v.z
	if speed2 < 1e-6 then
		return { x = p.x, y = p.y, z = p.z }, 0
	end
	local t = Logic.intercept(o, p, v, speed)
	if not t then
		local dx, dy, dz = p.x - o.x, p.y - o.y, p.z - o.z
		t = math.sqrt(dx * dx + dy * dy + dz * dz) / math.max(speed, 1e-6)
	end
	t = math.min(t, leadMax)
	return { x = p.x + v.x * t, y = p.y + v.y * t, z = p.z + v.z * t }, t
end

return Logic

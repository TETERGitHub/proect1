--!nonstrict
-- features/MurderTrainer: a Murderer practice arena on YOUR client - test mannequins only, never other players.
--   arena     N mannequins in front of you with TEST roles (Innocent / Sheriff), standing, walking or strafing; they come
--             back after a delay when hit. They live in a local folder: nobody else sees them, the game does not know them.
--   swing     a melee check against the mannequins (reach, arc in front of you, line of sight). Your real knife's swing
--             (features/KillEvents.Used) can trigger it while the arena is up; the Swing action works without a knife.
--   auto      Auto swing strikes a mannequin in reach every <delay> seconds - TEST ARENA ONLY: it only ever looks at the
--             mannequins of this module and does nothing in a real round.
--   throw     a simulated knife (own mesh) flies from your head along your view: speed and gravity are settings of THIS
--             model (MM2's real throw physics are not known to the client), hits mannequins, stops at walls; a cooldown.
--   preview   the predicted path and impact point of a throw from your current aim; after each throw the prediction
--             error (predicted vs actual end point) is logged.
--   stats     swings, hits, misses with reasons (out of reach, not in front, behind an obstacle, no mannequin, wall,
--             passed), streak / best streak, accuracy, hit distances, reaction times (mannequin appeared -> hit), backstabs.
--   log       the last 120 events; replay: the last N seconds (positions sampled 10x a second) played back as ghosts.
-- Targets: the hub's single target manager (features/TargetSelect) sees the mannequins through Training.addSource.
-- STATUS: implemented; verified against the mock layer only (not checked in Roblox). Test environment only.
-- Depends on: Settings, Perf, Services, Logger, Signal, Training, TargetSelect, KillEvents, FxKit, I18n.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Signal = import("core/Signal")
local Training = import("features/Training")
local TargetSelect = import("features/TargetSelect")
local KillEvents = import("features/KillEvents")
local FxKit = import("features/FxKit")
local I18n = import("core/I18n")

local MT = {}
MT.Event = Signal.new("MurderTrainer.Event") -- (kind, detail)

local ROLE_COLOR = { Innocent = Color3.fromRGB(90, 200, 120), Sheriff = Color3.fromRGB(70, 140, 255) }
local LOG_MAX, KNIFE_LIFE = 120, 3
local state = nil

local function s(k)
	return Settings.get("murder." .. k)
end

local function now()
	return state and state.clock or 0
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or Vector3.new(0, 0, -1)
end

-- log(kind, label, detail): label is a fixed phrase (translated when shown), detail only ids, numbers and translated words
local function log(kind, label, detail)
	if not state then
		return
	end
	local text = label .. (detail and detail ~= "" and (": " .. detail) or "")
	table.insert(state.log, { t = now(), kind = kind, label = label, detail = detail or "", text = text })
	while #state.log > LOG_MAX do
		table.remove(state.log, 1)
	end
	MT.Event:Fire(kind, text)
end

local function me()
	local lp = Services.Players.LocalPlayer
	local char = lp and lp.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, root
end

local function lookDir()
	local cam = Services.Workspace.CurrentCamera
	local ok, v = pcall(function()
		return cam.CFrame.LookVector
	end)
	return ok and v or Vector3.new(0, 0, -1)
end

-- mannequins ---------------------------------------------------------------------------------------------------------------

local PARTS = { -- name, size, offset from the feet (along up), sideways offset
	{ "Torso", Vector3.new(2, 2, 1), 3, 0 }, { "Head", Vector3.new(1.2, 1.2, 1.2), 4.6, 0 },
	{ "LeftArm", Vector3.new(1, 2, 1), 3, -1.5 }, { "RightArm", Vector3.new(1, 2, 1), 3, 1.5 },
	{ "LeftLeg", Vector3.new(1, 2, 1), 1, -0.5 }, { "RightLeg", Vector3.new(1, 2, 1), 1, 0.5 },
}

local function buildDummy(i, role, pos, facing)
	local model = Instance.new("Model")
	model.Name = "Mannequin" .. i
	model.Parent = state.folder
	local parts = {}
	for _, p in ipairs(PARTS) do
		local part = FxKit.part(model, p[1] == "Head" and "Ball" or "Block", p[2], p[1] == "Torso" and ROLE_COLOR[role] or Color3.fromRGB(205, 205, 210),
			Enum.Material.SmoothPlastic, 0)
		part.Name = p[1]
		parts[p[1]] = { part = part, up = p[3], side = p[4] }
	end
	return { id = string.format("M%d", i), index = i, role = role, model = model, parts = parts, pos = pos, home = pos, facing = facing,
		alive = true, appearedAt = now(), respawnAt = nil, phase = (i - 1) * 1.3, goal = pos }
end

local function placeDummy(d)
	local right = Vector3.new(-d.facing.Z, 0, d.facing.X)
	local list, cfs = {}, {}
	for _, p in pairs(d.parts) do
		local c = d.pos + Vector3.new(0, p.up, 0) + right * p.side
		table.insert(list, p.part)
		table.insert(cfs, CFrame.lookAt(c, c + d.facing))
		p.part.Transparency = d.alive and 0 or 1
	end
	FxKit.moveAll(list, cfs)
end

function MT.torso(d)
	return d.pos + Vector3.new(0, 3, 0)
end

local function setAlive(d, on)
	d.alive = on
	if on then
		d.appearedAt = now()
		d.respawnAt = nil
	end
	placeDummy(d)
end

function MT.spawnArena()
	if not state then
		return false, "Murder trainer is not running."
	end
	MT.clearArena()
	local _, root = me()
	if not root then
		return false, "No character to place the arena in front of."
	end
	local look = flat(lookDir())
	local right = Vector3.new(-look.Z, 0, look.X)
	local floorY = root.Position.Y - 3
	local n = s("count")
	local sheriffs = math.min(s("sheriffs"), n)
	for i = 1, n do
		local role = i <= sheriffs and "Sheriff" or "Innocent"
		local pos = root.Position + look * s("distance") + right * ((i - (n + 1) / 2) * 5)
		pos = Vector3.new(pos.X, floorY, pos.Z)
		local d = buildDummy(i, role, pos, -look)
		table.insert(state.dummies, d)
		placeDummy(d)
	end
	state.active = true
	state.replay = {}
	log("arena", "Arena up", string.format("%d / %d", n, sheriffs))
	return true
end

function MT.clearArena()
	if not state then
		return
	end
	for _, d in ipairs(state.dummies) do
		pcall(function()
			d.model:Destroy()
		end)
	end
	table.clear(state.dummies)
	MT.stop()
	state.active = false
end

function MT.isActive()
	return state ~= nil and state.active
end

-- list() -> mannequins for the target manager / ESP: { id, name, part, alive, role, position }
function MT.list()
	local out = {}
	if not state then
		return out
	end
	for _, d in ipairs(state.dummies) do
		table.insert(out, { id = d.id, name = "Mannequin " .. d.index .. " (" .. d.role .. ")", part = d.parts.Torso.part, alive = d.alive, role = d.role,
			position = MT.torso(d), facing = d.facing, model = d.model })
	end
	return out
end

local function moveDummies(dt)
	local mode, speed = s("movement"), s("speed")
	for _, d in ipairs(state.dummies) do
		if not d.alive and d.respawnAt and now() >= d.respawnAt then
			d.pos = d.home
			setAlive(d, true)
			log("respawn", "Mannequin back", d.id)
		end
		if d.alive and mode ~= "Still" and speed > 0 then
			if mode == "Walk" then
				local side = Vector3.new(-d.facing.Z, 0, d.facing.X)
				local x = math.sin((now() + d.phase) * speed / 8) * 8
				local target = d.home + side * x
				local step = target - d.pos
				if step.Magnitude > 1e-3 then
					d.facing = flat(step)
				end
				d.pos = target
			else -- Strafe: a new random point near home every 1.5 s
				if (d.goal - d.pos).Magnitude < 0.3 or (d.nextGoal or 0) <= now() then
					d.goal = d.home + Vector3.new(state.rng:NextNumber(-8, 8), 0, state.rng:NextNumber(-8, 8))
					d.nextGoal = now() + 1.5
				end
				local step = d.goal - d.pos
				local m = step.Magnitude
				if m > 1e-3 then
					d.pos = d.pos + step.Unit * math.min(m, speed * dt)
					d.facing = flat(step)
				end
			end
			placeDummy(d)
		end
	end
end

-- visibility: nothing solid between your head and the mannequin (the arena itself is ignored)
local function visible(from, to)
	local char = me()
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, state.folder, Services.Workspace.CurrentCamera }
		return Services.Workspace:Raycast(from, to - from, params)
	end)
	return not ok or hit == nil
end

local function headPos(root)
	return root.Position + Vector3.new(0, 1.5, 0)
end

-- stats ------------------------------------------------------------------------------------------------------------------

local function freshStats()
	return { swings = 0, hits = 0, misses = 0, throws = 0, throwHits = 0, streak = 0, best = 0, backstabs = 0, distances = {}, reactions = {},
		reasons = {}, predErrors = {} }
end

local function miss(reason, kind, extra)
	local st = state.stats
	st.misses += 1
	st.streak = 0
	st.reasons[reason] = (st.reasons[reason] or 0) + 1
	log("miss", (kind or "Swing") .. " missed", I18n.tr(reason) .. (extra or ""))
end

local function hit(d, dist, kind, from)
	local st = state.stats
	st.hits += 1
	st.streak += 1
	st.best = math.max(st.best, st.streak)
	table.insert(st.distances, dist)
	table.insert(st.reactions, now() - d.appearedAt)
	-- a backstab: you were behind the mannequin (it faced away from you)
	local toYou = flat(from - d.pos)
	local behind = toYou:Dot(d.facing) < -0.5
	if behind then
		st.backstabs += 1
	end
	d.respawnAt = now() + s("respawn")
	setAlive(d, false)
	log("hit", kind .. " hit", string.format("%s (%s) · %.1f %s%s", d.id, I18n.tr(d.role), dist, I18n.tr("studs"), behind and (" · " .. I18n.tr("from behind")) or ""))
end

function MT.stats()
	if not state then
		return nil
	end
	local st = state.stats
	local function avg(t)
		if #t == 0 then
			return nil
		end
		local sum = 0
		for _, v in ipairs(t) do
			sum += v
		end
		return sum / #t
	end
	local function median(t)
		if #t == 0 then
			return nil
		end
		local c = table.clone(t)
		table.sort(c)
		return c[math.floor((#c + 1) / 2)]
	end
	local attempts = st.hits + st.misses
	local minD, maxD = nil, nil
	for _, v in ipairs(st.distances) do
		minD = minD and math.min(minD, v) or v
		maxD = maxD and math.max(maxD, v) or v
	end
	return {
		swings = st.swings, throws = st.throws, hits = st.hits, throwHits = st.throwHits, misses = st.misses, streak = st.streak, best = st.best,
		backstabs = st.backstabs, accuracy = attempts > 0 and st.hits / attempts or nil, avgDistance = avg(st.distances), minDistance = minD,
		maxDistance = maxD, avgReaction = avg(st.reactions), medianReaction = median(st.reactions), reasons = table.clone(st.reasons),
		avgPredictionError = avg(st.predErrors),
	}
end

function MT.resetStats()
	if state then
		state.stats = freshStats()
		log("stats", "Statistics reset")
	end
end

function MT.log()
	return state and state.log or {}
end

-- melee ---------------------------------------------------------------------------------------------------------------------

-- swing(source) -> hit mannequin id | nil, reason
function MT.swing(source)
	if not state or not state.active then
		return nil, "the arena is not up"
	end
	local _, root = me()
	if not root then
		return nil, "no character"
	end
	state.stats.swings += 1
	state.lastSwing = now()
	local origin, look = root.Position, flat(lookDir())
	local reach, arc = s("reach"), math.cos(math.rad(s("arc")))
	local best, bestD, nearest, nearestD = nil, math.huge, nil, math.huge
	local sawOutOfArc, sawBlocked = false, false
	for _, d in ipairs(state.dummies) do
		if d.alive then
			local torso = MT.torso(d)
			local dist = (torso - origin).Magnitude
			if dist < nearestD then
				nearest, nearestD = d, dist
			end
			if dist <= reach then
				if flat(torso - origin):Dot(look) < arc then
					sawOutOfArc = true
				elseif s("requireVisible") and not visible(headPos(root), torso) then
					sawBlocked = true
				elseif dist < bestD then
					best, bestD = d, dist
				end
			end
		end
	end
	local kind = source == "knife" and "Knife" or source == "auto" and "Auto swing" or "Swing"
	if best then
		hit(best, bestD, kind, origin)
		return best.id
	end
	local reason = not nearest and "no mannequin" or sawBlocked and "behind an obstacle" or sawOutOfArc and "not in front of you" or "out of reach"
	miss(reason, kind, reason == "out of reach" and string.format(" (%.1f / %.1f %s)", nearestD, reach, I18n.tr("studs")) or nil)
	return nil, reason
end

-- the mannequin auto swing would strike now: the selected one (target manager) if it is a mannequin in reach, else the nearest
local function autoTarget(origin)
	local reach = s("reach")
	local sel = TargetSelect.selectedId()
	local nearest, nd = nil, math.huge
	for _, d in ipairs(state.dummies) do
		if d.alive then
			local dist = (MT.torso(d) - origin).Magnitude
			if s("autoTarget") == "Selected" and d.id == sel and dist <= reach then
				return d
			end
			if dist <= reach and dist < nd then
				nearest, nd = d, dist
			end
		end
	end
	return s("autoTarget") == "Nearest" and nearest or nil
end

local function autoSwing()
	if not s("autoSwing") or not state.active or now() - (state.lastSwing or -math.huge) < s("swingDelay") then
		return
	end
	local _, root = me()
	if root and autoTarget(root.Position) then
		MT.swing("auto")
	end
end

-- throw ---------------------------------------------------------------------------------------------------------------------

-- simulate(origin, dir, maxT, dt) -> points, endPoint, hitDummy, hitWall : the model used for both the throw and its preview
function MT.simulate(origin, dir, maxT, dt)
	local speed, g = s("throwSpeed"), s("gravity")
	local pos, vel = origin, dir.Unit * speed
	local points = { pos }
	local t = 0
	while t < maxT do
		local nextPos = pos + vel * dt + Vector3.new(0, -0.5 * g * dt * dt, 0)
		vel = vel + Vector3.new(0, -g * dt, 0)
		-- mannequins: segment against a sphere round the torso and one round the head
		if state then
			for _, d in ipairs(state.dummies) do
				if d.alive then
					for _, c in ipairs({ { MT.torso(d), 1.4 }, { d.pos + Vector3.new(0, 4.6, 0), 0.7 } }) do
						local seg = nextPos - pos
						local len = seg.Magnitude
						if len > 1e-6 then
							local u = seg / len
							local proj = math.clamp((c[1] - pos):Dot(u), 0, len)
							if ((pos + u * proj) - c[1]).Magnitude <= c[2] then
								local p = pos + u * proj
								table.insert(points, p)
								return points, p, d, false
							end
						end
					end
				end
			end
		end
		if not visible(pos, nextPos) then
			table.insert(points, nextPos)
			return points, nextPos, nil, true
		end
		pos = nextPos
		table.insert(points, pos)
		t += dt
	end
	return points, pos, nil, false
end

function MT.throwState()
	if not state then
		return "Unavailable"
	end
	if not state.active then
		return "Unavailable"
	end
	if #state.knives > 0 then
		return "Throwing"
	end
	local left = s("throwCooldown") - (now() - (state.lastThrow or -math.huge))
	if left > 0 then
		return "Cooldown", left
	end
	return "Ready"
end

-- throw() -> true | nil, reason
function MT.throw()
	if not state or not state.active then
		return nil, "the arena is not up"
	end
	local st = MT.throwState()
	if st ~= "Ready" then
		return nil, "throw is not ready (" .. st .. ")"
	end
	local _, root = me()
	if not root then
		return nil, "no character"
	end
	local origin, dir = headPos(root), lookDir()
	local _, predicted = MT.simulate(origin, dir, KNIFE_LIFE, 1 / 30)
	local part = FxKit.mesh(state.folder, "blade", Vector3.new(0.25, 0.1, 1.6), Color3.fromRGB(220, 225, 235), Enum.Material.Metal, 0, "Block")
	part.Name = "TrainingKnife"
	table.insert(state.knives, { part = part, pos = origin, vel = dir.Unit * s("throwSpeed"), age = 0, predicted = predicted, origin = origin })
	state.lastThrow = now()
	state.stats.throws += 1
	log("throw", "Knife thrown")
	return true
end

local function stepKnives(dt)
	for i = #state.knives, 1, -1 do
		local k = state.knives[i]
		local g = s("gravity")
		local pts, endPos, d, wall = MT.simulate(k.pos, k.vel, dt, dt)
		k.vel = k.vel + Vector3.new(0, -g * dt, 0)
		k.age += dt
		local done = d ~= nil or wall or k.age >= KNIFE_LIFE
		k.pos = endPos
		pcall(function()
			k.part.CFrame = CFrame.lookAt(endPos, endPos + (k.vel.Magnitude > 0 and k.vel.Unit or Vector3.new(0, 0, -1)))
		end)
		if done then
			if d then
				state.stats.throwHits += 1
				hit(d, (endPos - k.origin).Magnitude, "Throw", k.origin)
			else
				miss(wall and "hit a wall" or "passed every mannequin", "Throw")
			end
			if k.predicted then
				local err = (endPos - k.predicted).Magnitude
				table.insert(state.stats.predErrors, err)
				log("prediction", "Prediction error", string.format("%.2f %s", err, I18n.tr("studs")))
			end
			pcall(function()
				k.part:Destroy()
			end)
			table.remove(state.knives, i)
		end
		local _ = pts
	end
end

-- preview of the throw from your current aim: up to N dots and an impact marker, pooled parts
local function updatePreview()
	local on = state.active and s("showPath")
	local n = s("pathPoints")
	state.preview = state.preview or {}
	if on then
		local _, root = me()
		if root then
			local pts, endPos, d = MT.simulate(headPos(root), lookDir(), KNIFE_LIFE, KNIFE_LIFE / n)
			for i = 1, n + 1 do
				local p = state.preview[i]
				if not p then
					p = FxKit.part(state.folder, "Ball", Vector3.new(0.25, 0.25, 0.25), Color3.fromRGB(255, 80, 80), Enum.Material.Neon, 0.3)
					p.Name = "PathDot"
					state.preview[i] = p
				end
				local pos = i <= n and pts[i] or endPos
				p.Transparency = pos and 0.3 or 1
				if i == n + 1 then
					p.Size = Vector3.new(0.9, 0.9, 0.9)
					p.Color = d and Color3.fromRGB(255, 220, 60) or Color3.fromRGB(255, 80, 80)
				end
				if pos then
					p.CFrame = CFrame.new(pos)
				end
			end
			state.previewEnd = endPos
		end
	end
	for i, p in ipairs(state.preview) do
		if not on or i > n + 1 then
			p.Transparency = 1
		end
	end
end

function MT.predictedImpact()
	return state and state.previewEnd or nil
end

-- stop(): ends auto swing, throws in flight, replay playback - at once
function MT.stop()
	if not state then
		return
	end
	if Settings.get("murder.autoSwing") then
		Settings.set("murder.autoSwing", false)
	end
	for _, k in ipairs(state.knives) do
		pcall(function()
			k.part:Destroy()
		end)
	end
	table.clear(state.knives)
	MT.stopReplay()
end

-- replay ----------------------------------------------------------------------------------------------------------------------

local function record()
	local _, root = me()
	local sample = { t = now(), player = root and root.Position or nil, dummies = {}, knives = {} }
	for _, d in ipairs(state.dummies) do
		table.insert(sample.dummies, { id = d.id, pos = MT.torso(d), alive = d.alive, role = d.role })
	end
	for _, k in ipairs(state.knives) do
		table.insert(sample.knives, k.pos)
	end
	table.insert(state.replay, sample)
	local keep = s("replaySeconds")
	while #state.replay > 0 and now() - state.replay[1].t > keep do
		table.remove(state.replay, 1)
	end
end

function MT.replayLength()
	if not state or #state.replay < 2 then
		return 0
	end
	return state.replay[#state.replay].t - state.replay[1].t
end

function MT.playReplay()
	if not state or #state.replay < 2 then
		return nil, "nothing recorded yet"
	end
	MT.stopReplay()
	local folder = Instance.new("Folder")
	folder.Name = "Replay"
	folder.Parent = state.folder
	state.playback = { folder = folder, t = 0, samples = table.clone(state.replay), ghosts = {} }
	log("replay", "Replay started", string.format("%.1f s", MT.replayLength()))
	return true
end

function MT.stopReplay()
	if state and state.playback then
		pcall(function()
			state.playback.folder:Destroy()
		end)
		state.playback = nil
	end
end

function MT.isReplaying()
	return state ~= nil and state.playback ~= nil
end

local function ghost(pb, key, color, size)
	local g = pb.ghosts[key]
	if not g then
		g = FxKit.part(pb.folder, "Ball", Vector3.new(size, size, size), color, Enum.Material.Neon, 0.45)
		pb.ghosts[key] = g
	end
	return g
end

local function stepReplay(dt)
	local pb = state.playback
	if not pb then
		return
	end
	pb.t += dt * s("playbackSpeed")
	local start = pb.samples[1].t
	local sample = nil
	for _, smp in ipairs(pb.samples) do
		if smp.t - start <= pb.t then
			sample = smp
		end
	end
	if not sample or pb.t > pb.samples[#pb.samples].t - start then
		MT.stopReplay()
		log("replay", "Replay finished")
		return
	end
	for _, g in pairs(pb.ghosts) do
		g.Transparency = 1
	end
	if sample.player then
		local g = ghost(pb, "player", Color3.fromRGB(255, 255, 255), 1.6)
		g.CFrame, g.Transparency = CFrame.new(sample.player), 0.45
	end
	for _, d in ipairs(sample.dummies) do
		local g = ghost(pb, d.id, ROLE_COLOR[d.role] or Color3.fromRGB(200, 200, 200), 1.6)
		g.CFrame, g.Transparency = CFrame.new(d.pos), d.alive and 0.45 or 0.85
	end
	for i, p in ipairs(sample.knives) do
		local g = ghost(pb, "knife" .. i, Color3.fromRGB(255, 80, 80), 0.6)
		g.CFrame, g.Transparency = CFrame.new(p), 0.2
	end
end

-- lifecycle --------------------------------------------------------------------------------------------------------------------

function MT.status()
	if not state then
		return { running = false }
	end
	local alive = 0
	for _, d in ipairs(state.dummies) do
		if d.alive then
			alive += 1
		end
	end
	local t, left = MT.throwState()
	return { running = true, active = state.active, mannequins = #state.dummies, alive = alive, throw = t, cooldown = left,
		autoSwing = s("autoSwing"), replaying = state.playback ~= nil, recorded = MT.replayLength() }
end

-- tick(dt): one step of the arena (also what tests drive)
function MT.tick(dt)
	if not state then
		return
	end
	state.clock += dt
	if state.active then
		moveDummies(dt)
		stepKnives(dt)
		autoSwing()
		state.sampleAcc = (state.sampleAcc or 0) + dt
		if state.sampleAcc >= 0.1 then
			state.sampleAcc = 0
			record()
		end
	end
	stepReplay(dt)
end

function MT.start(ctx)
	assert(state == nil, "MurderTrainer already started")
	local folder = Instance.new("Folder")
	folder.Name = "MM2Hub_MurderTrainer"
	folder.Parent = Services.Workspace
	ctx.maid:Give(folder)
	state = { folder = folder, dummies = {}, knives = {}, log = {}, replay = {}, stats = freshStats(), clock = 0, active = false,
		rng = Random.new(7), preview = nil }
	ctx.maid:Give(function()
		MT.stop()
		Training.removeSource("murder")
		state = nil
	end)
	Training.addSource("murder", MT.list)
	-- your real knife's swing counts on the mannequins while the arena is up
	ctx.maid:Give(KillEvents.Used:Connect(function(ev)
		if state and state.active and ev.role == "murderer" and s("useKnife") then
			MT.swing("knife")
		end
	end))
	for _, k in ipairs({ "count", "sheriffs" }) do
		ctx.maid:Give(Settings.observe("murder." .. k, function()
			if state and state.active then
				MT.spawnArena()
			end
		end))
	end
	local h1 = Perf.every("murder.tick", 30, function(dt)
		MT.tick(math.min(dt, 0.1))
	end)
	local h2 = Perf.every("murder.preview", 20, function()
		if state then
			updatePreview()
		end
	end, { visual = true })
	ctx.maid:Give(h1.Cancel)
	ctx.maid:Give(h2.Cancel)
end

return MT

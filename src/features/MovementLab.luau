--!nonstrict
-- features/MovementLab: movement practice for YOUR character - measurements and drawings on your own screen only.
--   speed       your horizontal speed (studs/s), the top speed this session and your Humanoid's WalkSpeed; optional
--               on-screen speedometer.
--   routes      record your path (5 samples a second) into slot A or B, draw it as dots, length and duration; compare B
--               with A (average distance from A, time difference). Recording only: nothing ever walks for you.
--   course      a checkpoint course in front of you; touch the checkpoints in order, the time and the best time are kept.
--   path        save a destination, then draw the route to it from where you stand with Roblox's PathfindingService
--               (works where the game's map allows it; reported as unavailable when the service refuses).
--   dead end    eight rays round you: when most directions are blocked close by, a dead-end warning is shown.
--   visibility  your own character's parts becoming see-through is noticed (for example when a game ability makes you
--               invisible) with the time since; only what can be seen on your character, no game data is read.
-- STATUS: implemented; verified against the mock layer only (PathfindingService and real maps not exercised).
-- Depends on: Settings, Perf, Env, Services, Logger, FxKit, I18n.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")
local FxKit = import("features/FxKit")
local I18n = import("core/I18n")

local Lab = {}

local MAX_SAMPLES, MAX_DOTS = 1500, 150
local state = nil

local function s(k)
	return Settings.get("move." .. k)
end

local function me()
	local lp = Services.Players.LocalPlayer
	local char = lp and lp.Character
	return char, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local function now()
	return state and state.clock or 0
end

-- speed -----------------------------------------------------------------------------------------------------------------------

function Lab.speed()
	local _, root, hum = me()
	local v = 0
	if root then
		local ok, vel = pcall(function()
			return root.AssemblyLinearVelocity
		end)
		if ok and vel then
			v = Vector3.new(vel.X, 0, vel.Z).Magnitude
		end
	end
	return v, state and state.topSpeed or 0, hum and tonumber(hum.WalkSpeed) or nil
end

-- routes -----------------------------------------------------------------------------------------------------------------------

local function routeLength(r)
	local len = 0
	for i = 2, #r.points do
		len += (r.points[i].p - r.points[i - 1].p).Magnitude
	end
	return len
end

function Lab.startRecording(slot)
	if not state then
		return false
	end
	slot = slot == "B" and "B" or "A"
	state.routes[slot] = { points = {}, started = now() }
	state.recording = slot
	return true
end

function Lab.stopRecording()
	if not state or not state.recording then
		return nil
	end
	local slot = state.recording
	state.recording = nil
	return slot, Lab.routeInfo(slot)
end

function Lab.isRecording()
	return state ~= nil and state.recording ~= nil
end

function Lab.routeInfo(slot)
	local r = state and state.routes[slot]
	if not r or #r.points < 2 then
		return nil
	end
	return { samples = #r.points, length = routeLength(r), duration = r.points[#r.points].t - r.points[1].t }
end

-- compare(): how far route B runs from route A on average, and the time difference
function Lab.compare()
	local a, b = state and state.routes.A, state and state.routes.B
	if not a or not b or #a.points < 2 or #b.points < 2 then
		return nil
	end
	local sum = 0
	for _, pb in ipairs(b.points) do
		local best = math.huge
		for _, pa in ipairs(a.points) do
			best = math.min(best, (pb.p - pa.p).Magnitude)
		end
		sum += best
	end
	local ia, ib = Lab.routeInfo("A"), Lab.routeInfo("B")
	return { averageDistance = sum / #b.points, timeDifference = ib.duration - ia.duration, lengthDifference = ib.length - ia.length }
end

function Lab.clearRoutes()
	if state then
		state.routes = {}
		state.recording = nil
	end
end

local function sample()
	local _, root = me()
	if not root or not state.recording then
		return
	end
	local r = state.routes[state.recording]
	local last = r.points[#r.points]
	if not last or (root.Position - last.p).Magnitude > 0.3 or now() - last.t > 1 then
		table.insert(r.points, { p = root.Position, t = now() })
		if #r.points > MAX_SAMPLES then
			table.remove(r.points, 1)
		end
	end
end

-- dots: one pooled set of parts for the routes, the course and the path
local function dots(list, color)
	state.dots = state.dots or {}
	state.dotUse = state.dotUse or 0
	for _, p in ipairs(list) do
		if state.dotUse >= MAX_DOTS then
			return
		end
		state.dotUse += 1
		local d = state.dots[state.dotUse]
		if not d then
			d = FxKit.part(state.folder, "Ball", Vector3.new(0.4, 0.4, 0.4), color, Enum.Material.Neon, 0.25)
			d.Name = "Dot"
			state.dots[state.dotUse] = d
		end
		d.Color, d.Transparency = color, 0.25
		d.CFrame = CFrame.new(p)
	end
end

local function thin(points, max)
	local out = {}
	local step = math.max(1, math.ceil(#points / max))
	for i = 1, #points, step do
		table.insert(out, points[i].p or points[i])
	end
	return out
end

local function redraw()
	state.dotUse = 0
	if s("showRoutes") then
		if state.routes.A then
			dots(thin(state.routes.A.points, 60), Color3.fromRGB(80, 200, 255))
		end
		if state.routes.B then
			dots(thin(state.routes.B.points, 60), Color3.fromRGB(255, 170, 60))
		end
	end
	if state.path then
		dots(state.path, Color3.fromRGB(120, 255, 140))
	end
	for i = state.dotUse + 1, #(state.dots or {}) do
		state.dots[i].Transparency = 1
	end
end

-- course ----------------------------------------------------------------------------------------------------------------------

function Lab.startCourse()
	if not state then
		return false, "Movement lab is not running."
	end
	Lab.clearCourse()
	local _, root = me()
	if not root then
		return false, "no character"
	end
	local look = workspace.CurrentCamera.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local n = s("checkpoints")
	state.course = { points = {}, index = 1, started = nil, finished = nil }
	for i = 1, n do
		local pos = root.Position + look * (8 * i) + right * ((i % 2 == 0) and 6 or -6)
		local part = FxKit.mesh(state.folder, "ring", Vector3.new(4, 0.5, 4), Color3.fromRGB(255, 220, 60), Enum.Material.Neon, 0.3, "Cylinder")
		part.Name = "Checkpoint" .. i
		part.CFrame = CFrame.new(pos)
		table.insert(state.course.points, { pos = pos, part = part })
	end
	return true
end

function Lab.clearCourse()
	if state and state.course then
		for _, c in ipairs(state.course.points) do
			pcall(function()
				c.part:Destroy()
			end)
		end
		state.course = nil
	end
end

local function stepCourse()
	local c = state.course
	if not c or c.finished then
		return
	end
	local _, root = me()
	local cp = c.points[c.index]
	if not root or not cp then
		return
	end
	if (Vector3.new(root.Position.X, cp.pos.Y, root.Position.Z) - cp.pos).Magnitude <= 3.5 then
		if c.index == 1 then
			c.started = now()
		end
		cp.part.Color, cp.part.Transparency = Color3.fromRGB(90, 230, 120), 0.7
		c.index += 1
		if c.index > #c.points then
			c.finished = now()
			local t = c.finished - c.started
			state.bestCourse = state.bestCourse and math.min(state.bestCourse, t) or t
			table.insert(state.courseTimes, t)
		end
	end
end

function Lab.courseInfo()
	local c = state and state.course
	if not c then
		return { active = false, best = state and state.bestCourse or nil, runs = state and #state.courseTimes or 0 }
	end
	local t = c.started and ((c.finished or now()) - c.started) or nil
	return { active = true, next = math.min(c.index, #c.points), total = #c.points, time = t, finished = c.finished ~= nil,
		best = state.bestCourse, runs = #state.courseTimes }
end

-- path -----------------------------------------------------------------------------------------------------------------------

function Lab.setDestination()
	local _, root = me()
	if not state or not root then
		return false
	end
	state.destination = root.Position
	return true
end

-- showPath() -> waypoints count | nil, reason
function Lab.showPath()
	if not state then
		return nil, "not running"
	end
	local _, root = me()
	if not root or not state.destination then
		return nil, "set a destination first"
	end
	local ok, res = pcall(function()
		local path = Services.PathfindingService:CreatePath({ AgentCanJump = true })
		path:ComputeAsync(root.Position, state.destination)
		if path.Status ~= Enum.PathStatus.Success then
			return nil
		end
		local out = {}
		for _, w in ipairs(path:GetWaypoints()) do
			table.insert(out, w.Position)
		end
		return out
	end)
	if not ok then
		state.path = nil
		return nil, "path finding is unavailable here"
	end
	if not res then
		state.path = nil
		return nil, "no path to the destination"
	end
	state.path = res
	return #res
end

function Lab.clearPath()
	if state then
		state.path = nil
	end
end

-- dead end and visibility ----------------------------------------------------------------------------------------------------

-- blockedDirections() -> how many of 8 horizontal directions are blocked within the check distance
function Lab.blockedDirections()
	local char, root = me()
	if not root then
		return nil
	end
	local dist = s("deadEndDistance")
	local blocked = 0
	for i = 0, 7 do
		local a = i * math.pi / 4
		local ok, hit = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char, state.folder }
			return Services.Workspace:Raycast(root.Position, Vector3.new(math.cos(a), 0, math.sin(a)) * dist, params)
		end)
		if ok and hit then
			blocked += 1
		end
	end
	return blocked
end

-- seeThrough() -> share (0..1) of your visible body parts that are mostly transparent
function Lab.seeThrough()
	local char = me()
	if not char then
		return nil
	end
	local total, clear = 0, 0
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			total += 1
			if (tonumber(p.Transparency) or 0) >= 0.5 then
				clear += 1
			end
		end
	end
	return total > 0 and clear / total or nil
end

function Lab.status()
	if not state then
		return { running = false }
	end
	local v, top, walk = Lab.speed()
	return { running = true, speed = v, top = top, walkSpeed = walk, recording = state.recording, deadEnd = state.deadEnd,
		invisibleSince = state.invisibleSince and (now() - state.invisibleSince) or nil }
end

-- tick(dt): one step (what tests drive)
function Lab.tick(dt)
	if not state then
		return
	end
	state.clock += dt
	local v = Lab.speed()
	state.topSpeed = math.max(state.topSpeed, v)
	sample()
	stepCourse()
	state.slow += dt
	if state.slow >= 0.5 then
		state.slow = 0
		if s("deadEndWarning") then
			local b = Lab.blockedDirections()
			local dead = b ~= nil and b >= 6
			if dead and not state.deadEnd and now() - state.lastDeadEnd > 5 then
				state.lastDeadEnd = now()
			end
			state.deadEnd = dead
		else
			state.deadEnd = false
		end
		local share = Lab.seeThrough()
		if share and share >= 0.6 then
			state.invisibleSince = state.invisibleSince or now()
		else
			state.invisibleSince = nil
		end
		redraw()
	end
	if state.hud then
		state.hud.gui.Enabled = s("speedometer")
		if state.hud.gui.Enabled then
			local cur, top = Lab.speed()
			local lines = { string.format("%.1f %s/s  (%s %.1f)", cur, I18n.tr("studs"), I18n.tr("top"), top) }
			if state.deadEnd then
				table.insert(lines, I18n.tr("Dead end nearby"))
			end
			if state.invisibleSince then
				table.insert(lines, string.format("%s %.0f s", I18n.tr("See-through for"), now() - state.invisibleSince))
			end
			local info = Lab.courseInfo()
			if info.active and info.time then
				table.insert(lines, string.format("%s %d/%d  %.2f s", I18n.tr("Course"), info.next, info.total, info.time))
			end
			state.hud.label.Text = table.concat(lines, "\n")
		end
	end
end

local function buildHud(maid)
	local parent = Env.guiParent()
	if not parent then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubSpeed"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = parent
	maid:Give(gui)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -90)
	label.Size = UDim2.fromOffset(260, 64)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(240, 240, 245)
	label.TextStrokeTransparency = 0.4
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.Text = ""
	label.Parent = gui
	return { gui = gui, label = label }
end

function Lab.start(ctx)
	assert(state == nil, "MovementLab already started")
	local folder = Instance.new("Folder")
	folder.Name = "MM2HubMovementLab"
	folder.Parent = Services.Workspace.CurrentCamera
	ctx.maid:Give(folder)
	state = { folder = folder, clock = 0, topSpeed = 0, routes = {}, recording = nil, course = nil, courseTimes = {}, bestCourse = nil,
		slow = 0, deadEnd = false, lastDeadEnd = -100, destination = nil, path = nil }
	ctx.maid:Give(function()
		state = nil
	end)
	state.hud = buildHud(ctx.maid)
	local h = Perf.every("movelab", 15, function(dt)
		local ok, err = pcall(Lab.tick, math.min(dt, 0.2))
		if not ok then
			Logger.error("MovementLab", "tick failed: %s", tostring(err))
		end
	end)
	ctx.maid:Give(h.Cancel)
end

return Lab

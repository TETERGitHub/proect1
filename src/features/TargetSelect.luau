--!nonstrict
-- features/TargetSelect: "Select Aim" for the isolated TEST environment.
-- It selects ONE of your local test targets (training range targets, the physics dummy, the hitbox-lab
-- hitbox) using SelectLogic: crosshair-nearest / distance / manual modes, FOV radius, visibility check,
-- target lock, switching and reset. It highlights the selected target, shows its info and can mark a
-- predicted position for a moving target.
-- It does NOT fire, does NOT move or aim your camera, does NOT touch players or MM2 hit registration, and
-- is not a silent aim: the selection exists only as hub state and visuals on your own screen.
-- STATUS: implemented; logic unit-tested, adapter exercised against the mock layer only.
-- Depends on: Settings, Perf, Services, Env, Maid, Signal, Logger, SelectLogic, Training.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Env = import("core/Env")
local Maid = import("core/Maid")
local Signal = import("core/Signal")
local Logger = import("core/Logger")
local Logic = import("features/SelectLogic")
local Training = import("features/Training")

local TargetSelect = {}

TargetSelect.Changed = Signal.new("TargetSelect.Changed") -- (id|nil, reason)

local state = nil
local sourceOverride = nil
local clock = os.clock

-- setClock(fn): lets tests drive time; restored when the module stops.
function TargetSelect.setClock(fn)
	clock = fn or os.clock
end

local function s(name)
	return Settings.get("selectaim." .. name)
end

local function camera()
	return Services.Workspace.CurrentCamera
end

-- Source of candidates: Training.targetList() unless overridden (tests / other test environments).
-- Each item: { id, name, part (BasePart), alive (boolean) }
function TargetSelect.setSource(fn)
	sourceOverride = fn
end

local function sourceList()
	local fn = sourceOverride or Training.targetList
	local ok, list = pcall(fn)
	if not ok then
		Logger.error("SelectAim", "target source failed: %s", tostring(list))
		return {}
	end
	return list or {}
end

-- Search centre: the custom crosshair position when it is on, otherwise the screen centre.
local function searchCenter(vp)
	local cx, cy = vp.X / 2, vp.Y / 2
	if Settings.get("crosshair.enabled") then
		cx += Settings.get("crosshair.offsetX")
		cy += Settings.get("crosshair.offsetY")
	end
	return cx, cy
end

-- Candidates ---------------------------------------------------------------------------------------------------

local function updateVelocity(item, pos, now)
	local h = state.history[item.id]
	local vel = { x = 0, y = 0, z = 0 }
	if h then
		local dt = now - h.t
		if dt > 1e-3 then
			local dx, dy, dz = pos.X - h.pos.X, pos.Y - h.pos.Y, pos.Z - h.pos.Z
			if dx * dx + dy * dy + dz * dz < 40 * 40 then -- a jump (respawn / teleport) is not motion
				local k = 0.5
				vel = {
					x = h.vel.x + (dx / dt - h.vel.x) * k,
					y = h.vel.y + (dy / dt - h.vel.y) * k,
					z = h.vel.z + (dz / dt - h.vel.z) * k,
				}
			end
		else
			vel = h.vel
		end
	end
	state.history[item.id] = { pos = pos, t = now, vel = vel }
	return vel
end

-- Visibility: a ray from the camera to the target; anything else hit on the way hides it.
local function visibleFrom(camPos, pos, ignore)
	local ok, res = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		return Services.Workspace:Raycast(camPos, pos - camPos, params)
	end)
	if not ok then
		state.visibilityAvailable = false
		return nil
	end
	state.visibilityAvailable = true
	return res == nil
end

local function gather()
	local cam = camera()
	local items = sourceList()
	local out = {}
	if not cam then
		return out, nil
	end
	local vp = cam.ViewportSize
	local cx, cy = searchCenter(vp)
	local camPos = cam.CFrame.Position
	local now = clock()
	local fov = s("fov")
	local ignore = { state.folder }
	local player = Services.Players.LocalPlayer
	if player and player.Character then
		table.insert(ignore, player.Character)
	end
	for _, item in ipairs(items) do
		table.insert(ignore, item.part)
		if item.part and item.part.Parent and item.part.Parent:IsA("Model") then
			table.insert(ignore, item.part.Parent)
		end
	end
	for _, item in ipairs(items) do
		local part = item.part
		if part and part.Parent then
			local pos = part.Position
			local screen, onScreen = cam:WorldToViewportPoint(pos)
			local dist = (pos - camPos).Magnitude
			local vel = updateVelocity(item, pos, now)
			local t = {
				id = item.id, name = item.name, alive = item.alive ~= false, onScreen = onScreen and screen.Z > 0,
				sx = screen.X, sy = screen.Y, dist = dist, visible = nil,
				pos = { x = pos.X, y = pos.Y, z = pos.Z }, vel = vel, part = part,
			}
			-- raycast only for candidates that could win (inside the FOV), keeps the cost bounded
			if s("visibilityCheck") and t.alive and t.onScreen then
				local dx, dy = t.sx - cx, t.sy - cy
				if dx * dx + dy * dy <= fov * fov then
					t.visible = visibleFrom(camPos, pos, ignore)
				end
			end
			table.insert(out, t)
		end
	end
	-- forget history of targets that disappeared
	local present = {}
	for _, t in ipairs(out) do
		present[t.id] = true
	end
	for id in pairs(state.history) do
		if not present[id] then
			state.history[id] = nil
		end
	end
	return out, { camPos = camPos, cx = cx, cy = cy, vp = vp }
end

local function currentConfig(frame)
	return {
		mode = s("mode"), fov = s("fov"), lock = s("lock"), visibilityCheck = s("visibilityCheck"),
		autoAcquire = s("autoAcquire"), centerX = frame.cx, centerY = frame.cy,
	}
end

-- Visuals ------------------------------------------------------------------------------------------------------

local function newCorner(parent, x, y, color)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Size = UDim2.fromOffset(10, 3)
	f.AnchorPoint = Vector2.new(x, y)
	f.Position = UDim2.fromScale(x, y)
	f.Parent = parent
	local g = Instance.new("Frame")
	g.BorderSizePixel = 0
	g.BackgroundColor3 = color
	g.Size = UDim2.fromOffset(3, 10)
	g.AnchorPoint = Vector2.new(x, y)
	g.Position = UDim2.fromScale(x, y)
	g.Parent = parent
	return { f, g }
end

local function buildVisuals(maid)
	local folder = Instance.new("Folder")
	folder.Name = "MM2Hub_SelectAim"
	folder.Parent = Services.Workspace
	maid:Give(folder)
	state.folder = folder

	local gui = Instance.new("BillboardGui")
	gui.Name = "Highlight"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(74, 74)
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.8, 0.8)
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = ring
	ring.Parent = gui
	local brackets = {}
	for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for _, f in ipairs(newCorner(gui, c[1], c[2], Color3.fromRGB(255, 214, 10))) do
			table.insert(brackets, f)
		end
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 1, 2)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = gui
	state.highlight = { gui = gui, stroke = stroke, brackets = brackets, label = label }

	-- predicted-position marker: an invisible anchor part carrying a small diamond billboard
	local anchor = Instance.new("Part")
	anchor.Name = "PredictionAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = folder
	local pgui = Instance.new("BillboardGui")
	pgui.Name = "Prediction"
	pgui.AlwaysOnTop = true
	pgui.Size = UDim2.fromOffset(18, 18)
	pgui.Adornee = anchor
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(10, 10)
	diamond.Rotation = 45
	diamond.BorderSizePixel = 0
	diamond.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	diamond.Parent = pgui
	pgui.Enabled = false
	pgui.Parent = folder
	state.prediction = { anchor = anchor, gui = pgui, diamond = diamond }

	-- FOV circle (screen overlay)
	local parent = Env.guiParent()
	if parent then
		local sg = Instance.new("ScreenGui")
		sg.Name = "MM2HubSelectFov"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.DisplayOrder = 4
		sg.Parent = parent
		maid:Give(sg)
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.BackgroundTransparency = 1
		circle.BorderSizePixel = 0
		circle.Visible = false
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0.5, 0)
		cc.Parent = circle
		local cs = Instance.new("UIStroke")
		cs.Thickness = 1.5
		cs.Transparency = 0.45
		cs.Parent = circle
		circle.Parent = sg
		state.fov = { gui = sg, circle = circle, stroke = cs }
	else
		state.fovUnavailable = "no GUI container for the FOV circle"
	end
end

local function hideHighlight()
	local h = state.highlight
	if h.gui.Adornee ~= nil or h.gui.Parent ~= nil then
		h.gui.Adornee = nil
		h.gui.Parent = nil
	end
	state.prediction.gui.Enabled = false
end

local function paintVisuals(frame, selected, predicted)
	local c = s("highlightColor")
	local color = Color3.fromRGB(c.r, c.g, c.b)
	-- FOV circle follows the search centre and radius
	if state.fov then
		local on = s("enabled") and s("showFov")
		state.fov.circle.Visible = on
		if on then
			state.fov.circle.Position = UDim2.fromOffset(frame.cx, frame.cy)
			state.fov.circle.Size = UDim2.fromOffset(s("fov") * 2, s("fov") * 2)
			state.fov.stroke.Color = color
		end
	end
	local h = state.highlight
	if selected and s("highlight") then
		h.gui.Adornee = selected.part
		h.gui.Parent = state.folder
		h.stroke.Color = color
		for _, b in ipairs(h.brackets) do
			b.BackgroundColor3 = color
		end
		h.label.TextColor3 = color
		h.label.Text = selected.name
	else
		h.gui.Adornee = nil
		h.gui.Parent = nil
	end
	local p = state.prediction
	if predicted then
		p.anchor.Position = Vector3.new(predicted.x, predicted.y, predicted.z)
		p.gui.Enabled = true
		p.diamond.BackgroundColor3 = color
	else
		p.gui.Enabled = false
	end
end

-- Evaluation ------------------------------------------------------------------------------------------------------------

local function statusText(result, st)
	local mode = s("mode")
	if not s("enabled") then
		return "Disabled"
	elseif result.status == "no-targets" then
		return "No test targets (enable the training range or spawn the lab)"
	elseif result.status == "locked" then
		return "Locked"
	elseif result.status == "selected" then
		return "Selected"
	elseif result.status == "suspended" then
		return "Reset - press Select to acquire again"
	elseif result.status == "manual-wait" then
		return st.manualId and "Manual target not available" or "Manual: pick a target from the list or use Next / Previous"
	end
	return s("autoAcquire") and "No target inside the FOV" or "Press Select to acquire a target"
end

local function evaluate(forceAcquire)
	local candidates, frame = gather()
	if not frame then
		return nil
	end
	local st = { id = state.id, manualId = state.manualId, suspended = state.suspended, forceAcquire = forceAcquire or false }
	local cfg = currentConfig(frame)
	local result = Logic.evaluate(candidates, cfg, st)
	return result, candidates, frame, cfg
end

local function apply(result, candidates, frame)
	local previous = state.id
	state.id = result.id
	state.lost = result.lost
	if result.lost then
		state.lastLost = result.lost -- kept for the UI until a newer drop replaces it
	end
	state.result = result
	state.eligible = result.eligible
	state.candidates = candidates
	if result.id ~= previous then
		local reason = result.lost and result.lost.reason or (result.id and "selected" or "cleared")
		Logger.debug("SelectAim", "selection %s -> %s (%s)", tostring(previous), tostring(result.id), reason)
		TargetSelect.Changed:Fire(result.id, reason)
	end
	local selected
	for _, t in ipairs(candidates) do
		if t.id == result.id then
			selected = t
		end
	end
	local predicted, lead
	if selected and s("prediction") then
		predicted, lead = Logic.predict(
			{ x = frame.camPos.X, y = frame.camPos.Y, z = frame.camPos.Z },
			selected.pos, selected.vel, s("projectileSpeed"), s("leadMax")
		)
		if lead == 0 then
			predicted = nil -- a stationary target needs no marker
		end
	end
	state.selected, state.predicted, state.lead = selected, predicted, lead
	paintVisuals(frame, selected, predicted)
end

local function clearSelection()
	if state.id ~= nil then
		state.id = nil
		TargetSelect.Changed:Fire(nil, "disabled")
	end
	state.selected, state.predicted, state.result, state.lost = nil, nil, nil, nil
	hideHighlight()
	if state.fov then
		state.fov.circle.Visible = false
	end
end

local function tick()
	if not s("enabled") then
		if state.wasEnabled then
			state.wasEnabled = false
			clearSelection()
		end
		return
	end
	state.wasEnabled = true
	local force = state.forceAcquire
	state.forceAcquire = false
	local result, candidates, frame = evaluate(force)
	if not result then
		return
	end
	if force then
		state.suspended = false
	end
	apply(result, candidates, frame)
end

-- Public actions (hotkeys, buttons) ------------------------------------------------------------------------------------------

-- select(): acquire the best target by the current mode now. Manual mode adopts the crosshair-nearest one.
function TargetSelect.select()
	if not state or not s("enabled") then
		return false, "Select Aim is off"
	end
	state.suspended = false
	if s("mode") == "Manual" then
		local candidates, frame = gather()
		if not frame then
			return false, "no camera"
		end
		local cfg = currentConfig(frame)
		cfg.mode, cfg.lock = "Crosshair", false
		local r = Logic.evaluate(candidates, cfg, { forceAcquire = true })
		state.manualId = r.id
		if not r.id then
			return false, "no eligible target"
		end
	end
	state.forceAcquire = true
	tick()
	return state.id ~= nil, state.id == nil and "no eligible target" or nil
end

function TargetSelect.toggleLock()
	return Settings.toggle("selectaim.lock", "selectaim")
end

-- reset(): drop the selection (and the manual pick); auto-acquire stays suspended until Select / Next / Previous.
function TargetSelect.reset()
	if not state then
		return false
	end
	state.manualId = nil
	state.suspended = true
	if state.id ~= nil then
		state.id = nil
		TargetSelect.Changed:Fire(nil, "reset")
	end
	state.selected, state.predicted = nil, nil
	hideHighlight()
	return true
end

local function switchTarget(direction)
	if not state or not s("enabled") then
		return false, "Select Aim is off"
	end
	local result, candidates, frame = evaluate(false)
	if not result then
		return false, "no camera"
	end
	local id = Logic.cycle(result.eligible, state.id, direction)
	if not id then
		return false, "no eligible target"
	end
	-- manual switching means manual selection: the mode follows so the choice is not overridden next tick
	if s("mode") ~= "Manual" then
		Settings.set("selectaim.mode", "Manual", "selectaim")
	end
	state.manualId = id
	state.suspended = false
	local r2, c2, f2 = evaluate(true)
	if r2 then
		apply(r2, c2, f2)
	end
	return true
end

function TargetSelect.next()
	return switchTarget(1)
end

function TargetSelect.previous()
	return switchTarget(-1)
end

-- pick(id): choose a target from the UI list (Manual mode)
function TargetSelect.pick(id)
	if not state or not s("enabled") then
		return false, "Select Aim is off"
	end
	if s("mode") ~= "Manual" then
		Settings.set("selectaim.mode", "Manual", "selectaim")
	end
	state.manualId = id
	state.suspended = false
	local r, c, f = evaluate(true)
	if r then
		apply(r, c, f)
	end
	return state.id == id
end

-- Info for the UI -----------------------------------------------------------------------------------------------------------------

function TargetSelect.info()
	if not state then
		return { running = false, status = "Module not running" }
	end
	local sel = state.selected
	local st = { manualId = state.manualId }
	local result = state.result or { status = "none" }
	return {
		running = true,
		enabled = s("enabled"),
		status = statusText(result, st),
		raw = result.status,
		id = state.id,
		name = sel and sel.name or nil,
		distance = sel and sel.dist or nil,
		screenDistance = result.screenDist,
		locked = result.status == "locked",
		visible = sel and sel.visible or nil,
		visibilityAvailable = state.visibilityAvailable,
		mode = s("mode"),
		eligible = state.eligible and #state.eligible or 0,
		total = state.candidates and #state.candidates or 0,
		predicted = state.predicted,
		lead = state.lead,
		lost = state.lastLost,
		fovUnavailable = state.fovUnavailable,
	}
end

-- candidates() -> list for the manual-selection list in the UI: { id, name, eligible, selected }
function TargetSelect.list()
	local out = {}
	if not state or not state.candidates then
		return out
	end
	local eligible = {}
	for _, id in ipairs(state.eligible or {}) do
		eligible[id] = true
	end
	for _, t in ipairs(state.candidates) do
		table.insert(out, { id = t.id, name = t.name, eligible = eligible[t.id] == true, selected = t.id == state.id, distance = t.dist })
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function TargetSelect.selectedId()
	return state and state.id or nil
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------------------

function TargetSelect.start(ctx)
	assert(state == nil, "TargetSelect already started")
	state = {
		id = nil, manualId = nil, suspended = false, forceAcquire = false, wasEnabled = false,
		history = {}, candidates = {}, eligible = {}, visibilityAvailable = nil,
	}
	ctx.maid:Give(function()
		sourceOverride = nil
		clock = os.clock
		state = nil
	end)
	buildVisuals(ctx.maid)
	-- changing the mode while something is selected keeps it as the manual pick
	ctx.maid:Give(Settings.observe("selectaim.mode", function(mode)
		if state and mode == "Manual" and state.id and not state.manualId then
			state.manualId = state.id
		end
	end))
	for _, key in ipairs({ "selectaim.fov", "selectaim.showFov", "selectaim.highlight", "selectaim.prediction", "selectaim.highlightColor", "selectaim.lock", "selectaim.visibilityCheck" }) do
		ctx.maid:Give(Settings.observe(key, function()
			if state and s("enabled") then
				tick() -- apply setting changes immediately, not at the next scheduler step
			end
		end))
	end
	ctx.maid:Give(Settings.observe("selectaim.enabled", function(on)
		if state and not on then
			state.wasEnabled = true
			tick()
		end
	end))
	local h = Perf.every("selectaim", 30, tick, { visual = true })
	ctx.maid:Give(h.Cancel)
end

function TargetSelect.isRunning()
	return state ~= nil
end

return TargetSelect

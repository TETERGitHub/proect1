--!nonstrict
-- features/Drone: third-person flight of a procedurally built delta-wing loitering drone
-- (the "Shahed" model comes from data/ShahedSpec; nothing is downloaded). Controls: keyboard,
-- on-screen stick on touch devices. The reticle is a single dot.
-- Impacts: the drone collides with the local training dummy / targets only (Training.collide),
-- where it can fling them or - in the simulated Murderer role - eliminate them. It never
-- touches, flings or damages real players: map geometry just makes it crash and respawn.
-- STATUS: implemented; verified against the mock layer only (flight maths are unit-tested).
-- Depends on: Settings, Perf, Services, Env, Notify, Training, Sounds, DroneMath, ShahedSpec, Theme, Maid.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Env = import("core/Env")
local Notify = import("core/Notify")
local Maid = import("core/Maid")
local Logger = import("core/Logger")
local Signal = import("core/Signal")
local DM = import("features/DroneMath")
local Spec = import("data/ShahedSpec")
local Training = import("features/Training")
local Sounds = import("features/Sounds")
local Theme = import("ui/Theme")

local Drone = {}

Drone.Changed = Signal.new("Drone.Changed") -- (flying)

local mod = nil -- module-level state (set in start)
local fl = nil -- flight state (exists only while flying)

local function s(name)
	return Settings.get("drone." .. name)
end

-- Model --------------------------------------------------------------------------------------------------------

local SHAPES = { Block = "Block", Ball = "Ball", Cylinder = "Cylinder" }

-- buildModel(accent Color3) -> Model, propParts{ {part, rel CFrame} }, rearAttachments{a0,a1}
local function buildModel(accent)
	local model = Instance.new("Model")
	model.Name = "MM2HubDrone"
	local props = {}
	local primary
	for _, p in ipairs(Spec.parts) do
		local part = Instance.new("Part")
		part.Name = p.name
		part.Shape = Enum.PartType[SHAPES[p.shape]]
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.Material = Enum.Material[p.material]
		part.Color = p.accent and accent or Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local rel = CFrame.new(p.pos[1], p.pos[2], p.pos[3])
			* CFrame.Angles(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
		part.CFrame = rel
		part.Parent = model
		if p.name == "Fuselage" then
			primary = part
		end
		if p.spin then
			table.insert(props, { part = part, rel = rel })
		end
	end
	model.PrimaryPart = primary
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0.2, 0, 6)
	a0.Parent = primary
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.2, 0, 6)
	a1.Parent = primary
	return model, props, { a0, a1 }
end

Drone._buildModel = buildModel

-- HUD ----------------------------------------------------------------------------------------------------------------

local function newText(parent, name, size, bold, pos, anchor, align)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.AnchorPoint = anchor or Vector2.new(0, 0)
	l.Position = pos
	l.Size = UDim2.fromOffset(300, size + 6)
	l.Text = ""
	l.Parent = parent
	return l
end

local function buildHud(gui, maid)
	local hud = {}
	local root = Instance.new("Frame")
	root.Name = "Hud"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	hud.root = root

	-- single-dot reticle
	local dot = Instance.new("Frame")
	dot.Name = "ReticleDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0.5, 0)
	dc.Parent = dot
	local ds = Instance.new("UIStroke")
	ds.Thickness = 1
	ds.Transparency = 0.4
	ds.Color = Color3.fromRGB(0, 0, 0)
	ds.Parent = dot
	dot.Parent = root
	hud.dot = dot

	-- hit marker: two crossed bars around the dot
	local marker = Instance.new("Frame")
	marker.Name = "HitMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(26, 26)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Parent = root
	hud.marker = marker
	hud.markerBars = {}
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(26, 3)
		bar.Rotation = rot
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		bar.Parent = marker
		table.insert(hud.markerBars, bar)
	end

	local telemetry = Instance.new("Frame")
	telemetry.Name = "Telemetry"
	telemetry.AnchorPoint = Vector2.new(0, 1)
	telemetry.Position = UDim2.new(0, 22, 1, -24)
	telemetry.Size = UDim2.fromOffset(240, 72)
	telemetry.BackgroundTransparency = 0.45
	telemetry.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	telemetry.BorderSizePixel = 0
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 14)
	tc.Parent = telemetry
	telemetry.Parent = root
	hud.speed = newText(telemetry, "Speed", 20, true, UDim2.fromOffset(14, 8), nil, nil)
	hud.alt = newText(telemetry, "Alt", 13, false, UDim2.fromOffset(14, 36), nil, nil)
	hud.heading = newText(telemetry, "Heading", 13, false, UDim2.fromOffset(14, 52), nil, nil)

	hud.mode = newText(root, "Mode", 14, true, UDim2.new(1, -22, 0, 20), Vector2.new(1, 0), Enum.TextXAlignment.Right)
	hud.feed = newText(root, "Feed", 13, false, UDim2.new(1, -22, 0, 46), Vector2.new(1, 0), Enum.TextXAlignment.Right)
	hud.hint = newText(root, "Hint", 13, false, UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1), Enum.TextXAlignment.Center)
	hud.hint.Size = UDim2.fromOffset(600, 20)
	return hud
end

local function flashMarker(color)
	if not fl or not fl.hud then
		return
	end
	local m = fl.hud
	for _, bar in ipairs(m.markerBars) do
		bar.BackgroundColor3 = color
	end
	m.marker.Visible = true
	fl.markerUntil = os.clock() + 0.25
end

local function feed(text)
	if fl and fl.hud then
		fl.hud.feed.Text = text
		fl.feedUntil = os.clock() + 2.5
	end
end

-- Touch controls (drawn, shown only on touch devices) -------------------------------------------------------------------

local function buildTouch(gui, maid)
	local F = import("ui/Framework")
	local base = Instance.new("Frame")
	base.Name = "Stick"
	base.AnchorPoint = Vector2.new(0, 1)
	base.Position = UDim2.new(0, 36, 1, -110)
	base.Size = UDim2.fromOffset(140, 140)
	base.BackgroundTransparency = 0.6
	base.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	base.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = base
	base.Parent = gui
	local thumb = Instance.new("Frame")
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.Size = UDim2.fromOffset(60, 60)
	thumb.BackgroundTransparency = 0.15
	thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	thumb.BorderSizePixel = 0
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = thumb
	thumb.Parent = base
	maid:Give(base)
	maid:Give(base.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			local function upd(pos)
				local c = base.AbsolutePosition + base.AbsoluteSize / 2
				local r = base.AbsoluteSize.X / 2
				local vx = math.clamp((pos.X - c.X) / r, -1, 1)
				local vy = math.clamp((pos.Y - c.Y) / r, -1, 1)
				fl.touch.turn = -vx
				fl.touch.pitch = s("invertPitch") and -vy or vy
				thumb.Position = UDim2.new(0.5, vx * r * 0.6, 0.5, vy * r * 0.6)
			end
			upd(input.Position)
			F.beginDrag(upd, function()
				fl.touch.turn, fl.touch.pitch = 0, 0
				thumb.Position = UDim2.fromScale(0.5, 0.5)
			end)
		end
	end))
	local function holdButton(label, xOffset, field, value)
		local b = Instance.new("TextButton")
		b.Text = label
		b.AutoButtonColor = false
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, xOffset, 1, -110)
		b.Size = UDim2.fromOffset(70, 70)
		b.BackgroundTransparency = 0.5
		b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		b.TextColor3 = Color3.fromRGB(0, 0, 0)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 28
		b.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = b
		b.Parent = gui
		maid:Give(b)
		maid:Give(b.MouseButton1Down:Connect(function()
			fl.touch[field] = value
		end))
		maid:Give(b.MouseButton1Up:Connect(function()
			fl.touch[field] = 0
		end))
		maid:Give(b.MouseLeave:Connect(function()
			fl.touch[field] = 0
		end))
	end
	holdButton("+", -30, "throttle", 1)
	holdButton("–", -112, "throttleDown", -1)
	local exitBtn = Instance.new("TextButton")
	exitBtn.Text = "EXIT"
	exitBtn.AutoButtonColor = false
	exitBtn.Position = UDim2.new(0, 22, 0, 22)
	exitBtn.Size = UDim2.fromOffset(84, 36)
	exitBtn.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
	exitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	exitBtn.Font = Enum.Font.GothamBold
	exitBtn.TextSize = 14
	exitBtn.BorderSizePixel = 0
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0, 12)
	ec.Parent = exitBtn
	exitBtn.Parent = gui
	maid:Give(exitBtn)
	maid:Give(exitBtn.Activated:Connect(function()
		Drone.land()
	end))
end

-- Flight ------------------------------------------------------------------------------------------------------------------

local function pivotCFrame(st)
	return CFrame.new(st.x, st.y, st.z) * CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.pitch, 0, 0) * CFrame.Angles(0, 0, st.roll)
end

local function launchState()
	local player = Services.Players.LocalPlayer
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cam = Services.Workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pos = root and root.Position or cam.CFrame.Position
	local st = DM.newState(pos.X - math.sin(yaw) * 10, pos.Y + 34, pos.Z - math.cos(yaw) * 10, yaw)
	st.speed = s("speed")
	return st
end

local function rayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { fl.model }
	local player = Services.Players.LocalPlayer
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local tr = Services.Workspace:FindFirstChild("MM2Hub_Training")
	if tr then
		table.insert(ignore, tr)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

local function crash(pos)
	if fl.crashedUntil then
		return
	end
	fl.crashedUntil = os.clock() + 1.4
	fl.shake = 1
	feed("CRASHED - respawning")
	fl.model.Parent = nil
	pcall(function()
		local boom = Instance.new("Part")
		boom.Shape = Enum.PartType.Ball
		boom.Anchored = true
		boom.CanCollide = false
		boom.CanQuery = false
		boom.Material = Enum.Material.Neon
		boom.Color = Color3.fromRGB(255, 170, 70)
		boom.Size = Vector3.new(2, 2, 2)
		boom.Position = pos
		boom.Parent = Services.Workspace
		local goal = { Size = Vector3.new(16, 16, 16), Transparency = 1 }
		local tw = Services.TweenService:Create(boom, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
		tw:Play()
		Services.Debris:AddItem(boom, 1)
	end)
end

local function respawn()
	fl.st = launchState()
	fl.crashedUntil = nil
	fl.camPos = nil
	fl.model.Parent = fl.container
	fl.model:PivotTo(pivotCFrame(fl.st))
end

local lastWarn = 0
local function checkImpacts(ox, oy, oz)
	local st = fl.st
	local hits = Training.collide(ox, oy, oz, st.x, st.y, st.z, 1.0)
	for _, hit in ipairs(hits) do
		local ix, iy, iz = DM.impactVector(st, s("flingForce"), 0.4)
		local ok, msg = Training.impact(hit, s("mode"), s("simRole"), ix, iy, iz)
		if ok then
			flashMarker(s("mode") == "Eliminate" and Color3.fromRGB(255, 69, 58) or Color3.fromRGB(255, 255, 255))
			feed(msg)
		elseif os.clock() - lastWarn > 4 then
			lastWarn = os.clock()
			Notify.push({ title = "Drone", text = tostring(msg) .. ". Change the simulated role on the Drone page.", level = "warn" })
		end
	end
end

local function updateHud(dt)
	local h = fl.hud
	local st = fl.st
	fl.hudTimer += dt
	if fl.markerUntil and os.clock() > fl.markerUntil then
		h.marker.Visible = false
		fl.markerUntil = nil
	end
	if fl.feedUntil and os.clock() > fl.feedUntil then
		h.feed.Text = ""
		fl.feedUntil = nil
	end
	if fl.hudTimer < 0.1 then
		return
	end
	fl.hudTimer = 0
	h.root.Visible = s("showHud")
	h.speed.Text = string.format("%d studs/s", st.speed + 0.5)
	h.alt.Text = string.format("ALT %d", st.y + 0.5)
	h.heading.Text = string.format("HDG %03d°", (math.deg(-st.yaw) % 360) + 0.5)
	local role = s("simRole")
	h.mode.Text = string.upper(s("mode")) .. (s("mode") == "Eliminate" and (role == "Murderer" and "  ·  MURDERER" or "  ·  needs Murderer") or "")
	h.mode.TextColor3 = (s("mode") == "Eliminate" and role ~= "Murderer") and Color3.fromRGB(255, 159, 10) or Color3.fromRGB(255, 255, 255)
	if os.clock() - fl.startedAt > 7 then
		h.hint.Text = ""
	end
end

local function flyFrame(dt)
	if not fl then
		return
	end
	local st = fl.st
	local cam = Services.Workspace.CurrentCamera
	local now = os.clock()

	if fl.crashedUntil then
		if now >= fl.crashedUntil then
			respawn()
		end
		updateHud(dt)
		return
	end

	local turn, pitch, throttle = DM.axes(fl.keys, s("invertPitch"))
	turn = math.clamp(turn + fl.touch.turn, -1, 1)
	pitch = math.clamp(pitch + fl.touch.pitch, -1, 1)
	throttle = math.clamp(throttle + fl.touch.throttle + fl.touch.throttleDown, -1, 1)

	local ox, oy, oz = DM.step(st, { turn = turn, pitch = pitch, throttle = throttle }, dt, {
		cruise = s("speed"),
		turnRate = s("turnRate"),
	})

	-- world collision: map geometry crashes the drone; players are never affected
	if s("worldCollision") then
		local dx, dy, dz = st.x - ox, st.y - oy, st.z - oz
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist > 1e-4 then
			local dir = Vector3.new(dx / dist, dy / dist, dz / dist)
			local res = Services.Workspace:Raycast(Vector3.new(ox, oy, oz), dir * (dist + 1.4), fl.params)
			if res then
				crash(res.Position)
				return
			end
		end
	end

	checkImpacts(ox, oy, oz)

	local cf = pivotCFrame(st)
	fl.model:PivotTo(cf)
	-- spin the pusher propeller (anchored parts, so their CFrames are written explicitly)
	fl.propAngle += dt * (30 + st.speed * 0.4)
	for _, p in ipairs(fl.props) do
		p.part.CFrame = cf * p.rel * CFrame.Angles(0, 0, fl.propAngle)
	end

	-- chase camera with smoothing, speed-dependent FOV kick and crash shake
	local cx, cy, cz, lx, ly, lz = DM.chaseCamera(st, s("camDistance"), s("camHeight"))
	local target = Vector3.new(cx, cy, cz)
	fl.camPos = fl.camPos and fl.camPos:Lerp(target, 1 - math.exp(-dt * 9)) or target
	local shakeOffset = Vector3.new(0, 0, 0)
	if fl.shake > 0.01 then
		shakeOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * fl.shake * 1.5
		fl.shake *= 0.9
	end
	cam.CFrame = CFrame.lookAt(fl.camPos + shakeOffset, Vector3.new(lx, ly, lz))
	cam.FieldOfView = 70 + 14 * math.clamp((st.speed - s("speed")) / (s("speed") * 0.5), -0.3, 1)

	updateHud(dt)

	local humanoid = Services.Players.LocalPlayer.Character and Services.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		Drone.land()
	end
end

-- Input binding -------------------------------------------------------------------------------------------------------------------------

local KEY_NAMES = { LeftShift = "Shift", RightShift = "Shift" }
local function boundKeys()
	local k = Enum.KeyCode
	return { k.W, k.A, k.S, k.D, k.Up, k.Down, k.Left, k.Right, k.Space, k.LeftShift, k.RightShift }
end

local function bindKeys()
	local cas = Services.ContextActionService
	cas:BindActionAtPriority("MM2HubDrone", function(_, state, input)
		if not fl then
			return Enum.ContextActionResult.Pass
		end
		local name = KEY_NAMES[input.KeyCode.Name] or input.KeyCode.Name
		fl.keys[name] = (state == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Sink
	end, false, 3000, table.unpack(boundKeys()))
	cas:BindActionAtPriority("MM2HubDroneExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			Drone.land()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3001, Enum.KeyCode.X, Enum.KeyCode.Backspace)
end

local function unbindKeys()
	local cas = Services.ContextActionService
	pcall(function()
		cas:UnbindAction("MM2HubDrone")
		cas:UnbindAction("MM2HubDroneExit")
	end)
end

-- Public API ----------------------------------------------------------------------------------------------------------------------------------

function Drone.isFlying()
	return fl ~= nil
end

-- launch(): enter flight. Returns ok, err.
function Drone.launch()
	if not mod then
		return false, "drone module is not running"
	end
	if fl then
		return true
	end
	local parent, how = Env.guiParent()
	if not parent then
		return false, "no GUI container"
	end
	local cam = Services.Workspace.CurrentCamera
	if not cam then
		return false, "no camera"
	end
	local maid = Maid.new("drone-flight")
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubDroneHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	maid:Give(gui)

	local accent = Theme.color("accent")
	local model, props, attachments = buildModel(accent)
	local container = Services.Workspace
	model.Parent = container
	maid:Give(model)

	local trail
	if s("trail") then
		trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = attachments[1], attachments[2]
		trail.Lifetime = 0.7
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(accent, Color3.fromRGB(255, 255, 255))
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = model.PrimaryPart
	end

	fl = {
		maid = maid, gui = gui, model = model, props = props, container = container,
		st = launchState(), keys = {}, touch = { turn = 0, pitch = 0, throttle = 0, throttleDown = 0 },
		propAngle = 0, shake = 0, hudTimer = 1, startedAt = os.clock(), camPos = nil,
		saved = { type = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView },
	}
	fl.params = rayParams()
	fl.hud = buildHud(gui, maid)
	fl.hud.hint.Text = "W/S pitch · A/D turn · Space/Shift throttle · X exit"
	if Services.UserInputService.TouchEnabled then
		buildTouch(gui, maid)
		fl.hud.hint.Text = "Stick: steer · + / – throttle · EXIT to land"
	end
	model:PivotTo(pivotCFrame(fl.st))

	cam.CameraType = Enum.CameraType.Scriptable
	bindKeys()
	if s("engineSound") then
		Sounds.startLoop("engine")
	end
	local handle = Perf.every("drone.fly", 1000, flyFrame)
	maid:Give(handle.Cancel)
	maid:Give(function()
		Sounds.stopLoop("engine")
		unbindKeys()
		pcall(function()
			cam.CameraType = fl and fl.saved.type or Enum.CameraType.Custom
			cam.CameraSubject = fl and fl.saved.subject or nil
			cam.FieldOfView = fl and fl.saved.fov or 70
		end)
	end)
	Logger.info("Drone", "launched (GUI container %s)", how)
	Drone.Changed:Fire(true)
	return true
end

function Drone.land()
	if not fl then
		return false
	end
	local f = fl
	fl.model.Parent = nil
	f.maid:Clean()
	fl = nil
	Logger.info("Drone", "landed")
	Drone.Changed:Fire(false)
	return true
end

function Drone.toggle()
	if fl then
		return Drone.land()
	end
	return Drone.launch()
end

function Drone.start(ctx)
	assert(mod == nil, "Drone already started")
	mod = { started = os.clock() }
	ctx.maid:Give(function()
		Drone.land()
		mod = nil
	end)
end

function Drone.isRunning()
	return mod ~= nil
end

function Drone.telemetry()
	if not fl then
		return nil
	end
	return { speed = fl.st.speed, altitude = fl.st.y, yaw = fl.st.yaw }
end

return Drone

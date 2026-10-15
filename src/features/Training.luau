--!nonstrict
-- features/Training: local-only practice range and physics stand.
--   * Practice targets: spheres in front of you; click to hit; accuracy and reaction statistics.
--   * Physics stand: a mannequin that can be launched (impulse, speed limit) or "eliminated".
-- Everything lives in a client-side Folder and never touches other players.
-- STATUS: implemented; verified against the mock layer only.
-- Depends on: Settings, Perf, Services, Signal, TrainingLogic, Sounds, Theme(colour).

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Signal = import("core/Signal")
local TL = import("features/TrainingLogic")
local HB = import("features/HitboxMath")
local Geo = import("features/Geometry")
local Sounds = import("features/Sounds")
local KillEvents = import("features/KillEvents")
local Logger = import("core/Logger")
local Maid = import("core/Maid")

local Training = {}

Training.Event = Signal.new("Training.Event") -- (kind, detail)

local state = nil
local stats = TL.newStats()

local function s(name)
	return Settings.get("training." .. name)
end

local function playerRoot()
	local p = Services.Players.LocalPlayer
	local c = p and p.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function camera()
	return Services.Workspace.CurrentCamera
end

-- Origin: character position and camera yaw. Falls back to the camera when no character.
local function origin()
	local root = playerRoot()
	local cam = camera()
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local yaw = math.atan2(-look.X, -look.Z)
	local pos = root and root.Position or (cam and cam.CFrame.Position) or Vector3.new(0, 5, 0)
	return pos, yaw
end

local function rotateY(x, z, yaw)
	local c, sn = math.cos(yaw), math.sin(yaw)
	-- rotation about +Y by yaw ("yaw 0 faces -Z, left positive")
	return x * c + z * sn, -x * sn + z * c
end

local function cap()
	return math.min(s("count"), Settings.get("perf.maxDecor"))
end

-- Targets ---------------------------------------------------------------------------------------------------

local function newTargetPart(color, size)
	local part = Instance.new("Part")
	part.Name = "HubTarget"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(size, size, size)
	part.Color = color
	part:SetAttribute("HubObject", true)
	return part
end

local function emitBurst(part)
	if not s("particles") then
		return
	end
	local ok = pcall(function()
		local attach = Instance.new("Attachment")
		attach.Parent = part
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(0.35, 0.6)
		pe.Speed = NumberRange.new(12, 26)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.5, 0)
		pe.LightEmission = 1
		pe.Color = ColorSequence.new(part.Color, Color3.fromRGB(255, 255, 255))
		pe.Parent = attach
		pe:Emit(math.min(24, Settings.get("perf.maxDecor") * 2))
		Services.Debris:AddItem(attach, 1.2)
	end)
	if not ok then
		Logger.debug("Training", "particle burst failed")
	end
end

local function placeTarget(t, now)
	local pos, yaw = state.origin, state.yaw
	local layout = state.layout[t.index]
	local rx, rz = rotateY(layout.x, layout.z, yaw)
	t.base = { x = pos.X + rx, y = pos.Y + layout.y, z = pos.Z + rz }
	t.shownAt = now
end

local function buildTargets()
	local count = cap()
	for _, t in ipairs(state.targets) do
		t.part:Destroy()
	end
	table.clear(state.targets)
	local pos, yaw = origin()
	state.origin, state.yaw = pos, yaw
	state.layout = TL.layout(count, s("distance"))
	local c = s("targetColor")
	local color = Color3.fromRGB(c.r, c.g, c.b)
	for i = 1, count do
		local part = newTargetPart(color, s("targetSize"))
		part.Parent = state.folder
		local t = { part = part, index = i, base = { x = 0, y = 0, z = 0 }, pos = { x = 0, y = 0, z = 0 }, visible = true, respawnAt = nil, shownAt = os.clock() }
		placeTarget(t, os.clock())
		table.insert(state.targets, t)
	end
end

local function setTargetVisible(t, visible)
	if t.visible ~= visible then
		t.visible = visible
		t.part.Transparency = visible and 0 or 1
		if visible then
			t.shownAt = os.clock()
		end
	end
end

local function updateTargets(dt)
	local now = os.clock()
	local mode = s("mode")
	local speed = s("speed")
	for _, t in ipairs(state.targets) do
		if t.respawnAt then
			if now >= t.respawnAt then
				t.respawnAt = nil
				placeTarget(t, now)
				setTargetVisible(t, true)
			end
		else
			local dx, dy, dz, visible = TL.motion(mode, now - state.startedAt, speed, t.index)
			-- strafing moves along the camera-right axis at spawn time
			local rx, rz = rotateY(dx, dz, state.yaw)
			t.pos.x, t.pos.y, t.pos.z = t.base.x + rx, t.base.y + dy, t.base.z + rz
			t.part.Position = Vector3.new(t.pos.x, t.pos.y, t.pos.z)
			setTargetVisible(t, visible)
		end
	end
end

-- Demo guide: a drawn ring around the nearest target (never any player) ----------------------------------

local function ensureGuide()
	if state.guide then
		return state.guide
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HubGuide"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(90, 90)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Parent = ring
	ring.Parent = gui
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 1, 2)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.MontserratBold
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = ""
	label.Parent = gui
	state.guide = gui
	state.guideLabel = label
	return gui
end

local function updateGuide()
	if not s("demoGuide") then
		if state.guide then
			state.guide.Adornee = nil
			state.guide.Parent = nil
		end
		return
	end
	local cam = camera()
	if not cam then
		return
	end
	local camPos, look = cam.CFrame.Position, cam.CFrame.LookVector
	local best, bestScore = nil, -2
	for _, t in ipairs(state.targets) do
		if t.visible and not t.respawnAt then
			local dx, dy, dz = t.pos.x - camPos.X, t.pos.y - camPos.Y, t.pos.z - camPos.Z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d > 0 then
				local score = (dx * look.X + dy * look.Y + dz * look.Z) / d
				if score > bestScore then
					best, bestScore = t, score
				end
			end
		end
	end
	local guide = ensureGuide()
	if best then
		guide.Adornee = best.part
		guide.Parent = state.folder
		local dx, dy, dz = best.pos.x - camPos.X, best.pos.y - camPos.Y, best.pos.z - camPos.Z
		state.guideLabel.Text = string.format("%.0f studs", math.sqrt(dx * dx + dy * dy + dz * dz))
	else
		guide.Adornee = nil
	end
end

-- Shooting -----------------------------------------------------------------------------------------------------------

-- shoot(originVec, dirVec): returns true when a target was hit (exposed for tests and touch input)
function Training.shoot(o, d)
	if not state or (not s("enabled") and not state.lab) then
		return false
	end
	local ot = { x = o.X, y = o.Y, z = o.Z }
	local dt = { x = d.X, y = d.Y, z = d.Z }
	local best, bestDist = nil, math.huge
	for _, t in ipairs(state.targets) do
		if t.visible and not t.respawnAt then
			local dist = TL.raySphere(ot, dt, t.pos, s("targetSize") / 2)
			if dist and dist < bestDist then
				best, bestDist = t, dist
			end
		end
	end
	-- hitbox lab: ONLY the lab hitbox scores. Hitting just the visible body is recorded as a miss.
	local lab = state.lab
	if lab then
		local hp = lab.hitbox.Position
		local center = { x = hp.X, y = hp.Y, z = hp.Z }
		local size = s("hbSize")
		local dist
		if s("hbShape") == "Box" then
			dist = Geo.rayBox(ot, dt, center, { x = size / 2, y = size / 2, z = size / 2 })
		else
			dist = Geo.raySphere(ot, dt, center, size / 2)
		end
		if dist and dist < bestDist then
			lab.shots += 1
			lab.hits += 1
			stats:shot(true, 0)
			stats:kill()
			emitBurst(lab.hitbox)
			lab.flashUntil = os.clock() + 0.2
			Sounds.play("hit")
			Training.Event:Fire("lab-hit")
			return true
		end
		local bp = lab.body.PrimaryPart.Position
		local bodyDist = Geo.raySphere(ot, dt, { x = bp.X, y = bp.Y, z = bp.Z }, 2.2)
		if bodyDist and bodyDist < bestDist then
			lab.shots += 1
			lab.bodyOnly += 1
			stats:shot(false)
			Training.Event:Fire("lab-body-only")
			return false
		end
	end
	if not best then
		stats:shot(false)
		Training.Event:Fire("miss")
		return false
	end
	stats:shot(true, os.clock() - best.shownAt)
	stats:kill()
	emitBurst(best.part)
	setTargetVisible(best, false)
	best.respawnAt = os.clock() + 0.35
	Sounds.play("hit")
	Sounds.play("kill")
	-- a destroyed training target is a confirmed kill of the local sandbox (role: sheriff, source: training)
	KillEvents.report("sheriff", "target" .. tostring(best.index) .. ":" .. tostring(os.clock()), "training")
	Training.Event:Fire("hit", best.index)
	return true
end

local function onInput(input, processed)
	if processed or not state or (not s("enabled") and not state.lab) then
		return
	end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
		return
	end
	local cam = camera()
	if not cam then
		return
	end
	local loc = (t == Enum.UserInputType.Touch) and Vector2.new(input.Position.X, input.Position.Y) or Services.UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	Training.shoot(ray.Origin, ray.Direction)
end

-- Physics stand ----------------------------------------------------------------------------------------------------------

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = a
end

local function dummyPart(model, name, size, offset, root, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = name == "Torso"
	p.CanQuery = false
	p.CanTouch = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = root.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
	p.Parent = model
	weld(root, p)
	return p
end

local function buildDummy(cf)
	local model = Instance.new("Model")
	model.Name = "HubDummy"
	local body = Color3.fromRGB(205, 210, 222)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = body
	torso.Material = Enum.Material.SmoothPlastic
	torso.CFrame = cf
	torso.CanQuery = false
	torso.CanTouch = false
	torso.Parent = model
	model.PrimaryPart = torso
	dummyPart(model, "Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.7, 0), torso, body, Enum.PartType.Ball)
	dummyPart(model, "ArmL", Vector3.new(0.8, 2, 0.8), Vector3.new(-1.4, 0, 0), torso, body)
	dummyPart(model, "ArmR", Vector3.new(0.8, 2, 0.8), Vector3.new(1.4, 0, 0), torso, body)
	dummyPart(model, "LegL", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0), torso, body)
	dummyPart(model, "LegR", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0), torso, body)
	local belt = dummyPart(model, "Belt", Vector3.new(2.05, 0.25, 1.05), Vector3.new(0, -0.6, 0), torso, Color3.fromRGB(90, 160, 255))
	belt.Material = Enum.Material.Neon
	model:SetAttribute("HubObject", true)
	return model, torso
end

function Training.spawnDummy()
	if not state then
		return false, "training module is not running"
	end
	Training.clearDummy()
	local pos, yaw = origin()
	local fx, fz = rotateY(0, -14, yaw)
	local cf = CFrame.new(pos.X + fx, pos.Y + 3, pos.Z + fz)
	local model, torso = buildDummy(cf)
	model.Parent = state.folder
	state.dummy = { model = model, torso = torso, home = cf, eliminated = false }
	Training.Event:Fire("dummy-spawned")
	return true
end

function Training.clearDummy()
	if state and state.dummy then
		state.dummy.model:Destroy()
		state.dummy = nil
	end
end

function Training.resetDummy()
	local d = state and state.dummy
	if not d then
		return false, "no dummy"
	end
	d.torso.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	d.torso.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	d.model:PivotTo(d.home)
	d.eliminated = false
	for _, part in ipairs(d.model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "Belt" then
			part.Color = Color3.fromRGB(205, 210, 222)
		end
	end
	Training.Event:Fire("dummy-reset")
	return true
end

local function directionVector(name)
	local cam = camera()
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local fx, fz = look.X, look.Z
	local m = math.sqrt(fx * fx + fz * fz)
	if m < 1e-4 then
		fx, fz, m = 0, -1, 1
	end
	fx, fz = fx / m, fz / m
	if name == "Up" then
		return Vector3.new(0, 1, 0)
	elseif name == "Back" then
		return Vector3.new(-fx, 0.25, -fz)
	elseif name == "Left" then
		return Vector3.new(-fz, 0.25, fx)
	elseif name == "Right" then
		return Vector3.new(fz, 0.25, -fx)
	end
	return Vector3.new(fx, 0.25, fz)
end

local function applyImpulse(d, ix, iy, iz)
	local mass = d.torso.AssemblyMass or d.torso:GetMass()
	d.torso:ApplyImpulse(Vector3.new(ix, iy, iz) * mass)
	d.torso.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
end

-- launch(): impulse from the stand settings
function Training.launch()
	local d = state and state.dummy
	if not d then
		local ok, err = Training.spawnDummy()
		if not ok then
			return false, err
		end
		d = state.dummy
	end
	local dir = directionVector(s("physDirection"))
	local k = s("physImpulse")
	applyImpulse(d, dir.X * k, dir.Y * k, dir.Z * k)
	Training.Event:Fire("launch")
	return true
end

local function clampDummy()
	local d = state.dummy
	if not d then
		return
	end
	local v = d.torso.AssemblyLinearVelocity
	local x, y, z = TL.clampVelocity(v.X, v.Y, v.Z, s("physMaxSpeed"))
	if x ~= v.X or y ~= v.Y or z ~= v.Z then
		d.torso.AssemblyLinearVelocity = Vector3.new(x, y, z)
	end
	if d.torso.Position.Y < -200 then
		Training.resetDummy()
	end
end

-- Hitbox lab -------------------------------------------------------------------------------------------------------------
-- Three separate layers (never conflated):
--   1. VISUAL hitbox    : the translucent shape you see (Transparency / colour / Position). Cosmetic.
--   2. PHYSICAL geometry: real engine collisions between local parts of this isolated scene
--                         (floor, wall, hitbox with CanCollide, thrown probe projectiles).
--   3. SERVER registration: not available. MM2 decides real hits in its own scripts / on the server; this lab
--                         never sends, alters or predicts a real hit. Scores here are LOCAL ONLY.
-- Moving the lab hitbox therefore says nothing about how MM2 registers hits on a real player.

local function scenePart(name, size, cf, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("HubObject", true)
	return p
end

local function applyHitboxGeometry(lab)
	local size = s("hbSize")
	local hb = lab.hitbox
	local wantShape = s("hbShape") == "Box" and Enum.PartType.Block or Enum.PartType.Ball
	if hb.Shape ~= wantShape then
		hb.Shape = wantShape
	end
	if hb.Size.X ~= size then
		hb.Size = Vector3.new(size, size, size)
	end
	hb.CanCollide = s("hbCollide")
end

-- spawnLab(): builds the isolated test scene (floor, back wall), an anchored mannequin and the hitbox.
function Training.spawnLab()
	if not state then
		return false, "training module is not running"
	end
	Training.clearLab()
	local pos, yaw = origin()
	local fx, fz = rotateY(0, -20, yaw)
	local cx, cy, cz = pos.X + fx, pos.Y, pos.Z + fz
	local scene = Instance.new("Folder")
	scene.Name = "HubLabScene"
	scene.Parent = state.folder
	local floorCF = CFrame.new(cx, cy - 3.5, cz)
	local floor = scenePart("LabFloor", Vector3.new(60, 1, 60), floorCF, Color3.fromRGB(46, 48, 58))
	floor.Parent = scene
	local bx, bz = rotateY(0, -28, yaw)
	local wall = scenePart("LabWall", Vector3.new(60, 24, 1), CFrame.new(pos.X + bx, cy + 8, pos.Z + bz), Color3.fromRGB(34, 36, 44))
	wall.Parent = scene
	local body, torso = buildDummy(CFrame.new(cx, cy + 1, cz))
	body.Name = "HubLabBody"
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false -- the body is a visual reference only; the hitbox is the physical object
		end
	end
	body.Parent = scene
	local hitbox = Instance.new("Part")
	hitbox.Name = "HubLabHitbox"
	hitbox.Anchored = true
	hitbox.CanQuery = true
	hitbox.CanTouch = true
	hitbox.CastShadow = false
	hitbox.Material = Enum.Material.Neon
	hitbox.Color = Color3.fromRGB(80, 200, 255)
	hitbox:SetAttribute("HubObject", true)
	hitbox.Parent = scene
	local home = torso.Position
	local lab = {
		scene = scene, floor = floor, wall = wall, body = body, hitbox = hitbox, home = home,
		startedAt = os.clock(), shots = 0, hits = 0, bodyOnly = 0, collisions = 0, probes = 0, flashUntil = 0,
		probeMaid = Maid.new("lab-probes"), nearMiss = nil,
	}
	state.lab = lab
	applyHitboxGeometry(lab)
	hitbox.Position = Vector3.new(home.X + s("hbOffsetX"), home.Y + s("hbOffsetY"), home.Z + s("hbOffsetZ"))
	Training.Event:Fire("lab-spawned")
	return true
end

function Training.clearLab()
	if state and state.lab then
		state.lab.probeMaid:Clean()
		state.lab.scene:Destroy()
		state.lab = nil
		Training.Event:Fire("lab-cleared")
	end
end

function Training.resetLabCounters()
	local lab = state and state.lab
	if lab then
		lab.shots, lab.hits, lab.bodyOnly, lab.collisions, lab.probes, lab.nearMiss = 0, 0, 0, 0, 0, nil
	end
end

local function labParams()
	return {
		orbitRadius = s("orbitRadius"), orbitSpeed = s("orbitSpeed"), orbitTilt = s("orbitTilt"),
		jitterAmplitude = s("jitterAmplitude"), jitterSpeed = s("jitterSpeed"),
		blinkRange = s("blinkRange"), blinkInterval = s("blinkInterval"),
	}
end

local function updateLab()
	local lab = state.lab
	if not lab then
		return
	end
	applyHitboxGeometry(lab)
	local base = Vector3.new(lab.home.X + s("hbOffsetX"), lab.home.Y + s("hbOffsetY"), lab.home.Z + s("hbOffsetZ"))
	local dx, dy, dz = HB.offset(s("hbMode"), os.clock() - lab.startedAt, labParams())
	lab.hitbox.Position = Vector3.new(base.X + dx, base.Y + dy, base.Z + dz)
	local flash = os.clock() < lab.flashUntil
	lab.hitbox.Transparency = flash and 0.1 or (s("hbShow") and 0.55 or 1)
	lab.hitbox.Color = flash and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 200, 255)
end

-- labReadout() -> numbers for the UI: positions, offset, distance, what the active mode modifies, scores.
function Training.labReadout()
	local lab = state and state.lab
	if not lab then
		return nil
	end
	local b, h = lab.body.PrimaryPart.Position, lab.hitbox.Position
	local mode = s("hbMode")
	local cam = camera()
	local c = cam and cam.CFrame.Position or Vector3.new(0, 0, 0)
	return {
		body = { x = b.X, y = b.Y, z = b.Z },
		hitbox = { x = h.X, y = h.Y, z = h.Z },
		offset = { x = h.X - b.X, y = h.Y - b.Y, z = h.Z - b.Z },
		distanceFromBody = Geo.distance({ x = b.X, y = b.Y, z = b.Z }, { x = h.X, y = h.Y, z = h.Z }),
		distanceFromCamera = Geo.distance({ x = c.X, y = c.Y, z = c.Z }, { x = h.X, y = h.Y, z = h.Z }),
		mode = mode,
		modeChanges = HB.MODES[mode].affects,
		shape = s("hbShape"),
		size = s("hbSize"),
		shots = lab.shots, hits = lab.hits, bodyOnly = lab.bodyOnly, collisions = lab.collisions, probes = lab.probes,
		accuracy = lab.shots > 0 and lab.hits / lab.shots or 0,
	}
end

-- labLayers() -> the three layers with their honest state (used verbatim by the UI)
function Training.labLayers()
	local lab = state and state.lab
	return {
		{ name = "Visual hitbox", state = lab and (s("hbShow") and "shown" or "hidden") or "no lab", detail = "translucent " .. string.lower(s("hbShape")) .. ", cosmetic" },
		{ name = "Physical geometry", state = lab and (s("hbCollide") and "collidable" or "query only") or "no lab", detail = "real collisions between local parts of the isolated scene (probes, floor, wall)" },
		{ name = "Server hit registration", state = "not available", detail = "MM2 registers hits itself; this lab never sends or alters hits. Scores are local only" },
	}
end

-- labProbe(): intersection check of the screen-centre ray against hitbox and body (live readout).
function Training.labProbe()
	local lab = state and state.lab
	local cam = camera()
	if not lab or not cam then
		return nil
	end
	local vp = cam.ViewportSize
	local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local o = { x = ray.Origin.X, y = ray.Origin.Y, z = ray.Origin.Z }
	local d = { x = ray.Direction.X, y = ray.Direction.Y, z = ray.Direction.Z }
	local h, b = lab.hitbox.Position, lab.body.PrimaryPart.Position
	local hc, size = { x = h.X, y = h.Y, z = h.Z }, s("hbSize")
	local hitDist
	if s("hbShape") == "Box" then
		hitDist = Geo.rayBox(o, d, hc, { x = size / 2, y = size / 2, z = size / 2 })
	else
		hitDist = Geo.raySphere(o, d, hc, size / 2)
	end
	return {
		hitbox = hitDist,
		body = Geo.raySphere(o, d, { x = b.X, y = b.Y, z = b.Z }, 2.2),
		nearMiss = Geo.closestApproach(o, d, hc),
	}
end

-- labOverlap(): parts of the scene currently overlapping the hitbox (engine spatial query).
function Training.labOverlap()
	local lab = state and state.lab
	if not lab then
		return {}
	end
	local out = {}
	local ok = pcall(function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { lab.scene }
		for _, part in ipairs(Services.Workspace:GetPartBoundsInRadius(lab.hitbox.Position, s("hbSize") / 2, params)) do
			if part ~= lab.hitbox then
				table.insert(out, part.Name)
			end
		end
	end)
	return ok and out or {}
end

-- fireProbe(): throws a real physical projectile at the hitbox centre (gravity-compensated). When it touches
-- the hitbox the engine fires Touched - that is a physical collision in the isolated scene, nothing more.
function Training.fireProbe()
	local lab = state and state.lab
	local cam = camera()
	if not lab or not cam then
		return false, "spawn the lab first"
	end
	local speed = 140
	local from = cam.CFrame.Position + cam.CFrame.LookVector * 3
	local hp = lab.hitbox.Position
	local aim = Geo.ballisticAim({ x = from.X, y = from.Y, z = from.Z }, { x = hp.X, y = hp.Y, z = hp.Z }, speed, Services.Workspace.Gravity)
	local dir = (Vector3.new(aim.x, aim.y, aim.z) - from).Unit
	local probe = Instance.new("Part")
	probe.Name = "HubLabProbe"
	probe.Shape = Enum.PartType.Ball
	probe.Size = Vector3.new(1, 1, 1)
	probe.Material = Enum.Material.Neon
	probe.Color = Color3.fromRGB(255, 200, 80)
	probe.CanCollide = true
	probe.CanTouch = true
	probe.CanQuery = false
	probe:SetAttribute("HubObject", true)
	probe.Position = from
	probe.Parent = lab.scene
	probe.AssemblyLinearVelocity = dir * speed
	lab.probes += 1
	local counted = false
	lab.probeMaid:Give(probe.Touched:Connect(function(other)
		if other == lab.hitbox and not counted then
			counted = true
			lab.collisions += 1
			lab.flashUntil = os.clock() + 0.25
			Training.Event:Fire("lab-collision")
		end
	end))
	Services.Debris:AddItem(probe, 4)
	return true
end

-- extra test-object sources (other practice modules, e.g. features/MurderTrainer's mannequins): name -> fn() -> items
local sources = {}

function Training.addSource(name, fn)
	sources[name] = fn
end

function Training.removeSource(name)
	sources[name] = nil
end

-- targetList(): the test objects Select Aim may choose from. Items: { id, name, part, alive }.
function Training.targetList()
	local out = {}
	for name, fn in pairs(sources) do
		local ok, list = pcall(fn)
		if ok and type(list) == "table" then
			for _, item in ipairs(list) do
				table.insert(out, item)
			end
		else
			Logger.warn("Training", "target source '%s' failed: %s", name, tostring(list))
		end
	end
	if not state then
		return out
	end
	for _, t in ipairs(state.targets) do
		table.insert(out, { id = string.format("T%02d", t.index), name = "Target " .. t.index, part = t.part, alive = t.visible and not t.respawnAt })
	end
	if state.dummy then
		table.insert(out, { id = "Dummy", name = "Physics dummy", part = state.dummy.torso, alive = not state.dummy.eliminated })
	end
	if state.lab then
		table.insert(out, { id = "LabHitbox", name = "Lab hitbox", part = state.lab.hitbox, alive = true })
	end
	return out
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------------------------

local function spawnRange()
	if not state or state.active then
		return
	end
	state.active = true
	state.startedAt = os.clock()
	buildTargets()
	Training.Event:Fire("range-on")
end

local function clearRange()
	if not state then
		return
	end
	state.active = false
	for _, t in ipairs(state.targets) do
		t.part:Destroy()
	end
	table.clear(state.targets)
	if state.guide then
		state.guide.Adornee = nil
		state.guide.Parent = nil
	end
	Training.Event:Fire("range-off")
end

-- clear(): removes every spawned object (targets, dummy, guide) and turns the range off.
function Training.clear()
	if not state then
		return
	end
	clearRange()
	Training.clearDummy()
	Training.clearLab()
	if Settings.get("training.enabled") then
		Settings.set("training.enabled", false, "training-clear")
	end
end

function Training.start(ctx)
	assert(state == nil, "Training already started")
	local folder = Instance.new("Folder")
	folder.Name = "MM2Hub_Training"
	folder.Parent = Services.Workspace
	ctx.maid:Give(folder)
	state = { folder = folder, targets = {}, layout = {}, dummy = nil, lab = nil, active = false, startedAt = os.clock(), guide = nil }
	ctx.maid:Give(function()
		if state and state.guide then
			state.guide:Destroy()
		end
		state = nil
	end)
	ctx.maid:Give(Settings.observe("training.enabled", function(on)
		if on then
			spawnRange()
		else
			clearRange()
		end
	end))
	local function rebuild()
		if state and state.active then
			buildTargets()
		end
	end
	for _, k in ipairs({ "count", "targetSize", "distance", "targetColor" }) do
		ctx.maid:Give(Settings.observe("training." .. k, rebuild))
	end
	ctx.maid:Give(Settings.observe("perf.maxDecor", rebuild))
	ctx.maid:Give(Services.UserInputService.InputBegan:Connect(onInput))
	local h1 = Perf.every("training.update", 60, function(dt)
		if state.active then
			updateTargets(dt)
			updateGuide()
		end
		updateLab()
	end, { visual = true })
	local h2 = Perf.every("training.dummy", 20, clampDummy)
	ctx.maid:Give(h1.Cancel)
	ctx.maid:Give(h2.Cancel)
end

function Training.getStats()
	return stats:summary()
end

function Training.resetStats()
	stats:reset()
end

function Training.isRunning()
	return state ~= nil
end

function Training.objectCount()
	if not state then
		return 0
	end
	return #state.targets + (state.dummy and 1 or 0) + (state.lab and 1 or 0)
end

function Training.hasDummy()
	return state ~= nil and state.dummy ~= nil
end

function Training.dummyEliminated()
	return state ~= nil and state.dummy ~= nil and state.dummy.eliminated
end

return Training

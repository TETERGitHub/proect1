--!nonstrict
-- features/AuraVFX: the aura effect itself (angel wings, halo, rotating rune circle, orbiting chains, sparkles).
-- Supplied by the project owner (written by their Blender/VS assistant), reviewed before inclusion: it creates everything on this
-- client only (parts under workspace.CurrentCamera, attachments on your own root part), makes no network calls, uses no remotes
-- or files, and destroy() removes everything it created. Controlled by features/Aura (menu page Aura).
-- Changes from the supplied file: module header for the hub's import system; AuraVFX.start() is not used by the hub
-- (features/Aura handles respawns and stops a pending spawn after unload).
-- Depends on: nothing (Roblox services only).

local _import = ...
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AuraVFX = {}
local PRESETS = {
	Angel   = { primary = Color3.fromRGB(176, 84, 255), secondary = Color3.fromRGB(90, 210, 255) },
	Inferno = { primary = Color3.fromRGB(255, 96, 32),  secondary = Color3.fromRGB(255, 205, 70) },
	Frost   = { primary = Color3.fromRGB(80, 170, 255), secondary = Color3.fromRGB(215, 245, 255) },
	Toxic   = { primary = Color3.fromRGB(70, 255, 110), secondary = Color3.fromRGB(205, 255, 80) },
	Crimson = { primary = Color3.fromRGB(255, 40, 80),  secondary = Color3.fromRGB(255, 160, 195) },
	Rainbow = { primary = Color3.fromRGB(255, 80, 200), secondary = Color3.fromRGB(80, 220, 255), rainbow = true },
}
AuraVFX.presets = PRESETS

local PI, TAU = math.pi, math.pi * 2
local rad, sin, cos = math.rad, math.sin, math.cos
local WHITE = Color3.new(1, 1, 1)
local ALL = {}

-- ----------------------------------------------------------------------------- helpers
local function newPart(parent, size, ellipsoid)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = size
	if ellipsoid then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- a feather lies in the wing plane (local XY); `side` mirrors it for the left wing
local function featherCF(side, base, ang, len, z)
	local dx, dy = side * cos(ang), sin(ang)
	local centre = Vector3.new(side * base.X + dx * len / 2, base.Y + dy * len / 2, z)
	return CFrame.fromMatrix(centre, Vector3.new(dx, dy, 0), Vector3.new(-dy, dx, 0))
end

local function group(aura, name)
	local g = { name = name, parts = {}, roles = {}, locals = {}, cfs = {}, enabled = true }
	aura.groups[name] = g
	table.insert(aura.order, g)
	return g
end

local function add(aura, g, part, role, localCF)
	table.insert(g.parts, part)
	table.insert(g.roles, role)
	table.insert(g.locals, localCF or CFrame.new())
	table.insert(g.cfs, localCF or CFrame.new())
	return part
end

-- ----------------------------------------------------------------------------- builders
local function buildWing(aura, side, scale)
	local g = group(aura, side > 0 and "wingR" or "wingL")
	g.kind, g.side = "wing", side
	local rows = {
		{ n = 9, a0 = 54, a1 = -34, len = 3.0, var = 1.15, w = 0.58, base = Vector3.new(0.0, 0.0, 0), z = 0.00, role = "f1", rim = true },
		{ n = 8, a0 = 50, a1 = -28, len = 1.9, var = 0.75, w = 0.50, base = Vector3.new(0.25, -0.12, 0), z = -0.03, role = "f2" },
		{ n = 7, a0 = 46, a1 = -22, len = 1.05, var = 0.35, w = 0.40, base = Vector3.new(0.20, 0.05, 0), z = -0.06, role = "f3" },
	}
	for _, r in rows do
		for i = 0, r.n - 1 do
			local u = i / (r.n - 1)
			local ang = rad(r.a0 + (r.a1 - r.a0) * u)
			local len = (r.len + r.var * sin(PI * (i + 1) / (r.n + 1))) * scale
			local cf = featherCF(side, r.base * scale, ang, len, r.z)
			add(aura, g, newPart(aura.folder, Vector3.new(len, r.w * scale, 0.05), true), r.role, cf)
			if r.rim then
				local rcf = featherCF(side, r.base * scale, ang, len * 1.1, r.z + 0.05)
				add(aura, g, newPart(aura.folder, Vector3.new(len * 1.1, r.w * 1.45 * scale, 0.08), true), "rim", rcf)
			end
		end
	end
end

local function buildHalo(aura)
	local g = group(aura, "halo")
	g.kind = "halo"
	for ring = 1, 2 do
		local r = ring == 1 and 0.85 or 0.95
		local segs = 22
		for k = 0, segs - 1 do
			local a = TAU * k / segs
			local arc = TAU * r / segs * 0.95
			local cf = CFrame.new(r * cos(a), 0, r * sin(a)) * CFrame.Angles(0, -(a + PI / 2), 0)
			add(aura, g, newPart(aura.folder, Vector3.new(arc, ring == 1 and 0.07 or 0.04, ring == 1 and 0.11 or 0.05)), ring == 1 and "halo" or "haloRim", cf)
		end
	end
end

local function ringGroup(aura, name, radius, segs, w, h, role, speed)
	local g = group(aura, name)
	g.kind, g.speed = "circle", speed
	for k = 0, segs - 1 do
		local a = TAU * k / segs
		local arc = TAU * radius / segs * 0.93
		add(aura, g, newPart(aura.folder, Vector3.new(arc, h, w)), role, CFrame.new(radius * cos(a), 0, radius * sin(a)) * CFrame.Angles(0, -(a + PI / 2), 0))
	end
	return g
end

local function lineCF(p1, p2)
	local mid = (p1 + p2) / 2
	local d = p2 - p1
	return CFrame.new(mid) * CFrame.Angles(0, -math.atan2(d.Z, d.X), 0), d.Magnitude
end

local STROKES = {                       -- tiny rune glyph strokes: {x, z, length, rotation}
	{ 0, 0, 0.55, 90 }, { -0.12, 0.12, 0.34, 40 }, { 0.12, 0.12, 0.34, -40 }, { 0, -0.2, 0.34, 0 }, { 0.0, 0.26, 0.2, 0 },
	{ -0.14, -0.05, 0.3, 90 }, { 0.14, -0.05, 0.3, 90 },
}

local function buildCircle(aura)
	ringGroup(aura, "circleOuter", 5.0, 40, 0.16, 0.05, "ring", 0.35)
	ringGroup(aura, "circleMid", 4.3, 36, 0.07, 0.05, "ring2", -0.5)
	ringGroup(aura, "circleInner", 2.4, 26, 0.12, 0.05, "ring", 0.7)
	local hex = group(aura, "circleHex")
	hex.kind, hex.speed = "circle", -0.25
	for tri = 0, 1 do
		local pts = {}
		for k = 0, 2 do
			local a = rad(90 + 120 * k + 60 * tri)
			pts[k + 1] = Vector3.new(3.9 * cos(a), 0, 3.9 * sin(a))
		end
		for k = 1, 3 do
			local cf, len = lineCF(pts[k], pts[k % 3 + 1])
			add(aura, hex, newPart(aura.folder, Vector3.new(len, 0.04, 0.05)), "hex", cf)
		end
	end
	local runes = group(aura, "circleRunes")
	runes.kind, runes.speed = "circle", 0.22
	local n = 14
	for k = 0, n - 1 do
		local a = TAU * k / n
		local base = CFrame.new(3.35 * cos(a), 0, 3.35 * sin(a)) * CFrame.Angles(0, -(a + PI / 2), 0)
		for s, st in STROKES do
			if (k * 7 + s * 3) % 5 < 2 then                  -- deterministic "random" glyph shape
				add(aura, runes, newPart(aura.folder, Vector3.new(st[3], 0.04, 0.05)), "rune",
					base * CFrame.new(st[1], 0, st[2]) * CFrame.Angles(0, rad(st[4]), 0))
			end
		end
	end
	local ground = group(aura, "circleGlow")
	ground.kind = "glow"
	local disk = newPart(aura.folder, Vector3.new(0.05, 9.6, 9.6))
	disk.Shape = Enum.PartType.Cylinder
	add(aura, ground, disk, "glow", CFrame.Angles(0, 0, rad(90)))
end

local function buildChains(aura)
	local g = group(aura, "chains")
	g.kind = "chains"
	g.chains, g.links = 4, 9
	for k = 0, g.chains - 1 do
		for j = 0, g.links - 1 do
			add(aura, g, newPart(aura.folder, Vector3.new(0.17, 0.36, 0.06)), "chain")
		end
	end
end

local function buildParticles(aura, root)
	local fx = {}
	local function emitter(parent, texture)
		local e = Instance.new("ParticleEmitter")
		e.Texture = texture
		e.LightEmission = 1
		e.Lifetime = NumberRange.new(1.2, 2.4)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Rotation = NumberRange.new(0, 360)
		e.Parent = parent
		return e
	end
	local tex = "rbxasset://textures/particles/sparkles_main.dds"
	local a1 = Instance.new("Attachment")
	a1.Name = "AuraAttA"
	a1.Position = Vector3.new(0, 1.0, 0.3)
	a1.Parent = root
	local e1 = emitter(a1, tex)
	e1.Speed = NumberRange.new(0.8, 2.6)
	e1.SpreadAngle = Vector2.new(180, 180)
	e1.Acceleration = Vector3.new(0, 0.8, 0)
	e1.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.2, 0.42), NumberSequenceKeypoint.new(1, 0) })
	e1.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	local a2 = Instance.new("Attachment")
	a2.Name = "AuraAttB"
	a2.Position = Vector3.new(0, -2.8, 0)
	a2.Parent = root
	local e2 = emitter(a2, tex)
	e2.Speed = NumberRange.new(2, 4.5)
	e2.EmissionDirection = Enum.NormalId.Top
	e2.SpreadAngle = Vector2.new(12, 12)
	e2.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.25, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e2.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	pcall(function()
		e2.Shape = Enum.ParticleEmitterShape.Disc
		e2.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end)
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Shadows = false
	light.Parent = a1
	fx.e1, fx.e2, fx.light, fx.atts = e1, e2, light, { a1, a2 }
	aura.fx = fx
end

-- ----------------------------------------------------------------------------- colours / intensity
local function roleColor(aura, role)
	local p, s = aura.primary, aura.secondary
	if role == "f1" then return WHITE:Lerp(p, 0.10) end
	if role == "f2" then return WHITE:Lerp(p, 0.28) end
	if role == "f3" then return WHITE:Lerp(p, 0.50) end
	if role == "rim" or role == "ring" or role == "hex" or role == "chain" or role == "glow" then return p end
	if role == "ring2" or role == "rune" then return WHITE:Lerp(s, 0.7) end
	if role == "halo" then return WHITE:Lerp(s, 0.35) end
	if role == "haloRim" then return p end
	return WHITE
end

local BASE_TRANSPARENCY = { rim = 0.72, glow = 0.86, haloRim = 0.55, f3 = 0.05 }

local function applyLook(aura)
	local k = math.clamp(aura.intensity, 0.2, 2)
	for _, g in aura.order do
		for i, part in g.parts do
			local role = g.roles[i]
			part.Color = roleColor(aura, role)
			local base = BASE_TRANSPARENCY[role] or 0
			part.Transparency = math.clamp(base + (1 - k) * (role == "rim" and 0.2 or 0.35), 0, 0.97)
		end
	end
	local fx = aura.fx
	if fx then
		local cs = ColorSequence.new(aura.primary, aura.secondary)
		fx.e1.Color, fx.e2.Color = cs, cs
		fx.e1.Rate = 28 * k
		fx.e2.Rate = 22 * k
		fx.light.Color = aura.primary
		fx.light.Brightness = 1.4 * k
	end
end

-- ----------------------------------------------------------------------------- per-frame update
local function updateGroup(aura, g, t, rcf, rootPos)
	local cfs, locals = g.cfs, g.locals
	local base
	if g.kind == "wing" then
		local m = aura.moving
		local flap = sin(t * TAU * (1.1 + 0.9 * m)) * rad(5 + 9 * m)
		base = rcf * CFrame.new(g.side * 0.42, 1.05 + 0.04 * sin(t * 1.4), 0.5) * CFrame.Angles(0, -g.side * (rad(30) + flap), 0)
	elseif g.kind == "halo" then
		local head = aura.head or aura.root
		local up = aura.head and 1.1 or 3.2
		base = head.CFrame * CFrame.new(0, up + 0.05 * sin(t * 2), 0) * CFrame.Angles(rad(6) * sin(t * 0.9), t * 0.9, rad(5) * cos(t * 0.7))
	elseif g.kind == "circle" or g.kind == "glow" then
		local spin = (g.speed or 0) * t
		base = CFrame.new(aura.groundPos) * CFrame.Angles(0, spin, 0)
	end
	if g.kind == "chains" then
		local n = g.links
		for idx = 1, #g.parts do
			local k = (idx - 1) // n
			local j = (idx - 1) % n
			local theta = t * 0.55 + k * TAU / g.chains
			local sway = sin(t * 1.7 + j * 0.45 + k) * 0.14 * (j / n)
			local rr = 3.3 + sway
			local pos = rootPos + Vector3.new(rr * cos(theta), 4.2 - j * 0.4, rr * sin(theta))
			local face = CFrame.new(pos) * CFrame.Angles(0, -theta + PI / 2, 0)
			cfs[idx] = j % 2 == 0 and face or face * CFrame.Angles(0, PI / 2, 0)
		end
	else
		for i = 1, #g.parts do
			cfs[i] = base * locals[i]
		end
	end
	if not aura.slow then
		local ok = pcall(workspace.BulkMoveTo, workspace, g.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if ok then return end
		aura.slow = true
	end
	for i, p in g.parts do
		p.CFrame = cfs[i]
	end
end

local function step(aura, dt)
	local root = aura.root
	if not root or not root.Parent then
		aura:destroy()
		return
	end
	aura.time += dt
	local t = aura.time
	local speed = root.AssemblyLinearVelocity.Magnitude
	aura.moving += (math.clamp(speed / 16, 0, 1) - aura.moving) * math.min(1, dt * 6)
	local rcf = root.CFrame
	local rootPos = rcf.Position
	local hip = aura.humanoid and aura.humanoid.HipHeight or 2
	aura.groundPos = rootPos - Vector3.new(0, hip + root.Size.Y / 2 - 0.12, 0)
	if aura.rainbow then
		local h = (t * 0.12) % 1
		aura.primary = Color3.fromHSV(h, 0.7, 1)
		aura.secondary = Color3.fromHSV((h + 0.18) % 1, 0.6, 1)
		aura.hueTick = (aura.hueTick or 0) + 1
		if aura.hueTick % 3 == 0 then applyLook(aura) end
	end
	for _, g in aura.order do
		if g.enabled then
			updateGroup(aura, g, t, rcf, rootPos)
		end
	end
	local pulse = 0.5 + 0.5 * sin(t * 2.2)
	local ring = aura.groups.circleOuter
	if ring and ring.enabled then
		local lift = (1 - aura.intensity) * 0.35
		for _, part in ring.parts do part.Transparency = math.clamp(0.04 + 0.12 * pulse + lift, 0, 0.97) end
	end
end

-- ----------------------------------------------------------------------------- public API
local Aura = {}
Aura.__index = Aura

function Aura:setColors(primary, secondary)
	self.primary, self.secondary = primary, secondary or self.secondary
	self.rainbow = false
	applyLook(self)
end

function Aura:setIntensity(k)
	self.intensity = math.clamp(k, 0.2, 2)
	applyLook(self)
end

function Aura:setRainbow(on)
	self.rainbow = on and true or false
	if not on then applyLook(self) end
end

local FEATURE_GROUPS = {
	wings = { "wingR", "wingL" }, halo = { "halo" }, chains = { "chains" },
	circle = { "circleOuter", "circleMid", "circleInner", "circleHex", "circleRunes", "circleGlow" },
}

function Aura:toggle(feature, on)
	if on == nil then on = not self.features[feature] end
	self.features[feature] = on and true or false
	for _, name in FEATURE_GROUPS[feature] or {} do
		local g = self.groups[name]
		if g then
			g.enabled = on
			for _, p in g.parts do p.Parent = on and self.folder or nil end
		end
	end
	if feature == "particles" and self.fx then
		self.fx.e1.Enabled, self.fx.e2.Enabled, self.fx.light.Enabled = on, on, on
	end
end

function Aura:destroy()
	if self.destroyed then return end
	self.destroyed = true
	if self.conn then self.conn:Disconnect() end
	if self.charConn then self.charConn:Disconnect() end
	if self.folder then self.folder:Destroy() end
	if self.fx then
		for _, a in self.fx.atts do a:Destroy() end
	end
	self.groups, self.order = {}, {}
	for i, a in ALL do
		if a == self then table.remove(ALL, i) break end
	end
end

function AuraVFX.new(opts)
	opts = opts or {}
	local preset = PRESETS[opts.preset or "Angel"] or PRESETS.Angel
	local character = opts.character or (Players.LocalPlayer and Players.LocalPlayer.Character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	assert(root, "AuraVFX: no HumanoidRootPart (spawn first or pass opts.character)")
	local self = setmetatable({
		character = character, root = root, head = character:FindFirstChild("Head"),
		humanoid = character:FindFirstChildOfClass("Humanoid"),
		primary = opts.primary or preset.primary, secondary = opts.secondary or preset.secondary,
		rainbow = opts.rainbow or preset.rainbow or false, intensity = opts.intensity or 1,
		features = {}, groups = {}, order = {}, time = 0, moving = 0, groundPos = root.Position,
	}, Aura)
	local folder = Instance.new("Folder")
	folder.Name = "AuraVFX"
	folder.Parent = workspace.CurrentCamera
	self.folder = folder
	local want = { wings = true, halo = true, circle = true, chains = true, particles = true }
	for k in want do
		if opts[k] ~= nil then want[k] = opts[k] end
	end
	local scale = opts.wingScale or 1
	buildWing(self, 1, scale)
	buildWing(self, -1, scale)
	buildHalo(self)
	buildCircle(self)
	buildChains(self)
	buildParticles(self, root)
	for k in want do
		self.features[k] = true
		if not want[k] then self:toggle(k, false) end
	end
	applyLook(self)
	self.conn = RunService.RenderStepped:Connect(function(dt)
		step(self, dt)
	end)
	table.insert(ALL, self)
	return self
end

-- keeps the aura on your character across respawns; returns a controller with :destroy() and .aura
function AuraVFX.start(opts)
	local ctl = { aura = nil, opts = opts or {} }
	local lp = Players.LocalPlayer
	local function spawnAura(char)
		if ctl.aura then ctl.aura:destroy() end
		char:WaitForChild("HumanoidRootPart", 10)
		if ctl.stopped then return end
		local o = table.clone(ctl.opts)
		o.character = char
		local ok, a = pcall(AuraVFX.new, o)
		if ok then ctl.aura = a end
	end
	if lp.Character then task.spawn(spawnAura, lp.Character) end
	ctl.conn = lp.CharacterAdded:Connect(function(c) task.spawn(spawnAura, c) end)
	function ctl:destroy()
		self.stopped = true
		if self.conn then self.conn:Disconnect() end
		if self.aura then self.aura:destroy() end
	end
	return ctl
end

function AuraVFX.destroy()
	for i = #ALL, 1, -1 do
		ALL[i]:destroy()
	end
end

return AuraVFX

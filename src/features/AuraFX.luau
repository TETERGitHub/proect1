--!nonstrict
-- features/AuraFX: twelve large, detailed auras made by the hub itself (own meshes and particle textures from features/FxKit;
-- no toolbox or stock Roblox effects): Inferno Crown, Storm God, Galaxy, Frost Monarch, Void Wings, Sakura, Phoenix, Dragon
-- Spirit, Holy Light, Toxic Rift, Shadow Reaper, Neon Cyber. Selected with "Style" on the Aura page; the classic aura
-- (features/AuraVFX) stays as the "Classic" style. Same control surface as AuraVFX (setColors / setRainbow / setIntensity /
-- destroy) so features/Aura drives both. LOCAL ONLY: everything lives under your camera and follows your own root part.
-- STATUS: implemented; verified against the mock layer and an offline preview only (the look has not been checked in Roblox).
-- Depends on: FxKit.

local import = ...
local FxKit = import("features/FxKit")

local AuraFX = {}

AuraFX.STYLES = { "Inferno Crown", "Storm God", "Galaxy", "Frost Monarch", "Void Wings", "Sakura", "Phoenix", "Dragon Spirit",
	"Holy Light", "Toxic Rift", "Shadow Reaper", "Neon Cyber" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- default colours per style (primary, secondary); "Own colours" on the Aura page replaces them
AuraFX.palette = {
	["Inferno Crown"] = { rgb(255, 110, 30), rgb(255, 220, 90) },
	["Storm God"] = { rgb(120, 190, 255), rgb(235, 245, 255) },
	["Galaxy"] = { rgb(150, 90, 255), rgb(90, 200, 255) },
	["Frost Monarch"] = { rgb(140, 210, 255), rgb(235, 250, 255) },
	["Void Wings"] = { rgb(150, 60, 255), rgb(255, 90, 220) },
	["Sakura"] = { rgb(255, 150, 200), rgb(255, 225, 240) },
	["Phoenix"] = { rgb(255, 90, 30), rgb(255, 210, 80) },
	["Dragon Spirit"] = { rgb(60, 255, 170), rgb(255, 230, 120) },
	["Holy Light"] = { rgb(255, 230, 150), rgb(255, 255, 255) },
	["Toxic Rift"] = { rgb(110, 255, 60), rgb(200, 255, 120) },
	["Shadow Reaper"] = { rgb(220, 30, 50), rgb(40, 20, 50) },
	["Neon Cyber"] = { rgb(0, 240, 255), rgb(255, 40, 200) },
}

local PI, TAU = math.pi, math.pi * 2
local sin, cos, rad, rand = math.sin, math.cos, math.rad, math.random
local NEON = Enum.Material.Neon

local function v3(x, y, z)
	return Vector3.new(x, y, z)
end

local Aura = {}
Aura.__index = Aura

-- item kinds: a moving part (fn(t, base) -> CFrame), or an emitter holder that moves the same way. role picks the colour.
function Aura:add(part, role, fn)
	local it = { part = part, role = role, fn = fn }
	table.insert(self.items, it)
	return it
end

function Aura:part(shape, size, role, fn, material, transparency)
	local p = FxKit.part(self.folder, shape, size * self.s, self:colorOf(role), material or NEON, transparency or 0)
	return self:add(p, role, fn), p
end

function Aura:mesh(name, size, role, fn, material, transparency, fallback)
	local p = FxKit.mesh(self.folder, name, size * self.s, self:colorOf(role), material or NEON, transparency or 0, fallback)
	return self:add(p, role, fn), p
end

function Aura:emit(tex, o, role, fn)
	local h = FxKit.holder(self.folder)
	o.size = o.size and { o.size[1] * self.s, o.size[2] * self.s } or nil
	o.speed = o.speed and { o.speed[1] * self.s, o.speed[2] * self.s } or nil
	o.accel = o.accel and o.accel * self.s or nil
	local e = FxKit.emitter(h, tex, o)
	local it = self:add(h, role, fn)
	it.emitter, it.baseRate = e, o.rate or 0
	if e then
		FxKit.setEmitterColor(e, self:colorOf(role, true))
		e.Rate = it.baseRate * self.intensity
	end
	return it
end

-- colorOf(role, seq) -> Color3 (or ColorSequence for emitters when seq)
function Aura:colorOf(role, seq)
	local p, s = self.primary, self.secondary
	local white, dark = rgb(255, 255, 255), rgb(14, 10, 18)
	local c
	if role == "p" then
		c = p
	elseif role == "s" then
		c = s
	elseif role == "w" then
		c = white
	elseif role == "d" then
		c = dark
	elseif role == "ps" then
		if seq then
			return ColorSequence.new(p, s)
		end
		c = p:Lerp(s, 0.5)
	elseif role == "sp" then
		if seq then
			return ColorSequence.new(s, p)
		end
		c = s
	elseif role == "pd" then
		if seq then
			return ColorSequence.new(p, dark)
		end
		c = p:Lerp(dark, 0.5)
	else
		c = p
	end
	return seq and ColorSequence.new(c) or c
end

-- glow(it, width, o, role): a light streak (Trail) behind a moving item; recoloured with the aura
function Aura:glow(it, width, o, role)
	o = o or {}
	o.color = self:colorOf(role or it.role, true)
	local tr = FxKit.trail(it.part, width * self.s, o)
	if tr then
		table.insert(self.extras, { obj = tr, role = role or it.role })
	end
	return tr
end

-- ribbon(p0, p1, o, role): a Beam between two parts, recoloured with the aura
function Aura:ribbon(p0, p1, o, role)
	o = o or {}
	o.color = self:colorOf(role, true)
	o.width0 = (o.width0 or 0.5) * self.s
	o.width1 = (o.width1 or o.width0 / self.s) * self.s
	local b = FxKit.beam(p0, p1, o)
	if b then
		table.insert(self.extras, { obj = b, role = role })
	end
	return b
end

function Aura:applyColors()
	for _, ex in ipairs(self.extras) do
		pcall(FxKit.setEmitterColor, ex.obj, self:colorOf(ex.role, true))
	end
	for _, it in ipairs(self.items) do
		if it.emitter then
			FxKit.setEmitterColor(it.emitter, self:colorOf(it.role, true))
		elseif it.part and it.role ~= "keep" then
			it.part.Color = self:colorOf(it.role)
		end
	end
end

function Aura:setColors(primary, secondary)
	self.primary, self.secondary = primary, secondary
	self.basePrimary, self.baseSecondary = primary, secondary
	self:applyColors()
end

function Aura:setRainbow(on)
	self.rainbow = on and true or false
	if not on and self.basePrimary then
		self.primary, self.secondary = self.basePrimary, self.baseSecondary
		self:applyColors()
	end
end

function Aura:setIntensity(k)
	self.intensity = math.clamp(k or 1, 0.1, 3)
	for _, it in ipairs(self.items) do
		if it.emitter then
			it.emitter.Rate = it.baseRate * self.intensity
		end
	end
end

function Aura:toggle()
	-- the classic aura's part switches do not apply to these styles
end

-- the moment-to-moment base frame: at your root, turned with your facing only (no tilt), plus the floor height
function Aura:base()
	local root = self.root
	local pos = root.Position
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0), pos.Y - self.hip
end

function Aura:step(dt)
	if self.destroyed then
		return
	end
	if not self.root or not self.root.Parent then
		self:destroy()
		return
	end
	self.t += dt
	local t = self.t
	if self.rainbow then
		self.rainbowClock = (self.rainbowClock or 0) + dt
		if self.rainbowClock > 0.1 then
			self.rainbowClock = 0
			self.primary = Color3.fromHSV((t * 0.12) % 1, 0.75, 1)
			self.secondary = Color3.fromHSV((t * 0.12 + 0.33) % 1, 0.6, 1)
			self:applyColors()
		end
	end
	local base, floorY = self:base()
	self.floorY = floorY
	local parts, cfs = {}, {}
	for _, it in ipairs(self.items) do
		if it.fn then
			local cf = it.fn(t, base, it)
			if cf then
				table.insert(parts, it.part)
				table.insert(cfs, cf)
			end
		end
	end
	-- short-lived pieces (lightning bolts, ...)
	for i = #self.transient, 1, -1 do
		local tr = self.transient[i]
		tr.age += dt
		if tr.age >= tr.life then
			pcall(function()
				tr.part:Destroy()
			end)
			table.remove(self.transient, i)
		else
			tr.part.Transparency = tr.t0 + (1 - tr.t0) * (tr.age / tr.life)
		end
	end
	if self.tick then
		self.tick(t, base, dt)
	end
	FxKit.moveAll(parts, cfs)
end

function Aura:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.conn then
		pcall(function()
			self.conn:Disconnect()
		end)
	end
	pcall(function()
		self.folder:Destroy()
	end)
end

-- helpers for builders -------------------------------------------------------------------------------------------------------

-- local offset in the base frame (studs, scaled)
local function at(a, x, y, z)
	return CFrame.new(x * a.s, y * a.s, z * a.s)
end

-- a jagged bolt between two world points, fading out over life (transient)
local function bolt(a, from, to, role, width, life)
	local n = 7
	local dir = to - from
	local side = dir:Cross(v3(0, 1, 0))
	if side.Magnitude < 0.01 then
		side = v3(1, 0, 0)
	end
	side = side.Unit
	local up = dir:Cross(side).Unit
	local prev = from
	for i = 1, n do
		local f = i / n
		local p = (i == n) and to or (from + dir * f + side * (rand() * 2 - 1) * dir.Magnitude * 0.07 + up * (rand() * 2 - 1) * dir.Magnitude * 0.07)
		local len = (p - prev).Magnitude
		local seg = FxKit.part(a.folder, "Block", v3(width, width, len + width) * a.s ^ 0.5, a:colorOf(role), NEON, 0)
		seg.CFrame = CFrame.lookAt((prev + p) / 2, p)
		table.insert(a.transient, { part = seg, age = 0, life = life, t0 = 0 })
		prev = p
	end
end

-- a fan of feathers for a wing on one side (+1 right, -1 left)
local function wing(a, side, n, length, role, tipRole, flapSpeed, flapAmount)
	for i = 1, n do
		local f = (i - 1) / (n - 1)
		local len = length * (0.55 + 0.45 * sin(PI * (0.25 + f * 0.75)))
		local spread = rad(18 + f * 95)
		local role_ = (i % 3 == 0) and tipRole or role
		local fit = a:mesh("feather", v3(1.15, len, 0.2), role_, function(t, base)
			local flap = sin(t * flapSpeed) * rad(flapAmount) * (0.4 + f * 0.6)
			-- lean back (+X tilt) and sweep the outer part of each wing backwards (rotation about Y)
			return base * at(a, side * 0.35, 1.3, 0.6) * CFrame.Angles(rad(14), side * rad(-28), 0)
				* CFrame.Angles(0, 0, -side * (spread + flap)) * CFrame.new(0, len * a.s / 2, 0)
		end, NEON, 0.08 + f * 0.1, "Wedge")
		if i % 2 == 1 then
			a:glow(fit, 0.5, { life = 0.3, t = { 0.4, 1 } }, tipRole)
		end
	end
end

-- a ring of n pieces (meshes or parts) around a centre, spinning
local function orbit(a, n, radius, y, speed, make)
	for i = 1, n do
		local phase = i / n * TAU
		make(i, function(t, base)
			local ang = phase + t * speed
			return base * at(a, cos(ang) * radius, y, sin(ang) * radius) * CFrame.Angles(0, -ang, 0)
		end)
	end
end

local function flat(a, y)
	return function(t, base)
		return CFrame.new(base.Position.X, a.floorY + y * a.s, base.Position.Z)
	end
end

-- wisps(a, n, radius, y0, height, speed, role, size): glowing motes spiralling up round you, each with a light trail
local function wisps(a, n, radius, y0, height, speed, role, size)
	for i = 1, n do
		local phase = i / n * TAU
		local it = a:part("Ball", v3(size or 0.32, size or 0.32, size or 0.32), role, function(t, base)
			local ang = phase + t * speed
			local h = ((t * 0.3 + i / n) % 1)
			return base * at(a, cos(ang) * radius * (1 - h * 0.35), y0 + h * height, sin(ang) * radius * (1 - h * 0.35))
		end, NEON, 0)
		a:glow(it, (size or 0.32) * 1.4, { life = 0.45, t = { 0.1, 1 } }, role)
	end
end

-- styles ---------------------------------------------------------------------------------------------------------------------

local BUILD = {}

BUILD["Inferno Crown"] = function(a)
	-- burning ground circle
	a:mesh("ring", v3(9, 1.2, 9), "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.15, base.Position.Z) * CFrame.Angles(0, t * 0.6, 0)
	end, NEON, 0.1, "Cylinder")
	a:mesh("ring", v3(6.5, 1, 6.5), "s", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.15, base.Position.Z) * CFrame.Angles(0, -t * 0.9, 0)
	end, NEON, 0.3, "Cylinder")
	-- flame tongues dancing around the circle
	orbit(a, 12, 3.6, 0, 0.6, function(i, fn)
		local _, p = a:mesh("flame", v3(0.9, 2.4, 0.9), i % 2 == 0 and "p" or "s", nil, NEON, 0.15, "Wedge")
		a.items[#a.items].fn = function(t, base)
			local h = 2 + sin(t * 7 + i * 1.7) * 0.7 + sin(t * 13 + i) * 0.3
			FxKit.setSize(p, v3(0.9, h, 0.9) * a.s)
			local cf = fn(t, base)
			return CFrame.new(cf.Position.X, a.floorY + h * a.s / 2, cf.Position.Z) * (cf.Rotation or CFrame.new())
		end
	end)
	a:emit("flame", { rate = 45, size = { 2.2, 0.2 }, life = { 0.5, 0.9 }, speed = { 3, 7 }, spread = 25, accel = v3(0, 6, 0), drag = 1, t = { 0.1, 1 } }, "sp", flat(a, 0.3))
	a:emit("spark", { rate = 28, size = { 0.35, 0.05 }, life = { 0.8, 1.6 }, speed = { 5, 12 }, spread = 35, accel = v3(0, 4, 0), drag = 0.6, squash = true }, "s", flat(a, 0.5))
	a:emit("glow", { rate = 3, size = { 7, 9 }, life = { 0.6, 0.8 }, speed = { 0, 0 }, t = { 0.6, 1 } }, "p", flat(a, 0.4))
	-- crown of flame spikes above the head
	orbit(a, 8, 0.85, 3.9, 1.2, function(i, fn)
		a:mesh("crystal", v3(0.35, 0.9 + (i % 2) * 0.35, 0.35), i % 2 == 0 and "s" or "p", fn, NEON, 0, "Wedge")
	end)
	a:mesh("ring", v3(2, 0.6, 2), "s", function(t, base)
		return base * at(a, 0, 3.55, 0) * CFrame.Angles(0, t, 0)
	end, NEON, 0)
	wisps(a, 8, 2.6, 0.2, 4.2, 2.2, "s", 0.3)
	a:emit("glow", { rate = 6, size = { 1.6, 0 }, life = { 0.3, 0.5 }, speed = { 0, 0.5 }, t = { 0.2, 1 } }, "s", function(t, base)
		return base * at(a, 0, 3.9, 0)
	end)
end

BUILD["Storm God"] = function(a)
	-- the storm cloud above
	for i = 1, 9 do
		local ang, r = i / 9 * TAU, 1.5 + (i % 3) * 0.9
		local d = 2.2 + (i % 4) * 0.5
		a:part("Ball", v3(d, d * 0.55, d), "d", function(t, base)
			local aa = ang + t * 0.25
			return base * at(a, cos(aa) * r, 7 + sin(t + i) * 0.15, sin(aa) * r)
		end, Enum.Material.SmoothPlastic, 0.25)
	end
	a:emit("smoke", { rate = 6, size = { 3, 6 }, life = { 1.5, 2.5 }, speed = { 0.3, 1 }, light = 0, t = { 0.4, 1 } }, "d", function(t, base)
		return base * at(a, 0, 7, 0)
	end)
	-- orbiting charged orbs with trailing sparks
	orbit(a, 3, 3.4, 1.4, 1.6, function(i, fn)
		local orb = a:part("Ball", v3(0.7, 0.7, 0.7), "w", function(t, base)
			local cf = fn(t, base)
			return cf + v3(0, sin(t * 2 + i * 2) * 0.6 * a.s, 0)
		end)
		a:glow(orb, 0.9, { life = 0.5, t = { 0, 1 } }, "p")
		a:emit("glow", { rate = 8, size = { 2.2, 0 }, life = { 0.25, 0.4 }, speed = { 0, 0 }, t = { 0.3, 1 } }, "p", function(t, base)
			return fn(t, base) + v3(0, sin(t * 2 + i * 2) * 0.6 * a.s, 0)
		end)
		a:emit("arc", { rate = 6, size = { 1.6, 2.4 }, life = { 0.08, 0.18 }, speed = { 0, 1 }, spin = { -300, 300 } }, "p", function(t, base)
			return fn(t, base) + v3(0, sin(t * 2 + i * 2) * 0.6 * a.s, 0)
		end)
	end)
	-- pulsing cracks on the floor
	for i = 1, 10 do
		local ang = i / 10 * TAU
		local len = 2.2 + (i % 3) * 0.9
		local it, p = a:part("Block", v3(0.14, 0.06, len), "p", nil)
		it.fn = function(t, base)
			p.Transparency = 0.25 + 0.6 * (0.5 + 0.5 * sin(t * 5 + i))
			local c = base.Position
			return CFrame.new(c.X + cos(ang) * (len / 2 + 0.6) * a.s, a.floorY + 0.06, c.Z + sin(ang) * (len / 2 + 0.6) * a.s)
				* CFrame.Angles(0, -ang + PI / 2, 0)
		end
	end
	-- a strike every so often, from the cloud to the ground near you
	a.nextStrike = 0.5
	a.tick = function(t, base)
		if t >= a.nextStrike then
			a.nextStrike = t + 0.35 + rand() * 0.8
			local ang, r = rand() * TAU, (2.5 + rand() * 3) * a.s
			local top = base.Position + v3(cos(ang) * 1.5, 7, sin(ang) * 1.5) * a.s
			local ground = v3(base.Position.X + cos(ang) * r, a.floorY, base.Position.Z + sin(ang) * r)
			bolt(a, top, ground, rand() < 0.5 and "w" or "p", 0.25, 0.22)
			-- a crackling beam over the jagged core, and a flash where it lands
			local h0, h1 = FxKit.holder(a.folder, CFrame.new(top)), FxKit.holder(a.folder, CFrame.new(ground))
			a:ribbon(h0, h1, { tex = "bolt", width0 = 1.6, width1 = 1.2, segments = 12, speed = 6, repeatLength = 6 }, "w")
			table.insert(a.transient, { part = h0, age = 0, life = 0.22, t0 = 1 })
			table.insert(a.transient, { part = h1, age = 0, life = 0.22, t0 = 1 })
			local flash = FxKit.part(a.folder, "Ball", v3(1.5, 1.5, 1.5) * a.s, a:colorOf("w"), NEON, 0.3)
			flash.CFrame = CFrame.new(ground)
			table.insert(a.transient, { part = flash, age = 0, life = 0.25, t0 = 0.3 })
		end
	end
end

BUILD["Galaxy"] = function(a)
	a:mesh("swirl", v3(11, 1, 11), "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.12, base.Position.Z) * CFrame.Angles(0, t * 0.8, 0)
	end, NEON, 0.35, "Cylinder")
	a:mesh("swirl", v3(7, 1, 7), "s", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.18, base.Position.Z) * CFrame.Angles(0, -t * 1.3, 0)
	end, NEON, 0.45, "Cylinder")
	-- planets on tilted orbits, the big one with a ring
	local planets = { { 3.2, 0.7, 0.9, 1.1, "s" }, { 4.6, 1.0, 0.55, 2.3, "p" }, { 5.8, 0.5, 0.7, 0.4, "w" } }
	for k, pl in ipairs(planets) do
		local tilt = CFrame.Angles(0.35 * k, k, 0.2)
		local fn = function(t, base)
			local ang = t * pl[3] + k * 2
			return base * at(a, 0, pl[4], 0) * tilt * at(a, cos(ang) * pl[1], 0, sin(ang) * pl[1])
		end
		local planet = a:part("Ball", v3(pl[2], pl[2], pl[2]), pl[5], fn, Enum.Material.Neon, 0)
		a:glow(planet, pl[2] * 0.9, { life = 1.4, t = { 0.2, 1 }, widthTail = 0.3 }, pl[5])
		if k == 2 then
			a:mesh("ring", v3(2.1, 0.4, 2.1), "w", function(t, base)
				return fn(t, base) * CFrame.Angles(0.5, t, 0.3)
			end, NEON, 0.2)
		end
	end
	-- a disc of star grains turning with the vortex
	for i = 1, 36 do
		local r0, ph = 1.5 + (i % 9) * 0.45, i * 2.4
		a:part("Ball", v3(0.12, 0.12, 0.12), i % 4 == 0 and "w" or "s", function(t, base)
			local ang = ph + t * (1.6 - r0 * 0.12)
			return CFrame.new(base.Position.X + cos(ang) * r0 * a.s, a.floorY + 0.35 + sin(t * 2 + i) * 0.08, base.Position.Z + sin(ang) * r0 * a.s)
		end, NEON, 0)
	end
	a:emit("star", { rate = 14, size = { 0.7, 0 }, life = { 1, 2 }, speed = { 0.5, 2 }, spin = { -90, 90 } }, "w", function(t, base)
		return base * at(a, 0, 2, 0)
	end)
	a:emit("smoke", { rate = 5, size = { 5, 9 }, life = { 2, 3 }, speed = { 0.4, 1.2 }, light = 0.7, t = { 0.75, 1 }, spin = { -20, 20 } }, "ps", function(t, base)
		return base * at(a, 0, 1.5, 0)
	end)
end

BUILD["Frost Monarch"] = function(a)
	orbit(a, 8, 3.1, 1.6, 0.8, function(i, fn)
		local cr = a:mesh("crystal", v3(0.6, 1.5, 0.6), i % 2 == 0 and "p" or "s", function(t, base)
			return fn(t, base) * CFrame.new(0, sin(t * 1.8 + i) * 0.35 * a.s, 0) * CFrame.Angles(0, t * 2, 0.25)
		end, Enum.Material.Ice, 0.05, "Wedge")
		a:glow(cr, 0.5, { life = 0.4, t = { 0.3, 1 } }, "w")
	end)
	orbit(a, 7, 0.8, 3.95, 0.5, function(i, fn)
		a:mesh("crystal", v3(0.32, 0.8 + (i % 2) * 0.45, 0.32), "s", fn, NEON, 0, "Wedge")
	end)
	a:mesh("ring", v3(8, 0.8, 8), "p", flat(a, 0.12), NEON, 0.35, "Cylinder")
	orbit(a, 14, 4, 0, 0, function(i, fn)
		a:mesh("crystal", v3(0.45, 0.9 + (i % 3) * 0.4, 0.45), "p", function(t, base)
			local cf = fn(t, base)
			return CFrame.new(cf.Position.X, a.floorY + 0.3 * a.s, cf.Position.Z) * CFrame.Angles(0.25, i, 0)
		end, Enum.Material.Ice, 0.1, "Wedge")
	end)
	a:emit("star", { rate = 22, size = { 0.45, 0.2 }, life = { 2, 3 }, speed = { 1, 2 }, spread = 70, accel = v3(0, -1.5, 0), spin = { -60, 60 }, t = { 0, 0.4 } }, "w", function(t, base)
		return base * at(a, 0, 8, 0) * CFrame.Angles(PI, 0, 0)
	end)
	a:emit("smoke", { rate = 7, size = { 2, 5 }, life = { 1.5, 2.2 }, speed = { 1, 2.5 }, spread = 88, light = 0.2, t = { 0.7, 1 } }, "w", flat(a, 0.25))
	wisps(a, 6, 3.6, 0.2, 4, -1.2, "w", 0.22)
end

BUILD["Void Wings"] = function(a)
	wing(a, 1, 11, 5.2, "p", "s", 2.1, 14)
	wing(a, -1, 11, 5.2, "p", "s", 2.1, 14)
	a:emit("smoke", { rate = 10, size = { 2.5, 5 }, life = { 1.2, 2 }, speed = { 0.5, 1.5 }, light = 0, t = { 0.5, 1 } }, "pd", function(t, base)
		return base * at(a, 0, 1.6, 0.8)
	end)
	a:emit("glow", { rate = 16, size = { 0.5, 0 }, life = { 0.8, 1.5 }, speed = { 1, 3 }, accel = v3(0, 1.5, 0) }, "s", function(t, base)
		return base * at(a, 0, 1.4, 0.6)
	end)
	a:mesh("ring", v3(1.9, 0.35, 1.9), "s", function(t, base)
		return base * at(a, 0, 3.9, 0.15) * CFrame.Angles(0.35, t * 1.5, 0)
	end, NEON, 0)
	wisps(a, 7, 2.4, 0, 4.5, 1.5, "s", 0.26)
end

BUILD["Sakura"] = function(a)
	a:mesh("ring", v3(8.5, 0.7, 8.5), "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.12, base.Position.Z) * CFrame.Angles(0, t * 0.3, 0)
	end, NEON, 0.35, "Cylinder")
	a:emit("glow", { rate = 2, size = { 8, 9 }, life = { 0.8, 1 }, speed = { 0, 0 }, t = { 0.82, 1 } }, "p", flat(a, 0.3))
	-- petals stream off three emitters that circle you at different heights
	orbit(a, 3, 2.6, 1.5, 1.4, function(i, fn)
		a:emit("petal", { rate = 12, size = { 0.5, 0.4 }, life = { 1.6, 2.6 }, speed = { 1, 3 }, accel = v3(0, -1.2, 0), drag = 0.4,
			spin = { -180, 180 }, light = 0.3, t = { 0, 0.3 } }, i == 2 and "s" or "p", function(t, base)
			return fn(t, base) + v3(0, sin(t * 1.3 + i * 2) * 1.2 * a.s, 0)
		end)
	end)
	a:emit("petal", { rate = 10, size = { 0.45, 0.35 }, life = { 2.5, 3.5 }, speed = { 0.5, 1.5 }, spread = 60, accel = v3(0.6, -1.5, 0), spin = { -120, 120 },
		light = 0.3 }, "p", function(t, base)
		return base * at(a, 0, 6, 0)
	end)
	-- a whirl of solid petals spiralling up round you (visible even without particle textures)
	for i = 1, 22 do
		local phase, r0, speed = i / 22 * TAU, 2 + (i % 4) * 0.45, 1.1 + (i % 3) * 0.25
		a:part("Wedge", v3(0.28, 0.06, 0.42), i % 3 == 0 and "s" or "p", function(t, base)
			local ang = phase + t * speed
			local h = ((t * 0.35 + i / 22) % 1) * 4.6
			return base * at(a, cos(ang) * r0, h - 0.2, sin(ang) * r0) * CFrame.Angles(t * 2 + i, ang, t * 3 + i * 0.5)
		end, Enum.Material.SmoothPlastic, 0.05)
	end
	-- three floating blossoms: five petals round a bright centre, slowly turning
	for k = 1, 3 do
		local ang0 = k / 3 * TAU
		local centre = function(t, base)
			local ang = ang0 - t * 0.5
			return base * at(a, cos(ang) * 3.1, 2.4 + sin(t * 1.5 + k) * 0.4, sin(ang) * 3.1)
		end
		for j = 1, 5 do
			a:part("Ball", v3(0.36, 0.08, 0.26), "p", function(t, base)
				return centre(t, base) * CFrame.Angles(0.4, t + j / 5 * TAU, 0) * CFrame.new(0.2 * a.s, 0, 0)
			end, Enum.Material.SmoothPlastic, 0)
		end
		a:part("Ball", v3(0.16, 0.16, 0.16), "s", centre, NEON, 0)
	end
end

BUILD["Phoenix"] = function(a)
	wing(a, 1, 13, 6, "p", "s", 2.6, 20)
	wing(a, -1, 13, 6, "p", "s", 2.6, 20)
	for side = -1, 1, 2 do
		a:emit("flame", { rate = 30, size = { 1.6, 0.2 }, life = { 0.4, 0.8 }, speed = { 1, 3 }, accel = v3(0, 4, 0), t = { 0.1, 1 } }, "sp", function(t, base)
			return base * at(a, side * 2.6, 3, 1.4)
		end)
	end
	a:emit("flame", { rate = 25, size = { 1.4, 0.1 }, life = { 0.5, 1 }, speed = { 2, 4 }, spread = 20, accel = v3(0, 3, 0), t = { 0.2, 1 } }, "sp", function(t, base)
		return base * at(a, 0, 0.6, 0.9) * CFrame.Angles(-1.2, 0, 0)
	end)
	a:emit("spark", { rate = 22, size = { 0.3, 0.05 }, life = { 0.8, 1.4 }, speed = { 3, 8 }, spread = 60, accel = v3(0, 3, 0), squash = true }, "s", function(t, base)
		return base * at(a, 0, 2, 0.8)
	end)
	a:mesh("ring", v3(2, 0.5, 2), "s", function(t, base)
		return base * at(a, 0, 3.9, 0) * CFrame.Angles(0.2, t * 2, 0)
	end, NEON, 0)
	wisps(a, 9, 2.8, 0, 5, 2.4, "s", 0.3)
end

BUILD["Dragon Spirit"] = function(a)
	local n = 26
	for i = 1, n do
		local f = (i - 1) / (n - 1)
		local d = 1.0 - f * 0.65
		local seg = a:part("Ball", v3(d, d, d), i % 2 == 0 and "p" or "s", function(t, base)
			local s_ = t * 1.6 - i * 0.22
			local h = 2.2 + sin(s_ * 0.7) * 1.6
			return base * at(a, cos(s_) * 3.4, h, sin(s_) * 3.4)
		end, NEON, f * 0.35)
		if i % 4 == 1 then
			a:glow(seg, d * 0.8, { life = 0.6, t = { 0.35, 1 } }, "p")
		end
		if i % 2 == 1 and i < n - 2 then
			a:mesh("crystal", v3(0.25, 0.7 * d + 0.2, 0.25), "s", function(t, base)
				local s_ = t * 1.6 - i * 0.22
				local h = 2.2 + sin(s_ * 0.7) * 1.6
				return base * at(a, cos(s_) * 3.4, h + d * 0.5, sin(s_) * 3.4)
			end, NEON, 0.1, "Wedge")
		end
	end
	-- head: a pointed crystal looking along the path, with two horns
	local function head(t, base, ahead)
		local s_ = t * 1.6 + 0.25 + (ahead or 0)
		local h = 2.2 + sin(s_ * 0.7) * 1.6
		return (base * at(a, cos(s_) * 3.4, h, sin(s_) * 3.4)).Position
	end
	local headIt = a:mesh("crystal", v3(0.9, 1.8, 0.9), "p", function(t, base)
		local p0, p1 = head(t, base), head(t, base, 0.15)
		return CFrame.lookAt(p0, p1) * CFrame.Angles(-PI / 2, 0, 0)
	end, NEON, 0, "Wedge")
	a:glow(headIt, 1.2, { life = 0.8, t = { 0, 1 }, widthTail = 0.05 }, "s")
	for side = -1, 1, 2 do
		a:mesh("crystal", v3(0.2, 0.9, 0.2), "s", function(t, base)
			local p0, p1 = head(t, base), head(t, base, 0.15)
			return CFrame.lookAt(p0, p1) * CFrame.new(side * 0.35 * a.s, 0.45 * a.s, 0.3 * a.s) * CFrame.Angles(-0.6, 0, side * 0.4)
		end, NEON, 0, "Wedge")
	end
	a:emit("glow", { rate = 18, size = { 0.9, 0 }, life = { 0.5, 1 }, speed = { 0.2, 0.8 } }, "ps", function(t, base)
		return CFrame.new(head(t, base))
	end)
	a:emit("star", { rate = 10, size = { 0.5, 0 }, life = { 0.8, 1.4 }, speed = { 0.5, 1.5 } }, "s", function(t, base)
		return CFrame.new(head(t, base, -1.2))
	end)
end

BUILD["Holy Light"] = function(a)
	local _, pillar = a:part("Cylinder", v3(30, 1.8, 1.8), "s", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 15 * a.s, base.Position.Z) * CFrame.Angles(0, 0, PI / 2)
	end, NEON, 0.82)
	for k = 1, 3 do
		local y, r = 0.6 + k * 1.1, 2 + k * 0.5
		a:mesh("ring", v3(r * 2, 0.5, r * 2), k == 2 and "w" or "p", function(t, base)
			return base * at(a, 0, y, 0) * CFrame.Angles(0.15 * k, t * (k % 2 == 0 and -0.8 or 0.8), 0)
		end, NEON, 0.15)
		-- rune marks riding each ring
		orbit(a, 8, r, y, k % 2 == 0 and -0.8 or 0.8, function(i, fn)
			a:part("Block", v3(0.12, 0.45, 0.3), "s", fn, NEON, 0)
		end)
	end
	a:mesh("ring", v3(2, 0.4, 2), "w", function(t, base)
		return base * at(a, 0, 3.95, 0) * CFrame.Angles(0, t, 0)
	end, NEON, 0)
	-- six shafts of light from the ground circle into the sky, slowly turning
	for i = 1, 6 do
		local ang0 = i / 6 * TAU
		local low = a:add(FxKit.holder(a.folder), "keep", function(t, base)
			local ang = ang0 + t * 0.3
			return CFrame.new(base.Position.X + cos(ang) * 3 * a.s, a.floorY, base.Position.Z + sin(ang) * 3 * a.s)
		end)
		local high = a:add(FxKit.holder(a.folder), "keep", function(t, base)
			local ang = ang0 + t * 0.3
			return CFrame.new(base.Position.X + cos(ang) * 1.6 * a.s, a.floorY + 16 * a.s, base.Position.Z + sin(ang) * 1.6 * a.s)
		end)
		a:ribbon(low.part, high.part, { width0 = 0.55, width1 = 0.12, t = { 0.62, 0.97 }, speed = 1.5, repeatLength = 8 }, "s")
	end
	wisps(a, 8, 2.2, 0, 5, 0.9, "w", 0.22)
	a:emit("star", { rate = 12, size = { 0.6, 0 }, life = { 1, 2 }, speed = { 1, 3 }, accel = v3(0, 2, 0) }, "w", flat(a, 0.3))
	a:emit("petal", { rate = 6, size = { 0.5, 0.4 }, life = { 2.5, 3.5 }, speed = { 0.3, 1 }, accel = v3(0, -1, 0), spin = { -60, 60 }, light = 0.6 }, "w", function(t, base)
		return base * at(a, 0, 7, 0)
	end) -- falling feathers (soft white petals)
	a.tick = function(t)
		pillar.Transparency = 0.86 + 0.06 * sin(t * 3)
	end
end

BUILD["Toxic Rift"] = function(a)
	a:part("Cylinder", v3(0.12, 7.5, 7.5), "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.06, base.Position.Z) * CFrame.Angles(0, 0, PI / 2)
	end, NEON, 0.35)
	a:mesh("ring", v3(8, 0.6, 8), "s", flat(a, 0.1), NEON, 0.2, "Cylinder")
	-- bubbles rising and popping
	for i = 1, 14 do
		local ang, r = rand() * TAU, rand() * 3.2
		local speed, phase = 0.6 + rand() * 0.6, rand()
		local _, p = a:part("Ball", v3(0.4, 0.4, 0.4), i % 3 == 0 and "s" or "p", nil, Enum.Material.Glass, 0.25)
		a.items[#a.items].fn = function(t, base)
			local f = (t * speed + phase) % 1
			p.Transparency = 0.25 + 0.75 * f ^ 3
			FxKit.setSize(p, v3(1, 1, 1) * (0.25 + f * 0.6) * a.s)
			return CFrame.new(base.Position.X + cos(ang) * r * a.s, a.floorY + f * 3 * a.s, base.Position.Z + sin(ang) * r * a.s)
		end
	end
	a:emit("smoke", { rate = 9, size = { 2, 5 }, life = { 1.5, 2.5 }, speed = { 1, 2.5 }, spread = 30, light = 0.4, t = { 0.6, 1 } }, "p", flat(a, 0.3))
	a:emit("glow", { rate = 14, size = { 0.5, 0 }, life = { 0.8, 1.5 }, speed = { 2, 4 }, spread = 25 }, "s", flat(a, 0.2))
	wisps(a, 6, 2.8, 0.1, 3.5, 1.1, "s", 0.28)
end

BUILD["Shadow Reaper"] = function(a)
	a:emit("smoke", { rate = 18, size = { 2, 4.5 }, life = { 1, 1.8 }, speed = { 0.5, 1.5 }, light = 0, t = { 0.3, 1 }, accel = v3(0, 1, 0) }, "d", function(t, base)
		return base * at(a, 0, 0.8, 0)
	end)
	a:emit("smoke", { rate = 10, size = { 3, 6 }, life = { 1.2, 2 }, speed = { 0.3, 1 }, light = 0, t = { 0.4, 1 } }, "d", flat(a, 0.2))
	-- three scythes circling, blades facing outward
	orbit(a, 3, 3.3, 1.8, 1.8, function(i, fn)
		local bl = a:mesh("blade", v3(2.6, 2.6, 1), "p", function(t, base)
			return fn(t, base) * CFrame.Angles(0, PI / 2, t * 4)
		end, NEON, 0, "Wedge")
		a:glow(bl, 1.6, { life = 0.22, t = { 0.2, 1 }, widthTail = 0.4 }, "p")
		a:part("Block", v3(0.12, 3, 0.12), "d", function(t, base)
			return fn(t, base) * CFrame.Angles(0, PI / 2, t * 4) * CFrame.new(0, -1.2 * a.s, 0)
		end, Enum.Material.SmoothPlastic, 0)
	end)
	a:emit("spark", { rate = 20, size = { 0.3, 0.05 }, life = { 0.5, 1 }, speed = { 2, 5 }, squash = true }, "p", function(t, base)
		return base * at(a, 0, 1.5, 0)
	end)
	-- two red eyes glowing in the hood of smoke above your head
	for side = -1, 1, 2 do
		a:part("Ball", v3(0.25, 0.25, 0.25), "p", function(t, base)
			return base * at(a, side * 0.25, 4.2, -0.2)
		end, NEON, 0)
	end
end

BUILD["Neon Cyber"] = function(a)
	-- holographic rings at three heights, counter-rotating, and a hex floor
	for k = 1, 3 do
		a:mesh("ring", v3(6 - k * 0.8, 0.35, 6 - k * 0.8), k == 2 and "s" or "p", function(t, base)
			return base * at(a, 0, -1.6 + k * 1.3, 0) * CFrame.Angles(0, t * (k % 2 == 0 and -1.5 or 1.5), 0)
		end, NEON, 0.15)
		orbit(a, 6, 3 - k * 0.4, -1.6 + k * 1.3, k % 2 == 0 and -1.5 or 1.5, function(i, fn)
			local mk = a:part("Block", v3(0.6, 0.12, 0.12), "w", fn, NEON, 0.1)
			a:glow(mk, 0.18, { life = 0.35, t = { 0.2, 1 } }, k == 2 and "s" or "p")
		end)
	end
	a:emit("hex", { rate = 6, size = { 1.6, 2.4 }, life = { 0.8, 1.2 }, speed = { 0, 0.2 }, spread = 0, rot = { 0, 0 }, spin = { 0, 0 }, t = { 0.3, 1 } }, "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.1, base.Position.Z) * CFrame.Angles(-PI / 2, 0, 0)
	end)
	a:part("Cylinder", v3(0.1, 8, 8), "p", function(t, base)
		return CFrame.new(base.Position.X, a.floorY + 0.05, base.Position.Z) * CFrame.Angles(0, 0, PI / 2)
	end, NEON, 0.75)
	-- data rain: thin streaks rising on the outside
	a:emit("spark", { rate = 30, size = { 0.35, 0.1 }, life = { 0.6, 1 }, speed = { 6, 10 }, spread = 5, squash = true }, "ps", function(t, base)
		local ang = t * 3
		return CFrame.new(base.Position.X + cos(ang) * 3.6 * a.s, a.floorY, base.Position.Z + sin(ang) * 3.6 * a.s)
	end)
end

-- public ---------------------------------------------------------------------------------------------------------------------

-- new{ character, style, scale } -> aura (setColors / setRainbow / setIntensity / toggle / destroy, .features, .destroyed)
function AuraFX.new(opts)
	local char = opts.character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	assert(root, "character has no HumanoidRootPart")
	local style = BUILD[opts.style] and opts.style or AuraFX.STYLES[1]
	local hum = char:FindFirstChildOfClass("Humanoid")
	local folder = Instance.new("Folder")
	folder.Name = "MM2HubAuraFX"
	folder.Parent = workspace.CurrentCamera
	local pal = AuraFX.palette[style]
	local a = setmetatable({
		character = char, root = root, folder = folder, style = style, s = opts.scale or 1, intensity = 1, items = {}, transient = {}, extras = {},
		primary = pal[1], secondary = pal[2], basePrimary = pal[1], baseSecondary = pal[2], t = 0, features = {}, destroyed = false,
		hip = ((hum and hum.HipHeight) or 2) + root.Size.Y / 2,
	}, Aura)
	a.floorY = root.Position.Y - a.hip
	BUILD[style](a)
	a:step(0)
	if not opts.manual then
		local ok, conn = pcall(function()
			return game:GetService("RunService").RenderStepped:Connect(function(dt)
				a:step(math.min(dt, 0.05))
			end)
		end)
		if ok then
			a.conn = conn
		end
	end
	return a
end

return AuraFX

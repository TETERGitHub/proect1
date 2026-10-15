--!nonstrict
-- features/KillFX: big custom finishers played on the victim when you get a confirmed kill (features/KillEvents), in the style
-- of Rivals finishers: Lightning (bolts strike, the body chars and is torn apart), Explosion (layered fireball, shock ring, debris,
-- smoke), Vaporize (the body glows, rises and dissolves into dust under a light pillar), Black hole (a vortex pulls the pieces in
-- and collapses), Shatter (the body freezes and breaks into ice shards that bounce on the floor).
-- Everything is built here from our own parts and animated by our own small physics (no toolbox assets, no Explosion / Fire /
-- Sparkles / ParticleEmitter instances). LOCAL ONLY: the effect lives under your camera; the real body is hidden on YOUR screen
-- (LocalTransparencyModifier) and a copy is animated - nothing about the other player changes for anyone else.
-- STATUS: implemented; verified against the mock layer only (the look has not been checked in Roblox).
-- Own assets (tools/make_fx_assets.py -> data/FxPack): particle textures (glow, spark, smoke, flame, star, ring, arc) shown by
-- ParticleEmitters, and meshes (ring, swirl, crystal, rock, flame) shown through SpecialMesh. They are written to MM2Hub/fx/ once and
-- loaded with getcustomasset; an executor without that keeps the plain-part version of every effect (nothing is lost).
-- Depends on: Settings, Services, Perf, Logger, KillEvents, FxKit.

local import = ...
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local Logger = import("core/Logger")
local KillEvents = import("features/KillEvents")
local FxKit = import("features/FxKit")

local KillFX = {}

KillFX.EFFECTS = { "Lightning", "Explosion", "Vaporize", "BlackHole", "Shatter" }
KillFX.MAX_ACTIVE = 3

local sin, cos, rand, PI = math.sin, math.cos, math.random, math.pi
local state = nil

local function s(name)
	return Settings.get("killfx." .. name)
end

local function v3(x, y, z)
	return Vector3.new(x, y, z)
end

local function randUnit()
	local th, z = rand() * 2 * PI, rand() * 2 - 1
	local r = math.sqrt(1 - z * z)
	return v3(r * cos(th), z, r * sin(th))
end

-- Own assets ---------------------------------------------------------------------------------------------------------------------

-- asset(file) -> rbxasset url or nil (shared loader in features/FxKit)
function KillFX.asset(file)
	return FxKit.asset(file)
end

-- Parts --------------------------------------------------------------------------------------------------------------------------

local function newPart(fx, shape, size, color, material, transparency)
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Parent = fx.folder
	return p
end

-- meshPart(fx, mesh, size, color, material, transparency, fallbackShape) -> part: our own mesh (ring, swirl, crystal, rock, flame)
-- on a part through a SpecialMesh; size is in studs. Without asset support it is the fallback primitive instead.
local function meshPart(fx, mesh, size, color, material, transparency, fallbackShape)
	local url = KillFX.asset(mesh .. ".obj")
	if not url then
		return newPart(fx, fallbackShape or "Block", size, color, material, transparency)
	end
	local p = newPart(fx, "Block", size, color, material, transparency)
	local sm = Instance.new("SpecialMesh")
	sm.Name = "FxMesh"
	sm.MeshType = Enum.MeshType.FileMesh
	sm.MeshId = url
	sm.Scale = size
	sm.Parent = p
	return p
end

-- emit(fx, pos, tex, n, o): a burst of our own textured particles at pos. o: color (Color3 or ColorSequence), size {a, b},
-- life {min, max}, speed {min, max}, spread (degrees), accel (Vector3), drag, light (0-1), rot {min, max}, spin {min, max},
-- t {a, b} transparency, dir (Vector3, default up), squash (true = particles face their motion, for streaks)
local function emit(fx, pos, tex, n, o)
	local url = KillFX.asset(tex .. ".png")
	n = math.floor(n * fx.detail + 0.5)
	if not url or n <= 0 then
		return nil
	end
	local ok, holder = pcall(function()
		local h = Instance.new("Part")
		h.Anchored, h.CanCollide, h.CanQuery, h.CanTouch, h.Transparency = true, false, false, false, 1
		h.Size = Vector3.new(0.2, 0.2, 0.2)
		local dir = o.dir or Vector3.new(0, 1, 0)
		h.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-math.pi / 2, 0, 0) -- emitter "up" (+Y) along dir
		local e = Instance.new("ParticleEmitter")
		e.Texture = url
		local col = o.color or Color3.fromRGB(255, 255, 255)
		e.Color = typeof(col) == "ColorSequence" and col or ColorSequence.new(col)
		local sz = o.size or { 1, 0 }
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz[1] * fx.k), NumberSequenceKeypoint.new(1, sz[2] * fx.k) })
		local tr = o.t or { 0, 1 }
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, tr[1]), NumberSequenceKeypoint.new(1, tr[2]) })
		local life = o.life or { 0.5, 1 }
		e.Lifetime = NumberRange.new(life[1], life[2])
		local sp = o.speed or { 5, 10 }
		e.Speed = NumberRange.new(sp[1] * fx.k, sp[2] * fx.k)
		e.SpreadAngle = Vector2.new(o.spread or 180, o.spread or 180)
		e.Acceleration = (o.accel or Vector3.new(0, 0, 0)) * fx.k
		e.Drag = o.drag or 0
		e.LightEmission = o.light or 1
		e.LightInfluence = 0
		local rot, spin = o.rot or { 0, 360 }, o.spin or { -90, 90 }
		e.Rotation = NumberRange.new(rot[1], rot[2])
		e.RotSpeed = NumberRange.new(spin[1], spin[2])
		if o.squash then
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
		end
		e.Rate = 0
		e.Parent = h
		h.Parent = fx.folder
		e:Emit(n)
		return h
	end)
	if ok then
		fx.longest = math.max(fx.longest or 0, fx.age + (o.life and o.life[2] or 1))
	end
	return ok and holder or nil
end

-- particle(fx, part, opts): one moving piece. opts: pos, vel, rot (CFrame rotation), spin (Vector3 rad/s), gravity, drag,
-- life, size0/size1 (Vector3), t0/t1 (transparency), bounce (true = hits the floor), delay (s before it starts), color1
local function particle(fx, part, o)
	local p = {
		part = part, pos = o.pos, vel = o.vel or v3(0, 0, 0), rot = o.rot or CFrame.new(), spin = o.spin or v3(0, 0, 0),
		gravity = o.gravity or 0, drag = o.drag or 0, life = o.life or 1, age = -(o.delay or 0), size0 = o.size0 or part.Size,
		size1 = o.size1, t0 = o.t0 or part.Transparency, t1 = o.t1 or 1, bounce = o.bounce, color0 = part.Color, color1 = o.color1,
		fadeFrom = o.fadeFrom or 0, attract = o.attract, orbit = o.orbit,
	}
	if p.age < 0 then
		part.Transparency = 1
	end
	part.CFrame = CFrame.new(p.pos) * p.rot
	table.insert(fx.particles, p)
	return p
end

-- at(fx, seconds, fn): run fn(fx) once the effect is that old
local function at(fx, t, fn)
	table.insert(fx.events, { t = t + (fx.shift or 0), fn = fn })
end

-- Body copy ----------------------------------------------------------------------------------------------------------------------

local KEEP = { SpecialMesh = true, Decal = true, SurfaceAppearance = true, Texture = true }

-- body(fx, model, offset, hide) -> list of pieces { part, cf } copied from the visible parts of the model
local function body(fx, model, offset, hide)
	local pieces = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 and #pieces < 40 then
			local ok, copy = pcall(function()
				return d:Clone()
			end)
			if not ok or not copy then
				copy = Instance.new("Part")
				copy.Size, copy.Color, copy.Material = d.Size, d.Color, d.Material
			end
			for _, c in ipairs(copy:GetChildren()) do
				if not KEEP[c.ClassName] then
					c:Destroy()
				end
			end
			copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch, copy.CastShadow = true, false, false, false, false
			local cf = d.CFrame + (offset or v3(0, 0, 0))
			copy.CFrame = cf
			copy.Parent = fx.folder
			table.insert(pieces, { part = copy, cf = cf })
			if hide then
				pcall(function()
					d.LocalTransparencyModifier = 1
				end)
				state.hidden[d] = true
			end
		end
	end
	return pieces
end

local function centreOf(pieces, fallback)
	if #pieces == 0 then
		return fallback
	end
	local sum = v3(0, 0, 0)
	for _, pc in ipairs(pieces) do
		sum += pc.cf.Position
	end
	return sum / #pieces
end

local function floorUnder(pos, fx)
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { fx.folder, fx.model }
		return Services.Workspace:Raycast(pos, v3(0, -40, 0), params)
	end)
	if ok and hit and hit.Position then
		return hit.Position.Y
	end
	return pos.Y - 3
end

-- the body pieces stop being static and fly: fn(piece, i) -> vel, spin
local function release(fx, opts)
	for _, pc in ipairs(fx.pieces) do
		local p = particle(fx, pc.part, {
			pos = pc.cf.Position, rot = (pc.cf.Rotation or CFrame.new()), vel = opts.vel(pc), spin = opts.spin and opts.spin(pc) or randUnit() * 9,
			gravity = opts.gravity or -60, drag = opts.drag or 0.4, life = opts.life or 2.2, t0 = 0, t1 = 1, fadeFrom = opts.fadeFrom or 0.65,
			bounce = opts.bounce ~= false, size1 = opts.shrink and pc.part.Size * opts.shrink or nil, color1 = opts.color1,
			attract = opts.attract, orbit = opts.orbit,
		})
		if opts.stretch then
			-- pulled into a long thin streak, then swallowed
			local sz = pc.part.Size
			p.size1 = v3(sz.X * 0.15, sz.Y * 0.15, sz.Z * 4)
		end
		p.color0 = opts.color0 or pc.part.Color
	end
	fx.pieces = {}
end

local function tintBody(fx, color, material)
	for _, pc in ipairs(fx.pieces) do
		pcall(function()
			pc.part.Color = color
			if material then
				pc.part.Material = material
			end
			if pc.part:IsA("MeshPart") then
				pc.part.TextureID = ""
			end
			for _, c in ipairs(pc.part:GetChildren()) do
				if c:IsA("Decal") or c:IsA("SurfaceAppearance") or c:IsA("Texture") then
					c:Destroy()
				end
			end
		end)
	end
end

-- wave(fx, t0, span, fn): runs fn(piece) for each body piece from the feet up, spread over span seconds (frost / glow
-- crawling up the body)
local function wave(fx, t0, span, fn)
	local list = {}
	for _, pc in ipairs(fx.pieces) do
		table.insert(list, pc)
	end
	table.sort(list, function(a, b)
		return a.cf.Position.Y < b.cf.Position.Y
	end)
	for i, pc in ipairs(list) do
		at(fx, t0 + span * (i - 1) / math.max(1, #list - 1), function()
			if pc.part.Parent then
				pcall(fn, pc)
			end
		end)
	end
end

-- fragment(fx, n, color, material): every body piece breaks into n shards (wedges and slabs) filling its volume; the
-- originals are removed. Turns "six limbs fly off" into a proper burst of debris.
local function fragment(fx, n, color, material)
	n = math.max(2, math.floor(n * math.min(1.2, fx.detail) + 0.5))
	local out = {}
	for _, pc in ipairs(fx.pieces) do
		local sz = pc.part.Size
		local col = color or pc.part.Color
		for j = 1, n do
			local f = 0.35 + rand() * 0.35
			local shard = newPart(fx, rand() < 0.6 and "Wedge" or "Block", v3(sz.X * f, sz.Y * (0.3 + rand() * 0.3), sz.Z * f), col,
				material or Enum.Material.Slate)
			local cf = pc.cf * CFrame.new((rand() - 0.5) * sz.X * 0.6, ((j - 0.5) / n - 0.5) * sz.Y, (rand() - 0.5) * sz.Z * 0.6)
				* CFrame.Angles(rand() * 0.6, rand() * 6.28, rand() * 0.6)
			shard.CFrame = cf
			table.insert(out, { part = shard, cf = cf })
		end
		pcall(function()
			pc.part:Destroy()
		end)
	end
	fx.pieces = out
end

-- sparks(fx, origin, n, color, speed, life): thin glowing streaks with gravity
local function sparks(fx, origin, n, color, speed, life, gravity)
	n = math.floor(n * fx.detail)
	for _ = 1, n do
		local dir = randUnit()
		local part = newPart(fx, "Block", v3(0.12, 0.12, 0.7) * fx.k, color)
		particle(fx, part, {
			pos = origin, vel = dir * speed * (0.5 + rand()) * fx.k, rot = CFrame.lookAt(v3(0, 0, 0), dir), gravity = gravity or -40,
			drag = 0.8, life = life * (0.6 + rand() * 0.6), t0 = 0, t1 = 1, fadeFrom = 0.3, size1 = v3(0.04, 0.04, 0.3) * fx.k, bounce = true,
		})
	end
end

-- ring(fx, centre, radius, color, life, thickness): a shock ring made of glowing segments that expands and fades
local function ring(fx, centre, radius, color, life, thickness, tilt)
	local n = math.max(12, math.floor(28 * fx.detail))
	thickness = (thickness or 0.35) * fx.k
	for i = 1, n do
		local a = i / n * 2 * PI
		local dir = v3(cos(a), 0, sin(a))
		if tilt then
			dir = (tilt * CFrame.new(dir)).Position
		end
		local seg = newPart(fx, "Block", v3(thickness, thickness * 0.6, 0.6) * 1, color)
		particle(fx, seg, {
			pos = centre + dir * 0.6, vel = dir * radius * fx.k / life * 1.4, drag = 1.6, life = life, t0 = 0, t1 = 1, fadeFrom = 0.2,
			rot = CFrame.lookAt(v3(0, 0, 0), v3(-dir.Z, 0, dir.X)), size1 = v3(thickness * 0.4, thickness * 0.3, 2.4 * fx.k),
		})
	end
end

-- shock(fx, centre, d1, color, life, tilt): our ring mesh expanding (only when meshes can be loaded; the segment ring stays as well)
local function shock(fx, centre, d1, color, life, tilt, t0)
	if not KillFX.asset("ring.obj") then
		return
	end
	local part = meshPart(fx, "ring", v3(1, 1, 1) * fx.k, color, Enum.Material.Neon, t0 or 0)
	particle(fx, part, { pos = centre, rot = tilt or CFrame.new(), life = life, size0 = v3(1, 1, 1) * fx.k, size1 = v3(d1, d1 * 0.6, d1) * fx.k,
		t0 = t0 or 0, t1 = 1, fadeFrom = 0.25 })
end

-- ball(fx, centre, d0, d1, color, life, t0): a glowing sphere that grows and fades (fireball layers, flashes)
local function ball(fx, centre, d0, d1, color, life, t0, delay, material)
	local part = newPart(fx, "Ball", v3(d0, d0, d0) * fx.k, color, material)
	return particle(fx, part, { pos = centre, life = life, size1 = v3(d1, d1, d1) * fx.k, t0 = t0 or 0, t1 = 1, delay = delay })
end

-- bolt(fx, from, to, color, width, life): a jagged lightning bolt of glowing segments, with a few side branches
local function bolt(fx, from, to, color, width, life, branches)
	local pts = { from }
	local n = 9
	local dir = to - from
	local side1 = dir:Cross(v3(1, 0, 0))
	if side1.Magnitude < 0.01 then
		side1 = v3(0, 0, 1)
	end
	side1 = side1.Unit
	local side2 = dir:Cross(side1).Unit
	for i = 1, n - 1 do
		local f = i / n
		local jitter = (1 - math.abs(f - 0.5) * 1.2) * dir.Magnitude * 0.07
		table.insert(pts, from + dir * f + side1 * (rand() * 2 - 1) * jitter + side2 * (rand() * 2 - 1) * jitter)
	end
	table.insert(pts, to)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		local seg = newPart(fx, "Block", v3(width, width, len + width) * fx.k ^ 0.5, color)
		local cf = CFrame.lookAt((a + b) / 2, b)
		particle(fx, seg, { pos = cf.Position, rot = cf.Rotation or CFrame.new(), life = life, t0 = 0, t1 = 1, fadeFrom = 0.5 })
		if fx.detail >= 0.6 then
			-- soft glow round the core of the bolt
			local halo = newPart(fx, "Block", v3(width * 3.5, width * 3.5, len + width) * fx.k ^ 0.5, color, Enum.Material.Neon, 0.75)
			particle(fx, halo, { pos = cf.Position, rot = cf.Rotation or CFrame.new(), life = life, t0 = 0.75, t1 = 1, fadeFrom = 0.3 })
		end
		if branches and i > 2 and i < #pts - 1 and rand() < 0.45 then
			local bdir = (randUnit() + (b - a).Unit) * len * 1.6
			bolt(fx, a, a + bdir, color, width * 0.5, life * 0.8, false)
		end
	end
end

-- smoke(fx, origin, n, color): soft puffs that rise, grow and fade
local function smoke(fx, origin, n, color, rise, life)
	n = math.floor(n * fx.detail)
	for _ = 1, n do
		local d = (1 + rand() * 1.5) * fx.k
		local part = newPart(fx, "Ball", v3(d, d, d), color, Enum.Material.SmoothPlastic, 0.55)
		local off = randUnit() * 1.5 * fx.k
		particle(fx, part, {
			pos = origin + off, vel = v3(off.X, (rise or 6) * (0.5 + rand()), off.Z) * 1, drag = 1.2, life = life or 2.4, t0 = 0.55, t1 = 1,
			size1 = v3(d, d, d) * 2.8, delay = rand() * 0.25,
		})
	end
end

-- Effects ------------------------------------------------------------------------------------------------------------------------

local BUILD = {}

function BUILD.Lightning(fx)
	local c, col = fx.centre, fx.color or Color3.fromRGB(150, 210, 255)
	local white = Color3.fromRGB(255, 255, 255)
	local sky = c + v3(0, 26, 0) * fx.k
	-- 1. a storm cloud gathers above the victim and charge climbs out of the body (0 - 0.45 s)
	at(fx, 0, function()
		for _ = 1, math.floor(12 * fx.detail) + 4 do
			local d = (3 + rand() * 4) * fx.k
			local cloud = newPart(fx, "Ball", v3(d, d * 0.45, d), Color3.fromRGB(34, 36, 48), Enum.Material.SmoothPlastic, 0.95)
			local off = v3((rand() - 0.5) * 10, (rand() - 0.5) * 1.5, (rand() - 0.5) * 10) * fx.k
			particle(fx, cloud, { pos = sky + off, vel = -off * 0.4, drag = 1.5, life = 1.9, t0 = 0.95, t1 = 1, fadeFrom = 0.7,
				size1 = v3(d * 1.4, d * 0.6, d * 1.4) })
			local p = fx.particles[#fx.particles]
			p.t0, p.t1 = 0.25, 1 -- fades in quickly (handled by the transparency ramp below)
		end
		for i = 1, math.floor(18 * fx.detail) + 6 do
			local seg = newPart(fx, "Block", v3(0.08, 0.08, 0.6) * fx.k, col)
			particle(fx, seg, { pos = c + v3((rand() - 0.5) * 2, (rand() - 0.5) * 4, (rand() - 0.5) * 2) * fx.k, vel = v3(0, 10 + rand() * 8, 0) * fx.k,
				rot = CFrame.Angles(PI / 2, 0, 0), life = 0.35, delay = i * 0.015, t0 = 0, t1 = 1, fadeFrom = 0.5 })
		end
		ball(fx, c, 3, 4.5, col, 0.45, 0.85)
		emit(fx, c, "spark", 30, { color = col, size = { 0.5, 0.1 }, life = { 0.3, 0.5 }, speed = { 8, 16 }, spread = 25, squash = true })
		emit(fx, sky, "smoke", 14, { color = Color3.fromRGB(36, 38, 52), size = { 6, 10 }, life = { 1.6, 2.2 }, speed = { 1, 3 }, light = 0, t = { 0.15, 1 }, spread = 180 })
	end)
	fx.shift = 0.45
	-- 2. three strikes, each with a flash (0.45 - 0.65 s)
	for i = 0, 2 do
		at(fx, i * 0.09, function()
			local top = sky + v3((rand() * 2 - 1) * 4, 0, (rand() * 2 - 1) * 4) * fx.k
			bolt(fx, top, c + v3((rand() - 0.5) * 1.2, 0, (rand() - 0.5) * 1.2), i == 1 and white or col, 0.45, 0.32, true)
			ball(fx, c, 1.5, 6, white, 0.16, 0.45)
			ball(fx, sky, 6, 9, col, 0.2, 0.7) -- the cloud lights up
			emit(fx, sky, "glow", 2, { color = col, size = { 14, 18 }, life = { 0.15, 0.25 }, speed = { 0, 0 } })
		end)
	end
	at(fx, 0.12, function()
		tintBody(fx, Color3.fromRGB(28, 26, 30), Enum.Material.Slate) -- charred
		ball(fx, c, 2.5, 9, col, 0.3, 0.6)
		-- glowing cracks burnt into the floor
		for i = 1, math.floor(10 * fx.detail) + 4 do
			local a = i / 14 * 2 * PI + rand() * 0.4
			local len = (2.5 + rand() * 4) * fx.k
			local mid = v3(c.X + cos(a) * len / 2, fx.floor + 0.06, c.Z + sin(a) * len / 2)
			local crack = newPart(fx, "Block", v3(0.16 * fx.k, 0.05, len), col)
			particle(fx, crack, { pos = mid, rot = CFrame.lookAt(v3(0, 0, 0), v3(cos(a), 0, sin(a))), life = 2.6, t0 = 0, t1 = 1, fadeFrom = 0.35,
				color1 = Color3.fromRGB(255, 120, 40) })
		end
	end)
	-- electric arcs crawl over the body between the strike and the burst
	for i = 0, 3 do
		at(fx, 0.14 + i * 0.045, function()
			local pcs = fx.pieces
			if #pcs >= 2 then
				for _ = 1, 3 do
					local a, b = pcs[rand(1, #pcs)].cf.Position, pcs[rand(1, #pcs)].cf.Position
					if (a - b).Magnitude > 0.5 then
						bolt(fx, a, b, col, 0.14, 0.12, false)
					end
				end
			end
		end)
	end
	-- 3. the charred body is torn into dozens of smouldering shards (0.77 s)
	at(fx, 0.32, function()
		fragment(fx, 5, Color3.fromRGB(28, 26, 30))
		emit(fx, c, "glow", 3, { color = col, size = { 8, 16 }, life = { 0.25, 0.4 }, speed = { 0, 0 }, t = { 0.1, 1 } })
		emit(fx, c, "arc", 12, { color = col, size = { 3, 5 }, life = { 0.15, 0.35 }, speed = { 2, 8 }, spin = { -300, 300 } })
		emit(fx, c, "spark", 70, { color = ColorSequence.new(Color3.fromRGB(255, 255, 255), col), size = { 0.7, 0.1 }, life = { 0.4, 0.9 },
			speed = { 25, 45 }, accel = v3(0, -50, 0), drag = 1, squash = true })
		emit(fx, c, "smoke", 16, { color = Color3.fromRGB(40, 40, 48), size = { 3, 9 }, life = { 1.6, 2.6 }, speed = { 2, 5 }, accel = v3(0, 3, 0),
			drag = 1, light = 0, t = { 0.25, 1 } })
		shock(fx, v3(c.X, fx.floor + 0.3, c.Z), 26, col, 0.6)
		release(fx, {
			vel = function(pc)
				local away = (pc.cf.Position - c)
				away = away.Magnitude > 0.05 and away.Unit or randUnit()
				return (away * (18 + rand() * 18) + v3(0, 14 + rand() * 14, 0)) * fx.k
			end,
			life = 2.4, color0 = Color3.fromRGB(28, 26, 30), color1 = Color3.fromRGB(150, 50, 12), -- the shards smoulder
		})
		sparks(fx, c, 46, col, 34, 0.9)
		sparks(fx, c, 26, Color3.fromRGB(255, 150, 60), 12, 1.6, -20) -- embers
		ring(fx, v3(c.X, fx.floor + 0.2, c.Z), 16, col, 0.6, 0.35)
		smoke(fx, c, 8, Color3.fromRGB(40, 40, 46), 7, 2.2)
		local scorch = newPart(fx, "Cylinder", v3(0.1, 7, 7) * fx.k, Color3.fromRGB(12, 12, 14), Enum.Material.Slate, 0.15)
		particle(fx, scorch, { pos = v3(c.X, fx.floor + 0.05, c.Z), rot = CFrame.Angles(0, 0, PI / 2), life = 2.8, t0 = 0.15, t1 = 1, fadeFrom = 0.6 })
	end)
	-- 4. residual arcs flicker on the ground
	for i = 0, 4 do
		at(fx, 0.6 + i * 0.22, function()
			local a = rand() * 2 * PI
			local p0 = v3(c.X + cos(a) * 0.5, fx.floor + 0.2, c.Z + sin(a) * 0.5)
			bolt(fx, p0, p0 + v3(cos(a), 0.15, sin(a)) * (2 + rand() * 3) * fx.k, col, 0.1, 0.12, false)
		end)
	end
	fx.duration = 3.6
end

function BUILD.Explosion(fx)
	local c = fx.centre
	local base = fx.color
	local yellow, orange, red = Color3.fromRGB(255, 240, 150), base or Color3.fromRGB(255, 140, 30), Color3.fromRGB(220, 40, 20)
	-- 1. the body heats up from the feet, glows and swells (0 - 0.4 s)
	wave(fx, 0, 0.25, function(pc)
		pc.part.Material = Enum.Material.Neon
		pc.part.Color = orange
		pcall(function()
			pc.part.TextureID = ""
		end)
	end)
	at(fx, 0.05, function()
		ball(fx, c, 3, 6, orange, 0.35, 0.8)
		for _, pc in ipairs(fx.pieces) do
			particle(fx, pc.part, { pos = pc.cf.Position, rot = pc.cf.Rotation or CFrame.new(), life = 0.36, t0 = 0, t1 = 0, size1 = pc.part.Size * 1.25,
				spin = randUnit() * 0.6 })
		end
		sparks(fx, c, 18, yellow, 8, 0.35, 0)
	end)
	fx.shift = 0.4
	at(fx, 0, function()
		-- the swelling copies above were only for the heat-up: hand the pieces back as shards
		fragment(fx, 4, Color3.fromRGB(60, 40, 30))
		ball(fx, c, 1, 16, Color3.fromRGB(255, 255, 255), 0.16, 0)
		ball(fx, c, 2, 13, yellow, 0.45, 0)
		ball(fx, c, 3, 15, orange, 0.55, 0.35)
		ball(fx, c, 4, 18, red, 0.6, 0.65)
		ring(fx, v3(c.X, fx.floor + 0.3, c.Z), 26, orange, 0.7, 0.5)
		shock(fx, v3(c.X, fx.floor + 0.3, c.Z), 34, orange, 0.7)
		shock(fx, c, 22, yellow, 0.5, CFrame.Angles(PI / 2.3, 0, 0))
		emit(fx, c, "glow", 4, { color = yellow, size = { 10, 20 }, life = { 0.2, 0.35 }, speed = { 0, 0 } })
		emit(fx, c, "flame", 70, { color = ColorSequence.new({ ColorSequenceKeypoint.new(0, yellow), ColorSequenceKeypoint.new(0.4, orange),
			ColorSequenceKeypoint.new(1, red) }), size = { 3.5, 7 }, life = { 0.45, 0.95 }, speed = { 10, 26 }, accel = v3(0, 12, 0), drag = 2.2,
			rot = { -20, 20 }, spin = { -40, 40 }, t = { 0, 1 } })
		emit(fx, c, "spark", 90, { color = ColorSequence.new(yellow, orange), size = { 0.8, 0.1 }, life = { 0.5, 1.1 }, speed = { 30, 55 },
			accel = v3(0, -45, 0), drag = 0.8, squash = true })
		ring(fx, c, 18, yellow, 0.5, 0.3, CFrame.Angles(PI / 2.3, 0, 0))
		release(fx, {
			vel = function(pc)
				local away = (pc.cf.Position - c)
				away = away.Magnitude > 0.05 and away.Unit or randUnit()
				return (away * (34 + rand() * 18) + v3(0, 26 + rand() * 14, 0)) * fx.k
			end,
			life = 2.6, color0 = Color3.fromRGB(255, 160, 60), color1 = Color3.fromRGB(20, 18, 18), -- glowing shards cool down
		})
		-- tongues of fire licking up out of the crater
		for i = 1, math.floor(12 * fx.detail) + 4 do
			local a = i / 16 * 2 * PI
			local tongue = newPart(fx, "Wedge", v3(0.7, 0.2, 1.1) * fx.k, i % 2 == 0 and yellow or orange)
			particle(fx, tongue, {
				pos = v3(c.X + cos(a) * 1.4 * fx.k, fx.floor + 0.3, c.Z + sin(a) * 1.4 * fx.k), vel = v3(cos(a) * 3, 9 + rand() * 6, sin(a) * 3) * fx.k,
				rot = CFrame.lookAt(v3(0, 0, 0), v3(cos(a), 0, sin(a))), drag = 1.2, life = 0.8 + rand() * 0.4, t0 = 0, t1 = 1, fadeFrom = 0.3,
				size1 = v3(0.3, 3.5, 0.6) * fx.k, color1 = red,
			})
		end
		sparks(fx, c, 60, orange, 42, 1.1)
		sparks(fx, c, 24, yellow, 30, 0.7)
	end)
	at(fx, 0.02, function()
		-- rock and dirt chunks thrown up from the ground
		for _ = 1, math.floor(18 * fx.detail) do
			local sz = (0.3 + rand() * 0.6) * fx.k
			local rock = meshPart(fx, "rock", v3(sz, sz * (0.6 + rand() * 0.6), sz), Color3.fromRGB(70 + rand(0, 30), 60, 52), Enum.Material.Slate, 0,
				rand() < 0.5 and "Wedge" or "Block")
			local dir = v3(rand() * 2 - 1, 0, rand() * 2 - 1)
			dir = dir.Magnitude > 0.05 and dir.Unit or v3(1, 0, 0)
			particle(fx, rock, {
				pos = v3(c.X, fx.floor + 0.3, c.Z) + dir * rand() * 2, vel = (dir * (10 + rand() * 14) + v3(0, 22 + rand() * 18, 0)) * fx.k,
				spin = randUnit() * 10, gravity = -70, life = 2.4, t0 = 0, t1 = 1, fadeFrom = 0.75, bounce = true,
			})
		end
		-- scorched crater
		local crater = newPart(fx, "Cylinder", v3(0.12, 10, 10) * fx.k, Color3.fromRGB(16, 14, 14), Enum.Material.Slate, 0.1)
		particle(fx, crater, { pos = v3(c.X, fx.floor + 0.05, c.Z), rot = CFrame.Angles(0, 0, PI / 2), life = 3, t0 = 0.1, t1 = 1, fadeFrom = 0.7 })
		local glowRim = newPart(fx, "Cylinder", v3(0.14, 6, 6) * fx.k, orange, Enum.Material.Neon, 0.3)
		particle(fx, glowRim, { pos = v3(c.X, fx.floor + 0.08, c.Z), rot = CFrame.Angles(0, 0, PI / 2), life = 1.6, t0 = 0.3, t1 = 1, size1 = v3(0.14, 9, 9) * fx.k })
	end)
	for i = 1, 2 do
		at(fx, 0.12 + i * 0.1, function()
			local off = v3(rand() * 2 - 1, rand() * 0.8, rand() * 2 - 1) * 4 * fx.k
			ball(fx, c + off, 1, 8, yellow, 0.3, 0.1)
			ball(fx, c + off, 2, 10, orange, 0.45, 0.3)
			sparks(fx, c + off, 14, orange, 26, 0.7)
		end)
	end
	at(fx, 0.25, function()
		smoke(fx, c, 14, Color3.fromRGB(50, 46, 44), 9, 2.6)
		emit(fx, c, "smoke", 34, { color = Color3.fromRGB(46, 42, 40), size = { 4, 13 }, life = { 2, 3 }, speed = { 4, 10 }, accel = v3(0, 4, 0),
			drag = 1.2, light = 0, t = { 0.15, 1 }, spin = { -30, 30 } })
		smoke(fx, c + v3(0, 3, 0) * fx.k, 8, Color3.fromRGB(30, 28, 28), 12, 3)
	end)
	fx.duration = 3.2
end

function BUILD.Vaporize(fx)
	local c = fx.centre
	local col = fx.color or Color3.fromRGB(110, 255, 230)
	wave(fx, 0, 0.3, function(pc)
		pc.part.Material = Enum.Material.Neon
		pc.part.Color = col
		pcall(function()
			pc.part.TextureID = ""
		end)
		for _, ch in ipairs(pc.part:GetChildren()) do
			if ch:IsA("Decal") or ch:IsA("SurfaceAppearance") then
				ch:Destroy()
			end
		end
		sparks(fx, pc.cf.Position, 4, Color3.fromRGB(255, 255, 255), 5, 0.4, 6)
	end)
	at(fx, 0, function()
		local pillar = newPart(fx, "Cylinder", v3(60, 0.4, 0.4) * fx.k, col, Enum.Material.Neon, 0.5)
		particle(fx, pillar, {
			pos = c + v3(0, 27 * fx.k, 0), rot = CFrame.Angles(0, 0, PI / 2), life = 1.1, t0 = 0.55, t1 = 1, fadeFrom = 0.25,
			size1 = v3(60, 2.6, 2.6) * fx.k, delay = 0.2,
		})
		ring(fx, v3(c.X, fx.floor + 0.2, c.Z), 9, col, 1.0, 0.3)
		shock(fx, v3(c.X, fx.floor + 0.2, c.Z), 14, col, 1.0, nil, 0.2)
		emit(fx, c, "glow", 2, { color = col, size = { 6, 10 }, life = { 0.6, 0.9 }, speed = { 0, 0 }, t = { 0.4, 1 } })
	end)
	at(fx, 0.35, function()
		release(fx, {
			vel = function()
				return v3((rand() - 0.5) * 3, 6 + rand() * 6, (rand() - 0.5) * 3) * fx.k
			end,
			spin = function()
				return randUnit() * 2.5
			end,
			gravity = 0, drag = 0.2, life = 1.8, bounce = false, shrink = 0.05, fadeFrom = 0.2, color0 = col,
			color1 = Color3.fromRGB(255, 255, 255),
		})
		-- three glowing rings climb up the body
		for r = 0, 2 do
			local n = math.max(10, math.floor(20 * fx.detail))
			for i = 1, n do
				local a = i / n * 2 * PI
				local seg = newPart(fx, "Block", v3(0.18, 0.12, 0.55) * fx.k, Color3.fromRGB(255, 255, 255))
				particle(fx, seg, {
					pos = v3(c.X + cos(a) * 1.8 * fx.k, fx.floor + 0.3, c.Z + sin(a) * 1.8 * fx.k), vel = v3(0, 7 * fx.k, 0), delay = r * 0.22,
					rot = CFrame.lookAt(v3(0, 0, 0), v3(-sin(a), 0, cos(a))), life = 1.1, t0 = 0, t1 = 1, fadeFrom = 0.5,
				})
			end
		end
		emit(fx, c, "glow", 90, { color = col, size = { 0.7, 0 }, life = { 1, 2 }, speed = { 2, 6 }, accel = v3(0, 7, 0), spread = 50, drag = 0.5 })
		emit(fx, c, "star", 30, { color = Color3.fromRGB(255, 255, 255), size = { 1.2, 0 }, life = { 0.5, 1.2 }, speed = { 1, 4 }, accel = v3(0, 4, 0),
			spin = { -120, 120 } })
		for r = 0, 2 do
			at(fx, 0.35 + r * 0.22, function()
				if not KillFX.asset("ring.obj") then
					return
				end
				local rp = meshPart(fx, "ring", v3(4, 1, 4) * fx.k, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, 0)
				particle(fx, rp, { pos = v3(c.X, fx.floor + 0.3, c.Z), vel = v3(0, 7, 0) * fx.k, life = 1.1, size0 = v3(4, 1, 4) * fx.k,
					size1 = v3(2, 1, 2) * fx.k, t0 = 0, t1 = 1, fadeFrom = 0.4 })
			end)
		end
		-- dust motes drifting up
		for _ = 1, math.floor(70 * fx.detail) do
			local d = (0.12 + rand() * 0.16) * fx.k
			local part = newPart(fx, "Ball", v3(d, d, d), col)
			particle(fx, part, {
				pos = c + v3((rand() - 0.5) * 2.4, (rand() - 0.5) * 4.5, (rand() - 0.5) * 2.4) * fx.k,
				vel = v3((rand() - 0.5) * 2, 4 + rand() * 9, (rand() - 0.5) * 2) * fx.k, drag = 0.4, life = 1.2 + rand() * 1.2,
				t0 = 0, t1 = 1, fadeFrom = 0.4, delay = rand() * 0.6,
				orbit = rand() < 0.35 and { centre = c + v3(0, rand() * 3, 0) * fx.k, radius = (1 + rand()) * fx.k, angle = rand() * 2 * PI, speed = 5, tilt = CFrame.new(), rise = 6 * fx.k } or nil,
			})
		end
	end)
	fx.duration = 2.8
end

function BUILD.BlackHole(fx)
	local c = fx.centre + v3(0, 1.5 * fx.k, 0)
	local col = fx.color or Color3.fromRGB(170, 80, 255)
	at(fx, 0, function()
		-- the core and three tilted, spinning rings of glowing segments
		local core = ball(fx, c, 0.5, 4.5, Color3.fromRGB(0, 0, 0), 1.4, 0, 0, Enum.Material.SmoothPlastic)
		core.fadeFrom = 0.85
		-- two counter-rotating spiral vortex meshes
		if KillFX.asset("swirl.obj") then
			for k = 0, 1 do
				local sw = meshPart(fx, "swirl", v3(1, 1, 1) * fx.k, k == 0 and col or Color3.fromRGB(255, 200, 255), Enum.Material.Neon, 0.55)
				particle(fx, sw, { pos = c, rot = CFrame.Angles(0.35 + k * 0.2, 0, 0.15), spin = v3(0, k == 0 and 7 or -5, 0), life = 1.45,
					size0 = v3(2, 1, 2) * fx.k, size1 = v3(13 - k * 3, 1, 13 - k * 3) * fx.k, t0 = 0.55 + k * 0.15, t1 = 1, fadeFrom = 0.75 })
			end
		end
		emit(fx, c, "glow", 3, { color = col, size = { 5, 8 }, life = { 1.2, 1.4 }, speed = { 0, 0 }, t = { 0.5, 1 } })
		for r = 1, 3 do
			local n = math.floor(18 * fx.detail) + 6
			for i = 1, n do
				local seg = newPart(fx, "Block", v3(0.25, 0.15, 0.9) * fx.k, r == 2 and Color3.fromRGB(255, 255, 255) or col)
				particle(fx, seg, {
					pos = c, life = 1.55, t0 = 0, t1 = 1, fadeFrom = 0.75,
					orbit = { centre = c, radius = (2 + r * 1.2) * fx.k, angle = i / n * 2 * PI, speed = 6 - r, tilt = CFrame.Angles(0.5 * r, r, 0) },
				})
			end
		end
	end)
	at(fx, 0.05, function()
		-- accretion disc: a flat stream of glowing grains spiralling in
		for i = 1, math.floor(110 * fx.detail) do
			local d = (0.12 + rand() * 0.18) * fx.k
			local grain = newPart(fx, "Ball", v3(d, d, d), rand() < 0.3 and Color3.fromRGB(255, 220, 255) or col)
			particle(fx, grain, {
				pos = c, life = 1.3, t0 = 0, t1 = 1, fadeFrom = 0.8, delay = rand() * 0.2,
				orbit = { centre = c, radius = (2.2 + rand() * 4.5) * fx.k, angle = rand() * 2 * PI, speed = 4 + rand() * 4, tilt = CFrame.Angles(0.35, 0, 0.15) },
			})
		end
		-- thin bright lensing ring round the core
		local n = math.floor(30 * fx.detail) + 8
		for i = 1, n do
			local seg = newPart(fx, "Block", v3(0.08, 0.08, 0.5) * fx.k, Color3.fromRGB(255, 255, 255))
			particle(fx, seg, { pos = c, life = 1.3, t0 = 0.2, t1 = 1, fadeFrom = 0.8, orbit = { centre = c, radius = 2.6 * fx.k, angle = i / n * 2 * PI, speed = 1.5, tilt = CFrame.Angles(PI / 2, 0, 0), rise = 0 } })
		end
	end)
	at(fx, 0.15, function()
		release(fx, {
			vel = function(pc)
				local d = pc.cf.Position - c
				return v3(-d.Z, 0, d.X) * 2 -- start swirling round
			end,
			gravity = 0, drag = 0, life = 1.3, bounce = false, fadeFrom = 0.8,
			attract = { centre = c, strength = 70 }, stretch = true,
		})
	end)
	at(fx, 1.35, function()
		ball(fx, c, 1, 9, col, 0.3, 0.35)
		ball(fx, c, 0.5, 4, Color3.fromRGB(255, 255, 255), 0.18, 0.1)
		ring(fx, c, 14, col, 0.5, 0.3)
		sparks(fx, c, 40, col, 30, 0.8, 0)
		shock(fx, c, 20, col, 0.5)
		emit(fx, c, "star", 40, { color = Color3.fromRGB(255, 220, 255), size = { 1.4, 0 }, life = { 0.4, 0.9 }, speed = { 15, 35 }, drag = 2 })
		emit(fx, c, "glow", 2, { color = Color3.fromRGB(255, 255, 255), size = { 6, 12 }, life = { 0.15, 0.25 }, speed = { 0, 0 } })
	end)
	fx.duration = 2.6
end

function BUILD.Shatter(fx)
	local c = fx.centre
	local ice = fx.color or Color3.fromRGB(170, 225, 255)
	wave(fx, 0, 0.3, function(pc)
		pc.part.Color = ice
		pc.part.Material = Enum.Material.Ice
		pcall(function()
			pc.part.TextureID = ""
		end)
		for _, ch in ipairs(pc.part:GetChildren()) do
			if ch:IsA("Decal") or ch:IsA("SurfaceAppearance") then
				ch:Destroy()
			end
		end
	end)
	-- white cracks spread over the frozen body just before it breaks
	for i = 0, 2 do
		at(fx, 0.25 + i * 0.06, function()
			for _, pc in ipairs(fx.pieces) do
				local sz = pc.part.Size
				local crack = newPart(fx, "Block", v3(0.06, sz.Y * (0.4 + rand() * 0.5), 0.06), Color3.fromRGB(255, 255, 255))
				local face = rand() < 0.5 and -1 or 1
				local cf = pc.cf * CFrame.new((rand() - 0.5) * sz.X * 0.8, (rand() - 0.5) * sz.Y * 0.4, face * (sz.Z / 2 + 0.02)) * CFrame.Angles(0, 0, (rand() - 0.5) * 1.6)
				particle(fx, crack, { pos = cf.Position, rot = cf.Rotation or CFrame.new(), life = 0.45 - i * 0.06, t0 = 0, t1 = 0.2 })
			end
		end)
	end
	at(fx, 0, function()
		ball(fx, c, 2, 9, Color3.fromRGB(230, 248, 255), 0.25, 0.4)
		-- ice spikes burst out of the floor round the body
		for i = 1, math.floor(14 * fx.detail) + 4 do
			local a = rand() * 2 * PI
			local r = (1.6 + rand() * 2.6) * fx.k
			local h = (2.5 + rand() * 3.5) * fx.k
			local spike = meshPart(fx, "crystal", v3(0.8 * fx.k, 0.1, 1.3 * fx.k), ice, Enum.Material.Ice, 0.1, "Wedge")
			local base = v3(c.X + cos(a) * r, fx.floor, c.Z + sin(a) * r)
			particle(fx, spike, {
				pos = base, rot = CFrame.lookAt(v3(0, 0, 0), v3(cos(a), 0, sin(a))) * CFrame.Angles(-0.35, 0, 0), life = 2.6, t0 = 0.1, t1 = 1,
				fadeFrom = 0.75, size1 = v3(0.8 * fx.k, h, 1.3 * fx.k), delay = rand() * 0.25,
			})
		end
		-- frost mist rolling along the floor
		for _ = 1, math.floor(10 * fx.detail) do
			local d = (1.5 + rand() * 2) * fx.k
			local mist = newPart(fx, "Ball", v3(d, d * 0.35, d), Color3.fromRGB(235, 248, 255), Enum.Material.SmoothPlastic, 0.85)
			local dir = randUnit()
			particle(fx, mist, {
				pos = v3(c.X, fx.floor + 0.25, c.Z), vel = v3(dir.X, 0, dir.Z) * 7 * fx.k, drag = 1, life = 2.4, t0 = 0.85, t1 = 1,
				size1 = v3(d * 2.2, d * 0.5, d * 2.2), delay = rand() * 0.3,
			})
		end
	end)
	at(fx, 0.45, function()
		-- every body piece breaks into a few wedge shards
		local shards = {}
		for _, pc in ipairs(fx.pieces) do
			local sz = pc.part.Size
			for j = 1, (fx.detail >= 1 and 3 or 2) do
				local shard = meshPart(fx, "crystal", v3(sz.X * (0.4 + rand() * 0.3), sz.Y * (0.4 + rand() * 0.3), sz.Z * (0.4 + rand() * 0.3)), ice,
					Enum.Material.Ice, 0.15, "Wedge")
				shard.CFrame = pc.cf * CFrame.new((rand() - 0.5) * sz.X * 0.5, (j - 2) * sz.Y * 0.3, (rand() - 0.5) * sz.Z * 0.5)
				table.insert(shards, { part = shard, cf = shard.CFrame })
			end
			pc.part:Destroy()
		end
		fx.pieces = shards
		release(fx, {
			vel = function(pc)
				local away = (pc.cf.Position - c)
				away = away.Magnitude > 0.05 and away.Unit or randUnit()
				return (away * (14 + rand() * 12) + v3(0, 12 + rand() * 10, 0)) * fx.k
			end,
			gravity = -70, life = 2.6, fadeFrom = 0.7, color0 = ice,
		})
		sparks(fx, c, 34, Color3.fromRGB(235, 250, 255), 24, 0.7)
		ring(fx, v3(c.X, fx.floor + 0.2, c.Z), 12, ice, 0.6, 0.3)
		shock(fx, v3(c.X, fx.floor + 0.2, c.Z), 18, ice, 0.6)
		emit(fx, c, "star", 45, { color = Color3.fromRGB(235, 250, 255), size = { 1, 0 }, life = { 0.5, 1.2 }, speed = { 8, 20 }, accel = v3(0, -10, 0),
			spin = { -180, 180 } })
		emit(fx, v3(c.X, fx.floor + 0.3, c.Z), "smoke", 20, { color = Color3.fromRGB(225, 240, 255), size = { 1.5, 4 }, life = { 1.2, 2 },
			speed = { 5, 10 }, spread = 88, drag = 1.8, light = 0.2, t = { 0.72, 1 } })
	end)
	fx.duration = 3.2
end

-- Runtime ------------------------------------------------------------------------------------------------------------------------

local function destroyFx(fx)
	fx.done = true
	pcall(function()
		fx.folder:Destroy()
	end)
end

local function stepFx(fx, dt)
	fx.age += dt
	for i = #fx.events, 1, -1 do
		local e = fx.events[i]
		if fx.age >= e.t then
			table.remove(fx.events, i)
			local ok, err = pcall(e.fn, fx)
			if not ok then
				Logger.warn("KillFX", "%s: %s", fx.name, tostring(err))
			end
		end
	end
	local parts, cfs = {}, {}
	for i = #fx.particles, 1, -1 do
		local p = fx.particles[i]
		p.age += dt
		if p.age >= 0 then
			local f = p.age / p.life
			if f >= 1 then
				pcall(function()
					p.part:Destroy()
				end)
				table.remove(fx.particles, i)
			else
				if p.orbit then
					local o = p.orbit
					o.angle += o.speed * dt
					local r = o.radius * (1 - f * (o.rise and 0.2 or 0.9))
					p.pos = o.centre + (o.tilt * CFrame.new(cos(o.angle) * r, (o.rise or 0) * p.age, sin(o.angle) * r)).Position
					p.rot = CFrame.lookAt(v3(0, 0, 0), (o.tilt * CFrame.new(-sin(o.angle), 0, cos(o.angle))).Position)
				else
					if p.attract then
						local d = p.attract.centre - p.pos
						p.vel += d.Unit * p.attract.strength * dt * math.min(1, d.Magnitude)
						p.vel += v3(-d.Z, 0, d.X) * dt * 3
					end
					p.vel = p.vel * math.max(0, 1 - p.drag * dt) + v3(0, p.gravity * dt, 0)
					p.pos += p.vel * dt
					if p.bounce and p.pos.Y < fx.floor + 0.15 and p.vel.Y < 0 then
						p.pos = v3(p.pos.X, fx.floor + 0.15, p.pos.Z)
						p.vel = v3(p.vel.X * 0.6, -p.vel.Y * 0.32, p.vel.Z * 0.6)
						p.spin *= 0.6
					end
					p.rot = p.rot * CFrame.Angles(p.spin.X * dt, p.spin.Y * dt, p.spin.Z * dt)
				end
				if p.size1 then
					local sz = p.size0:Lerp(p.size1, f)
					p.part.Size = sz
					local sm = p.part:FindFirstChild("FxMesh")
					if sm then
						sm.Scale = sz
					end
				end
				local tf = f <= p.fadeFrom and 0 or (f - p.fadeFrom) / math.max(0.001, 1 - p.fadeFrom)
				p.part.Transparency = p.t0 + (p.t1 - p.t0) * tf
				if p.color1 then
					p.part.Color = p.color0:Lerp(p.color1, f)
				end
				table.insert(parts, p.part)
				table.insert(cfs, CFrame.new(p.pos) * p.rot)
			end
		end
	end
	if #parts > 0 then
		local ok = pcall(Services.Workspace.BulkMoveTo, Services.Workspace, parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if not ok then
			for i, part in ipairs(parts) do
				part.CFrame = cfs[i]
			end
		end
	end
	if fx.age >= fx.duration and fx.age >= (fx.longest or 0) and #fx.particles == 0 then
		destroyFx(fx)
	end
end

-- play(model, opts) -> fx | nil, err. opts = { effect = name, offset = Vector3, hide = bool }. The public entry used by the kill
-- events and by the page's test button (which plays on a copy of your own avatar in front of you, with hide = false).
function KillFX.play(model, opts)
	if not state then
		return nil, "KillFX is not running"
	end
	opts = opts or {}
	if not model or not model.GetDescendants then
		return nil, "no body to play on"
	end
	local name = opts.effect or s("effect")
	if name == "Random" or not BUILD[name] then
		name = KillFX.EFFECTS[rand(1, #KillFX.EFFECTS)]
	end
	while #state.active >= KillFX.MAX_ACTIVE do
		destroyFx(table.remove(state.active, 1))
	end
	local cam = Services.Workspace.CurrentCamera
	local folder = Instance.new("Folder")
	folder.Name = "MM2HubKillFX"
	folder.Parent = cam
	local low = Perf.isLow() or Settings.get("ui.reduceEffects")
	local fx = {
		name = name, folder = folder, model = model, particles = {}, events = {}, age = 0, duration = 3,
		k = s("scale"), detail = low and 0.4 or s("detail"), color = s("customColor") and Color3.fromRGB(s("color").r, s("color").g, s("color").b) or nil,
	}
	fx.pieces = body(fx, model, opts.offset, opts.hide ~= false and s("hideBody"))
	local okPivot, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	fx.centre = centreOf(fx.pieces, (opts.offset or v3(0, 0, 0)) + (okPivot and pivot or v3(0, 0, 0)))
	fx.floor = floorUnder(fx.centre, fx)
	local ok, err = pcall(BUILD[name], fx)
	if not ok then
		destroyFx(fx)
		return nil, tostring(err)
	end
	table.insert(state.active, fx)
	state.played += 1
	state.last = name
	return fx
end

-- test(effect?) -> fx | nil, err: plays on a copy of your own character 10 studs in front of you (your avatar is not hidden)
function KillFX.test(effect)
	local lp = Services.Players.LocalPlayer
	local char = lp and lp.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, "your character is not loaded"
	end
	return KillFX.play(char, { effect = effect, offset = root.CFrame.LookVector * 10, hide = false })
end

function KillFX.status()
	if not state then
		return "off"
	end
	return string.format("%s, played %d, active %d%s", s("enabled") and "on" or "off", state.played, #state.active,
		state.last and (", last " .. state.last) or "")
end

function KillFX.activeCount()
	return state and #state.active or 0
end

function KillFX.start(ctx)
	assert(state == nil, "KillFX already started")
	state = { active = {}, hidden = setmetatable({}, { __mode = "k" }), played = 0, last = nil }
	ctx.maid:Give(function()
		for _, fx in ipairs(state.active) do
			destroyFx(fx)
		end
		for part in pairs(state.hidden) do
			pcall(function()
				part.LocalTransparencyModifier = 0
			end)
		end
		state = nil
	end)
	ctx.maid:Give(KillEvents.Confirmed:Connect(function(ev)
		if not state or not s("enabled") then
			return
		end
		if (ev.role == "murderer" and not s("onMurderer")) or (ev.role == "sheriff" and not s("onSheriff")) then
			return
		end
		local victim = ev.victim
		if typeof(victim) == "Instance" and victim:IsA("Model") then
			local _, err = KillFX.play(victim)
			if err then
				Logger.warn("KillFX", "could not play: %s", err)
			end
		end
	end))
	local handle = Perf.every("killfx", 60, function(dt)
		if not state then
			return
		end
		for i = #state.active, 1, -1 do
			local fx = state.active[i]
			if fx.done then
				table.remove(state.active, i)
			else
				stepFx(fx, math.min(dt, 0.05))
			end
		end
	end, { visual = true })
	ctx.maid:Give(handle.Cancel)
	Logger.info("KillFX", "ready")
end

return KillFX

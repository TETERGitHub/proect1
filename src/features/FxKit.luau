--!nonstrict
-- features/FxKit: shared building blocks for the hub's own visual effects (kill effects, auras): loading our own bundled
-- textures and meshes (data/FxPack, made by tools/make_fx_assets.py; written to MM2Hub/fx/ once, shown via getcustomasset),
-- anchored effect parts, meshes on parts through SpecialMesh, and ParticleEmitters with our own textures.
-- Without getcustomasset every mesh falls back to a plain primitive and textured emitters are skipped, so effects still work.
-- Depends on: Env, Codec, FxPack.

local import = ...
local Env = import("core/Env")
local Codec = import("core/Codec")
local FxPack = import("data/FxPack")

local FxKit = {}

local urls = {} -- file -> url | false

-- asset(file) -> rbxasset url or nil
function FxKit.asset(file)
	if urls[file] ~= nil then
		return urls[file] or nil
	end
	local e = FxPack[file]
	local url = nil
	if e and Env.persistent() and Env.has("getcustomasset") then
		local path = Env.ROOT .. "/fx/" .. file
		local have = Env.read(path)
		if not have or #have ~= e.bytes then
			local raw = Codec.b64decode(e.data)
			if raw and #raw == e.bytes then
				Env.write(path, raw)
			end
		end
		url = Env.customAsset(path)
	end
	urls[file] = url or false
	return url
end

-- part(parent, shape, size, color, material, transparency) -> anchored, non-colliding effect part
function FxKit.part(parent, shape, size, color, material, transparency)
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = true, false, false, false, false, true
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- mesh(parent, name, size, color, material, transparency, fallbackShape) -> part showing our mesh (ring, swirl, crystal, rock,
-- flame, feather, blade) scaled to size studs; the fallback primitive when meshes cannot be loaded. setSize keeps them in step.
function FxKit.mesh(parent, name, size, color, material, transparency, fallbackShape)
	local url = FxKit.asset(name .. ".obj")
	local p = FxKit.part(parent, url and "Block" or (fallbackShape or "Block"), size, color, material, transparency)
	if url then
		local sm = Instance.new("SpecialMesh")
		sm.Name = "FxMesh"
		sm.MeshType = Enum.MeshType.FileMesh
		sm.MeshId = url
		sm.Scale = size
		sm.Parent = p
	end
	return p
end

function FxKit.setSize(p, size)
	p.Size = size
	local sm = p:FindFirstChild("FxMesh")
	if sm then
		sm.Scale = size
	end
end

-- emitter(holder, tex, o) -> ParticleEmitter | nil: our textured particles on a holder part (or attachment). o: rate, color
-- (Color3 or ColorSequence), size {a, b}, t {a, b} transparency, life {min, max}, speed {min, max}, spread, accel (Vector3),
-- drag, light, rot {min, max}, spin {min, max}, squash (face motion), lock (particles move with the holder)
function FxKit.emitter(holder, tex, o)
	local url = FxKit.asset(tex .. ".png")
	if not url then
		return nil
	end
	local ok, e = pcall(function()
		local em = Instance.new("ParticleEmitter")
		em.Texture = url
		FxKit.setEmitterColor(em, o.color or Color3.fromRGB(255, 255, 255))
		local sz = o.size or { 1, 0 }
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz[1]), NumberSequenceKeypoint.new(1, sz[2]) })
		local tr = o.t or { 0, 1 }
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, tr[1]), NumberSequenceKeypoint.new(1, tr[2]) })
		local life = o.life or { 0.6, 1.2 }
		em.Lifetime = NumberRange.new(life[1], life[2])
		local sp = o.speed or { 1, 3 }
		em.Speed = NumberRange.new(sp[1], sp[2])
		em.SpreadAngle = Vector2.new(o.spread or 180, o.spread or 180)
		em.Acceleration = o.accel or Vector3.new(0, 0, 0)
		em.Drag = o.drag or 0
		em.LightEmission = o.light or 1
		em.LightInfluence = 0
		local rot, spin = o.rot or { 0, 360 }, o.spin or { -60, 60 }
		em.Rotation = NumberRange.new(rot[1], rot[2])
		em.RotSpeed = NumberRange.new(spin[1], spin[2])
		if o.squash then
			em.Orientation = Enum.ParticleOrientation.VelocityParallel
		end
		em.LockedToPart = o.lock == true
		em.Rate = o.rate or 0
		em.Parent = holder
		return em
	end)
	return ok and e or nil
end

function FxKit.setEmitterColor(em, col)
	em.Color = typeof(col) == "ColorSequence" and col or ColorSequence.new(col)
end

local function attach(part, offset)
	local a = Instance.new("Attachment")
	a.Position = offset
	a.Parent = part
	return a
end

local function seq(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- trail(part, width, o) -> Trail | nil: a glowing streak left behind a moving part (our beam texture). o: color (Color3 or
-- ColorSequence), life (seconds), t {a, b} transparency head->tail, light, tex ("beam" default), widthTail (0-1 scale at tail)
function FxKit.trail(part, width, o)
	o = o or {}
	local url = FxKit.asset((o.tex or "beam") .. ".png")
	local ok, tr = pcall(function()
		local a0 = attach(part, Vector3.new(0, width / 2, 0))
		local a1 = attach(part, Vector3.new(0, -width / 2, 0))
		local t = Instance.new("Trail")
		t.Attachment0, t.Attachment1 = a0, a1
		if url then
			t.Texture = url
			t.TextureMode = Enum.TextureMode.Stretch
		end
		FxKit.setEmitterColor(t, o.color or Color3.fromRGB(255, 255, 255))
		t.Lifetime = o.life or 0.4
		local tt = o.t or { 0, 1 }
		t.Transparency = seq(tt[1], tt[2])
		t.WidthScale = seq(1, o.widthTail or 0.1)
		t.LightEmission = o.light or 1
		t.LightInfluence = 0
		t.FaceCamera = true
		t.MinLength = 0.05
		t.Parent = part
		return t
	end)
	return ok and tr or nil
end

-- beam(p0, p1, o) -> Beam | nil: a textured energy ribbon between two parts (positions of their centres). o: width0, width1,
-- color, t {a, b}, tex ("beam" or "bolt"), segments, curve0, curve1 (bend), speed (texture scroll), light, repeat (texture tiles)
function FxKit.beam(p0, p1, o)
	o = o or {}
	local url = FxKit.asset((o.tex or "beam") .. ".png")
	local ok, b = pcall(function()
		local a0 = attach(p0, Vector3.new(0, 0, 0))
		local a1 = attach(p1, Vector3.new(0, 0, 0))
		local bm = Instance.new("Beam")
		bm.Attachment0, bm.Attachment1 = a0, a1
		if url then
			bm.Texture = url
			bm.TextureMode = Enum.TextureMode.Wrap
			bm.TextureLength = o.repeatLength or 4
			bm.TextureSpeed = o.speed or 1
		end
		FxKit.setEmitterColor(bm, o.color or Color3.fromRGB(255, 255, 255))
		bm.Width0, bm.Width1 = o.width0 or 0.5, o.width1 or o.width0 or 0.5
		local tt = o.t or { 0, 0 }
		bm.Transparency = seq(tt[1], tt[2])
		bm.LightEmission = o.light or 1
		bm.LightInfluence = 0
		bm.FaceCamera = true
		bm.Segments = o.segments or 10
		bm.CurveSize0, bm.CurveSize1 = o.curve0 or 0, o.curve1 or 0
		bm.Parent = p0
		return bm
	end)
	return ok and b or nil
end

-- holder(parent, cf) -> an invisible anchored part to carry emitters
function FxKit.holder(parent, cf)
	local h = FxKit.part(parent, "Block", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 1)
	h.CFrame = cf or CFrame.new()
	return h
end

-- moveAll(parts, cfs): BulkMoveTo with a per-part fallback
function FxKit.moveAll(parts, cfs)
	if #parts == 0 then
		return
	end
	local ws = workspace
	local ok = ws ~= nil and pcall(ws.BulkMoveTo, ws, parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

return FxKit

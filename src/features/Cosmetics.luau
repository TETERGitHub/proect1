--!nonstrict
-- features/Cosmetics: LOCAL-ONLY skins. Replaces how your own gun/knife tools and your own character
-- look on your screen; other players keep seeing the original items.
--   proc:<name>   procedural models built from Part primitives (no downloads)
--   asset:<id>    a model you supply by asset id (loaded with game:GetObjects, executor-dependent)
--   file:<name>   a .rbxm/.rbxmx in MM2Hub/models/ (needs getcustomasset + GetObjects)
-- Loaded models are sanitised: every script is removed before use.
-- STATUS: env-dependent. Skinning assumes the standard Tool + "Handle" structure; if MM2 changes it,
-- adjust the tool name on the Cosmetics page.
-- Depends on: Settings, Sources, Perf, Services, Env, Logger.

local import = ...
local Settings = import("core/Settings")
local Sources = import("features/Sources")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Env = import("core/Env")
local Logger = import("core/Logger")
local Lib = import("data/ModelLib")
local Custom = import("features/CustomLogic")
local Meshes = import("features/MeshModels")
local MeshCache = import("features/MeshCache")
local Kit = import("data/ModelKit")
local Rig = import("data/Rig")

local Cosmetics = {}

local state = nil
local cache = {} -- source text -> {model=template} | {err=...} | {loading=true}

-- Procedural models ------------------------------------------------------------------------------------------------

local function newRoot(model)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function bit(model, root, name, shape, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType[shape]
	p.Size = size
	p.Color = color
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * cf
	p.Parent = model
	return p
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local PROC = { gun = {}, knife = {}, char = {} }

function PROC.gun.neon(model, root)
	local dark, glow = rgb(28, 30, 38), rgb(60, 200, 255)
	bit(model, root, "Frame", "Block", Vector3.new(0.32, 0.55, 1.5), CFrame.new(0, 0, 0), dark, "Metal")
	bit(model, root, "Slide", "Block", Vector3.new(0.3, 0.26, 1.7), CFrame.new(0, 0.38, -0.05), rgb(46, 49, 60), "Metal")
	bit(model, root, "Barrel", "Cylinder", Vector3.new(0.7, 0.14, 0.14), CFrame.new(0, 0.38, -1.05) * CFrame.Angles(0, math.rad(90), 0), rgb(16, 16, 20), "Metal")
	bit(model, root, "Grip", "Block", Vector3.new(0.3, 0.85, 0.42), CFrame.new(0, -0.62, 0.55) * CFrame.Angles(math.rad(-14), 0, 0), dark, "Plastic")
	bit(model, root, "Guard", "Block", Vector3.new(0.12, 0.08, 0.5), CFrame.new(0, -0.3, 0.1), dark, "Metal")
	bit(model, root, "GlowStrip", "Block", Vector3.new(0.34, 0.05, 1.25), CFrame.new(0, 0.1, -0.05), glow, "Neon")
	bit(model, root, "SightF", "Block", Vector3.new(0.06, 0.12, 0.08), CFrame.new(0, 0.58, -0.82), glow, "Neon")
	bit(model, root, "SightR", "Block", Vector3.new(0.12, 0.1, 0.08), CFrame.new(0, 0.56, 0.72), glow, "Neon")
end

function PROC.gun.retro(model, root)
	local steel, wood = rgb(150, 154, 160), rgb(112, 70, 40)
	bit(model, root, "Frame", "Block", Vector3.new(0.3, 0.5, 1.3), CFrame.new(0, 0, 0), steel, "Metal")
	bit(model, root, "Barrel", "Cylinder", Vector3.new(1.4, 0.2, 0.2), CFrame.new(0, 0.18, -1.2) * CFrame.Angles(0, math.rad(90), 0), rgb(110, 114, 120), "Metal")
	bit(model, root, "Cylinder", "Cylinder", Vector3.new(0.5, 0.46, 0.46), CFrame.new(0, 0.12, 0.05) * CFrame.Angles(0, math.rad(90), 0), steel, "Metal")
	bit(model, root, "Grip", "Block", Vector3.new(0.34, 0.9, 0.5), CFrame.new(0, -0.62, 0.65) * CFrame.Angles(math.rad(-22), 0, 0), wood, "Wood")
	bit(model, root, "Hammer", "Block", Vector3.new(0.1, 0.24, 0.12), CFrame.new(0, 0.34, 0.62) * CFrame.Angles(math.rad(25), 0, 0), steel, "Metal")
end

function PROC.knife.blade(model, root)
	local steel, glow = rgb(205, 212, 222), rgb(255, 80, 120)
	bit(model, root, "Blade", "Block", Vector3.new(0.08, 0.52, 1.9), CFrame.new(0, 0, -1.2), steel, "Metal")
	bit(model, root, "TipA", "Block", Vector3.new(0.08, 0.36, 0.5), CFrame.new(0, 0.08, -2.3) * CFrame.Angles(math.rad(-24), 0, 0), steel, "Metal")
	bit(model, root, "Edge", "Block", Vector3.new(0.09, 0.05, 1.8), CFrame.new(0, -0.26, -1.2), glow, "Neon")
	bit(model, root, "Guard", "Block", Vector3.new(0.16, 0.95, 0.18), CFrame.new(0, 0, -0.2), rgb(40, 40, 46), "Metal")
	bit(model, root, "Handle", "Cylinder", Vector3.new(0.9, 0.2, 0.2), CFrame.new(0, 0, 0.35) * CFrame.Angles(0, math.rad(90), 0), rgb(30, 30, 36), "SmoothPlastic")
	bit(model, root, "Pommel", "Ball", Vector3.new(0.28, 0.28, 0.28), CFrame.new(0, 0, 0.85), glow, "Neon")
end

function PROC.knife.karambit(model, root)
	local steel, glow = rgb(200, 206, 216), rgb(120, 255, 190)
	-- crescent blade from rotated segments along an arc
	local segments = 9
	for i = 0, segments - 1 do
		local t = i / (segments - 1)
		local ang = math.rad(-10 + 110 * t)
		local r = 1.1
		local y, z = -math.sin(ang) * r * 0.9 + 0.2, -math.cos(ang) * r - 0.2
		bit(model, root, "Seg" .. i, "Block", Vector3.new(0.08, 0.26 - 0.16 * t, 0.34), CFrame.new(0, y, z) * CFrame.Angles(ang, 0, 0), steel, "Metal")
	end
	bit(model, root, "Ring", "Cylinder", Vector3.new(0.1, 0.5, 0.5), CFrame.new(0, -0.5, 0.45) * CFrame.Angles(0, 0, 0), glow, "Neon")
	bit(model, root, "Handle", "Cylinder", Vector3.new(0.85, 0.2, 0.2), CFrame.new(0, 0, 0.1) * CFrame.Angles(0, math.rad(90), 0), rgb(34, 34, 40), "SmoothPlastic")
end

function PROC.char.halo(model, root)
	local glow = rgb(255, 232, 140)
	local n, radius = 18, 1.15
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		bit(model, root, "H" .. i, "Block", Vector3.new(0.2, 0.08, 0.42), CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0), glow, "Neon")
	end
end

function PROC.char.crown(model, root)
	local gold = rgb(255, 205, 70)
	local n, radius = 8, 0.75
	bit(model, root, "BandR", "Cylinder", Vector3.new(0.25, 1.55, 1.55), CFrame.Angles(0, 0, math.rad(90)), gold, "Metal")
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		bit(model, root, "S" .. i, "Block", Vector3.new(0.18, 0.55, 0.18), CFrame.new(math.cos(a) * radius, 0.38, math.sin(a) * radius), gold, "Metal")
		bit(model, root, "G" .. i, "Ball", Vector3.new(0.16, 0.16, 0.16), CFrame.new(math.cos(a) * radius, 0.68, math.sin(a) * radius), rgb(255, 80, 120), "Neon")
	end
end

function PROC.char.wings(model, root)
	local glow = rgb(140, 200, 255)
	for _, side in ipairs({ 1, -1 }) do
		for i = 0, 5 do
			local len = 2.6 - i * 0.28
			bit(model, root, "W" .. side .. i, "Block", Vector3.new(len, 0.07, 0.34), CFrame.new(side * (0.5 + len / 2), 0.9 - i * 0.28, 0.5 + i * 0.05) * CFrame.Angles(0, 0, math.rad(-18 * side + i * 4 * side)), glow, "Neon")
		end
	end
end

function Cosmetics.procNames(kind)
	local out = {}
	for name in pairs(PROC[kind] or {}) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function buildProc(kind, name)
	local fn = PROC[kind] and PROC[kind][name]
	if not fn then
		return nil, "unknown procedural model '" .. tostring(name) .. "' for " .. kind
	end
	local model = Instance.new("Model")
	model.Name = "Skin_" .. name
	local root = newRoot(model)
	fn(model, root)
	return model
end

-- Custom looks (data/ModelLib) -----------------------------------------------------------------------------------------------
-- A custom look is plain data (models + colours + material); these builders turn it into Parts. Every part is welded to a
-- hidden root, has collisions/queries off and is massless, so a skin can never push, block or weigh down the real tool/avatar.

local function instantiate(model, root, list)
	for _, d in ipairs(list) do
		local p = Instance.new(d.shape == "Wedge" and "WedgePart" or "Part")
		p.Name = d.name
		if d.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif d.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = Vector3.new(math.max(0.05, d.size[1]), math.max(0.05, d.size[2]), math.max(0.05, d.size[3]))
		p.Color = Color3.fromRGB(d.color[1], d.color[2], d.color[3])
		p.Material = Enum.Material[d.material] or Enum.Material.SmoothPlastic
		p.Transparency = d.transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = root.CFrame * CFrame.new(d.pos[1], d.pos[2], d.pos[3]) * CFrame.Angles(math.rad(d.rot[1]), math.rad(d.rot[2]), math.rad(d.rot[3]))
		if d.bone then
			p:SetAttribute("bone", d.bone) -- the body part this piece follows (costumes), see data/Rig
		end
		p.Parent = model
	end
end

local function weldAll(model)
	local root = model.PrimaryPart
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, d
			w.Parent = d
		end
	end
end

local function effectsAllowed(look)
	return look.effects and not Perf.isLow() and not Settings.get("ui.reduceEffects")
end

-- addEffects(model, kind, look): soft light (all kinds), a short trail (knife) or a slow sparkle (character). Capped and
-- removed together with the skin; nothing here loops on its own.
local function addEffects(model, kind, look, slotId)
	if not effectsAllowed(look) or look.glowAmount <= 0.05 then
		return
	end
	local root = model.PrimaryPart
	local c = look.glow
	local color = Color3.fromRGB(c[1], c[2], c[3])
	local light = Instance.new("PointLight")
	light.Name = "SkinLight"
	light.Color = color
	light.Brightness = 0.4 + look.glowAmount * 1.1
	light.Range = kind == "char" and 9 or 6
	light.Shadows = false
	light.Parent = root
	if kind == "knife" then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "TrailA", "TrailB"
		a0.Position, a1.Position = Vector3.new(0, 0.28, -1.9), Vector3.new(0, -0.28, -1.9)
		a0.Parent, a1.Parent = root, root
		local trail = Instance.new("Trail")
		trail.Name = "SkinTrail"
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.22
		trail.MinLength = 0.1
		trail.LightEmission = 0.8
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new(0.35, 1)
		trail.Parent = root
	elseif kind == "char" and slotId ~= "head" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "SkinSparkle"
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.Size = NumberSequence.new(0.18, 0)
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(color)
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.Parent = root
	end
end

-- buildSmooth(kind, id, look) -> Model | nil, reason. The smooth-mesh version of a built-in model (features/MeshCache); nil unless the meshes are ready.
local function buildSmooth(kind, id, look)
	if not MeshCache.enabled() then
		return nil, "smooth meshes are switched off"
	end
	local st, detail = MeshCache.status(kind, id)
	if st == "none" then
		MeshCache.request(kind, id)
		return nil, "meshes are being prepared"
	elseif st == "loading" then
		return nil, "meshes are being prepared"
	elseif st == "failed" then
		return nil, detail
	end
	local groups = MeshCache.groups(kind, id)
	local model = Instance.new("Model")
	model.Name = "Skin_" .. id
	local root = newRoot(model)
	for i, g in ipairs(groups) do
		local color, material, transparency = Kit.partLook(g.role, g.material, g.decor, look)
		local ok, part = pcall(function()
			local mp = Instance.new("MeshPart")
			mp.MeshId = g.url
			return mp
		end)
		if not ok then
			model:Destroy()
			return nil, "MeshPart could not be created: " .. tostring(part)
		end
		part.Name = "Mesh" .. i
		part.Size = Vector3.new(g.size[1], g.size[2], g.size[3])
		part.CFrame = root.CFrame * CFrame.new(g.center[1], g.center[2], g.center[3])
		part.Color = Color3.fromRGB(color[1], color[2], color[3])
		part.Material = Enum.Material[material] or Enum.Material.SmoothPlastic
		part.Transparency = transparency or 0
		if g.bone then
			part:SetAttribute("bone", g.bone)
		end
		part.Parent = model
	end
	weldAll(model)
	return model
end

-- buildCustom(kind, id, look, slotId) -> Model (root at the origin, parts welded) | nil, err
local function buildCustom(kind, id, look, slotId)
	local imported = string.match(tostring(id), "^import:([%w_]+)$")
	if imported then
		-- a real mesh you imported (tools/convert_mesh.py): own textures, only the light/sparkle effects apply
		local m, err = Meshes.build(kind, imported)
		if m then
			m:SetAttribute("mesh", true)
			m:SetAttribute("meshNote", "imported mesh")
			addEffects(m, kind, look, slotId)
		end
		return m, err
	end
	if not Lib.has(kind, id) then
		return nil, "unknown model '" .. tostring(id) .. "'"
	end
	local model, why = buildSmooth(kind, id, look)
	if model then
		model:SetAttribute("mesh", true)
	else
		model = Instance.new("Model")
		model.Name = "Skin_" .. id
		local root = newRoot(model)
		instantiate(model, root, Lib.parts(kind, id, look))
		weldAll(model)
		model:SetAttribute("mesh", false)
		model:SetAttribute("meshNote", tostring(why))
	end
	addEffects(model, kind, look, slotId)
	return model
end

-- (see buildPreviewChar below for the character rig)
-- buildPreview(kind, id, look) -> Model for the preview window: anchored, no lights/particles/trails
function Cosmetics.buildPreview(kind, id, look)
	local imported = string.match(tostring(id), "^import:([%w_]+)$")
	if imported then
		local m, err = Meshes.build(kind, imported)
		if m then
			m:SetAttribute("mesh", true)
			m:SetAttribute("meshNote", "imported mesh")
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
				end
			end
		end
		return m, err
	end
	if not Lib.has(kind, id) then
		return nil, "unknown model '" .. tostring(id) .. "'"
	end
	local model, why = buildSmooth(kind, id, look)
	if model then
		model.Name = "Preview_" .. id
		model:SetAttribute("mesh", true)
	else
		model = Instance.new("Model")
		model.Name = "Preview_" .. id
		local root = newRoot(model)
		instantiate(model, root, Lib.parts(kind, id, look))
		model:SetAttribute("mesh", false)
		model:SetAttribute("meshNote", tostring(why))
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		end
	end
	return model
end

-- buildPreviewChar(sel, look) -> Model: a neutral mannequin (or the chosen costume) with the chosen accessories attached to the
-- same bones the live builder uses. Every piece carries its bone and its base CFrame, so Cosmetics.poseRig can swing the limbs
-- (the preview walk). It is a separate model in the preview window and never touches your avatar.
local PREVIEW_ANCHOR_Y = { head = 1.9, back = 0.6, aura = 0 }

function Cosmetics.buildPreviewChar(sel, look)
	local rig = Instance.new("Model")
	rig.Name = "Preview_char"
	local root = newRoot(rig)
	root.Anchored = true
	local costume = sel.costume and sel.costume ~= "" and sel.costume or nil
	local body = Cosmetics.buildPreview("char", costume or "mannequin", costume and look or Lib.styleLook("char", "mannequin"))
	if body then
		body.Parent = rig
	end
	for _, slot in ipairs({ "head", "back", "aura" }) do
		local id = sel[slot]
		if id and id ~= "" then
			local m = Cosmetics.buildPreview("char", id, look)
			if m then
				m.Parent = rig
				m:PivotTo(CFrame.new(0, PREVIEW_ANCHOR_Y[slot], 0))
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d:SetAttribute("bone", Rig.SLOT_BONE[slot] or "Root")
					end
				end
			end
		end
	end
	-- remember every piece's rest CFrame for posing
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("bone") then
			d:SetAttribute("base", d.CFrame)
		end
	end
	return rig
end

-- poseRig(rig, t) -> number of pieces moved. Swings arms, legs and head of a preview rig (walk cycle); t = seconds, nil = rest pose.
function Cosmetics.poseRig(rig, t)
	local moved = 0
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			local boneId, base = d:GetAttribute("bone"), d:GetAttribute("base")
			local bone = boneId and Rig.bone(boneId)
			if bone and base then
				local angle = t and Rig.swingAngle(bone.swing, t) or 0
				local pv = CFrame.new(bone.pivot[1], bone.pivot[2], bone.pivot[3])
				d.CFrame = pv * CFrame.Angles(angle, 0, 0) * pv:Inverse() * base
				moved += 1
			end
		end
	end
	return moved
end

-- Loading and sanitising ----------------------------------------------------------------------------------------------------

local function sanitize(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	if model:IsA("Model") and not model.PrimaryPart then
		local first = model:FindFirstChildWhichIsA("BasePart", true)
		if first then
			model.PrimaryPart = first
		end
	end
end

local function loadExternal(url)
	local ok, objs = pcall(function()
		return game:GetObjects(url)
	end)
	if not ok then
		return nil, "GetObjects failed: " .. tostring(objs)
	end
	local first = objs and objs[1]
	if not first then
		return nil, "asset contained no objects"
	end
	local model = first
	if not first:IsA("Model") then
		model = Instance.new("Model")
		model.Name = "Skin_loaded"
		for _, o in ipairs(objs) do
			o.Parent = model
		end
	end
	sanitize(model)
	if not model.PrimaryPart then
		return nil, "model has no parts"
	end
	return model
end

-- template(kind, sourceText) -> Model|nil, err|nil, pending. Asset/file loads happen in a thread.
local function template(kind, text)
	local key = kind .. "|" .. text
	local entry = cache[key]
	if entry then
		return entry.model, entry.err, entry.loading
	end
	if string.sub(text, 1, 7) == "custom:" then
		local snap, serr = Custom.decodeSnapshot(kind, string.sub(text, 8))
		local m, err
		if snap and snap.sel.model then
			m, err = buildCustom(kind, snap.sel.model, snap.look)
		else
			err = serr or "invalid custom look"
		end
		if m then
			sanitize(m)
		end
		cache[key] = m and { model = m } or { err = err }
		return m, err
	end
	local parsed, perr = Sources.parse(text, "model")
	if not parsed then
		cache[key] = { err = perr }
		return nil, perr
	end
	if parsed.type == "proc" then
		local m, err = buildProc(kind, parsed.ref)
		if m then
			sanitize(m)
			weldAll(m)
		end
		cache[key] = m and { model = m } or { err = err }
		return m, err
	end
	cache[key] = { loading = true }
	task.spawn(function()
		local url, err
		if parsed.type == "asset" then
			url = "rbxassetid://" .. parsed.ref
		else
			url, err = Env.customAsset(Env.ROOT .. "/models/" .. parsed.ref)
		end
		local model
		if url then
			model, err = loadExternal(url)
		end
		if not state then
			-- the hub was unloaded while this was loading: do not leave the model in the (already cleared) cache
			if model then
				model:Destroy()
			end
			return
		end
		cache[key] = model and { model = model } or { err = err or "load failed" }
		if not model then
			Logger.warn("Cosmetics", "%s: %s", text, tostring(err))
		end
		if state then
			state.dirty = true
		end
	end)
	return nil, nil, true
end

-- Application ---------------------------------------------------------------------------------------------------------------------

local function weldTo(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = part0, part1
	w.Parent = part1
end

local function placeSkin(kind, text, anchorPart, scale, offset, rotY, parent)
	local tpl, err, pending = template(kind, text)
	if not tpl then
		return nil, err, pending
	end
	local skin = tpl:Clone()
	skin.Name = "MM2HubSkin"
	for _, attr in ipairs({ "mesh", "meshNote" }) do
		skin:SetAttribute(attr, tpl:GetAttribute(attr)) -- how the template was built (smooth meshes or simple parts, and why)
	end
	pcall(function()
		skin:ScaleTo(scale)
	end)
	skin:PivotTo(anchorPart.CFrame * CFrame.new(offset.X, offset.Y, offset.Z) * CFrame.Angles(0, math.rad(rotY), 0))
	skin.Parent = parent
	weldTo(anchorPart, skin.PrimaryPart)
	return skin
end

local function hideOriginals(container, record)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" and not d:IsDescendantOf(record.skin) then
			table.insert(record.hidden, { d, d.Transparency })
			d.Transparency = 1
		elseif (d:IsA("Decal") or d:IsA("Texture")) and not d:IsDescendantOf(record.skin) then
			table.insert(record.hidden, { d, d.Transparency })
			d.Transparency = 1
		end
	end
end

local function removeRecord(rec)
	if rec.skin then
		pcall(function()
			rec.skin:Destroy()
		end)
	end
	for _, pair in ipairs(rec.hidden) do
		pcall(function()
			pair[1].Transparency = pair[2]
		end)
	end
end

local function toolSlots()
	return {
		gun = { enabled = "cosmetics.gunEnabled", source = "cosmetics.gunSource", tool = "cosmetics.gunTool", scale = "cosmetics.gunScale", ox = "cosmetics.gunOffsetX", oy = "cosmetics.gunOffsetY", oz = "cosmetics.gunOffsetZ", rot = "cosmetics.gunRotY", kind = "gun" },
		knife = { enabled = "cosmetics.knifeEnabled", source = "cosmetics.knifeSource", tool = "cosmetics.knifeTool", scale = "cosmetics.knifeScale", ox = "cosmetics.knifeOffsetX", oy = "cosmetics.knifeOffsetY", oz = "cosmetics.knifeOffsetZ", rot = "cosmetics.knifeRotY", kind = "knife" },
	}
end

local function findTools(name)
	local out = {}
	local player = Services.Players.LocalPlayer
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == name then
					table.insert(out, child)
				end
			end
		end
	end
	return out
end

local function clearTools(slotName)
	local list = state.tools[slotName]
	for tool, rec in pairs(list) do
		removeRecord(rec)
		list[tool] = nil
	end
end

local function applyTools(slotName, slot)
	local list = state.tools[slotName]
	-- an applied custom look (pages Custom gun / Custom knife) wins over the older single-source skin of the same slot
	local custom = Custom.applied(slotName)
	if not custom and not Settings.get(slot.enabled) then
		if next(list) then
			clearTools(slotName)
		end
		state.status[slotName] = "off"
		return
	end
	local text = custom and ("custom:" .. Custom.encodeSnapshot(custom)) or Settings.get(slot.source)
	local tools = findTools(Settings.get(slot.tool))
	-- drop records of tools that vanished or were re-created
	for tool, rec in pairs(list) do
		if not tool.Parent then
			removeRecord(rec)
			list[tool] = nil
		end
	end
	if #tools == 0 then
		state.status[slotName] = "waiting for a '" .. Settings.get(slot.tool) .. "' tool"
		return
	end
	for _, tool in ipairs(tools) do
		if not list[tool] then
			local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
			if handle then
				local rec = { hidden = {}, skin = nil }
				local skin, err, pending = placeSkin(slot.kind, text, handle, Settings.get(slot.scale),
					Vector3.new(Settings.get(slot.ox), Settings.get(slot.oy), Settings.get(slot.oz)), Settings.get(slot.rot), tool)
				if skin then
					rec.skin = skin
					hideOriginals(tool, rec)
					list[tool] = rec
					state.status[slotName] = "applied"
					local meshed = skin:GetAttribute("mesh")
					state.status[slotName .. "Mesh"] = meshed == true and "smooth meshes" or (meshed == false and ("simple parts: " .. tostring(skin:GetAttribute("meshNote"))) or "")
				elseif pending then
					state.status[slotName] = "loading model..."
				else
					state.status[slotName] = "error: " .. tostring(err)
				end
			else
				state.status[slotName] = "tool has no Handle part"
			end
		end
	end
end

-- Character -----------------------------------------------------------------------------------------------------------------------------

local function charAnchor(char)
	local mode = Settings.get("cosmetics.charAttach")
	if mode == "Head" then
		return char:FindFirstChild("Head")
	elseif mode == "Torso" then
		return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function clearChar()
	if state.charRecord then
		removeRecord(state.charRecord)
		state.charRecord = nil
	end
end

local function applyChar()
	local player = Services.Players.LocalPlayer
	local char = player.Character
	if not Settings.get("cosmetics.charEnabled") or not char then
		if state.charRecord then
			clearChar()
		end
		state.status.char = Settings.get("cosmetics.charEnabled") and "waiting for character" or "off"
		return
	end
	local rec = state.charRecord
	if rec and rec.skin and rec.skin.Parent and rec.char == char then
		return
	end
	clearChar()
	local anchor = charAnchor(char)
	if not anchor then
		state.status.char = "no body part to attach to"
		return
	end
	local skin, err, pending = placeSkin("char", Settings.get("cosmetics.charSource"), anchor, Settings.get("cosmetics.charScale"),
		Vector3.new(0, Settings.get("cosmetics.charOffsetY"), 0), 0, char)
	if skin then
		state.charRecord = { skin = skin, hidden = {}, char = char }
		state.status.char = "applied"
	elseif pending then
		state.status.char = "loading model..."
	else
		state.status.char = "error: " .. tostring(err)
	end
end

-- Custom character (pages Custom character): an optional costume over your avatar plus accessories in head/back/aura slots.
-- Only your own client sees it. The costume hides your real avatar by setting local Transparency (restored on removal);
-- nothing here touches collisions, size, speed or the humanoid.
local function isSkin(inst, char)
	local cur = inst
	while cur and cur ~= char do
		if cur.Name == "MM2HubSkin" then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function clearCustomChar()
	local rec = state.customRec
	if not rec then
		return
	end
	state.customRec = nil
	for _, sk in ipairs(rec.skins) do
		pcall(function()
			sk:Destroy()
		end)
	end
	for inst, old in pairs(rec.hidden) do
		pcall(function()
			inst.Transparency = old
		end)
	end
end

local function inTool(d, char)
	local cur = d.Parent
	while cur and cur ~= char do
		if cur:IsA("Tool") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- Hides the avatar's own body under a costume. Held tools are left alone: their visibility belongs to the tool skins, and
-- restoring a recorded value here could otherwise leave the real gun or knife invisible.
local function hideAvatar(char, rec)
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) and not rec.hidden[d] and d.Name ~= "HumanoidRootPart" and not isSkin(d, char) and not inTool(d, char) then
			rec.hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end
end

local ACCESSORY_ANCHOR = {
	head = function(char) return char:FindFirstChild("Head") end,
	back = function(char) return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") end,
	aura = function(char) return char:FindFirstChild("HumanoidRootPart") end,
	costume = function(char) return char:FindFirstChild("HumanoidRootPart") end,
}

-- restPose(char) -> map of part name -> CFrame relative to the HumanoidRootPart in the rig's REST pose (the Motor6D chain with no
-- animation applied), and "R15" | "R6". Pieces are welded with offsets from this, so they stay correct whatever pose the avatar is in.
local function restPose(char)
	local rest = { HumanoidRootPart = CFrame.new() }
	local motors = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			table.insert(motors, d)
		end
	end
	local progress = true
	while progress do
		progress = false
		for _, m in ipairs(motors) do
			local p0, p1 = m.Part0, m.Part1
			if p0 and p1 and rest[p0.Name] and not rest[p1.Name] then
				rest[p1.Name] = rest[p0.Name] * m.C0 * m.C1:Inverse()
				progress = true
			end
		end
	end
	return rest, char:FindFirstChild("UpperTorso") and "R15" or "R6"
end
Cosmetics.restPose = restPose

-- attachToRig(char, model, slot) -> animated, static, rigType. Replaces the model's rigid welds: every piece is welded to the body
-- part of its bone (costume pieces carry their own bone, head/back accessories the Head/UpperTorso, the aura stays on the root).
-- A piece whose body part or Motor6D rest pose is missing is welded to the root instead and counted as static.
local function attachToRig(char, model, slot)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local rest, rigType = restPose(char)
	local root = model.PrimaryPart
	local anchorId = slot == "costume" and "Root" or (Rig.SLOT_BONE[slot] or "Root")
	local anchorName = Rig.partName(anchorId, rigType)
	local anchorRest = (anchorName and rest[anchorName]) or CFrame.new()
	local base = slot == "costume" and CFrame.new() or anchorRest
	local rootInv = root.CFrame:Inverse()
	local pieces = {}
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("WeldConstraint") then
					c:Destroy()
				end
			end
			table.insert(pieces, d)
		end
	end
	local animated, static = 0, 0
	for _, d in ipairs(pieces) do
		local boneId = slot == "costume" and d:GetAttribute("bone") or Rig.SLOT_BONE[slot]
		local partName = boneId and Rig.partName(boneId, rigType)
		local bonePart = partName and char:FindFirstChild(partName)
		local boneRest = partName and rest[partName]
		if not (bonePart and boneRest) then
			bonePart, boneRest, partName = hrp, CFrame.new(), "HumanoidRootPart"
		end
		local w = Instance.new("Weld")
		w.Part0 = bonePart
		w.Part1 = d
		w.C0 = boneRest:Inverse() * (base * (rootInv * d.CFrame))
		w.C1 = CFrame.new()
		w.Parent = d
		if partName == "HumanoidRootPart" and boneId ~= "Root" and boneId ~= nil then
			static += 1 -- wanted to follow a limb but the rig has no such part / rest pose
		elseif partName ~= "HumanoidRootPart" then
			animated += 1
		end
	end
	return animated, static, rigType
end

local function applyCustomChar()
	local snap = Custom.applied("char")
	local char = Services.Players.LocalPlayer.Character
	if not snap or not char then
		if state.customRec then
			clearCustomChar()
		end
		state.status.customChar = snap and "waiting for character" or "off"
		return
	end
	local text = Custom.encodeSnapshot(snap)
	local rec = state.customRec
	if rec and rec.char == char and rec.text == text and rec.scale == Settings.get("cosmetics.charScale") then
		if rec.costume then
			hideAvatar(char, rec) -- the game may add new visible parts (tools, accessories)
		end
		return
	end
	clearCustomChar()
	rec = { skins = {}, hidden = {}, char = char, text = text, scale = Settings.get("cosmetics.charScale"), costume = snap.sel.costume ~= "", animated = 0, static = 0 }
	local problems = {}
	for _, slot in ipairs(Custom.CHAR_SLOTS) do
		local id = snap.sel[slot]
		if id and id ~= "" then
			local anchor = ACCESSORY_ANCHOR[slot](char)
			local model, err
			if anchor then
				model, err = buildCustom("char", id, snap.look, slot)
			else
				err = "no body part for the " .. slot .. " slot"
			end
			if model then
				sanitize(model)
				model.Name = "MM2HubSkin"
				pcall(function()
					model:ScaleTo(rec.scale)
				end)
				model.Parent = char
				local animated, static, rigType = attachToRig(char, model, slot)
				rec.animated += animated
				rec.static += static
				rec.rigType = rigType
				table.insert(rec.skins, model)
			else
				table.insert(problems, tostring(err))
			end
		end
	end
	state.customRec = rec
	if rec.costume then
		hideAvatar(char, rec)
	end
	state.status.customChar = #problems > 0 and ("error: " .. table.concat(problems, "; ")) or "applied"
	local meshN, partN = 0, 0
	for _, sk in ipairs(rec.skins) do
		if sk:GetAttribute("mesh") == true then meshN += 1 else partN += 1 end
	end
	state.status.customCharRig = rec.animated > 0 and string.format("%s rest pose: %d pieces follow their body parts%s", tostring(rec.rigType), rec.animated, rec.static > 0 and (", " .. rec.static .. " attached to the root") or "")
		or (#rec.skins > 0 and "attached to the root (static): the model has no bone information or the rig has no Motor6D rest pose" or "")
	state.status.customCharMesh = meshN > 0 and partN == 0 and "smooth meshes" or (partN > 0 and "simple parts (meshes unavailable, see the model status above)" or "")
end

local function applyBody()
	local player = Services.Players.LocalPlayer
	local char = player.Character
	local on = Settings.get("cosmetics.bodyColorEnabled") or Settings.get("cosmetics.neon")
	if not on or not char then
		for part, orig in pairs(state.bodyOrig) do
			pcall(function()
				part.Color, part.Material = orig.color, orig.material
			end)
			state.bodyOrig[part] = nil
		end
		return
	end
	for part in pairs(state.bodyOrig) do
		if part.Parent == nil then
			state.bodyOrig[part] = nil -- a part of a previous (respawned) character
		end
	end
	local c = Settings.get("cosmetics.bodyColor")
	local color = Color3.fromRGB(c.r, c.g, c.b)
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if not state.bodyOrig[d] then
				state.bodyOrig[d] = { color = d.Color, material = d.Material }
			end
			if Settings.get("cosmetics.bodyColorEnabled") then
				d.Color = color
			else
				d.Color = state.bodyOrig[d].color
			end
			d.Material = Settings.get("cosmetics.neon") and Enum.Material.Neon or state.bodyOrig[d].material
		end
	end
end

local function applyAll()
	if not state then
		return
	end
	state.dirty = false
	for name, slot in pairs(toolSlots()) do
		applyTools(name, slot)
	end
	applyChar()
	applyCustomChar()
	applyBody()
end

-- Public API -----------------------------------------------------------------------------------------------------------------------------

-- reapply(): forget applied skins and apply from scratch (after changing offsets or sources)
function Cosmetics.reapply()
	if not state then
		return
	end
	clearCustomChar() -- before the tools, so the tool restore is the last word on their transparency
	for name in pairs(toolSlots()) do
		clearTools(name)
	end
	clearChar()
	for key, entry in pairs(cache) do
		if entry.err then
			cache[key] = nil
		elseif string.find(key, "|custom:", 1, true) then
			-- templates of old custom looks are not kept: the cache must not grow with every colour change
			if entry.model then
				entry.model:Destroy()
			end
			cache[key] = nil
		end
	end
	applyAll()
end

function Cosmetics.status()
	return state and table.clone(state.status) or {}
end

-- effectStats() -> { lights, trails, emitters } currently alive in applied skins (a test and diagnostics aid)
function Cosmetics.effectStats()
	local n = { lights = 0, trails = 0, emitters = 0 }
	if not state then
		return n
	end
	local function scan(model)
		if not model then
			return
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				n.lights += 1
			elseif d:IsA("Trail") then
				n.trails += 1
			elseif d:IsA("ParticleEmitter") then
				n.emitters += 1
			end
		end
	end
	for _, list in pairs(state.tools) do
		for _, rec in pairs(list) do
			scan(rec.skin)
		end
	end
	if state.customRec then
		for _, sk in ipairs(state.customRec.skins) do
			scan(sk)
		end
	end
	return n
end

function Cosmetics.isRunning()
	return state ~= nil
end

function Cosmetics.start(ctx)
	assert(state == nil, "Cosmetics already started")
	state = { tools = { gun = {}, knife = {} }, charRecord = nil, customRec = nil, bodyOrig = {}, status = { gun = "off", knife = "off", char = "off", customChar = "off" }, dirty = true }
	ctx.maid:Give(function()
		if not state then
			return
		end
		clearCustomChar()
		for name in pairs(toolSlots()) do
			clearTools(name)
		end
		clearChar()
		for part, orig in pairs(state.bodyOrig) do
			pcall(function()
				part.Color, part.Material = orig.color, orig.material
			end)
		end
		for _, entry in pairs(cache) do
			if entry.model then
				entry.model:Destroy()
			end
		end
		table.clear(cache)
		MeshCache.reset()
		state = nil
	end)
	for _, key in ipairs(Settings.keys({ category = "cosmetics" })) do
		ctx.maid:Give(Settings.observe(key, function()
			if state then
				state.dirty = true
			end
		end))
	end
	for _, cat in ipairs({ "custom" }) do
		for _, key in ipairs(Settings.keys({ category = cat, includeHidden = true })) do
			ctx.maid:Give(Settings.observe(key, function()
				if state then
					state.dirty = true
				end
			end))
		end
	end
	for _, kind in ipairs(Custom.KINDS) do
		for _, f in ipairs({ "applied", "enabled" }) do
			ctx.maid:Give(Settings.observe(Custom.key(kind, f), function()
				if state then
					state.needsReset = true
				end
			end))
		end
	end
	for _, key in ipairs({ "perf.lowProfile", "ui.reduceEffects" }) do
		ctx.maid:Give(Settings.observe(key, function()
			if state then
				state.needsReset = true
			end
		end))
	end
	-- skin changes need a clean re-apply; routine scans only fill in what is missing
	for _, key in ipairs({
		"cosmetics.gunSource", "cosmetics.gunScale", "cosmetics.gunOffsetX", "cosmetics.gunOffsetY", "cosmetics.gunOffsetZ", "cosmetics.gunRotY",
		"cosmetics.knifeSource", "cosmetics.knifeScale", "cosmetics.knifeOffsetX", "cosmetics.knifeOffsetY", "cosmetics.knifeOffsetZ", "cosmetics.knifeRotY",
		"cosmetics.charSource", "cosmetics.charAttach", "cosmetics.charScale", "cosmetics.charOffsetY", "cosmetics.gunTool", "cosmetics.knifeTool",
	}) do
		ctx.maid:Give(Settings.observe(key, function()
			if state then
				state.needsReset = true
			end
		end))
	end
	ctx.maid:Give(MeshCache.Ready:Connect(function()
		if state then
			state.needsReset = true -- meshes became ready (or failed): rebuild the skins so they use them
		end
	end))
	ctx.maid:Give(Settings.observe("custom.useMeshes", function()
		if state then
			state.needsReset = true
		end
	end))
	local h = Perf.every("cosmetics.scan", 2, function()
		if not state then
			return
		end
		if state.needsReset then
			state.needsReset = false
			Cosmetics.reapply()
		elseif state.dirty or true then
			applyAll()
		end
	end)
	ctx.maid:Give(h.Cancel)
	applyAll()
end

return Cosmetics

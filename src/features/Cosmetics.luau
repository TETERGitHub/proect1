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

-- buildCustom(kind, id, look, slotId) -> Model (root at the origin, parts welded) | nil, err
local function buildCustom(kind, id, look, slotId)
	local imported = string.match(tostring(id), "^import:([%w_]+)$")
	if imported then
		-- a real mesh you imported (tools/convert_mesh.py): own textures, only the light/sparkle effects apply
		local m, err = Meshes.build(kind, imported)
		if m then
			addEffects(m, kind, look, slotId)
		end
		return m, err
	end
	if not Lib.has(kind, id) then
		return nil, "unknown model '" .. tostring(id) .. "'"
	end
	local model = Instance.new("Model")
	model.Name = "Skin_" .. id
	local root = newRoot(model)
	instantiate(model, root, Lib.parts(kind, id, look))
	weldAll(model)
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
	local model = Instance.new("Model")
	model.Name = "Preview_" .. id
	local root = newRoot(model)
	instantiate(model, root, Lib.parts(kind, id, look))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		end
	end
	return model
end

-- buildPreviewChar(sel, look) -> Model: a neutral mannequin (or the chosen costume) with the chosen accessories attached at
-- the same anchor offsets the live builder uses. It is a separate model in the preview window and never touches your avatar.
local PREVIEW_ANCHOR_Y = { head = 1.9, back = 0.6, aura = 0 }

function Cosmetics.buildPreviewChar(sel, look)
	local rig = Instance.new("Model")
	rig.Name = "Preview_char"
	local root = newRoot(rig)
	local function piece(name, size, y, x)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = Color3.fromRGB(196, 198, 206)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.CFrame = root.CFrame * CFrame.new(x or 0, y, 0)
		p.Parent = rig
	end
	local costume = sel.costume and sel.costume ~= "" and sel.costume or nil
	if costume then
		local m = Cosmetics.buildPreview("char", costume, look)
		if m then
			m.Parent = rig
		end
	else
		piece("Head", Vector3.new(1.1, 1.1, 1.1), 1.9)
		piece("Torso", Vector3.new(2, 2, 1), 0.4)
		piece("ArmL", Vector3.new(1, 2, 1), 0.4, 1.5)
		piece("ArmR", Vector3.new(1, 2, 1), 0.4, -1.5)
		piece("LegL", Vector3.new(0.95, 2.1, 1), -1.95, 0.5)
		piece("LegR", Vector3.new(0.95, 2.1, 1), -1.95, -0.5)
	end
	for _, slot in ipairs({ "head", "back", "aura" }) do
		local id = sel[slot]
		if id and id ~= "" then
			local m = Cosmetics.buildPreview("char", id, look)
			if m then
				m.Parent = rig
				m:PivotTo(CFrame.new(0, PREVIEW_ANCHOR_Y[slot], 0))
			end
		end
	end
	return rig
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

local function hideAvatar(char, rec)
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) and not rec.hidden[d] and d.Name ~= "HumanoidRootPart" and not isSkin(d, char) then
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
	rec = { skins = {}, hidden = {}, char = char, text = text, scale = Settings.get("cosmetics.charScale"), costume = snap.sel.costume ~= "" }
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
				model:PivotTo(anchor.CFrame)
				model.Parent = char
				weldTo(anchor, model.PrimaryPart)
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
	for name in pairs(toolSlots()) do
		clearTools(name)
	end
	clearChar()
	clearCustomChar()
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
		for name in pairs(toolSlots()) do
			clearTools(name)
		end
		clearChar()
		clearCustomChar()
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

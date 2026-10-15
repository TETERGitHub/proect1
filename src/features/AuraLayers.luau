--!nonstrict
-- features/AuraLayers: extra layers that go with ANY aura style (classic or big), switched on the Aura page and coloured with
-- the aura's colours:
--   highlight  a pulsing colour fill over your character with a thin outline (Roblox Highlight on your own character)
--   spheres    glowing spheres circling you, each bobbing on its own sine wave, with light trails
--   feet       a turning ring at your feet, stars rising from it, and a double trail behind your feet while you walk
-- Built from the hub's own textures/meshes (features/FxKit). LOCAL ONLY: everything lives under your camera.
-- STATUS: implemented; verified against the mock layer only (not checked in Roblox).
-- Depends on: FxKit.

local import = ...
local FxKit = import("features/FxKit")

local AuraLayers = {}

local TAU = math.pi * 2
local sin, cos = math.sin, math.cos
local NEON = Enum.Material.Neon

local L = {}
L.__index = L

local function v3(x, y, z)
	return Vector3.new(x, y, z)
end

local function limb(char, names)
	for _, n in ipairs(names) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

function L:setColors(p, s)
	self.cp, self.cs = p, s
	if self.hl then
		self.hl.FillColor = p
		self.hl.OutlineColor = s
	end
	for _, it in ipairs(self.colored) do
		pcall(function()
			if it.kind == "part" then
				it.obj.Color = it.role == "s" and s or p
			else
				FxKit.setEmitterColor(it.obj, it.role == "s" and s or p)
			end
		end)
	end
end

function L:step(dt)
	if self.destroyed then
		return
	end
	if not self.root or not self.root.Parent then
		self:destroy()
		return
	end
	self.t += dt
	local t = self.t
	if self.hl then
		-- pulse: the fill breathes, the outline stays crisp
		self.hl.FillTransparency = 0.5 + 0.35 * (0.5 + 0.5 * sin(t * self.pulseSpeed))
	end
	local pos = self.root.Position
	local floorY = pos.Y - self.hip
	local parts, cfs = {}, {}
	for i, sp in ipairs(self.spheres) do
		local ang = sp.phase + t * 1.4
		local y = 2.2 + sin(t * 2.1 + sp.phase * 2) * 0.9 -- each sphere rides its own sine wave
		table.insert(parts, sp.part)
		table.insert(cfs, CFrame.new(pos.X + cos(ang) * 3.2 * self.s, floorY + y * self.s, pos.Z + sin(ang) * 3.2 * self.s))
	end
	if self.ring then
		table.insert(parts, self.ring)
		table.insert(cfs, CFrame.new(pos.X, floorY + 0.1, pos.Z) * CFrame.Angles(0, t * 0.9, 0))
	end
	if self.stars then
		table.insert(parts, self.stars)
		table.insert(cfs, CFrame.new(pos.X, floorY + 0.2, pos.Z))
	end
	for _, f in ipairs(self.feet) do
		if f.limb.Parent then
			table.insert(parts, f.holder)
			table.insert(cfs, f.limb.CFrame * CFrame.new(0, -f.limb.Size.Y / 2 + 0.15, 0))
		end
	end
	FxKit.moveAll(parts, cfs)
end

function L:destroy()
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

-- new{ character, highlight = bool, pulse = 0..1, spheres = n (0 = off), feet = bool, scale, primary, secondary, manual }
function AuraLayers.new(opts)
	local char = opts.character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	assert(root, "character has no HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	local folder = Instance.new("Folder")
	folder.Name = "MM2HubAuraLayers"
	folder.Parent = workspace.CurrentCamera
	local self = setmetatable({
		character = char, root = root, folder = folder, s = opts.scale or 1, t = 0, spheres = {}, feet = {}, colored = {},
		cp = opts.primary or Color3.fromRGB(176, 84, 255), cs = opts.secondary or Color3.fromRGB(90, 210, 255), destroyed = false, pulseSpeed = 1 + (opts.pulse or 0.5) * 5,
		hip = ((hum and hum.HipHeight) or 2) + root.Size.Y / 2,
	}, L)
	local p, s = self.cp, self.cs
	local built, buildErr = pcall(function()
	if opts.highlight then
		local ok, hl = pcall(function()
			local h = Instance.new("Highlight")
			h.Adornee = char
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.FillColor, h.OutlineColor = p, s
			h.FillTransparency, h.OutlineTransparency = 0.6, 0
			h.Parent = folder
			return h
		end)
		if ok then
			self.hl = hl
		end
	end
	for i = 1, math.clamp(opts.spheres or 0, 0, 8) do
		local ball = FxKit.part(folder, "Ball", v3(0.55, 0.55, 0.55) * self.s, i % 2 == 0 and s or p, NEON, 0)
		table.insert(self.colored, { kind = "part", obj = ball, role = i % 2 == 0 and "s" or "p" })
		local tr = FxKit.trail(ball, 0.45 * self.s, { color = i % 2 == 0 and s or p, life = 0.55, t = { 0.1, 1 } })
		if tr then
			table.insert(self.colored, { kind = "fx", obj = tr, role = i % 2 == 0 and "s" or "p" })
		end
		local glow = FxKit.emitter(ball, "glow", { rate = 6, size = { 1.6 * self.s, 0 }, life = { 0.25, 0.4 }, speed = { 0, 0 }, t = { 0.4, 1 }, lock = true })
		if glow then
			table.insert(self.colored, { kind = "fx", obj = glow, role = i % 2 == 0 and "s" or "p" })
		end
		table.insert(self.spheres, { part = ball, phase = (i - 1) / math.max(1, opts.spheres) * TAU })
	end
	if opts.feet then
		self.ring = FxKit.mesh(folder, "ring", v3(4.6, 0.6, 4.6) * self.s, p, NEON, 0.25, "Cylinder")
		table.insert(self.colored, { kind = "part", obj = self.ring, role = "p" })
		self.stars = FxKit.holder(folder)
		self.stars.Size = v3(4, 0.2, 4) * self.s
		local em = FxKit.emitter(self.stars, "star", { rate = 12, size = { 0.55 * self.s, 0 }, life = { 1, 1.8 }, speed = { 2, 5 }, spread = 15,
			accel = v3(0, 1.5, 0), spin = { -120, 120 }, surface = true })
		if em then
			table.insert(self.colored, { kind = "fx", obj = em, role = "s" })
		end
		-- double trail: one from each foot, in the two aura colours (visible while you move)
		local left = limb(char, { "LeftFoot", "LeftLowerLeg", "Left Leg" })
		local right = limb(char, { "RightFoot", "RightLowerLeg", "Right Leg" })
		for k, lb in ipairs({ left, right }) do
			if lb then
				local h = FxKit.holder(folder)
				local role = k == 1 and "p" or "s"
				local tr = FxKit.trail(h, 0.5 * self.s, { color = role == "s" and s or p, life = 0.6, t = { 0.15, 1 } })
				if tr then
					table.insert(self.colored, { kind = "fx", obj = tr, role = role })
				end
				table.insert(self.feet, { limb = lb, holder = h })
			end
		end
	end
	self:setColors(p, s)
	self:step(0)
	end)
	if not built then
		pcall(function()
			folder:Destroy()
		end)
		error(buildErr, 0)
	end
	if not opts.manual then
		local ok, conn = pcall(function()
			return game:GetService("RunService").RenderStepped:Connect(function(dt)
				self:step(math.min(dt, 0.05))
			end)
		end)
		if ok then
			self.conn = conn
		end
	end
	return self
end

return AuraLayers

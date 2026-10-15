--!nonstrict
-- features/HitFX: hit markers and bullet tracers, drawn from the hub's own textures (tools/make_hitfx.py, data/FxPack).
--   hit marker  when one of YOUR kills is confirmed (features/KillEvents), a marker pops at the screen centre and fades
--   tracer      when YOU fire your own gun, a glowing beam runs from the gun to where you aimed, with sparks at the end
-- Only what you see changes: the parts live under your camera, nothing is sent to the game, nobody else sees it, and the
-- aim point is just where your own mouse / screen centre points (no target information).
-- STATUS: implemented; verified against the mock layer only (not checked in Roblox).
-- Depends on: Settings, Perf, Env, Services, Logger, KillEvents, FxKit.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")
local KillEvents = import("features/KillEvents")
local FxKit = import("features/FxKit")

local HitFX = {}

-- order = the cells of hitmarkers.png (4 x 2 of 256 px)
HitFX.MARKERS = { "Classic", "Burst", "Diamond", "Skull", "Cross", "Spark", "Ring", "Heart" }
HitFX.TRACERS = { "Laser", "Energy", "Lightning", "Rainbow" }
local CELL = 256
local markerIndex = {}
for i, n in ipairs(HitFX.MARKERS) do
	markerIndex[n] = i
end

local state = nil

local function s(k)
	return Settings.get("hitfx." .. k)
end

local function rgbOf(k)
	local c = s(k)
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function seq(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- hit marker -------------------------------------------------------------------------------------------------------------

local function markerLabel(parent, name, z)
	local im = Instance.new("ImageLabel")
	im.Name = name
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.ImageRectSize = Vector2.new(CELL, CELL)
	im.ZIndex = z
	im.Visible = false
	im.Parent = parent
	return im
end

-- showMarker(): pops the marker (restarts it when one is already showing)
function HitFX.showMarker()
	if not state or not state.marker then
		return false
	end
	local url, outl = FxKit.asset("hitmarkers.png"), FxKit.asset("hitmarkers_outline.png")
	if not url then
		return false
	end
	local i = markerIndex[s("markerStyle")] or 1
	local off = Vector2.new(((i - 1) % 4) * CELL, math.floor((i - 1) / 4) * CELL)
	state.marker.main.Image, state.marker.main.ImageRectOffset = url, off
	state.marker.outline.Image, state.marker.outline.ImageRectOffset = outl or "", off
	state.markerT = 0
	return true
end

local function stepMarker(dt)
	local m, t = state.marker, state.markerT
	if not m or t == nil then
		return
	end
	t += dt
	state.markerT = t
	local life = s("markerTime")
	if t >= life then
		m.main.Visible, m.outline.Visible = false, false
		state.markerT = nil
		return
	end
	-- pop in big, settle, then fade out over the last 40%
	local pop = t < 0.08 and (1.45 - 0.45 * (t / 0.08)) or 1
	local fade = math.clamp((t - life * 0.6) / (life * 0.4), 0, 1)
	local px = s("markerSize") * pop
	local col = rgbOf("markerColor")
	for _, im in ipairs({ m.main, m.outline }) do
		im.Visible = im.Image ~= ""
		im.Size = UDim2.fromOffset(px, px)
		im.Rotation = (1 - pop) * -18
	end
	m.main.ImageColor3, m.main.ImageTransparency = col, fade
	m.outline.ImageColor3, m.outline.ImageTransparency = Color3.fromRGB(0, 0, 0), math.min(1, 0.25 + fade)
end

-- tracers ----------------------------------------------------------------------------------------------------------------

local function rainbow()
	local kps = {}
	for i = 0, 6 do
		table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.8, 1)))
	end
	return ColorSequence.new(kps)
end

-- tracer(from, to) -> true when drawn. Draws one tracer from `from` to `to` (Vector3) in the chosen style.
function HitFX.tracer(from, to)
	if not state then
		return false
	end
	local style = s("tracerStyle")
	local cam = workspace.CurrentCamera
	local ok, item = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "MM2HubTracer"
		folder.Parent = cam
		local p0, p1 = FxKit.holder(folder, CFrame.new(from)), FxKit.holder(folder, CFrame.new(to))
		local w = s("tracerWidth")
		local col = rgbOf("tracerColor")
		local tex = style == "Energy" and "tracer_energy" or style == "Lightning" and "bolt" or "tracer"
		local beams = {}
		local main = FxKit.beam(p0, p1, {
			tex = tex, width0 = w, width1 = w * 0.8, color = style == "Rainbow" and rainbow() or col, t = { 0, 0 },
			segments = style == "Lightning" and 12 or 2, speed = style == "Energy" and 6 or style == "Lightning" and 14 or 0,
			repeatLength = style == "Energy" and 3 or style == "Lightning" and 6 or (to - from).Magnitude + 1,
		})
		table.insert(beams, main)
		-- a wide soft glow under the core
		table.insert(beams, FxKit.beam(p0, p1, { tex = "tracer", width0 = w * 3, width1 = w * 2, t = { 0.6, 0.75 },
			color = style == "Rainbow" and rainbow() or col, segments = 2, repeatLength = (to - from).Magnitude + 1 }))
		if s("impact") then
			local em = FxKit.emitter(p1, "spark", { rate = 0, size = { 0.35, 0.05 }, life = { 0.2, 0.45 }, speed = { 8, 20 }, spread = 70,
				accel = Vector3.new(0, -30, 0), drag = 3, squash = true, color = col })
			local flash = FxKit.emitter(p1, "glow", { rate = 0, size = { 2.2, 0 }, life = { 0.12, 0.18 }, speed = { 0, 0 }, color = col })
			local muzzle = FxKit.emitter(p0, "glow", { rate = 0, size = { 1.4, 0 }, life = { 0.08, 0.12 }, speed = { 0, 0 }, color = col })
			pcall(function()
				if em then
					em:Emit(16)
				end
				if flash then
					flash:Emit(1)
				end
				if muzzle then
					muzzle:Emit(1)
				end
			end)
		end
		return { folder = folder, beams = beams, age = 0, life = s("tracerLife"), width = w }
	end)
	if not ok then
		Logger.warn("HitFX", "tracer failed: %s", tostring(item))
		return false
	end
	table.insert(state.tracers, item)
	-- never more than a handful alive (fast fire)
	while #state.tracers > 12 do
		local old = table.remove(state.tracers, 1)
		pcall(function()
			old.folder:Destroy()
		end)
	end
	return true
end

local function stepTracers(dt)
	for i = #state.tracers, 1, -1 do
		local tr = state.tracers[i]
		tr.age += dt
		local k = tr.age / tr.life
		if k >= 1 then
			-- keep the parts a little longer so the impact sparks can finish, beams already gone
			for _, b in ipairs(tr.beams) do
				if b then
					b.Enabled = false
				end
			end
			if tr.age >= tr.life + 0.5 then
				pcall(function()
					tr.folder:Destroy()
				end)
				table.remove(state.tracers, i)
			end
		else
			local fade = k * k
			for j, b in ipairs(tr.beams) do
				if b then
					local base = j == 1 and 0 or 0.6
					b.Transparency = seq(base + (1 - base) * fade, base + (1 - base) * math.min(1, fade + 0.15))
					b.Width0 = (j == 1 and 1 or 3) * tr.width * (1 - k * 0.6)
				end
			end
		end
	end
end

-- where the shot goes: the point under your mouse (or the screen centre when the mouse is locked), first thing hit
local function aimPoint(from)
	local cam = workspace.CurrentCamera
	local uis = Services.UserInputService
	local ok, pos = pcall(function()
		local vp = cam.ViewportSize
		local x, y = vp.X / 2, vp.Y / 2
		if uis and uis.MouseBehavior == Enum.MouseBehavior.Default then
			local m = uis:GetMouseLocation()
			x, y = m.X, m.Y
		end
		local ray = cam:ViewportPointToRay(x, y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local lp = Services.Players.LocalPlayer
		params.FilterDescendantsInstances = { lp and lp.Character, cam }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
		return hit and hit.Position or (ray.Origin + ray.Direction * 600)
	end)
	if ok and pos then
		return pos
	end
	return from + cam.CFrame.LookVector * 100
end

local function muzzleOf(tool)
	local handle = tool and tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle.Position
	end
	local lp = Services.Players.LocalPlayer
	local char = lp and lp.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart"))
	return hand and hand.Position or nil
end

-- test(): marker and a tracer from your character 40 studs ahead (the page's preview button)
function HitFX.test()
	if not state then
		return false, "Hit effects are not running."
	end
	HitFX.showMarker()
	local lp = Services.Players.LocalPlayer
	local root = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return true
	end
	local from = root.Position + Vector3.new(0, 1.5, 0)
	return HitFX.tracer(from, from + root.CFrame.LookVector * 40), nil
end

function HitFX.activeTracers()
	return state and #state.tracers or 0
end

function HitFX.markerVisible()
	return state ~= nil and state.marker ~= nil and state.marker.main.Visible
end

function HitFX.start(ctx)
	assert(state == nil, "HitFX already started")
	state = { tracers = {}, markerT = nil }
	ctx.maid:Give(function()
		for _, tr in ipairs(state.tracers) do
			pcall(function()
				tr.folder:Destroy()
			end)
		end
		state = nil
	end)
	local parent = Env.guiParent()
	if parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "MM2HubHitMarker"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 6
		gui.Parent = parent
		ctx.maid:Give(gui)
		state.marker = { outline = markerLabel(gui, "Outline", 1), main = markerLabel(gui, "Marker", 2) }
	end
	ctx.maid:Give(KillEvents.Confirmed:Connect(function()
		if s("marker") then
			HitFX.showMarker()
		end
	end))
	ctx.maid:Give(KillEvents.Used:Connect(function(ev)
		if ev.role == "sheriff" and s("tracer") then
			local from = muzzleOf(ev.tool)
			if from then
				HitFX.tracer(from, aimPoint(from))
			end
		end
	end))
	local handle = Perf.every("hitfx", 60, function(dt)
		if state then
			stepMarker(dt)
			stepTracers(dt)
		end
	end, { visual = true })
	ctx.maid:Give(handle.Cancel)
end

return HitFX

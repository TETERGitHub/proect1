--!nonstrict
-- features/Camera: client camera preferences: mouse sensitivity, scroll-zoom control with
-- smoothing and respawn memory, camera mode, FOV override, optional head bob and local
-- own-character opacity. Original values are captured on start and restored on stop or
-- when the individual feature is switched off.
-- STATUS: env-dependent (writes engine properties that games may also write).
-- Depends on: Settings, Perf, Services, Logger.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Logger = import("core/Logger")

local Camera = {}

local state = nil

local function s(name)
	return Settings.get("camera." .. name)
end

local function player()
	return Services.Players.LocalPlayer
end

local function cam()
	local ws = Services.Workspace
	return ws and ws.CurrentCamera
end

local function humanoid()
	local p = player()
	local c = p and p.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

-- Sensitivity -------------------------------------------------------------------------------------------

local function applySensitivity()
	local uis = Services.UserInputService
	if s("sensitivityEnabled") then
		uis.MouseDeltaSensitivity = s("sensitivity")
	else
		uis.MouseDeltaSensitivity = state.orig.sensitivity
	end
end

-- Camera mode ------------------------------------------------------------------------------------------------

local function applyMode()
	local p = player()
	local mode = s("mode")
	if mode == "FirstPerson" then
		p.CameraMode = Enum.CameraMode.LockFirstPerson
	elseif mode == "ThirdPerson" then
		p.CameraMode = Enum.CameraMode.Classic
	else
		p.CameraMode = state.orig.mode
	end
end

-- Zoom --------------------------------------------------------------------------------------------------------------

local function currentDistance()
	local c = cam()
	if not c then
		return nil
	end
	local d = (c.CFrame.Position - c.Focus.Position).Magnitude
	return d
end

local function restoreZoomLimits()
	local p = player()
	p.CameraMinZoomDistance = state.orig.minZoom
	p.CameraMaxZoomDistance = state.orig.maxZoom
end

local function zoomActive()
	return s("zoomEnabled") and s("mode") ~= "FirstPerson"
end

local function setTarget(v)
	state.zoomTarget = math.clamp(v, s("minZoom"), s("maxZoom"))
end

local function zoomTick(dt)
	if not zoomActive() then
		return
	end
	local current = currentDistance()
	if not current then
		return
	end
	local p = player()
	local smoothing = s("smoothing")
	local k = smoothing <= 0 and 1 or math.clamp(dt * (18 * (1 - smoothing) + 2), 0, 1)
	state.zoomCurrent = (state.zoomCurrent or current)
	state.zoomCurrent = state.zoomCurrent + (state.zoomTarget - state.zoomCurrent) * k
	local z = math.clamp(state.zoomCurrent, s("minZoom"), s("maxZoom"))
	p.CameraMinZoomDistance = z
	p.CameraMaxZoomDistance = z
end

-- onWheel(direction): +1 zoom in, -1 zoom out
function Camera.onWheel(direction)
	if not state or not zoomActive() then
		return
	end
	local base = state.zoomTarget or currentDistance() or 12
	local step = (0.8 + base * 0.12) * s("zoomSpeed")
	setTarget(base - direction * step)
	if s("rememberZoom") then
		state.pendingRemember = true
	end
end

-- FOV -------------------------------------------------------------------------------------------------------------------

local function fovTick(dt)
	local c = cam()
	if not c then
		return
	end
	if s("fovEnabled") then
		local target = s("fov")
		local smoothing = s("smoothing")
		local k = smoothing <= 0 and 1 or math.clamp(dt * (14 * (1 - smoothing) + 2), 0, 1)
		if math.abs(c.FieldOfView - target) > 0.05 then
			c.FieldOfView = c.FieldOfView + (target - c.FieldOfView) * k
		end
		state.fovOwned = true
	elseif state.fovOwned then
		-- hand control back: ease to the value we found at start
		if math.abs(c.FieldOfView - state.orig.fov) > 0.1 then
			c.FieldOfView = c.FieldOfView + (state.orig.fov - c.FieldOfView) * 0.35
		else
			c.FieldOfView = state.orig.fov
			state.fovOwned = false
		end
	end
end

-- Head bob --------------------------------------------------------------------------------------------------------------------

local function bobTick(dt)
	local hum = humanoid()
	if not hum then
		return
	end
	local intensity = s("bobIntensity")
	if s("disableEffects") or intensity <= 0 then
		if state.bobOwned then
			hum.CameraOffset = Vector3.new(0, 0, 0)
			state.bobOwned = false
		end
		return
	end
	local move = hum.MoveDirection
	local speed = move.Magnitude * hum.WalkSpeed
	state.bobTime += dt * (speed * 0.55)
	local amp = intensity * math.clamp(speed / 16, 0, 1.5)
	hum.CameraOffset = Vector3.new(math.sin(state.bobTime) * 0.05 * amp, math.abs(math.sin(state.bobTime)) * 0.08 * amp, 0)
	state.bobOwned = true
end

-- Own character opacity -----------------------------------------------------------------------------------------------------------

local function opacityTick()
	if Settings.get("ghost.enabled") then
		return -- the Ghost module owns LocalTransparencyModifier while it is on
	end
	local p = player()
	local char = p and p.Character
	if not char then
		return
	end
	local o = s("ownOpacity")
	if o >= 0.999 then
		if state.opacityOwned then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
			state.opacityOwned = false
		end
		return
	end
	local mod = 1 - o
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= mod then
			d.LocalTransparencyModifier = mod
		end
	end
	state.opacityOwned = true
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------------------

function Camera.start(ctx)
	assert(state == nil, "Camera already started")
	local p = player()
	local c = cam()
	state = {
		orig = {
			sensitivity = Services.UserInputService.MouseDeltaSensitivity,
			minZoom = p.CameraMinZoomDistance,
			maxZoom = p.CameraMaxZoomDistance,
			mode = p.CameraMode,
			fov = c and c.FieldOfView or 70,
		},
		zoomTarget = s("preferredZoom"),
		zoomCurrent = nil,
		bobTime = 0,
		bobOwned = false,
		opacityOwned = false,
		fovOwned = false,
		pendingRemember = false,
	}
	ctx.maid:Give(function()
		if not state then
			return
		end
		pcall(function()
			Services.UserInputService.MouseDeltaSensitivity = state.orig.sensitivity
			restoreZoomLimits()
			player().CameraMode = state.orig.mode
			local cm = cam()
			if cm then
				cm.FieldOfView = state.orig.fov
			end
			local hum = humanoid()
			if hum then
				hum.CameraOffset = Vector3.new(0, 0, 0)
			end
		end)
		state = nil
	end)

	for _, k in ipairs({ "sensitivityEnabled", "sensitivity" }) do
		ctx.maid:Give(Settings.observe("camera." .. k, applySensitivity))
	end
	ctx.maid:Give(Settings.observe("camera.mode", function()
		applyMode()
		if zoomActive() then
			state.zoomTarget = state.zoomTarget or currentDistance()
		end
	end))
	ctx.maid:Give(Settings.observe("camera.zoomEnabled", function(on)
		if on then
			state.zoomTarget = currentDistance() or s("preferredZoom")
			state.zoomCurrent = nil
		else
			restoreZoomLimits()
		end
	end))
	for _, k in ipairs({ "minZoom", "maxZoom" }) do
		ctx.maid:Give(Settings.observe("camera." .. k, function()
			if zoomActive() then
				setTarget(state.zoomTarget or 12)
			end
		end))
	end

	ctx.maid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			Camera.onWheel(input.Position.Z)
		end
	end))

	local function onCharacter(char)
		if s("rememberZoom") and zoomActive() then
			task.defer(function()
				if state then
					state.zoomTarget = s("preferredZoom")
					state.zoomCurrent = nil
				end
			end)
		end
	end
	ctx.maid:Give(p.CharacterAdded:Connect(onCharacter))

	local h1 = Perf.every("camera.zoom", 60, function(dt)
		zoomTick(dt)
		if state.pendingRemember and state.zoomTarget then
			state.pendingRemember = false
			Settings.set("camera.preferredZoom", state.zoomTarget, "camera")
		end
	end, { visual = true })
	local h2 = Perf.every("camera.fov", 30, fovTick, { visual = true })
	local h3 = Perf.every("camera.bob", 60, bobTick, { visual = true })
	local h4 = Perf.every("camera.opacity", 10, opacityTick, { visual = true })
	for _, h in ipairs({ h1, h2, h3, h4 }) do
		ctx.maid:Give(h.Cancel)
	end

	applySensitivity()
	applyMode()
	if zoomActive() then
		state.zoomTarget = s("preferredZoom")
	end
	Logger.info("Camera", "started (orig fov %.0f, zoom %.1f-%.0f)", state.orig.fov, state.orig.minZoom, state.orig.maxZoom)
end

-- reset(): back to defaults for every camera setting and engine values restored.
function Camera.reset()
	local n = Settings.resetModule("Camera")
	if state then
		applySensitivity()
		applyMode()
		restoreZoomLimits()
	end
	return n
end

function Camera.isRunning()
	return state ~= nil
end

function Camera.zoomTarget()
	return state and state.zoomTarget or nil
end

return Camera

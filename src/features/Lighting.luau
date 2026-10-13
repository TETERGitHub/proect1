--!nonstrict
-- features/Lighting: local lighting preferences. Owns three effect instances (ColorCorrection,
-- Blur, Bloom) that are created only while enabled and destroyed on stop; touches
-- Lighting.Brightness / ClockTime / ambient only while the matching override is on and restores
-- the originals afterwards. A 2 Hz task re-applies values the game overwrote.
-- STATUS: implemented; the game may rewrite Lighting (documented limitation).
-- Depends on: Settings, Perf, Services, LightingMath.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local LM = import("features/LightingMath")
local Logger = import("core/Logger")

local Lighting = {}

local state = nil

local function s(name)
	return Settings.get("lighting." .. name)
end

local function ensure(kind, name)
	local lighting = Services.Lighting
	local inst = state.effects[name]
	if inst and inst.Parent then
		return inst
	end
	inst = Instance.new(kind)
	inst.Name = "MM2Hub" .. name
	inst.Parent = lighting
	state.effects[name] = inst
	return inst
end

local function drop(name)
	local inst = state.effects[name]
	if inst then
		inst:Destroy()
		state.effects[name] = nil
	end
end

local function rgb(t)
	return Color3.fromRGB(t[1] or t.r, t[2] or t.g, t[3] or t.b)
end

local function applyEffects()
	local low = Perf.isLow()
	local noFx = Settings.get("camera.disableEffects")
	-- colour correction
	if s("colorEnabled") then
		local cc = ensure("ColorCorrectionEffect", "CC")
		local v = LM.combine({ saturation = s("saturation"), contrast = s("contrast"), exposure = s("exposure"), tint = s("tint") }, s("filter"))
		cc.Saturation, cc.Contrast, cc.Brightness = v.saturation, v.contrast, v.exposure
		cc.TintColor = Color3.fromRGB(v.tint.r, v.tint.g, v.tint.b)
		cc.Enabled = true
	else
		drop("CC")
	end
	-- blur
	if s("blurEnabled") and not low and not noFx then
		local b = ensure("BlurEffect", "Blur")
		b.Size = s("blurSize")
		b.Enabled = true
	else
		drop("Blur")
	end
	-- bloom
	if s("bloomEnabled") and not low then
		local b = ensure("BloomEffect", "Bloom")
		b.Intensity, b.Size, b.Threshold = s("bloomIntensity"), s("bloomSize"), s("bloomThreshold")
		b.Enabled = true
	else
		drop("Bloom")
	end
end

local function applyWorld()
	local l = Services.Lighting
	local orig = state.orig
	if s("brightnessEnabled") then
		if l.Brightness ~= s("brightness") then
			l.Brightness = s("brightness")
		end
	elseif state.worldOwned.brightness then
		l.Brightness = orig.Brightness
	end
	state.worldOwned.brightness = s("brightnessEnabled")

	local preset = LM.times[s("timePreset")]
	if preset then
		if l.ClockTime ~= preset.clock then
			l.ClockTime = preset.clock
		end
		l.Ambient = rgb(preset.ambient)
		l.OutdoorAmbient = rgb(preset.outdoor)
		state.worldOwned.time = true
	elseif state.worldOwned.time then
		l.ClockTime, l.Ambient, l.OutdoorAmbient = orig.ClockTime, orig.Ambient, orig.OutdoorAmbient
		state.worldOwned.time = false
	end
end

local function applyAll()
	if not state then
		return
	end
	applyEffects()
	applyWorld()
end

function Lighting.start(ctx)
	assert(state == nil, "Lighting already started")
	local l = Services.Lighting
	state = {
		effects = {},
		worldOwned = { brightness = false, time = false },
		orig = { Brightness = l.Brightness, ClockTime = l.ClockTime, Ambient = l.Ambient, OutdoorAmbient = l.OutdoorAmbient },
	}
	ctx.maid:Give(function()
		if not state then
			return
		end
		pcall(function()
			for name in pairs(table.clone(state.effects)) do
				drop(name)
			end
			l.Brightness, l.ClockTime, l.Ambient, l.OutdoorAmbient = state.orig.Brightness, state.orig.ClockTime, state.orig.Ambient, state.orig.OutdoorAmbient
		end)
		state = nil
	end)
	for _, key in ipairs(Settings.keys({ category = "lighting" })) do
		ctx.maid:Give(Settings.observe(key, applyAll))
	end
	ctx.maid:Give(Settings.observe("camera.disableEffects", applyAll))
	ctx.maid:Give(Perf.LowChanged:Connect(applyAll))
	local h = Perf.every("lighting.enforce", 2, applyWorld)
	ctx.maid:Give(h.Cancel)
	applyAll()
	Logger.info("Lighting", "started")
end

-- reset(): restores every lighting setting to default and the engine to its original values.
function Lighting.reset()
	local n = Settings.resetModule("Lighting")
	applyAll()
	return n
end

function Lighting.isRunning()
	return state ~= nil
end

function Lighting.effectCount()
	if not state then
		return 0
	end
	local n = 0
	for _ in pairs(state.effects) do
		n += 1
	end
	return n
end

return Lighting

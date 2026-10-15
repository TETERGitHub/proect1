--!nonstrict
-- features/Aura: puts the owner-supplied aura effect (features/AuraVFX) on YOUR character and keeps it in sync with the settings on
-- the Aura page: on/off, preset, which parts are shown, intensity, rainbow and your own two colours. Rebuilt after a respawn, removed
-- completely when switched off or when the hub unloads. Local to this client: nobody else sees it.
-- STATUS: implemented; verified against the mock layer only (the look has not been checked in Roblox).
-- Depends on: Settings, Services, Perf, Logger, AuraVFX.

local import = ...
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local Logger = import("core/Logger")
local VFX = import("features/AuraVFX")
local AuraFX = import("features/AuraFX")

local Aura = {}

Aura.PRESETS = { "Angel", "Inferno", "Frost", "Toxic", "Crimson", "Rainbow" }
Aura.PARTS = { "wings", "halo", "circle", "chains", "particles" }

local state = nil

local function s(name)
	return Settings.get("aura." .. name)
end

local function rgb(c)
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function destroyAura()
	if state and state.aura then
		pcall(function()
			state.aura:destroy()
		end)
		state.aura = nil
	end
end

local function sync()
	if not state then
		return
	end
	local char = Services.Players.LocalPlayer and Services.Players.LocalPlayer.Character
	if not s("enabled") or not char or not char:FindFirstChild("HumanoidRootPart") then
		destroyAura()
		state.status = s("enabled") and "waiting for your character" or "off"
		return
	end
	local a = state.aura
	local style = s("style")
	if a and (a.destroyed or a.character ~= char or state.builtScale ~= s("wingScale") or state.builtStyle ~= style) then
		destroyAura()
		a = nil
	end
	if not a then
		local ok, res
		if style == "Classic" then
			ok, res = pcall(VFX.new, { character = char, preset = s("preset"), wingScale = s("wingScale") })
		else
			ok, res = pcall(AuraFX.new, { character = char, style = style, scale = s("wingScale") })
		end
		if not ok then
			state.status = "error: " .. tostring(res)
			Logger.warn("Aura", "could not create the aura: %s", tostring(res))
			return
		end
		a = res
		state.aura, state.builtScale, state.builtStyle = a, s("wingScale"), style
	end
	if style ~= "Classic" then
		-- the big styles (features/AuraFX): own colours or the style's palette; the classic part switches do not apply
		local pal = AuraFX.palette[style] or AuraFX.palette[AuraFX.STYLES[1]]
		if s("customColors") then
			a:setColors(rgb(s("primary")), rgb(s("secondary")))
		else
			a:setColors(pal[1], pal[2])
		end
		a:setRainbow(s("rainbow"))
		a:setIntensity(s("intensity"))
		state.status = "on (" .. style .. ")"
		return
	end
	local preset = VFX.presets[s("preset")] or VFX.presets.Angel
	if s("customColors") then
		a:setColors(rgb(s("primary")), rgb(s("secondary")))
	else
		a:setColors(preset.primary, preset.secondary)
	end
	a:setRainbow(s("rainbow") or preset.rainbow == true)
	a:setIntensity(s("intensity"))
	for _, part in ipairs(Aura.PARTS) do
		local on = s(part) and true or false
		if part == "particles" and (Perf.isLow() or Settings.get("ui.reduceEffects")) then
			on = false -- particles and the light are the expensive part
		end
		if (a.features[part] and true or false) ~= on then
			a:toggle(part, on)
		end
	end
	state.status = "on"
end

function Aura.status()
	return state and state.status or "off"
end

function Aura.current()
	return state and state.aura
end

function Aura.start(ctx)
	assert(state == nil, "Aura already started")
	state = { status = "off" }
	ctx.maid:Give(function()
		destroyAura()
		state = nil
	end)
	for _, key in ipairs(Settings.keys({ module = "Aura", includeHidden = true })) do
		ctx.maid:Give(Settings.observe(key, sync))
	end
	ctx.maid:Give(Settings.observe("ui.reduceEffects", sync))
	local lp = Services.Players.LocalPlayer
	if lp then
		ctx.maid:Give(lp.CharacterAdded:Connect(function(char)
			task.spawn(function()
				char:WaitForChild("HumanoidRootPart", 10)
				sync() -- after unload state is nil and sync does nothing
			end)
		end))
	end
	sync()
end

return Aura

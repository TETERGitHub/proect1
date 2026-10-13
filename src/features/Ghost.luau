--!nonstrict
-- features/Ghost: local-only invisibility of YOUR character.
--   * Visual transparency: BasePart.LocalTransparencyModifier (never replicates) plus face decals,
--     with an eased fade between the current and target opacity.
--   * Character state: tracks respawns, accessories/tools added later, death (optional reveal),
--     and restores every touched value when switched off or when the hub unloads.
--   * Name tag: Humanoid.DisplayDistanceType is set to None locally and restored.
-- It does NOT make you invisible to others and does not move or resize your hitbox; the game and the
-- server keep seeing your character exactly as before.
-- STATUS: implemented; behaviour verified against the mock layer. Games/camera scripts that also write
-- LocalTransparencyModifier are re-overridden at 15 Hz.
-- Depends on: Settings, Perf, Services, Maid, Logger.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Maid = import("core/Maid")
local Logger = import("core/Logger")

local Ghost = {}

local state = nil

local function s(name)
	return Settings.get("ghost." .. name)
end

local function inside(inst, className, stopAt)
	local p = inst.Parent
	while p and p ~= stopAt do
		if p:IsA(className) then
			return true
		end
		p = p.Parent
	end
	return false
end

-- wanted(part) -> boolean: does the current configuration include this descendant?
local function wanted(char, d)
	if d:IsA("BasePart") then
		if d.Name == "HumanoidRootPart" then
			return false -- invisible anyway; leaving it alone avoids touching physics-related defaults
		end
		if not s("includeAccessories") and inside(d, "Accessory", char) then
			return false
		end
		if not s("includeTools") and inside(d, "Tool", char) then
			return false
		end
		return true
	end
	if d:IsA("Decal") or d:IsA("Texture") then
		return s("includeFace") and d.Parent and d.Parent.Name == "Head"
	end
	return false
end

local function track(char, d)
	if state.items[d] == nil and wanted(char, d) then
		if d:IsA("BasePart") then
			state.items[d] = { kind = "part" }
		else
			state.items[d] = { kind = "decal", original = d.Transparency }
		end
	end
end

local function rebuild(char)
	-- restore anything we touched before switching character / configuration
	Ghost._restoreItems()
	state.items = {}
	if not char then
		return
	end
	for _, d in ipairs(char:GetDescendants()) do
		track(char, d)
	end
end

function Ghost._restoreItems()
	if not state then
		return
	end
	for inst, info in pairs(state.items) do
		pcall(function()
			if info.kind == "part" then
				inst.LocalTransparencyModifier = 0
			else
				inst.Transparency = info.original
			end
		end)
	end
end

local function restoreName()
	if state.nameHum and state.nameOriginal ~= nil then
		pcall(function()
			state.nameHum.DisplayDistanceType = state.nameOriginal
		end)
	end
	state.nameHum, state.nameOriginal = nil, nil
end

local function character()
	local p = Services.Players.LocalPlayer
	return p and p.Character
end

-- The opacity the character should have right now (1 = normal).
local function targetOpacity()
	if not s("enabled") then
		return 1
	end
	if state.dead and s("restoreOnDeath") then
		return 1
	end
	return s("opacity")
end

local function applyOpacity(opacity)
	local mod = 1 - opacity
	for inst, info in pairs(state.items) do
		if inst.Parent then
			if info.kind == "part" then
				if inst.LocalTransparencyModifier ~= mod then
					inst.LocalTransparencyModifier = mod
				end
			else
				local want = 1 - opacity * (1 - info.original)
				if inst.Transparency ~= want then
					inst.Transparency = want
				end
			end
		end
	end
end

local function applyName(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if s("enabled") and s("hideName") and hum and not (state.dead and s("restoreOnDeath")) then
		if state.nameHum ~= hum then
			restoreName()
			state.nameHum, state.nameOriginal = hum, hum.DisplayDistanceType
		end
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	else
		restoreName()
	end
end

local function bindCharacter(char)
	state.charMaid:Clean()
	state.dead = false
	rebuild(char)
	if not char then
		return
	end
	state.charMaid:Give(char.DescendantAdded:Connect(function(d)
		track(char, d)
	end))
	state.charMaid:Give(char.DescendantRemoving:Connect(function(d)
		state.items[d] = nil
	end))
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		state.charMaid:Give(hum.Died:Connect(function()
			state.dead = true
		end))
	end
end

local function tick(dt)
	local char = character()
	if char ~= state.char then
		state.char = char
		bindCharacter(char)
	end
	local target = targetOpacity()
	local fade = s("fadeTime")
	if fade <= 0 then
		state.current = target
	else
		local speed = dt / fade
		if state.current < target then
			state.current = math.min(target, state.current + speed)
		else
			state.current = math.max(target, state.current - speed)
		end
	end
	if state.current < 0.999 or state.touched then
		applyOpacity(state.current)
		state.touched = state.current < 0.999
		if not state.touched then
			Ghost._restoreItems()
		end
	end
	applyName(char)
end

function Ghost.start(ctx)
	assert(state == nil, "Ghost already started")
	state = { items = {}, current = 1, charMaid = Maid.new("ghost-char"), char = nil, dead = false, touched = false }
	ctx.maid:Give(function()
		if state then
			Ghost._restoreItems()
			restoreName()
			state.charMaid:Clean()
		end
		state = nil
	end)
	-- configuration changes that alter WHICH parts are affected need a rebuild
	for _, key in ipairs({ "ghost.includeAccessories", "ghost.includeFace", "ghost.includeTools" }) do
		ctx.maid:Give(Settings.observe(key, function()
			if state and state.char then
				rebuild(state.char)
			end
		end))
	end
	local p = Services.Players.LocalPlayer
	ctx.maid:Give(p.CharacterAdded:Connect(function(char)
		if state then
			state.char = char
			bindCharacter(char)
		end
	end))
	local h = Perf.every("ghost.tick", 15, tick)
	ctx.maid:Give(h.Cancel)
	if p.Character then
		state.char = p.Character
		bindCharacter(p.Character)
	end
end

-- toggle(): switch the effect on/off (used by the hotkey and the on-screen button)
function Ghost.toggle()
	return Settings.toggle("ghost.enabled", "action")
end

function Ghost.status()
	if not state then
		return { running = false }
	end
	local n = 0
	for _ in pairs(state.items) do
		n += 1
	end
	return { running = true, tracked = n, opacity = state.current, dead = state.dead, nameHidden = state.nameHum ~= nil }
end

function Ghost.isRunning()
	return state ~= nil
end

return Ghost

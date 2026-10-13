--!nonstrict
-- features/Sounds: user-configurable sound slots (gun shot, knife swing, hit, kill, drone engine,
-- interface click). Each slot plays a sound from an asset id or a file the user placed in
-- MM2Hub/sounds/. No audio is bundled and no Roblox default sounds are used: a slot without a
-- source stays silent. Playback is local-only.
-- STATUS: env-dependent (file sounds need getcustomasset; asset ids must be loadable by the client).
-- Depends on: Settings, Sources, Env, Services, Logger, Data/Schema (slot list).

local import = ...
local Settings = import("core/Settings")
local Sources = import("features/Sources")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Schema = import("data/Schema")

local Sounds = {}

local resolved = {} -- source string -> {id=...} | {err=...}
local loops = {}
local hooked = setmetatable({}, { __mode = "k" })
local started = false

function Sounds.slots()
	local out = {}
	for _, s in ipairs(Schema.soundSlots) do
		table.insert(out, { id = s[1], label = s[2], desc = s[3] })
	end
	return out
end

-- resolveParsed(parsed, folder) -> soundId|nil, err
function Sounds.resolveParsed(parsed, folder)
	if parsed.type == "asset" then
		return "rbxassetid://" .. parsed.ref
	elseif parsed.type == "file" then
		return Env.customAsset(Env.ROOT .. "/" .. folder .. "/" .. parsed.ref)
	end
	return nil, "unsupported source type"
end

-- slotSound(slot) -> soundId|nil, err (nil, nil when the slot is simply unset/disabled)
function Sounds.slotSound(slot)
	if not Settings.get("sounds." .. slot .. "Enabled") then
		return nil
	end
	local text = Settings.get("sounds." .. slot .. "Source")
	if text == "" then
		return nil, "no source set"
	end
	local cached = resolved[text]
	if cached == nil then
		local parsed, perr = Sources.parse(text, "audio")
		if not parsed then
			cached = { err = perr }
		else
			local id, rerr = Sounds.resolveParsed(parsed, "sounds")
			cached = id and { id = id } or { err = rerr }
		end
		resolved[text] = cached
		if cached.err then
			Logger.warn("Sounds", "slot %s: %s", slot, tostring(cached.err))
		end
	end
	return cached.id, cached.err
end

local function makeSound(slot, id)
	local snd = Instance.new("Sound")
	snd.Name = "MM2Hub_" .. slot
	snd.SoundId = id
	snd.Volume = Settings.get("sounds." .. slot .. "Volume") * Settings.get("sounds.master")
	snd.PlaybackSpeed = Settings.get("sounds." .. slot .. "Pitch")
	return snd
end

-- play(slot) -> true when a sound was started
function Sounds.play(slot)
	local id = Sounds.slotSound(slot)
	if not id then
		return false
	end
	local ok = pcall(function()
		local snd = makeSound(slot, id)
		snd.Parent = Services.SoundService
		snd.Ended:Once(function()
			snd:Destroy()
		end)
		Services.Debris:AddItem(snd, 10)
		snd:Play()
	end)
	return ok
end

function Sounds.test(slot)
	local id, err = Sounds.slotSound(slot)
	if not id then
		return false, err or "slot is disabled or has no source"
	end
	return Sounds.play(slot)
end

function Sounds.startLoop(slot)
	if loops[slot] then
		return true
	end
	local id = Sounds.slotSound(slot)
	if not id then
		return false
	end
	local ok, snd = pcall(function()
		local s = makeSound(slot, id)
		s.Looped = true
		s.Parent = Services.SoundService
		s:Play()
		return s
	end)
	if ok then
		loops[slot] = snd
	end
	return ok
end

function Sounds.stopLoop(slot)
	local snd = loops[slot]
	if snd then
		loops[slot] = nil
		pcall(function()
			snd:Stop()
			snd:Destroy()
		end)
	end
end

function Sounds.clearCache()
	table.clear(resolved)
end

-- Tool hooks: play gun/knife sounds when the player's own tools are activated.
local function hookTool(tool, maid)
	if hooked[tool] or not tool:IsA("Tool") then
		return
	end
	hooked[tool] = true
	maid:Give(tool.Activated:Connect(function()
		local name = tool.Name
		if name == Settings.get("cosmetics.gunTool") then
			Sounds.play("gunShot")
		elseif name == Settings.get("cosmetics.knifeTool") then
			Sounds.play("knifeSwing")
		end
	end))
end

local function watch(container, maid)
	for _, child in ipairs(container:GetChildren()) do
		hookTool(child, maid)
	end
	maid:Give(container.ChildAdded:Connect(function(child)
		hookTool(child, maid)
	end))
end

function Sounds.start(ctx)
	assert(not started, "Sounds already started")
	started = true
	ctx.maid:Give(function()
		started = false
		for slot in pairs(table.clone(loops)) do
			Sounds.stopLoop(slot)
		end
		table.clear(resolved)
	end)
	for _, s in ipairs(Schema.soundSlots) do
		ctx.maid:Give(Settings.observe("sounds." .. s[1] .. "Source", Sounds.clearCache))
	end
	local player = Services.Players.LocalPlayer
	local function watchCharacter(char)
		watch(char, ctx.maid)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watch(backpack, ctx.maid)
	end
	ctx.maid:Give(player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child, ctx.maid)
		end
	end))
	if player.Character then
		watchCharacter(player.Character)
	end
	ctx.maid:Give(player.CharacterAdded:Connect(watchCharacter))
end

return Sounds

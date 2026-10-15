--!nonstrict
-- features/Emotes: play animations on YOUR OWN character - the standard Roblox R15 emotes (wave, point, cheer, laugh and
-- three dances; the animation ids the default Animate script uses). Preview, speed, loop, stop, and everything is stopped
-- when you switch it off, respawn or unload the hub, so your character goes back to its normal animations.
-- An emote played on your own character is seen by other players the same way as a normal Roblox emote; nothing is done to
-- anyone else's character. Needs an R15 character with an Animator; R6 characters are reported as not supported.
-- STATUS: implemented; verified against the mock layer only. Whether MM2 allows these animations on its characters is not
-- confirmed.
-- Depends on: Settings, Services, Logger.

local import = ...
local Settings = import("core/Settings")
local Services = import("core/Services")
local Logger = import("core/Logger")

local Emotes = {}

-- the standard R15 emote animation ids (Roblox's default Animate script)
Emotes.LIST = {
	{ name = "Wave", id = "rbxassetid://507770239" },
	{ name = "Point", id = "rbxassetid://507770453" },
	{ name = "Cheer", id = "rbxassetid://507770677" },
	{ name = "Laugh", id = "rbxassetid://507770818" },
	{ name = "Dance 1", id = "rbxassetid://507771019" },
	{ name = "Dance 2", id = "rbxassetid://507776043" },
	{ name = "Dance 3", id = "rbxassetid://507777268" },
}
local byName = {}
for _, e in ipairs(Emotes.LIST) do
	byName[e.name] = e
end

local state = nil

local function animator()
	local lp = Services.Players.LocalPlayer
	local char = lp and lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil, "no character"
	end
	local okRig, rig = pcall(function()
		return hum.RigType
	end)
	if okRig and rig ~= nil and tostring(rig) ~= "Enum.HumanoidRigType.R15" and tostring(rig) ~= "R15" then
		return nil, "this character is not R15 (these emotes are R15 animations)"
	end
	local a = hum:FindFirstChildOfClass("Animator")
	if not a then
		return nil, "the character has no Animator"
	end
	return a
end

-- play(name) -> true | nil, reason
function Emotes.play(name)
	if not state then
		return nil, "Emotes are not running."
	end
	local e = byName[name or ""]
	if not e then
		return nil, "unknown emote"
	end
	Emotes.stop()
	local a, why = animator()
	if not a then
		return nil, why
	end
	local ok, track = pcall(function()
		local anim = Instance.new("Animation")
		anim.AnimationId = e.id
		local t = a:LoadAnimation(anim)
		t.Looped = Settings.get("emote.loop")
		t:Play(0.15, 1, Settings.get("emote.speed"))
		return t
	end)
	if not ok or not track then
		Logger.warn("Emotes", "could not play %s: %s", e.name, tostring(track))
		return nil, "Animation unavailable"
	end
	state.track, state.playing = track, e.name
	return true
end

function Emotes.stop()
	if state and state.track then
		pcall(function()
			state.track:Stop(0.2)
		end)
		pcall(function()
			state.track:Destroy()
		end)
		state.track, state.playing = nil, nil
	end
end

function Emotes.playing()
	if not state or not state.track then
		return nil
	end
	local ok, on = pcall(function()
		return state.track.IsPlaying
	end)
	if ok and on == false then
		state.track, state.playing = nil, nil
		return nil
	end
	return state.playing
end

function Emotes.start(ctx)
	assert(state == nil, "Emotes already started")
	state = {}
	ctx.maid:Give(function()
		Emotes.stop()
		state = nil
	end)
	ctx.maid:Give(Settings.observe("emote.speed", function(v)
		if state and state.track then
			pcall(function()
				state.track:AdjustSpeed(v)
			end)
		end
	end))
	local lp = Services.Players.LocalPlayer
	if lp then
		ctx.maid:Give(lp.CharacterAdded:Connect(function()
			if state then
				state.track, state.playing = nil, nil -- the old character's track went with it
			end
		end))
	end
end

return Emotes

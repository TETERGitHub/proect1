--!nonstrict
-- features/KillEvents: the two confirmed-kill events the kill sounds listen to.
--   MurdererKillConfirmed  role "murderer"   a victim died soon after YOU used your knife, close to you
--   SheriffKillConfirmed   role "sheriff"    a victim died soon after YOU used your gun
-- WHAT "CONFIRMED" MEANS HERE (honest limits): a client cannot prove who killed whom. The death itself is real replicated
-- state (Humanoid.Died of another player), but the credit is a local heuristic: your own tool was activated within the
-- last RECENT_S seconds and the victim was within RANGE studs of you. Clicking, swinging or shooting alone never fires an
-- event, and a death that is not preceded by your own tool use never does either. The training range reports its own
-- confirmed target kills as "sheriff" (source "training"). The page's test buttons use report() with source "test" and are
-- labelled as tests. One death can fire at most one event (dedupe by victim and role).
-- Depends on: Settings, Signal, Services, Logger.

local import = ...
local Settings = import("core/Settings")
local Signal = import("core/Signal")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Maid = import("core/Maid")

local KillEvents = {}

KillEvents.Confirmed = Signal.new("KillEvents.Confirmed")
-- Used: you activated your own gun or knife ({ role = "sheriff" | "murderer", tool = Tool }); features/HitFX draws tracers on it
KillEvents.Used = Signal.new("KillEvents.Used")

local RECENT_S = 2.5
local RANGE = { murderer = 45, sheriff = 600 }
local DEDUPE_S = 5
local ROLES = { murderer = true, sheriff = true }

local seen = { murderer = setmetatable({}, { __mode = "k" }), sheriff = setmetatable({}, { __mode = "k" }) }
local state = nil
local serial = 0

-- report(role, victimKey, source) -> true when an event was fired. The same victim key and role fire only once per DEDUPE_S.
function KillEvents.report(role, victimKey, source)
	if not ROLES[role] or victimKey == nil then
		return false
	end
	local now = os.clock()
	local map = seen[role]
	local last = map[victimKey]
	if last and now - last < DEDUPE_S then
		return false
	end
	map[victimKey] = now
	if type(victimKey) == "string" then
		-- string keys are not weak: forget old ones so the table cannot grow without bound
		for k, t in pairs(map) do
			if type(k) == "string" and now - t > DEDUPE_S * 4 then
				map[k] = nil
			end
		end
	end
	KillEvents.Confirmed:Fire({ role = role, victim = victimKey, source = source or "world", at = now })
	return true
end

-- simulate(role) -> true: fires a labelled test event (source "test") through the same pipeline, with a unique victim key
function KillEvents.simulate(role)
	serial += 1
	return KillEvents.report(role, "test:" .. serial, "test")
end

-- candidates(): the role(s) the local player acted as recently, newest first. Pure helper, used by the death handler and tests.
function KillEvents.attribute(lastUse, now, distance)
	local best, bestAt = nil, -1
	for role, at in pairs(lastUse) do
		if ROLES[role] and now - at <= RECENT_S and at > bestAt and distance <= RANGE[role] then
			best, bestAt = role, at
		end
	end
	return best
end

local function rootOf(char)
	return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
end

function KillEvents.start(ctx)
	assert(state == nil, "KillEvents already started")
	state = { lastUse = {}, hookedTools = setmetatable({}, { __mode = "k" }), hookedChars = setmetatable({}, { __mode = "k" }) }
	local lp = Services.Players.LocalPlayer
	ctx.maid:Give(function()
		state = nil
	end)

	-- Connections live in a Maid per container (backpack, own character) and per other player's character; a respawn replaces
	-- the old Maid, so connections do not pile up over a long session.
	local function hookTool(tool, owner)
		if not tool:IsA("Tool") or state.hookedTools[tool] then
			return
		end
		state.hookedTools[tool] = true
		owner:Give(tool.Activated:Connect(function()
			if not state then
				return
			end
			if tool.Name == Settings.get("cosmetics.knifeTool") then
				state.lastUse.murderer = os.clock()
				KillEvents.Used:Fire({ role = "murderer", tool = tool })
			elseif tool.Name == Settings.get("cosmetics.gunTool") then
				state.lastUse.sheriff = os.clock()
				KillEvents.Used:Fire({ role = "sheriff", tool = tool })
			end
		end))
	end
	local function watchContainer(c, slot)
		local m = Maid.new("KillEvents." .. slot)
		ctx.maid:GiveNamed("container:" .. slot, m)
		for _, child in ipairs(c:GetChildren()) do
			hookTool(child, m)
		end
		m:Give(c.ChildAdded:Connect(function(child)
			hookTool(child, m)
		end))
	end
	local backpack = lp:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack, "backpack")
	end
	ctx.maid:Give(lp.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(child, "backpack")
		end
	end))
	if lp.Character then
		watchContainer(lp.Character, "character")
	end
	ctx.maid:Give(lp.CharacterAdded:Connect(function(char)
		watchContainer(char, "character")
	end))

	local function onDeath(char)
		if not state then
			return
		end
		local me, them = rootOf(lp.Character), rootOf(char)
		if not me or not them then
			return
		end
		local d = (me.Position - them.Position).Magnitude
		local role = KillEvents.attribute(state.lastUse, os.clock(), d)
		if role then
			KillEvents.report(role, char, "world")
		end
	end
	local function hookCharacter(player, char)
		if state.hookedChars[char] then
			return
		end
		state.hookedChars[char] = true
		local m = Maid.new("KillEvents.char")
		ctx.maid:GiveNamed("char:" .. tostring(player.UserId), m) -- replaces (and cleans) the previous character's hooks
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			m:Give(hum.Died:Once(function()
				onDeath(char)
			end))
		else
			m:Give(char.ChildAdded:Connect(function(child)
				if child:IsA("Humanoid") then
					m:Give(child.Died:Once(function()
						onDeath(char)
					end))
				end
			end))
		end
	end
	local function hookPlayer(player)
		if player == lp then
			return
		end
		if player.Character then
			hookCharacter(player, player.Character)
		end
		ctx.maid:GiveNamed("player:" .. tostring(player.UserId), player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end))
	end
	for _, p in ipairs(Services.Players:GetPlayers()) do
		hookPlayer(p)
	end
	ctx.maid:Give(Services.Players.PlayerAdded:Connect(hookPlayer))
	ctx.maid:Give(Services.Players.PlayerRemoving:Connect(function(player)
		ctx.maid:Remove("char:" .. tostring(player.UserId))
		ctx.maid:Remove("player:" .. tostring(player.UserId))
	end))
	Logger.info("KillEvents", "watching tool use and other players' deaths")
end

return KillEvents

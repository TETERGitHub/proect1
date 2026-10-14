--!nonstrict
-- features/AntiFling: protects YOUR character from being flung.
--   1. Velocity guard: when the character's speed/spin is abnormal (AntiFlingLogic), motion is cancelled
--      and the character is put back at its last safe position.
--   2. Ghost collisions: other players' parts have collisions disabled locally, so contact physics
--      that would throw you never run on your client. Original values are restored when switched off.
-- It changes only what your own client simulates; other players and the server are not touched.
-- STATUS: env-dependent (depends on the game not re-enabling collisions / respecting local physics).
-- Depends on: Settings, Perf, Services, Notify, AntiFlingLogic, Signal.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Notify = import("core/Notify")
local Logic = import("features/AntiFlingLogic")
local Signal = import("core/Signal")

local AntiFling = {}

AntiFling.Blocked = Signal.new("AntiFling.Blocked") -- (reason, count)

local state = nil

local function s(name)
	return Settings.get("antifling." .. name)
end

local function root()
	local p = Services.Players.LocalPlayer
	local c = p and p.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- Velocity guard --------------------------------------------------------------------------------------------------

local function guard()
	local r = root()
	if not r then
		return
	end
	local v, w = r.AssemblyLinearVelocity, r.AssemblyAngularVelocity
	local abnormal, reason = Logic.evaluate({ x = v.X, y = v.Y, z = v.Z }, { x = w.X, y = w.Y, z = w.Z }, { maxSpeed = s("maxSpeed"), angularLimit = s("angularLimit") })
	if abnormal then
		local x, y, z = Logic.cleaned({ x = v.X, y = v.Y, z = v.Z })
		r.AssemblyLinearVelocity = Vector3.new(x, y, z)
		r.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		if state.safe then
			r.CFrame = state.safe
		end
		state.blocks += 1
		AntiFling.Blocked:Fire(reason, state.blocks)
		local now = os.clock()
		if s("notify") and now - state.lastNotice > 3 then
			state.lastNotice = now
			Notify.push({ title = "Anti-fling", text = "Blocked an abnormal " .. reason .. " movement.", level = "warn", duration = 2.5 })
		end
	else
		-- remember a position we know was normal (updated at most every 0.25 s)
		local now = os.clock()
		if now - state.safeAt > 0.25 then
			state.safe = r.CFrame
			state.safeAt = now
		end
	end
end

-- Ghost collisions ---------------------------------------------------------------------------------------------------

local function ghost()
	local me = Services.Players.LocalPlayer
	for _, p in ipairs(Services.Players:GetPlayers()) do
		if p ~= me and p.Character then
			for _, d in ipairs(p.Character:GetDescendants()) do
				if d:IsA("BasePart") and d.CanCollide and state.touched[d] == nil then
					state.touched[d] = true
					d.CanCollide = false
				end
			end
		end
	end
end

local function restoreGhost()
	for part in pairs(state.touched) do
		pcall(function()
			part.CanCollide = true
		end)
	end
	table.clear(state.touched)
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------------

function AntiFling.start(ctx)
	assert(state == nil, "AntiFling already started")
	state = { blocks = 0, safe = nil, safeAt = 0, lastNotice = 0, touched = {} }
	ctx.maid:Give(function()
		if state then
			restoreGhost()
		end
		state = nil
	end)
	local h1 = Perf.every("antifling.guard", 60, function()
		if s("enabled") then
			guard()
		end
	end)
	local h2 = Perf.every("antifling.ghost", 10, function()
		if s("enabled") and s("noCollide") then
			ghost()
		elseif next(state.touched) then
			restoreGhost()
		end
	end)
	ctx.maid:Give(h1.Cancel)
	ctx.maid:Give(h2.Cancel)
	ctx.maid:Give(Settings.observe("antifling.enabled", function(on)
		if not on and state and next(state.touched) then
			restoreGhost()
		end
	end))
end

function AntiFling.blocks()
	return state and state.blocks or 0
end

function AntiFling.resetCounter()
	if state then
		state.blocks = 0
	end
end

function AntiFling.ghostedParts()
	if not state then
		return 0
	end
	local n = 0
	for _ in pairs(state.touched) do
		n += 1
	end
	return n
end

function AntiFling.isRunning()
	return state ~= nil
end

return AntiFling

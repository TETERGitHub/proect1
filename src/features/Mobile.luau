--!nonstrict
-- features/Mobile: mobile optimisation for the whole hub (one place; no other module checks the device itself).
--   device      Desktop / Phone / Tablet / Touch desktop from UserInputService (TouchEnabled, KeyboardEnabled, MouseEnabled)
--               and the shorter screen side (ui/Platform.detect, the same rule the first-run layout uses).
--   layout      Auto / Phone / Tablet / Desktop re-applies ui/Platform's layout preset for that device by hand (window size and
--               scale, compact rows, on-screen buttons and their size). The first run on a device already does this.
--   profiles    Ultra Low / Balanced / High write a consistent set of the hub's real load settings (visual update rate,
--               decoration limit, reduced effects, animation speed, kill-effect detail, aura intensity, low profile);
--               Custom leaves your own values alone; Auto adapts between four quality levels from the measured FPS.
--   adaptive    level 0..3, sampled once a second; drops after a sustained FPS deficit, rises only after a long good stretch,
--               never twice within 8 s (hysteresis) and never touches your settings unless the profile is Auto.
--   battery     caps decorative updates at 20 per second (core/Perf) and switches on reduced effects while it is on.
--   unfocused   visual tasks are paused while the game window is in the background (core/Perf), resumed on return.
--   monitor     a small overlay: FPS, frame time, scheduled tasks, hub objects in the world, quality level.
-- Measurements are what the client reports (Perf.fps, instance counts); temperature and battery level are not available
-- to Roblox scripts and are not shown.
-- STATUS: implemented; verified against the mock layer only (not on a phone).
-- Depends on: Settings, Perf, Env, Services, Logger, Notify, Platform.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Notify = import("core/Notify")
local Platform = import("ui/Platform")

local Mobile = {}

-- quality levels (also what the fixed profiles write). Every key is an existing hub setting.
Mobile.LEVELS = {
	[0] = { name = "Minimum", values = { ["perf.visualHz"] = 15, ["perf.maxDecor"] = 4, ["ui.reduceEffects"] = true, ["ui.animSpeed"] = 0,
		["killfx.detail"] = 0.4, ["aura.intensity"] = 0.4, ["perf.lowProfile"] = true } },
	[1] = { name = "Low", values = { ["perf.visualHz"] = 20, ["perf.maxDecor"] = 8, ["ui.reduceEffects"] = true, ["ui.animSpeed"] = 0.7,
		["killfx.detail"] = 0.6, ["aura.intensity"] = 0.7, ["perf.lowProfile"] = false } },
	[2] = { name = "Balanced", values = { ["perf.visualHz"] = 30, ["perf.maxDecor"] = 12, ["ui.reduceEffects"] = false, ["ui.animSpeed"] = 1,
		["killfx.detail"] = 1, ["aura.intensity"] = 1, ["perf.lowProfile"] = false } },
	[3] = { name = "High", values = { ["perf.visualHz"] = 60, ["perf.maxDecor"] = 24, ["ui.reduceEffects"] = false, ["ui.animSpeed"] = 1,
		["killfx.detail"] = 1.4, ["aura.intensity"] = 1.3, ["perf.lowProfile"] = false } },
}
local PROFILE_LEVEL = { ["Ultra Low"] = 0, Balanced = 2, High = 3 }

local state = nil

local function s(k)
	return Settings.get("mobile." .. k)
end

local function apply(values)
	local changed = 0
	for k, v in pairs(values) do
		if Settings.has(k) and Settings.get(k) ~= v then
			local ok, err = pcall(Settings.set, k, v)
			if ok then
				changed += 1
			else
				Logger.warn("Mobile", "could not set %s: %s", k, tostring(err))
			end
		end
	end
	return changed
end

-- detect() -> { device, touch, keyboard, mouse, width, height }
function Mobile.detect()
	local uis = Services.UserInputService
	local touch, keyboard, mouse = false, false, false
	pcall(function()
		touch, keyboard, mouse = uis.TouchEnabled == true, uis.KeyboardEnabled == true, uis.MouseEnabled == true
	end)
	local w, h = 0, 0
	pcall(function()
		local vp = Services.Workspace.CurrentCamera.ViewportSize
		w, h = vp.X, vp.Y
	end)
	local kind = Platform.detect(touch, keyboard or mouse, w, h)
	local device = ({ phone = "Phone", tablet = "Tablet" })[kind] or (touch and "Touch desktop") or ((keyboard or mouse) and "Desktop") or "Unknown"
	return { device = device, touch = touch, keyboard = keyboard, mouse = mouse, width = w, height = h }
end

-- applyLayout(choice) -> layout, changed: "Auto" uses the detected device; Phone / Tablet / Desktop force that preset
function Mobile.applyLayout(choice)
	local layout = choice
	if layout == nil or layout == "Auto" then
		local d = Mobile.detect().device
		layout = (d == "Phone" or d == "Tablet") and d or "Desktop"
	end
	return layout, Platform.apply(string.lower(layout))
end

-- applyProfile(name) -> changed settings count. Custom changes nothing; Auto starts adaptive quality at Balanced.
function Mobile.applyProfile(name)
	if name == "Custom" then
		return 0
	end
	local level = PROFILE_LEVEL[name] or 2
	if state then
		state.level, state.lastChange = level, state.now
	end
	return apply(Mobile.LEVELS[level].values)
end

function Mobile.level()
	return state and state.level or nil
end

-- adaptive step (once a second): fps sample; returns the new level when it changed
function Mobile.adapt(fps)
	if not state or s("profile") ~= "Auto" then
		return nil
	end
	local target = s("targetFps")
	state.now += 1
	if fps < target - 5 then
		state.bad += 1
		state.good = 0
	elseif fps > target + 10 then
		state.good += 1
		state.bad = 0
	else
		state.bad, state.good = math.max(0, state.bad - 1), 0
	end
	if state.now - state.lastChange < 8 then
		return nil -- hysteresis: at most one change in 8 s
	end
	local new = state.level
	if state.bad >= 4 and state.level > 0 then
		new = state.level - 1
	elseif state.good >= 12 and state.level < 3 then
		new = state.level + 1
	end
	if new == state.level then
		return nil
	end
	state.level, state.lastChange, state.bad, state.good = new, state.now, 0, 0
	apply(Mobile.LEVELS[new].values)
	if s("adaptiveNotify") then
		Notify.push({ title = "Mobile", text = "Quality: " .. Mobile.LEVELS[new].name })
	end
	return new
end

-- objectCount(): instances the hub owns in the world (effect folders under the camera)
function Mobile.objectCount()
	local n = 0
	pcall(function()
		for _, c in ipairs(Services.Workspace.CurrentCamera:GetChildren()) do
			if string.sub(c.Name, 1, 6) == "MM2Hub" then
				n += 1 + #c:GetDescendants()
			end
		end
	end)
	return n
end

function Mobile.status()
	if not state then
		return { running = false }
	end
	local d = Mobile.detect()
	return {
		running = true, device = d.device, layout = Settings.get("state.platform"), profile = s("profile"),
		level = state.level, levelName = Mobile.LEVELS[state.level].name, paused = Perf.visualPaused(), battery = s("battery"),
		objects = Mobile.objectCount(), tasks = Perf.taskCount(), fps = Perf.fps(),
	}
end

local function buildMonitor(maid)
	local parent = Env.guiParent()
	if not parent then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubMonitor"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 7
	gui.Enabled = false
	gui.Parent = parent
	maid:Give(gui)
	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -10, 0, 44)
	label.Size = UDim2.fromOffset(200, 58)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(235, 235, 245)
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingTop = UDim.new(0, 8), UDim.new(0, 6)
	pad.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	return { gui = gui, label = label }
end

function Mobile.monitorText()
	local st = Mobile.status()
	if not st.running then
		return ""
	end
	local fps = st.fps or 0
	return string.format("FPS %d  (%.1f ms)\ntasks %d  objects %d\n%s%s", math.floor(fps + 0.5), fps > 0 and 1000 / fps or 0, st.tasks, st.objects,
		st.profile == "Auto" and ("quality " .. st.levelName) or st.profile, st.paused and "  paused" or "")
end

function Mobile.start(ctx)
	assert(state == nil, "Mobile already started")
	state = { level = PROFILE_LEVEL[s("profile")] or 2, now = 0, lastChange = -100, bad = 0, good = 0 }
	ctx.maid:Give(function()
		Perf.setVisualPaused(false)
		state = nil
	end)
	ctx.maid:Give(Settings.observe("mobile.layout", function(v)
		Mobile.applyLayout(v)
	end))
	ctx.maid:Give(Settings.observe("mobile.profile", function(v)
		Mobile.applyProfile(v)
	end))
	ctx.maid:Give(Settings.observe("mobile.battery", function(v)
		if v then
			Settings.set("ui.reduceEffects", true)
		end
	end))
	-- pause decorations while the game window is in the background
	local uis = Services.UserInputService
	pcall(function()
		ctx.maid:Give(uis.WindowFocusReleased:Connect(function()
			if s("pauseUnfocused") then
				Perf.setVisualPaused(true)
			end
		end))
		ctx.maid:Give(uis.WindowFocused:Connect(function()
			Perf.setVisualPaused(false)
		end))
	end)
	ctx.maid:Give(Settings.observe("mobile.pauseUnfocused", function(v)
		if not v then
			Perf.setVisualPaused(false)
		end
	end))
	local mon = buildMonitor(ctx.maid)
	-- once a second: adaptive quality; monitor text twice a second (a logic task, so it keeps running while paused)
	local tick = 0
	local h = Perf.every("mobile", 2, function()
		if not state then
			return
		end
		tick += 1
		if tick % 2 == 0 then
			Mobile.adapt(Perf.fps())
		end
		if mon then
			mon.gui.Enabled = s("monitor")
			if mon.gui.Enabled then
				mon.label.Text = Mobile.monitorText()
			end
		end
	end)
	ctx.maid:Give(h.Cancel)
end

return Mobile

--!nonstrict
-- app/Hub: composition root. Defines settings, registers actions and hotkeys, registers every
-- feature as a lifecycle module and starts them in dependency order. A previous instance in the
-- same executor session is shut down first (re-initialisation detection).
-- Depends on: everything.

local import = ...
local Signal = import("core/Signal")
local Logger = import("core/Logger")
local Settings = import("core/Settings")
local Schema = import("data/Schema")
local Env = import("core/Env")
local Config = import("core/Config")
local Core = import("core/Core")
local Actions = import("core/Actions")
local Input = import("core/Input")
local Perf = import("core/Perf")
local Notify = import("core/Notify")
local Maid = import("core/Maid")
local Cleanup = import("core/Cleanup")
local Diagnostics = import("core/Diagnostics")
local I18n = import("core/I18n")
local Recents = import("core/Recents")
local Version = import("core/Version")
local Services = import("core/Services")
local Search = import("core/Search")
local License = import("core/License")
local Platform = import("ui/Platform")

local Hub = {}

local current = nil

local function defineSettings()
	Settings.defineAll(Schema.settings)
	for _, c in ipairs(Schema.conflicts) do
		Settings.defineConflict(c.id, c.keys, c.check)
	end
end

local function registerActions(h)
	local Window = import("ui/Window")
	local Training = import("features/Training")
	local Drone = import("features/Drone")
	local Camera = import("features/Camera")
	local Lighting = import("features/Lighting")
	local Music = import("features/Music")
	local Tools = import("features/Tools")
	local Ghost = import("features/Ghost")
	local Select = import("features/TargetSelect")
	local function A(id, name, desc, fn, keywords)
		Actions.register(id, { name = name, desc = desc, fn = fn, keywords = keywords or {} })
	end
	A("window.toggle", "Show / hide hub", "Toggles the hub window.", Window.toggle, { "open", "close" })
	A("window.minimize", "Minimise hub", "Collapses the hub into the quick bar.", Window.minimize)
	A("window.expand", "Expand hub", "Restores the full window from the quick bar.", Window.expand)
	A("window.nextTab", "Next page", "Switches to the next page.", Window.nextTab, { "tab" })
	A("window.prevTab", "Previous page", "Switches to the previous page.", Window.prevTab, { "tab" })
	A("window.focusSearch", "Focus search", "Puts the cursor in the search box.", Window.focusSearch)
	A("ui.toggleCompact", "Toggle compact mode", "Hides descriptions to fit more rows.", function() Settings.toggle("ui.compact", "action") end)
	A("crosshair.toggle", "Toggle crosshair", "Turns the custom crosshair on or off.", function() Settings.toggle("crosshair.enabled", "action") end, { "aim", "dot" })
	A("lowprofile.toggle", "Toggle low load profile", "Halves update rates and disables heavy effects.", function() Settings.toggle("perf.lowProfile", "action") end, { "fps", "performance" })
	A("camera.reset", "Reset camera", "Resets camera settings and restores originals.", Camera.reset)
	A("lighting.reset", "Reset graphics", "Resets lighting settings and restores originals.", Lighting.reset, { "brightness", "filters" })
	A("training.toggle", "Toggle training range", "Spawns or removes the local practice targets.", function() Settings.toggle("training.enabled", "action") end)
	A("training.clear", "Clear training objects", "Removes all spawned targets, dummies and guides.", Training.clear)
	A("training.spawnDummy", "Spawn training dummy", "Creates the local physics dummy.", Training.spawnDummy)
	A("training.launch", "Launch dummy", "Applies the stand impulse to the dummy.", Training.launch, { "fling" })
	A("training.resetDummy", "Reset dummy", "Restores the dummy position and velocity.", Training.resetDummy)
	A("ghost.toggle", "Toggle local invisibility", "Fades your own character on your screen only.", Ghost.toggle, { "invisible", "transparent", "hide" })
	A("training.spawnLab", "Spawn hitbox lab", "Builds the isolated hitbox test scene.", Training.spawnLab, { "hitbox", "geometry" })
	A("training.clearLab", "Remove hitbox lab", "Removes the hitbox lab scene.", Training.clearLab)
	A("training.fireProbe", "Fire lab probe", "Throws a physical probe at the lab hitbox.", Training.fireProbe, { "collision" })
	A("training.resetLab", "Reset lab counters", "Zeroes the lab scores.", Training.resetLabCounters)
	A("selectaim.toggle", "Toggle Select Aim", "Turns the test-target selector on or off.", function() Settings.toggle("selectaim.enabled", "action") end, { "target", "select" })
	A("selectaim.select", "Select target now", "Acquires a test target by the current mode.", function() Select.select() end, { "target" })
	A("selectaim.lock", "Toggle target lock", "Keeps the selected test target while it stays valid.", Select.toggleLock, { "target" })
	A("selectaim.reset", "Reset target", "Clears the selected test target.", Select.reset, { "target" })
	A("selectaim.next", "Next target", "Selects the next test target (switches to Manual mode).", function() Select.next() end, { "target", "switch" })
	A("selectaim.prev", "Previous target", "Selects the previous test target (switches to Manual mode).", function() Select.previous() end, { "target", "switch" })
	A("drone.toggle", "Launch / land drone", "Starts or ends the FPV drone flight.", Drone.toggle, { "fpv", "shahed", "fly" })
	A("music.toggle", "Play / pause music", "Toggles the music player.", Music.toggle, { "song", "playlist" })
	A("music.next", "Next track", "Skips to the next track.", Music.next)
	A("tools.stopwatchToggle", "Start / stop stopwatch", "Toggles the stopwatch.", Tools.stopwatchToggle, { "timer" })
	A("diagnostics.export", "Export diagnostic report", "Saves and copies a diagnostic report.", function()
		local ok, msg = Diagnostics.export()
		Notify.push({ title = "Diagnostics", text = tostring(msg), level = ok and "success" or "error" })
	end, { "bug", "log" })
	A("config.save", "Save active profile", "Writes the active profile now.", function()
		local ok, err = Config.save()
		Notify.push({ title = "Profile", text = ok and ("Saved '" .. Config.active() .. "'") or tostring(err), level = ok and "success" or "error" })
	end)
	A("hub.unload", "Unload hub", "Stops every module and removes all hub objects.", function() h.unload() end, { "exit", "quit", "panic" })

	Input.bind("window.toggle", "RightShift")
	Input.bind("window.nextTab", "PageDown", { hubOnly = true })
	Input.bind("window.prevTab", "PageUp", { hubOnly = true })
	Input.bind("window.focusSearch", "Slash", { hubOnly = true })
	Input.bind("crosshair.toggle", "None")
	Input.bind("drone.toggle", "None")
	Input.bind("selectaim.select", "None")
	Input.bind("selectaim.lock", "None")
	Input.bind("selectaim.reset", "None")
	Input.bind("selectaim.next", "RightBracket")
	Input.bind("selectaim.prev", "LeftBracket")
	Input.bind("ghost.toggle", "None")
	Input.bind("music.toggle", "None")
	Input.bind("lowprofile.toggle", "None")
	Input.bind("training.toggle", "None")
	Input.bind("hub.unload", "None")
end

local function registerModules(h)
	local Window = import("ui/Window")
	local Pages = import("ui/Pages")
	local F = import("ui/Framework")
	local Sounds = import("features/Sounds")
	local Tools = import("features/Tools")

	Core.registerModule({
		name = "services",
		start = function(ctx)
			local rs = Services.RunService
			ctx.maid:Give(rs.RenderStepped:Connect(function(dt)
				Perf.frame(dt)
			end))
			Perf.setSources({
				ping = function()
					return Services.Players.LocalPlayer:GetNetworkPing() * 1000
				end,
			})
			local c1 = Perf.every("core.notify", 10, function(dt) Notify.tick(dt) end)
			local c2 = Perf.every("core.autosave", 2, function(dt) Config.tick(dt) end)
			local c3 = Perf.every("core.tools", 10, function(dt) Tools.tick(dt) end)
			ctx.maid:Give(c1.Cancel); ctx.maid:Give(c2.Cancel); ctx.maid:Give(c3.Cancel)
			ctx.maid:Give(Perf.TaskFailed:Connect(function(name, err)
				Notify.push({ title = "Task disabled", text = name .. " failed repeatedly and was stopped.", level = "error" })
			end))
		end,
	})
	Core.registerModule({
		name = "input",
		deps = { "services" },
		start = function(ctx)
			Input.connect(Services.UserInputService, ctx.maid, Window.isVisible)
		end,
	})
	Core.registerModule({ name = "sounds", deps = { "services" }, start = function(ctx)
		Sounds.start(ctx)
		F.setClickHandler(function() Sounds.play("uiClick") end)
		ctx.maid:Give(function() F.setClickHandler(nil) end)
	end })
	Core.registerModule({ name = "window", deps = { "services", "input" }, optionalEnv = { "gethui" }, start = function(ctx)
		Pages.registerAll()
		Window.start(ctx)
		ctx.maid:Give(function() Window._reset() end)
	end })
	for _, def in ipairs({
		{ "crosshair", "features/Crosshair", { "services" } },
		{ "camera", "features/Camera", { "services" } },
		{ "lighting", "features/Lighting", { "services" } },
		{ "training", "features/Training", { "services", "sounds" } },
		{ "drone", "features/Drone", { "services", "training", "window" } },
		{ "cosmetics", "features/Cosmetics", { "services" } },
		{ "music", "features/Music", { "services" } },
		{ "screenbuttons", "ui/ScreenButtons", { "services" } },
		{ "antifling", "features/AntiFling", { "services" } },
		{ "selectaim", "features/TargetSelect", { "services", "training" } },
		{ "ghost", "features/Ghost", { "services" } },
	}) do
		local mod = import(def[2])
		Core.registerModule({ name = def[1], deps = def[3], start = function(ctx) mod.start(ctx) end })
	end
end

local function registerDiagnostics()
	Diagnostics.addProvider("Modules", function()
		local lines = {}
		for _, m in ipairs(Core.status()) do
			table.insert(lines, string.format("%-12s %-8s %6.1f ms  attempts=%d%s", m.name, m.state, m.startMs, m.attempts, m.err and ("  " .. string.match(m.err, "^[^\n]*")) or ""))
		end
		return lines
	end)
	Diagnostics.addProvider("Config", function()
		return {
			"active profile: " .. Config.active(),
			"profiles: " .. table.concat(Config.list(), ", "),
			"unsaved changes: " .. tostring(Config.isDirty()),
		}
	end)
	Diagnostics.addProvider("Settings changed from default", function()
		local lines = {}
		for _, key in ipairs(Settings.keys({ scope = "profile" })) do
			if not Settings.isDefault(key) then
				local v = Settings.get(key)
				table.insert(lines, key .. " = " .. (type(v) == "table" and "{…}" or tostring(v)))
			end
		end
		return #lines > 0 and lines or { "(none)" }
	end)
	Diagnostics.addProvider("Scheduler", function()
		local lines = {}
		for _, t in ipairs(Perf.timings()) do
			table.insert(lines, string.format("%-22s avg %.3f ms  max %.2f ms  calls %d%s", t.name, t.avgMs, t.maxMs, t.calls, t.disabled and "  DISABLED" or ""))
		end
		return lines
	end)
end

-- run(opts) -> handle. opts.skipLicense is for tests only.
function Hub.run(opts)
	opts = opts or {}
	Signal.onError = function(msg, name)
		Logger.error("Signal", "%s: %s", tostring(name), tostring(msg))
	end

	local handle = { started = false }
	local bootHandle = Core.boot({ shutdown = function() if handle.unload then handle.unload() end end })
	handle.replaced = bootHandle.replaced

	function handle.unload()
		if not handle.started and not handle.pending then
			return
		end
		handle.started, handle.pending = false, false
		pcall(Config.flush)
		local report = Core.stopAll()
		local cleanup = Cleanup.run()
		if handle.mainMaid then
			handle.mainMaid:Clean()
		end
		-- leave every singleton pristine so the hub can be started again in the same session
		for _, title in ipairs({ "Modules", "Config", "Settings changed from default", "Scheduler" }) do
			Diagnostics.removeProvider(title)
		end
		Actions._reset()
		Input._reset()
		Config._reset()
		Perf._reset()
		Notify._reset()
		Core._reset()
		Search.invalidate()
		Settings._reset()
		Core.release()
		Services.clear()
		current = nil
		Logger.info("Hub", "unloaded (%d modules stopped, %d errors)", report.stopped, report.errors + #cleanup.failed)
	end

	local function boot()
		handle.mainMaid = Maid.new("hub")
		if not Settings.has("ui.theme") then
			defineSettings()
		end
		local cfg = Config.init()
		Config.attach(handle.mainMaid)
		I18n.set(Settings.get("ui.language"))
		handle.mainMaid:Give(Settings.observe("ui.language", function(v) I18n.set(v) end))
		-- device class: small compact layout and on-screen buttons on phones (applied once)
		local uis = Services.UserInputService
		local cam = Services.Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		handle.platform = Platform.ensure(uis.TouchEnabled, uis.KeyboardEnabled, vp.X, vp.Y)
		registerActions(handle)
		registerDiagnostics()
		registerModules(handle)
		local problems = Core.checkDependencies()
		for _, p in ipairs(problems) do
			if p.kind ~= "missing-env" then
				Logger.error("Core", "dependency problem in %s: %s %s", p.module, p.kind, p.detail)
			else
				Logger.warn("Core", "%s: optional executor API missing: %s", p.module, p.detail)
			end
		end
		local report = Core.startAll({ hub = handle })
		handle.report = report
		handle.started = true
		handle.config = cfg
		Logger.info("Hub", "%s started: %d modules running, %d failed, %d blocked", Version.info(), #report.started, #report.failed, #report.blocked)
		if not cfg.persistent then
			Notify.push({ title = "Storage", text = I18n.t("notify.nofileio"), level = "warn", duration = 7 })
		end
		for _, name in ipairs(report.failed) do
			Notify.push({ title = "Module failed", text = name .. " did not start. See Diagnostics.", level = "error", duration = 8 })
		end
		Notify.push({ title = Version.NAME .. " " .. Version.VERSION, text = "Press " .. (Input.keyOf("window.toggle") or "the launcher") .. " to toggle the hub.", level = "success" })
		if Settings.get("music.autoplay") then
			-- Music handles autoplay itself on start; nothing to do here.
		end
	end

	if License.isRequired() and not opts.skipLicense then
		handle.pending = true
		local ok = License.verifyStored()
		if ok then
			defineSettings()
			boot()
			handle.pending = false
		else
			defineSettings()
			local Gate = import("ui/LicenseGate")
			handle.gate = Gate.show(function()
				if handle.pending then
					boot()
					handle.pending = false
				end
			end)
		end
	else
		boot()
	end
	current = handle
	return handle
end

function Hub.current()
	return current
end

return Hub

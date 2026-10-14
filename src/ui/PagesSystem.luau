--!nonstrict
-- ui/PagesSystem: performance, tools, hotkeys, configurations, diagnostics, help and about pages.
-- Depends on: PageKit, Framework, Theme, Settings, Config, Input, Perf, Core, Diagnostics, Logger, Maid,
--   Tools, Registry, Version, Env, License(optional), Window.

local import = ...
local Kit = import("ui/PageKit")
local F = import("ui/Framework")
local Theme = import("ui/Theme")
local Settings = import("core/Settings")
local Config = import("core/Config")
local Input = import("core/Input")
local Perf = import("core/Perf")
local Core = import("core/Core")
local Diagnostics = import("core/Diagnostics")
local Logger = import("core/Logger")
local Maid = import("core/Maid")
local Tools = import("features/Tools")
local Registry = import("core/Registry")
local Version = import("core/Version")
local Env = import("core/Env")
local Sounds = import("features/Sounds")
local Window = import("ui/Window")
local I18n = import("core/I18n")

local notify, visible, auto, section, resetButton, dataList, infoLine = Kit.notify, Kit.visible, Kit.auto, Kit.section, Kit.resetButton, Kit.dataList, Kit.infoLine

local S = {}

local function buttonRow(page, buttons, height)
	local card = F.frame(page.content, { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, height or 40) })
	F.list(card, 8, true)
	for i, b in ipairs(buttons) do
		local btn = F.button(card, b.text, b.fn, b.style or "tinted", UDim2.fromOffset(b.width or 130, (height or 40) - 6), page.maid)
		btn.LayoutOrder = i
	end
	return card
end

-- Performance ------------------------------------------------------------------------------------------------------------------

function S.perf(page)
	local update = page:stats({
		{ title = "FPS", value = "—" }, { title = "PING", value = "—" }, { title = "TASKS", value = "0" }, { title = "UI BINDINGS", value = "0" },
	})
	local timings = dataList(page, { rowHeight = 44, maxRows = 12 })
	local handle
	local function refresh()
		update(1, string.format("%d", Perf.fps() + 0.5), Perf.fps() < 30 and "warn" or "text")
		local ping = Perf.ping()
		update(2, ping and string.format("%d ms", ping) or "n/a")
		update(3, tostring(Perf.taskCount()))
		update(4, tostring(Theme.bindingCount()))
		local items = {}
		for _, t in ipairs(Perf.timings()) do
			table.insert(items, {
				title = t.name, raw = true, rawValue = false,
				sub = I18n.tr(string.format("avg %.3f ms · max %.2f ms · %s Hz%s", t.avgMs, t.maxMs, t.hz >= 999 and "per-frame" or tostring(t.hz), t.visual and " · visual" or "")),
				value = t.disabled and "DISABLED" or (t.errors > 0 and (t.errors .. " errors") or (t.calls .. " calls")),
				valueToken = (t.disabled or t.errors > 0) and "bad" or "textDim",
			})
		end
		timings.set(items)
	end
	page:section("Live")
	handle = Perf.every("ui.perf", 1, function()
		if visible("perf") then
			refresh()
		end
	end)
	page.maid:Give(handle.Cancel)
	refresh()
	page:note("Timings are measured with os.clock() around each scheduled task on your machine, not synthetic benchmarks. A long-operation warning is logged above the threshold below.", "textDim", 44)
	resetButton(page, "Performance")
	section(page, "Load control", { "perf.lowProfile", "perf.autoLow", "perf.autoLowFps", "perf.visualHz", "perf.maxDecor", "perf.warnMs" })
	page:section("Recent long operations")
	local long = dataList(page, { rowHeight = 36, maxRows = 8 })
	local function renderLong()
		local items = {}
		for _, op in ipairs(Perf.longOps()) do
			table.insert(items, { title = op.name, raw = true, value = string.format("%.1f ms", op.ms), valueToken = "warn" })
		end
		if #items == 0 then
			items[1] = { title = "none recorded", titleToken = "textDim" }
		end
		long.set(items)
	end
	local h2 = Perf.every("ui.perf.long", 0.5, function()
		if visible("perf") then
			renderLong()
		end
	end)
	page.maid:Give(h2.Cancel)
	renderLong()
end

-- Tools ----------------------------------------------------------------------------------------------------------------------------

local function parseSeconds(text)
	text = string.match(text or "", "^%s*(.-)%s*$")
	local mm, ss = string.match(text, "^(%d+):(%d+)$")
	if mm then
		return tonumber(mm) * 60 + tonumber(ss)
	end
	local n, unit = string.match(text, "^(%d+%.?%d*)%s*([smh]?)$")
	if n then
		local mult = unit == "m" and 60 or (unit == "h" and 3600 or 1)
		return tonumber(n) * mult
	end
	return nil
end

function S.tools(page)
	local sessionUpdate = infoLine(page, "Session time", function()
		return Tools.formatTime(Tools.sessionSeconds())
	end)
	page:section("Stopwatch")
	local card = page:card(96)
	F.padding(card, 16, 10, 16, 10)
	local display = F.label(card, "00:00.0", { size = 32, bold = true, dim = UDim2.new(1, 0, 0, 40) })
	local btns = F.frame(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34) })
	F.list(btns, 8, true)
	local startBtn
	startBtn = F.button(btns, "Start", function()
		Tools.stopwatchToggle()
		startBtn.Text = Tools.stopwatchRunning() and "Stop" or "Start"
	end, "filled", UDim2.fromOffset(100, 32), page.maid)
	local laps = dataList(page, { rowHeight = 34, maxRows = 10 })
	local function renderLaps()
		local items = {}
		local all = Tools.laps()
		for i = #all, math.max(1, #all - 9), -1 do
			table.insert(items, { title = "Lap " .. i, value = Tools.formatTime(all[i].total, true), sub = "" })
		end
		laps.set(items)
	end
	F.button(btns, "Lap", function()
		Tools.stopwatchLap()
		renderLaps()
	end, "tinted", UDim2.fromOffset(80, 32), page.maid)
	F.button(btns, "Reset", function()
		Tools.stopwatchReset()
		startBtn.Text = "Start"
		renderLaps()
	end, "tinted", UDim2.fromOffset(80, 32), page.maid)

	page:section("Countdown timers")
	local nameBox, durBox
	local r1, h1 = page:row({ label = "Name", width = 200 })
	nameBox = F.textBox(h1, { placeholder = "optional", dim = UDim2.fromOffset(200, 30) }, page.maid)
	nameBox.AnchorPoint = Vector2.new(1, 0.5); nameBox.Position = UDim2.fromScale(1, 0.5)
	local r2, h2 = page:row({ label = "Duration", desc = "90 · 1:30 · 5m · 2h", width = 200 })
	durBox = F.textBox(h2, { placeholder = "e.g. 5m", dim = UDim2.fromOffset(200, 30) }, page.maid)
	durBox.AnchorPoint = Vector2.new(1, 0.5); durBox.Position = UDim2.fromScale(1, 0.5)
	local timerList
	local function renderTimers()
		local items = {}
		for _, t in ipairs(Tools.timers()) do
			table.insert(items, { id = t.id, title = t.name, value = t.done and "done" or Tools.formatTime(t.remaining), valueToken = t.done and "good" or "text", paused = not t.running and not t.done })
		end
		timerList.set(items)
	end
	timerList = dataList(page, {
		rowHeight = 38, maxRows = 8,
		buttons = {
			{ icon = "pause", tip = "Pause / resume", fn = function(item)
				for _, t in ipairs(Tools.timers()) do
					if t.id == item.id then
						Tools.pauseTimer(item.id, t.running)
					end
				end
				renderTimers()
			end },
			{ icon = "close", tip = "Remove", token = "bad", fn = function(item)
				Tools.removeTimer(item.id)
				renderTimers()
			end },
		},
	})
	buttonRow(page, { { text = "Add timer", style = "filled", fn = function()
		local secs = parseSeconds(durBox.Text)
		if not secs then
			notify("Timers", "Enter a duration like 90, 1:30, 5m or 2h.", "warn")
			return
		end
		local id, err = Tools.addTimer(nameBox.Text, secs)
		if id then
			nameBox.Text, durBox.Text = "", ""
			renderTimers()
		else
			notify("Timers", tostring(err), "warn")
		end
	end } })
	page.maid:Give(Tools.TimerDone:Connect(function(_, name)
		notify("Timer finished", name, "success")
		if Settings.get("tools.timerSound") then
			Sounds.play("uiClick")
		end
		renderTimers()
	end))

	page:section("Notes")
	local notesCard = page:card(150)
	F.padding(notesCard, 10, 10, 10, 10)
	local notesBox = F.textBox(notesCard, { multiline = true, placeholder = "Local notes, saved to MM2Hub/notes.txt", text = Tools.getNotes(), dim = UDim2.fromScale(1, 1) }, page.maid)
	page.maid:Give(notesBox:GetPropertyChangedSignal("Text"):Connect(function()
		Tools.setNotes(notesBox.Text)
	end))
	page.maid:Give(notesBox.FocusLost:Connect(function()
		Tools.saveNotes()
	end))
	auto(page, "tools.notesAutosave")
	auto(page, "tools.timerSound")

	local h = Perf.every("ui.tools", 8, function()
		if visible("tools") then
			sessionUpdate()
			display.Text = Tools.formatTime(Tools.stopwatchElapsed(), true)
			renderTimers()
		end
	end)
	page.maid:Give(h.Cancel)
	Tools.loadNotes()
	notesBox.Text = Tools.getNotes()
end

-- Hotkeys -------------------------------------------------------------------------------------------------------------------------------

function S.keys(page)
	local note, noteLabel = page:note("", "warn", 34)
	local function refresh()
		local c = Input.conflicts()
		note.Visible = #c > 0
		if #c > 0 then
			noteLabel.Text = string.format("⚠ %s is assigned to more than one action.", c[1].key)
		end
	end
	page.maid:Give(Settings.Changed:Connect(function(key)
		if string.sub(key, 1, 5) == "keys." then
			refresh()
		end
	end))
	refresh()
	section(page, "Input", { "input.enabled", "input.ignoreTyping" })
	page:section("Bindings  (click a box, then press a key · Esc cancels)")
	for _, b in ipairs(Input.list()) do
		page:keybind({ actionId = b.id })
	end
	buttonRow(page, { { text = "Reset all hotkeys", style = "danger", width = 170, fn = function()
		for _, b in ipairs(Input.list()) do
			Input.resetBinding(b.id)
		end
		notify("Hotkeys", "All hotkeys reset to defaults.", "success")
	end } })
	page:note("Mouse buttons 2 and 3 can be bound too. On touch devices use the floating launcher button.", "textDim", 30)
end

-- Configurations ------------------------------------------------------------------------------------------------------------------------------

function S.configs(page)
	local activeLine = infoLine(page, "Active profile", function()
		return Config.active() .. (Env.persistent() and "" or "  (session only)")
	end)
	if not Env.persistent() then
		page:note("No file API detected in this executor: profiles live only in memory for this session. Export a profile string to keep it.", "warn", 44)
	end
	local list
	local function render()
		local items = {}
		for _, name in ipairs(Config.list()) do
			table.insert(items, { name = name, title = name, raw = true, rawValue = false, value = I18n.tr(name == Config.active() and "active" or ""), valueToken = "good" })
		end
		list.set(items)
		activeLine()
	end
	page:section("Profiles")
	list = dataList(page, {
		rowHeight = 40, maxRows = 20,
		buttons = {
			{ icon = "check", tip = "Load", fn = function(item)
				local ok, res = Config.load(item.name)
				notify("Profile", ok and ("Loaded '" .. item.name .. "'") or tostring(res), ok and "success" or "error")
				render()
			end },
			{ icon = "plus", tip = "Duplicate", fn = function(item)
				local ok, res = Config.duplicate(item.name, item.name .. "_copy")
				if not ok then
					notify("Duplicate", tostring(res), "warn")
				end
				render()
			end },
			{ icon = "trash", tip = "Delete", token = "bad", fn = function(item)
				F.confirm({ title = "Delete profile", text = "Delete '" .. item.name .. "'? This cannot be undone.", danger = true, confirmText = "Delete", onConfirm = function()
					local ok, err = Config.delete(item.name)
					if not ok then
						notify("Delete", tostring(err), "warn")
					end
					render()
				end })
			end },
		},
	})
	page.maid:Give(Config.Changed:Connect(render))

	local newBox
	local r, h = page:row({ label = "New / rename", desc = "Letters, digits, space, _ and - (max 32)", width = 220 })
	newBox = F.textBox(h, { placeholder = "profile name", dim = UDim2.fromOffset(220, 30) }, page.maid)
	newBox.AnchorPoint = Vector2.new(1, 0.5); newBox.Position = UDim2.fromScale(1, 0.5)
	buttonRow(page, {
		{ text = "Create from current", style = "filled", width = 170, fn = function()
			local ok, res = Config.create(newBox.Text, true)
			notify("Profile", ok and ("Created '" .. res .. "'") or tostring(res), ok and "success" or "warn")
			if ok then newBox.Text = "" end
		end },
		{ text = "Rename active", width = 140, fn = function()
			local ok, res = Config.rename(Config.active(), newBox.Text)
			notify("Profile", ok and ("Renamed to '" .. res .. "'") or tostring(res), ok and "success" or "warn")
		end },
		{ text = "Save now", width = 110, fn = function()
			local ok, err = Config.save()
			notify("Profile", ok and "Saved." or tostring(err), ok and "success" or "error")
		end },
	})

	page:section("Export / import")
	local ioBox = F.frame(page.content, { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 90) })
	local io = F.textBox(ioBox, { multiline = true, placeholder = "Export string appears here; paste one to import", dim = UDim2.fromScale(1, 1) }, page.maid)
	buttonRow(page, {
		{ text = "Export active", width = 140, style = "filled", fn = function()
			local s, err = Config.exportString(Config.active())
			if not s then
				notify("Export", tostring(err), "error")
				return
			end
			io.Text = s
			local copied = Env.clipboard(s)
			notify("Export", copied and "Copied to clipboard." or "Shown in the box (no clipboard API).", "success")
		end },
		{ text = "Import as new", width = 150, fn = function()
			local ok, rep = Config.importString(io.Text)
			if ok then
				notify("Import", "Imported as '" .. rep.name .. "'" .. ((#rep.rejected + #rep.unknown) > 0 and string.format(" (%d value(s) skipped)", #rep.rejected + #rep.unknown) or ""), "success")
			else
				notify("Import failed", tostring(rep.error), "error")
			end
		end },
	})

	page:section("Compare & integrity")
	local diffList = dataList(page, { rowHeight = 36, maxRows = 20 })
	buttonRow(page, {
		{ text = "Compare active with live", width = 190, fn = function()
			local diff, err = Config.diff(Config.active(), nil)
			if not diff then
				notify("Compare", tostring(err), "error")
				return
			end
			local items = {}
			for _, d in ipairs(diff) do
				table.insert(items, { title = d.key, value = tostring(type(d.a) == "table" and "…" or d.a) .. " → " .. tostring(type(d.b) == "table" and "…" or d.b) })
			end
			if #items == 0 then
				items[1] = { title = "No differences: live settings equal the saved profile.", titleToken = "good" }
			end
			diffList.set(items)
		end },
		{ text = "Check integrity", width = 150, fn = function()
			local items = {}
			for _, r in ipairs(Config.checkIntegrity()) do
				table.insert(items, { title = r.name, sub = r.problem or "", value = r.ok and "OK" or "PROBLEM", valueToken = r.ok and "good" or "bad" })
			end
			diffList.set(items)
		end },
	})
	render()
end

-- Diagnostics ----------------------------------------------------------------------------------------------------------------------------------

function S.diagnostics(page)
	buttonRow(page, {
		{ text = "Export report", style = "filled", width = 150, fn = function()
			local ok, msg = Diagnostics.export()
			notify("Report", tostring(msg), ok and "success" or "error")
		end },
		{ text = "Clear log", width = 120, fn = function() Logger.clear() end },
	})
	page:section("Modules")
	local mods
	mods = dataList(page, {
		rowHeight = 46, maxRows = 24,
		buttons = { { icon = "repeatIcon", tip = "Restart module", fn = function(item)
			local ok, err = Core.restart(item.name)
			notify("Module", item.name .. (ok and " restarted" or (" failed: " .. tostring(err))), ok and "success" or "error")
		end } },
	})
	page:section("Environment")
	local caps = dataList(page, { rowHeight = 30, maxRows = 20 })
	page:section("Resources")
	local res = dataList(page, { rowHeight = 30, maxRows = 12 })
	page:section("Setting conflicts")
	local conflicts = dataList(page, { rowHeight = 40, maxRows = 10 })
	page:section("Recent setting changes")
	local history = dataList(page, { rowHeight = 34, maxRows = 12 })
	page:section("Log")
	local logList = dataList(page, { rowHeight = 32, maxRows = 25 })

	local function short(v)
		if type(v) == "table" then
			return "…"
		end
		return string.sub(tostring(v), 1, 18)
	end
	local function refresh()
		local items = {}
		for _, m in ipairs(Core.status()) do
			table.insert(items, {
				name = m.name, title = m.name, raw = true, rawValue = false,
				sub = m.err and string.sub(string.match(m.err, "^[^\n]*"), 1, 90) or I18n.tr(string.format("started in %.1f ms · attempts %d", m.startMs, m.attempts)),
				value = I18n.tr(m.state), valueToken = m.state == "running" and "good" or (m.state == "failed" and "bad" or "warn"),
			})
		end
		mods.set(items)
		local ci = {}
		for _, c in ipairs(Env.capList()) do
			table.insert(ci, { title = c.name, raw = true, rawValue = false, value = I18n.tr(c.available and "yes" or "no"), valueToken = c.available and "good" or "textDim" })
		end
		caps.set(ci)
		local stats = Maid.stats()
		local ri = {
			{ title = "Maids / tracked tasks", value = stats.maids .. " / " .. stats.tasks },
			{ title = "Scheduled tasks", value = tostring(Perf.taskCount()) },
			{ title = "Theme bindings", value = tostring(Theme.bindingCount()) },
			{ title = "UI pages built", value = tostring(Window.builtPageCount()) },
			{ title = "Log entries (warn / error)", value = Logger.count("warn") .. " / " .. Logger.count("error") },
		}
		res.set(ri)
		local cf = {}
		for _, c in ipairs(Settings.conflicts()) do
			table.insert(cf, { title = c.message, titleToken = "warn" })
		end
		if #cf == 0 then
			cf[1] = { title = "No conflicting settings found.", titleToken = "good" }
		end
		conflicts.set(cf)
		local hi = {}
		local all = Settings.history()
		for i = #all, math.max(1, #all - 11), -1 do
			local e = all[i]
			table.insert(hi, { title = e.key, raw = true, rawValue = true, value = short(e.old) .. " → " .. short(e.new), sub = e.source })
		end
		if #hi == 0 then
			hi[1] = { title = "No changes yet this session.", titleToken = "textDim" }
		end
		history.set(hi)
		local li = {}
		local entries = Logger.entries()
		for i = #entries, math.max(1, #entries - 24), -1 do
			local e = entries[i]
			table.insert(li, { title = e.message, raw = true, rawValue = false, value = I18n.tr(e.level), valueToken = e.level == "error" and "bad" or (e.level == "warn" and "warn" or "textDim") })
		end
		logList.set(li)
	end
	local h = Perf.every("ui.diagnostics", 1, function()
		if visible("diagnostics") then
			refresh()
		end
	end)
	page.maid:Give(h.Cancel)
	refresh()
end

-- Help / About --------------------------------------------------------------------------------------------------------------------------------------

function S.help(page)
	local topics = {
		{ "Opening the hub", "Press the configured hotkey (default RightShift) or tap the round launcher button. Drag the title bar to move, drag the bottom-right grip to resize, use – to collapse into the quick bar." },
		{ "Search", "Type in the top box to search names, descriptions and categories (Russian names too). Start with > to run a command. Use the chips to filter by Active, Favourites or category." },
		{ "Favourites & recents", "Tap the star on any setting that belongs to a catalogued feature. Favourites appear on the dashboard and as buttons in the quick bar; recently changed features are listed too." },
		{ "Profiles", "Settings autosave to the active profile. Create, duplicate, rename or delete profiles on the Configs page; export gives a checksummed text string you can share and import elsewhere." },
		{ "Hotkeys", "Open the Hotkeys page, click a key box and press the new key. Duplicate keys are refused unless you confirm moving them." },
		{ "Crosshair, camera, environment", "Everything is local to your screen and reversible: switching a feature off, resetting a page or unloading the hub restores the original game values." },
		{ "Training range", "Targets and the dummy exist only on your client. They never affect other players." },
		{ "Cosmetics, music, sounds", "You supply the content: asset ids you can use, or files in MM2Hub/models, MM2Hub/music and MM2Hub/sounds. Nothing is downloaded from third-party sites." },
		{ "Mobile", "Use the launcher button and the Interface page to raise text size or scale." },
		{ "Troubleshooting", "Open Diagnostics: module states, executor capabilities, recent warnings. Export the report and send it when asking for help." },
	}
	for _, t in ipairs(topics) do
		page:section(t[1])
		page:note(t[2], "text", 62)
	end
end

function S.about(page)
	page:stats({
		{ title = "VERSION", value = Version.VERSION }, { title = "CONFIG SCHEMA", value = tostring(Version.SCHEMA) },
		{ title = "FEATURES", value = tostring(Registry.count()) }, { title = "STORAGE", value = Env.persistent() and "files" or "session" },
	})
	page:section("Feature status (honest)")
	local c = Registry.statusCounts()
	page:note(string.format("%d features catalogued: %d logic-tested, %d implemented (UI/engine code, verified only against a mock), %d environment-dependent, %d partial. Status of each feature is listed in docs/FEATURES.md.", Registry.count(), c.tested, c.implemented, c.env, c.partial), "text", 62)
	page:section("Changelog")
	for _, entry in ipairs(Version.changelog) do
		local notes = (I18n.get() == "ru" and entry.notesRu) or entry.notes
		page:note("v" .. entry.version .. "  ·  " .. entry.date .. "\n• " .. table.concat(notes, "\n• "), "text", 24 + #notes * 34)
	end
	page:section("Limits")
	page:note("This hub is client-side. It cannot reveal hidden game data (such as other players' roles) and it does not interact with or affect other players. License keys are time-limited and signed; see the security note in the documentation for what that does and does not protect.", "textDim", 70)
end

return S

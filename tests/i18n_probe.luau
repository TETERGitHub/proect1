--!nonstrict
-- tests/i18n_probe: drives the whole UI in Russian and returns every visible English text that has no translation.
local import = ...
local Mock = import("tests/mock_roblox")
local T = import("tests/Framework")
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local I18n = import("core/I18n")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Notify = import("core/Notify")
local Training = import("features/Training")
local Music = import("features/Music")
local Tools = import("features/Tools")
local Config = import("core/Config")
local Recents = import("core/Recents")
local TargetSelect = import("features/TargetSelect")
local Actions = import("core/Actions")

local Probe = {}

local function frames(n, dt) for _ = 1, n do Perf.frame(dt or 1 / 30) end end

-- the "Unload hub" command (a search result) would end the very run being probed
local function isUnload(button)
	for _, d in ipairs(button:GetDescendants()) do
		if d:IsA("TextLabel") and type(d.Text) == "string" and (string.find(d.Text, "Unload hub", 1, true) or string.find(d.Text, "Выгрузить хаб", 1, true)) then return true end
	end
	return false
end

local function clickAll(root)
	local buttons = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextButton") and d.Name ~= "Launcher" and d.Name ~= "SheetBackdrop" and d.Name ~= "PopoverCatcher" and not isUnload(d) then table.insert(buttons, d) end
	end
	for _, b in ipairs(buttons) do
		pcall(function() b.Activated:Fire({ UserInputType = "MouseButton1", Position = Mock.v3(0, 0, 0) }, 1) end)
	end
end

-- run(): returns the sorted list of untranslated visible texts
function Probe.run(lang)
	lang = lang or "ru"
	T.fresh()
	Mock.uninstall()
	local game = Mock.install()
	Services.clear()
	local h = Hub.run({ skipLicense = true })
	I18n.set(lang); I18n.clearMisses()
	Window.relocalize()
	-- restarting the window module (a Diagnostics button) replaces the ScreenGui, so it is looked up fresh each time
	local function GUI() return game.__services.CoreGui:FindFirstChild("MM2Hub") end
	local gui = GUI()
	-- exercise dynamic states
	Settings.set("training.enabled", true); Training.spawnDummy(); Training.spawnLab(); Training.fireProbe()
	local p = Mock.makeInstance("Part"); p.Name = "X"; p.Position = Mock.v3(0, 10, -20); p.Parent = game.Workspace
	Settings.set("selectaim.enabled", true); Settings.set("selectaim.prediction", true)
	Music.add("asset:111", "Песня"); Music.add("file:a.mp3", "")
	Tools.addTimer("", 60); Tools.stopwatchStart(); Tools.setNotes("n")
	Recents.toggleFavorite("xh.enable"); Recents.toggleFavorite("win.toggle"); Recents.toggleFavorite("ui.theme"); Recents.touch("cam.fov")
	Settings.set("perf.lowProfile", true); Settings.set("lighting.blurEnabled", true)
	Config.create("Test", true)
	for _, kind in ipairs({ "info", "success", "warn", "error" }) do Notify.push({ title = "Test", text = "Operation completed", level = kind }) end
	frames(40)
	-- every page, with every button pressed once (confirm sheets get their own pass)
	for _, id in ipairs(Window.pageIds()) do
		Window.navigate(id); frames(10)
		clickAll(GUI()); frames(5); clickAll(GUI()); frames(3)
		Window.show()
	end
	-- search page, commands, filters
	Window.navigate("dashboard")
	for _, q in ipairs({ "crosshair", ">toggle", "zzzzzz", "" }) do
		local box = GUI().Root.Window.TitleBar:FindFirstChildOfClass("TextBox")
		if box then box.Text = q; frames(8) end
	end
	clickAll(GUI()); frames(5)
	Tools.tick(1000); frames(20)
	local misses = I18n.misses()
	h.unload(); Mock.uninstall()
	I18n.set("en")
	return misses
end

return Probe

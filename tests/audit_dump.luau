--!nonstrict
-- tests/audit_dump: not part of the suite. Boots the hub on the mock, visits every page and presses every button
-- one at a time, recording what each press did (action run, setting changed, notification, navigation, other UI
-- change, nothing). tools/audit_registry.py runs it and writes the result into docs/AUDIT.md.
local import = ...
local Mock = import("tests/mock_roblox")
local T = import("tests/Framework")
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Notify = import("core/Notify")
local Recents = import("core/Recents")
local Config = import("core/Config")
local Training = import("features/Training")
local Music = import("features/Music")
local Tools = import("features/Tools")
local Actions = import("core/Actions")
local Json = import("core/Json")
local I18n = import("core/I18n")

local function frames(n) for _ = 1, n do Perf.frame(1 / 30) end end
local SKIP = { Launcher = true, SheetBackdrop = true, PopoverCatcher = true }

-- visible = no ancestor below the ScreenGui is hidden (built pages stay in the tree while another page is shown)
local function shown(inst, root)
	local cur = inst
	while cur and cur ~= root do
		if cur:IsA("GuiObject") and cur.Visible == false then return false end
		cur = cur.Parent
	end
	return true
end

local function buttonsOf(gui, pageId)
	local list = {}
	local entry = Window.page(pageId)
	local root = entry and entry.group or gui
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextButton") and not SKIP[d.Name] then table.insert(list, d) end
	end
	return list
end

-- what a person would call this control: the nearest row named after a setting (or any named row) plus its label
local function describe(b, root)
	local cur, rowName = b.Parent, nil
	while cur and cur ~= root do
		if Settings.has(cur.Name) then rowName = cur.Name break end
		cur = cur.Parent
	end
	local label
	local scope = cur and cur ~= root and cur or b.Parent
	if scope then
		for _, d in ipairs(scope:GetDescendants()) do
			if d:IsA("TextLabel") and type(d.Text) == "string" and d.Text ~= "" then label = d.Text break end
		end
	end
	return rowName, label
end

T.fresh(); Mock.uninstall()
local game = Mock.install(); Services.clear()
local h = Hub.run({ skipLicense = true })
I18n.set("en"); Window.relocalize()
Settings.set("ui.animSpeed", 0) -- no tweens: a page switch hides the old page immediately
local gui = game.__services.CoreGui.MM2Hub
-- seed state so "reset / stop / clear / remove" buttons have something to act on
Music.add("asset:111", "Track A"); Music.add("file:a.mp3", "")
Tools.addTimer("", 60); Tools.stopwatchStart(); Tools.setNotes("n")
Settings.set("training.enabled", false)
local world = game.Workspace
local function worldCount() return #world:GetDescendants() end
local rows, pageKeys = {}, {}
local ran, changed = {}, {}
Actions.Ran:Connect(function(id, ok, err) table.insert(ran, id .. (ok and "" or (" FAILED " .. tostring(err)))) end)
Settings.Changed:Connect(function(key) table.insert(changed, key) end)

local clock = os.clock
local started = clock()
for _, pageId in ipairs(Window.pageIds()) do
	Window.navigate(pageId); frames(4)
	local keys = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if Settings.has(d.Name) then keys[d.Name] = true end
	end
	local list = {}
	for k in pairs(keys) do table.insert(list, k) end
	table.sort(list)
	pageKeys[pageId] = list
	local btns = buttonsOf(gui, pageId)
	local total = #btns
	for i = 1, total do
		-- a press can rebuild the page (its old buttons are then dead), so the list is re-read for every press
		btns = buttonsOf(gui, pageId)
		local b = btns[i]
		if b then
			Settings.set("state.favorites", {}, "audit") -- keep the favourites limit out of the picture
			table.clear(ran); table.clear(changed)
			local rk0 = describe(b, gui)
			local before = rk0 and Settings.get(rk0)
			local notifyBefore, favBefore, recBefore, worldBefore = #Notify.history(), #Recents.favorites(), #Recents.recent(), worldCount()
			local ok, err = pcall(function() b.Activated:Fire({ UserInputType = "MouseButton1", Position = Mock.v3(0, 0, 0) }, 1) end)
			frames(1)
			local effect
			if not ok then effect = "ERROR " .. tostring(err)
			elseif #ran > 0 then effect = "action " .. table.concat(ran, ",")
			elseif #changed > 0 then effect = "setting " .. table.concat(changed, ",")
			elseif #Notify.history() > notifyBefore then effect = "notification"
			elseif #Recents.favorites() ~= favBefore then effect = "favourite toggled"
			elseif worldCount() ~= worldBefore then effect = "world instances changed"
			elseif Window.currentPage() ~= pageId then effect = "navigate " .. tostring(Window.currentPage())
			elseif not b.Parent then effect = "ui (page rebuilt)"
			else effect = "NONE" end
			local rowKey, rowLabel = describe(b, gui)
			local after = rowKey and Settings.get(rowKey)
			-- sliders, colour swatches and key-capture boxes take a drag / pick / key press: a bare click carries no value
			local def = rowKey and Settings.schema(rowKey)
			if effect == "NONE" and def and def.type == "enum" then
				for _, d in ipairs(gui:GetDescendants()) do if d.Name == "PopoverCatcher" and d.Visible ~= false then effect = "opens dropdown list" break end end
			end
			if effect == "NONE" and def and b.Text == "" and (def.kind == "number" or def.kind == "color" or def.kind == "key" or def.type == "number" or def.type == "color" or def.type == "key") then effect = "value control (needs drag/pick/key)" end
			local row = { page = pageId, name = b.Name, text = b.Text, key = rowKey, label = rowLabel, effect = effect, chain = (function() local c, cur = {}, b while cur and cur ~= gui and #c < 4 do table.insert(c, cur.Name) cur = cur.Parent end return table.concat(c, "<") end)(), idx = i, before = tostring(before), after = tostring(after), type = def and def.type }
			table.insert(rows, row)
			-- a confirm sheet opened by this press would block the next one: dismiss it like a user would (click outside)
			local sheets = {}
			for _, d in ipairs(gui:GetDescendants()) do if d.Name == "SheetBackdrop" and d.Visible ~= false then table.insert(sheets, d) end end
			if #sheets > 0 and row.effect == "NONE" then row.effect = "opens confirm sheet" end
			for _, d in ipairs(sheets) do
				local cancel = I18n.t("btn.cancel")
				for _, b2 in ipairs(d:GetDescendants()) do
					if b2:IsA("TextButton") and b2.Text == cancel then pcall(function() b2.Activated:Fire({}, 1) end) end
				end
			end
			frames(1)
			if Window.currentPage() ~= pageId then Window.navigate(pageId); frames(2) end
			Window.show()
		end
	end
	print(string.format("page %s: %d buttons, %.1fs", pageId, total, clock() - started))
end
h.unload(); Mock.uninstall()
print("@@" .. Json.encode({ rows = rows, pageKeys = pageKeys }))
return true

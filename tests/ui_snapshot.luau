--!nonstrict
-- tests/ui_snapshot: not part of the suite. Boots the hub on the mock, drives it into a series of states and
-- prints the resulting GUI tree as JSON ("@@SNAP <name> <json>") for tools/ui_render.py, which lays it out and
-- paints a PNG. The picture is an APPROXIMATION (a proxy renderer, not Roblox): it shows structure, sizes,
-- colours, transparency, rounding, strokes, gradients and text, so layout mistakes and weak contrast become visible.
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
local F = import("ui/Framework")
local Json = import("core/Json")
local Training = import("features/Training")
local TargetSelect = import("features/TargetSelect")
local Music = import("features/Music")
local Tools = import("features/Tools")
local Recents = import("core/Recents")

local CFG = Json.decode(SNAP_CFG_JSON)

local KEEP_CLASSES = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ScrollingFrame = true, CanvasGroup = true, ImageLabel = true, ImageButton = true,
	UICorner = true, UIStroke = true, UIGradient = true, UIListLayout = true, UIGridLayout = true, UIPadding = true, UIScale = true, ScreenGui = true,
	UIAspectRatioConstraint = true, UISizeConstraint = true,
}

local function enumOf(v)
	if type(v) == "table" and rawget(v, "EnumType") ~= nil then return { en = tostring(v.EnumType) .. "." .. tostring(v.Name) } end
	return nil
end

local function ser(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "number" or t == "string" or t == "boolean" then return v end
	if t ~= "table" or depth > 4 then return nil end
	if rawget(v, "__isInstance") ~= nil then return nil end
	local e = enumOf(v)
	if e then return e end
	if v.kind == "UDim2" then return { u2 = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } } end
	if v.kind == "Color3" then return { c3 = { v.r, v.g, v.b } } end
	if rawget(v, "x") ~= nil and rawget(v, "y") ~= nil and rawget(v, "z") == nil then return { v2 = { v.x, v.y } } end
	if rawget(v, "Scale") ~= nil and rawget(v, "Offset") ~= nil then return { ud = { v.Scale, v.Offset } } end
	if v.kind == "NumberSequence" or v.kind == "ColorSequence" then
		local pts = {}
		for _, e2 in ipairs(v) do
			if type(e2) == "table" and e2.Time == nil and e2.kind ~= "Color3" and e2[1] ~= nil then
				for _, k in ipairs(e2) do table.insert(pts, ser(k, depth + 1)) end
			else
				table.insert(pts, ser(e2, depth + 1))
			end
		end
		return { seq = v.kind, pts = pts }
	end
	if rawget(v, "Time") ~= nil and rawget(v, "Value") ~= nil then return { kp = { v.Time, ser(v.Value, depth + 1) } } end
	return nil
end

local function node(inst)
	local props = inst.__props
	local out = {}
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "__destroyed" and k ~= "ClassName" and string.sub(k, 1, 2) ~= "__" then
			local s = ser(v)
			if s ~= nil then out[k] = s end
		end
	end
	local kids = {}
	for _, c in ipairs(inst:GetChildren()) do
		if KEEP_CLASSES[c.ClassName] then table.insert(kids, node(c)) end
	end
	return { c = inst.ClassName, n = inst.Name, p = out, k = kids }
end

local function frames(n) for _ = 1, n do Perf.frame(1 / 30) end end

-- icon sheet: every icon at 2 sizes on a dark surface, to judge the glyphs on their own
local function iconSheet(game)
	local Icons = import("ui/Icons")
	local gui = Instance.new("ScreenGui")
	gui.Name = "IconSheet"
	gui.Parent = game.__services.CoreGui
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(36, 36, 38)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local names = Icons.names()
	for i, name in ipairs(names) do
		local col, row = (i - 1) % 8, (i - 1) // 8
		local cell = Instance.new("Frame")
		cell.Position = UDim2.fromOffset(20 + col * 150, 20 + row * 120)
		cell.Size = UDim2.fromOffset(140, 110)
		cell.BackgroundTransparency = 1
		cell.Parent = bg
		local big = Icons.draw(cell, name, 56, "text")
		big.Position = UDim2.fromOffset(8, 6)
		local small = Icons.draw(cell, name, 22, "text")
		small.Position = UDim2.fromOffset(90, 12)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = name
		l.TextSize = 12
		l.TextColor3 = Color3.fromRGB(170, 170, 175)
		l.Position = UDim2.fromOffset(8, 78)
		l.Size = UDim2.fromOffset(130, 16)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = cell
	end
end

local function runJob(job)
	T.fresh(); Mock.uninstall()
	local game = Mock.install(); Services.clear()
	local cam = game.Workspace.CurrentCamera
	local vp = job.viewport or { 1280, 720 }
	cam.ViewportSize = Mock.v2(vp[1], vp[2])
	if job.phone then game.__services.UserInputService.TouchEnabled = true; game.__services.UserInputService.KeyboardEnabled = false end
	if job.icons then
		iconSheet(game)
		local trees = {}
		for _, g in ipairs(game.__services.CoreGui:GetChildren()) do table.insert(trees, node(g)) end
		print("@@SNAP " .. job.name .. " " .. Json.encode({ viewport = vp, trees = trees }))
		Mock.uninstall()
		return
	end
	local h = Hub.run({ skipLicense = true })
	Settings.set("ui.animSpeed", 0)
	if job.language then I18n.set(job.language); Window.relocalize() end
	if job.theme then Settings.set("ui.theme", job.theme) end
	for k, v in pairs(job.settings or {}) do Settings.set(k, v) end
	-- some live state so pages are not empty
	Settings.set("training.enabled", true); Training.spawnDummy()
	Music.add("asset:111", "Track A"); Music.add("file:a.mp3", "Track B")
	Tools.addTimer("", 90); Tools.stopwatchStart()
	Recents.toggleFavorite("xh.enable"); Recents.toggleFavorite("train.range"); Recents.touch("cam.fov")
	frames(6)
	if job.page then Window.navigate(job.page); frames(8) end
	local gui = game.__services.CoreGui:FindFirstChild("MM2Hub")
	-- the mock has no layout engine: give the root its real size so size-dependent code (compact sidebar) behaves as on a client
	local root = gui and gui:FindFirstChild("Root")
	if root then
		local sc = Settings.get("ui.scale")
		root.__props.__w = Settings.get("state.width") * sc
		root.__props.__h = Settings.get("state.height") * sc
		root:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		frames(2)
	end
	if job.setup ~= "toast" then
		Notify.clear(); frames(2)
		local th = gui and gui:FindFirstChild("Toasts")
		if th then th.Visible = false end -- the mock keeps expired toasts around; hide them so they do not cover the window
	end
	if job.setup == "toast" then
		Notify.push({ title = "Profile saved", text = "Default was saved with 42 settings.", level = "success" })
		Notify.push({ title = "Module", text = "sounds failed: no source", level = "error" })
		frames(6)
	elseif job.setup == "confirm" then
		F.confirm({ title = "Reset this page?", text = "Every setting on this page returns to its default value.", confirmText = "Reset", danger = true, onConfirm = function() end })
		frames(4)
	elseif job.setup == "minimized" then
		Settings.set("state.minimized", true); frames(6)
	end
	if job.press then
		-- press the first button whose name/text matches, to open popovers
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextButton") and (d.Name == job.press or d.Text == job.press) then d.Activated:Fire({}, 1); break end
		end
		frames(4)
	end
	local trees = {}
	for _, g in ipairs(game.__services.CoreGui:GetChildren()) do
		if g.ClassName == "ScreenGui" then table.insert(trees, node(g)) end
	end
	print("@@SNAP " .. job.name .. " " .. Json.encode({ viewport = vp, trees = trees }))
	h.unload(); Mock.uninstall()
end

for _, job in ipairs(CFG.jobs) do
	local ok, err = pcall(runJob, job)
	if not ok then print("@@ERR " .. job.name .. " " .. tostring(err)); pcall(function() Mock.uninstall() end) end
end
return true

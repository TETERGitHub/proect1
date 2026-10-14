--!nonstrict
-- ui/PagesCustom: the five customisation pages (Custom gun, Custom knife, Custom character, Murderer kill sound,
-- Sheriff kill sound). All of them edit real settings (see data/Schema, features/CustomLogic, features/KillSounds):
--   * the DRAFT is what the preview shows; Apply copies it to the applied snapshot that features/Cosmetics draws on your
--     own tool or avatar; Reset undoes that for this page only; presets are per page.
--   * the preview is a ViewportFrame with its own copy of the model: it never touches your real tool or avatar.
-- The kill-sound pages share one builder but no state: every call takes the role and touches only that role's keys.
-- Depends on: PageKit, Framework, Theme, Motion, Settings, Perf, Cosmetics, CustomLogic, KillSounds, KillEvents, ModelLib.

local import = ...
local Kit = import("ui/PageKit")
local F = import("ui/Framework")
local Theme = import("ui/Theme")
local Motion = import("ui/Motion")
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local I18n = import("core/I18n")
local Cosmetics = import("features/Cosmetics")
local Custom = import("features/CustomLogic")
local KillSounds = import("features/KillSounds")
local KillEvents = import("features/KillEvents")
local Lib = import("data/ModelLib")
local Meshes = import("features/MeshModels")
local Maid = import("core/Maid")
local Probe = import("features/AudioProbe")
local MeshCache = import("features/MeshCache")

local notify, visible, auto, section, dataList, infoLine = Kit.notify, Kit.visible, Kit.auto, Kit.section, Kit.dataList, Kit.infoLine

local P = {}

local PREVIEW_H, PREVIEW_H_BIG = 250, 400

-- quick colour palettes (primary, secondary, grip, detail, glow). Pure data: pick one, then fine-tune the colours below.
local PALETTES = {
	{ "Ruby", { 190, 36, 52 }, { 90, 16, 28 }, { 36, 28, 30 }, { 255, 200, 160 }, { 255, 70, 80 } },
	{ "Ocean", { 40, 120, 220 }, { 20, 60, 130 }, { 24, 34, 56 }, { 170, 220, 255 }, { 80, 220, 255 } },
	{ "Forest", { 56, 130, 70 }, { 30, 76, 44 }, { 40, 34, 24 }, { 190, 230, 150 }, { 140, 255, 120 } },
	{ "Gold", { 226, 184, 70 }, { 150, 110, 36 }, { 60, 44, 24 }, { 255, 240, 190 }, { 255, 220, 100 } },
	{ "Violet", { 130, 70, 220 }, { 70, 34, 130 }, { 28, 20, 44 }, { 220, 190, 255 }, { 200, 110, 255 } },
	{ "Mono", { 226, 228, 232 }, { 120, 124, 132 }, { 34, 34, 38 }, { 255, 255, 255 }, { 255, 255, 255 } },
	{ "Sunset", { 255, 120, 60 }, { 200, 50, 90 }, { 50, 24, 40 }, { 255, 210, 150 }, { 255, 150, 80 } },
	{ "Mint", { 90, 220, 190 }, { 40, 140, 130 }, { 24, 50, 52 }, { 210, 255, 240 }, { 120, 255, 220 } },
}

local function dateText(t)
	if not t or t <= 0 then
		return ""
	end
	local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", t)
	return ok and s or ""
end

local function rgbColor(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Preview ---------------------------------------------------------------------------------------------------------------------

-- previewCard(page, kind) -> { rebuild(), pop(), reset() }
local function previewCard(page, kind)
	local card = F.surface(page.content, "card", { name = "Preview", props = { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, PREVIEW_H), ClipsDescendants = true }, sheen = 110 })
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Viewport"
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(150, 152, 162)
	vp.LightColor = Color3.fromRGB(255, 252, 245)
	vp.LightDirection = Vector3.new(-0.5, -1, -0.6)
	vp.Parent = card
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam

	local view = { walk = false, t = 0, yaw = 0, pitch = 0.22, dist = 6, dist0 = 6, zoom = 1, cx = 0, cy = 0, cz = 0, spin = false, model = nil, dirty = true, popping = false }
	local defaultYaw = kind == "char" and (math.pi - 0.45) or 2.35
	view.yaw = defaultYaw
	local popValue = Instance.new("NumberValue")
	popValue.Value = 0
	page.maid:Give(popValue)

	local function placeCamera()
		local d = view.dist0 * view.zoom * (1 + 0.28 * popValue.Value)
		local cp, sp = math.cos(view.pitch), math.sin(view.pitch)
		local dx, dy, dz = math.sin(view.yaw) * cp, sp, math.cos(view.yaw) * cp
		cam.CFrame = CFrame.lookAt(Vector3.new(view.cx + dx * d, view.cy + dy * d, view.cz + dz * d), Vector3.new(view.cx, view.cy, view.cz))
	end

	local function rebuild()
		view.dirty = false
		if view.model then
			view.model:Destroy()
			view.model = nil
		end
		local look = Custom.readLook(kind)
		local model
		if kind == "char" then
			model = Cosmetics.buildPreviewChar(Custom.readSelection("char"), look)
		else
			model = Cosmetics.buildPreview(kind, Settings.get(Custom.key(kind, "model")), look)
		end
		if not model then
			return
		end
		model.Parent = vp
		view.model = model
		local cf, size = model:GetBoundingBox()
		local ext = math.max(size.X, size.Y, size.Z, 1)
		view.cx, view.cy, view.cz = cf.Position.X, cf.Position.Y, cf.Position.Z
		view.dist0 = ext * 1.45 / math.tan(math.rad(cam.FieldOfView / 2)) * 0.5 + ext * 0.6
		placeCamera()
	end

	local function pop()
		popValue.Value = 1
		Motion.tween(popValue, { Value = 0 }, Motion.D.slow, "smooth")
		view.popping = true
		placeCamera()
	end

	local obj = { view = view }
	-- meshStatus() -> text about how the previewed model is drawn (smooth mesh or the simple Part fallback and why)
	function obj.meshStatus()
		local m = view.model
		if not m then
			return "no model"
		end
		local meshed = m:GetAttribute("mesh")
		if meshed == true then
			return "smooth meshes"
		end
		return "simple parts: " .. tostring(m:GetAttribute("meshNote") or "no mesh information")
	end
	page.maid:Give(MeshCache.Ready:Connect(function()
		view.dirty = true
	end))
	function obj.rebuild()
		rebuild()
	end
	function obj.pop()
		pop()
	end
	function obj.reset()
		view.yaw, view.pitch, view.zoom = defaultYaw, 0.22, 1
		placeCamera()
	end
	function obj.zoomBy(f)
		view.zoom = math.clamp(view.zoom * f, 0.4, 2.2)
		placeCamera()
	end

	-- drag to rotate, wheel to zoom
	page.maid:Give(vp.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local start, y0, p0 = input.Position, view.yaw, view.pitch
			F.beginDrag(function(p)
				view.yaw = y0 - (p.X - start.X) * 0.012
				view.pitch = math.clamp(p0 + (p.Y - start.Y) * 0.008, -0.6, 1.2)
				placeCamera()
			end)
		end
	end))
	page.maid:Give(vp.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			obj.zoomBy(input.Position.Z > 0 and 0.9 or 1.1)
		end
	end))

	-- small controls in the corner
	local bar = F.frame(card, { Name = "Tools", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
	F.list(bar, 4, true)
	local function tool(icon, tip, fn, order)
		local b = F.iconButton(bar, icon, fn, 28, page.maid, "text", false, "bg3")
		b.LayoutOrder = order
		b.Name = "Tool_" .. tip
		F.tooltip(b, tip, page.maid)
		return b
	end
	tool("plus", "Zoom in", function() obj.zoomBy(0.85) end, 1)
	tool("minus", "Zoom out", function() obj.zoomBy(1.18) end, 2)
	tool("repeatIcon", "Reset view", function() obj.reset() end, 3)
	local spinBtn
	spinBtn = tool("play", "Auto-rotate", function()
		view.spin = not view.spin
		F.setButtonStyle(spinBtn, view.spin and "filled" or "tinted")
	end, 4)
	if kind == "char" then
		local walkBtn
		walkBtn = tool("skip", "Walk preview", function()
			view.walk = not view.walk
			view.t = 0
			F.setButtonStyle(walkBtn, view.walk and "filled" or "tinted")
			if not view.walk and view.model then
				Cosmetics.poseRig(view.model, nil)
			end
		end, 5)
	end
	local big = false
	tool("chevron", "Enlarge preview", function()
		big = not big
		Motion.tween(card, { Size = UDim2.new(1, 0, 0, big and PREVIEW_H_BIG or PREVIEW_H) }, Motion.D.std, "smooth")
	end, 5)
	local hint = F.label(card, "Drag to rotate · scroll to zoom · preview only", { size = 11, token = "textDim", dim = UDim2.new(1, -20, 0, 16) })
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 14, 1, -8)

	-- ticker: rebuild when the draft changed, rotate while the page is on screen (24 Hz, nothing runs while hidden)
	local h = Perf.every("ui.preview." .. kind, 24, function(dt)
		if not visible(page.id) then
			return
		end
		if view.dirty then
			rebuild()
		end
		if view.walk and view.model and Motion.enabled() then
			view.t += dt
			Cosmetics.poseRig(view.model, view.t)
		end
		if view.spin and Motion.enabled() then
			view.yaw += dt * 0.7
			placeCamera()
		elseif view.popping then
			placeCamera()
			if popValue.Value < 0.001 then
				view.popping = false
			end
		end
	end)
	page.maid:Give(h.Cancel)
	page.maid:Give(function()
		if view.model then
			view.model:Destroy()
			view.model = nil
		end
	end)
	-- any draft change marks the model stale
	for _, key in ipairs(Settings.keys({ category = "custom" })) do
		if string.find(key, "^custom%." .. kind) then
			page.maid:Give(Settings.observe(key, function()
				view.dirty = true
			end))
		end
	end
	rebuild()
	return obj
end

-- Model cards ------------------------------------------------------------------------------------------------------------------

local function isSelected(kind, id)
	local info = Custom.modelInfo(kind, id)
	if not info then
		return false
	end
	if kind == "char" then
		local slot = info.group == "costume" and "costume" or info.slot
		return Settings.get(Custom.key("char", slot)) == id
	end
	return Settings.get(Custom.key(kind, "model")) == id
end

-- modelGrid(page, kind, ids, preview) -> { set(ids), frame }: a grid of selectable cards (name, category, palette dots or poly count,
-- selected state). Built-in shapes show their default palette; imported meshes show their triangle count (they keep their own textures).
local function modelGrid(page, kind, ids, preview)
	local grid = F.frame(page.content, { Name = "ModelGrid", LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -8, 0, 86)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local cards = {}
	local cardMaid = Maid.new("model-cards")
	page.maid:Give(cardMaid)
	local Icons = import("ui/Icons")
	local function refresh()
		for id, c in pairs(cards) do
			local on = isSelected(kind, id)
			c.check.Visible = on
			Theme.bind(c.ring, "Color", on and "accent" or "stroke")
			Motion.tween(c.ring, { Thickness = on and 2 or 1, Transparency = on and 0 or 0.5 }, Motion.D.fast, "smooth")
		end
	end
	local function populate(list)
		cardMaid:Clean()
		table.clear(cards)
		for i, id in ipairs(list) do
			local info = Custom.modelInfo(kind, id)
			if info then
				local b = Instance.new("TextButton")
				b.Name = "Model_" .. string.gsub(id, ":", "_")
				b.Text = ""
				b.AutoButtonColor = false
				b.BorderSizePixel = 0
				b.LayoutOrder = i
				Theme.bind(b, "BackgroundColor3", function()
					return Theme.color((Theme.surface("control")))
				end)
				Theme.bind(b, "BackgroundTransparency", function()
					return select(2, Theme.surface("control"))
				end)
				F.corner(b, "card")
				local ring = F.stroke(b, "stroke", 1, 0.5)
				F.padding(b, 12, 10, 12, 10)
				F.label(b, info.name, { size = 13, bold = true, dim = UDim2.new(1, -24, 0, 18) })
				local sub = info.imported and (I18n.tr("Imported mesh") .. " · " .. info.tris .. " " .. I18n.tr("tris")) or (I18n.tr(info.category) .. " · " .. info.partCount .. " " .. I18n.tr("parts"))
				local cat = F.label(b, sub, { size = 11, token = "textDim", dim = UDim2.new(1, 0, 0, 14) })
				cat.Position = UDim2.fromOffset(0, 20)
				if not info.imported then
					local look = Lib.styleLook(kind, id)
					local dots = F.frame(b, { Name = "Dots", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 14) })
					F.list(dots, 5, true)
					for k, f in ipairs({ "primary", "secondary", "detail", "glow" }) do
						local d = Instance.new("Frame")
						d.Name = "Dot_" .. f
						d.LayoutOrder = k
						d.Size = UDim2.fromOffset(14, 14)
						d.BackgroundColor3 = rgbColor(look[f])
						d.BorderSizePixel = 0
						F.pillCorner(d)
						F.stroke(d, "stroke", 1, 0.55)
						d.Parent = dots
					end
				end
				local check = Instance.new("Frame")
				check.Name = "Check"
				check.AnchorPoint = Vector2.new(1, 0)
				check.Position = UDim2.new(1, 0, 0, 0)
				check.Size = UDim2.fromOffset(18, 18)
				check.BorderSizePixel = 0
				Theme.bind(check, "BackgroundColor3", "accent")
				F.pillCorner(check)
				check.Visible = false
				check.Parent = b
				local tick = Icons.draw(check, "check", 12, "text")
				tick.AnchorPoint = Vector2.new(0.5, 0.5)
				tick.Position = UDim2.fromScale(0.5, 0.5)
				cardMaid:Give(b.Activated:Connect(function()
					F.click()
					Custom.selectModel(kind, id)
					if preview then
						preview.pop()
					end
				end))
				if info.imported then
					local e = Meshes.info(kind, string.match(id, "^import:(.+)$"))
					if e and e.credit ~= "" then
						F.tooltip(b, e.credit, cardMaid)
					end
				end
				b.Parent = grid
				cards[id] = { button = b, ring = ring, check = check }
			end
		end
		refresh()
	end
	local keys = kind == "char" and { "costume", "head", "back", "aura" } or { "model" }
	for _, k in ipairs(keys) do
		page.maid:Give(Settings.observe(Custom.key(kind, k), refresh))
	end
	populate(ids)
	return { frame = grid, set = populate }
end

-- Page builder -----------------------------------------------------------------------------------------------------------------

local function buttonStrip(page, buttons)
	local card = F.frame(page.content, { Name = "Actions", LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 38) })
	F.list(card, 8, true)
	local out = {}
	for i, b in ipairs(buttons) do
		local btn = F.button(card, b.text, b.fn, b.style or "tinted", UDim2.fromOffset(b.width or 120, 34), page.maid)
		btn.LayoutOrder = i
		btn.Name = b.name or ("Btn_" .. b.text)
		out[b.name or b.text] = btn
	end
	return card, out
end

local function chips(page, items, onPick, current)
	local grid = F.frame(page.content, { Name = "Chips", LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(118, 30)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local btns = {}
	for i, id in ipairs(items) do
		local b = F.button(grid, id, function()
			onPick(id)
		end, "tinted", UDim2.fromOffset(118, 30), page.maid)
		b.LayoutOrder = i
		b.Name = "Chip_" .. id
		btns[id] = b
	end
	local function refresh(now)
		for id, b in pairs(btns) do
			F.setButtonStyle(b, id == now and "filled" or "tinted")
		end
	end
	return refresh
end

local function swatchRow(page, kind)
	local row = F.frame(page.content, { Name = "Palettes", LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 44) })
	F.padding(row, 2, 4, 2, 4)
	F.list(row, 10, true)
	for i, pal in ipairs(PALETTES) do
		local b = Instance.new("TextButton")
		b.Name = "Palette_" .. pal[1]
		b.Text = ""
		b.AutoButtonColor = false
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(36, 36)
		b.BackgroundColor3 = rgbColor(pal[2])
		b.BorderSizePixel = 0
		F.pillCorner(b)
		local ring = Instance.new("UIStroke")
		ring.Color = rgbColor(pal[6])
		ring.Thickness = 2.5
		ring.Transparency = 0.1
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = b
		local half = Instance.new("Frame")
		half.AnchorPoint = Vector2.new(1, 1)
		half.Position = UDim2.fromScale(1, 1)
		half.Size = UDim2.fromOffset(18, 18)
		half.BackgroundColor3 = rgbColor(pal[3])
		half.BorderSizePixel = 0
		F.pillCorner(half)
		half.Parent = b
		Motion.pressable(b, page.maid, 0.08)
		F.tooltip(b, pal[1], page.maid)
		page.maid:Give(b.Activated:Connect(function()
			F.click()
			Custom.writeLook(kind, { primary = pal[2], secondary = pal[3], grip = pal[4], detail = pal[5], glow = pal[6] })
			Settings.set(Custom.key(kind, "style"), "Custom", "custom")
		end))
		b.Parent = row
	end
end

local function fitSection(page, kind)
	if kind == "gun" then
		section(page, "Fit on the tool", { "cosmetics.gunTool", "cosmetics.gunScale", "cosmetics.gunOffsetX", "cosmetics.gunOffsetY", "cosmetics.gunOffsetZ", "cosmetics.gunRotY" })
	elseif kind == "knife" then
		section(page, "Fit on the tool", { "cosmetics.knifeTool", "cosmetics.knifeScale", "cosmetics.knifeOffsetX", "cosmetics.knifeOffsetY", "cosmetics.knifeOffsetZ", "cosmetics.knifeRotY" })
	else
		section(page, "Fit on the avatar", { "cosmetics.charScale" })
	end
end

local STATUS_KEY = { gun = "gun", knife = "knife", char = "customChar" }

local function presetsBlock(page, kind, label)
	page:section("Presets")
	local nameBox
	local row, holder = page:row({ label = "Preset name", desc = "Saved for " .. label .. " only; saving under an existing name replaces just that preset.", width = 220 })
	nameBox = F.textBox(holder, { placeholder = "My look", dim = UDim2.fromOffset(220, 30) }, page.maid)
	nameBox.AnchorPoint = Vector2.new(1, 0.5)
	nameBox.Position = UDim2.fromScale(1, 0.5)
	local list
	local function render()
		local items = {}
		for _, e in ipairs(Custom.presets(kind)) do
			table.insert(items, { title = e.name, sub = (e.category ~= "" and e.category or "Custom") .. (dateText(e.t) ~= "" and ("  ·  " .. dateText(e.t)) or ""), raw = true, name = e.name })
		end
		list.set(items)
		if #items == 0 then
			list.holder.Visible = false
		end
	end
	list = dataList(page, {
		rowHeight = 46, maxRows = Custom.MAX_PRESETS,
		buttons = {
			{ icon = "check", tip = "Load into the editor", fn = function(item)
				Custom.loadPreset(kind, item.name)
				notify(label, "Preset '" .. item.name .. "' loaded. Press Apply to use it.", "info")
			end },
			{ icon = "plus", tip = "Duplicate", fn = function(item)
				local ok, err, copy = Custom.duplicatePreset(kind, item.name)
				notify(label, ok and ("Created '" .. tostring(copy) .. "'.") or tostring(err), ok and "success" or "warn")
				render()
			end },
			{ icon = "trash", tip = "Delete", token = "bad", fn = function(item)
				F.confirm({ title = "Delete preset", text = "Delete '" .. item.name .. "'? This cannot be undone.", danger = true, confirmText = "Delete", onConfirm = function()
					Custom.deletePreset(kind, item.name)
					render()
				end })
			end },
		},
	})
	page.maid:Give(Settings.observe(Custom.key(kind, "presets"), render))
	local saveBtn
	local _, strip = buttonStrip(page, {
		{ text = "Save preset", style = "filled", width = 130, name = "SavePreset", fn = function()
			local ok, err = Custom.savePreset(kind, nameBox.Text)
			if ok then
				notify(label, "Preset '" .. nameBox.Text .. "' saved.", "success")
				F.flashButton(saveBtn, "success")
			else
				F.setInvalid(nameBox, true)
				notify(label, tostring(err), "warn")
				F.flashButton(saveBtn, "error")
			end
		end },
	})
	saveBtn = strip.SavePreset
	page.maid:Give(nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		F.setInvalid(nameBox, false)
	end))
	render()
end

-- buildCustom(kind, label, intro): one function builds all three appearance pages
local function buildCustom(kind, label, intro)
	return function(page)
		page:note(intro, "textDim", 52)
		auto(page, Custom.key(kind, "enabled"))
		local preview = previewCard(page, kind)
		local _, strip = buttonStrip(page, {
			{ text = "Preview", name = "Preview", style = "tinted", width = 110, fn = function()
				preview.rebuild()
				preview.pop()
			end },
			{ text = "Apply", name = "Apply", style = "filled", width = 110, fn = function()
				local ok, err = Custom.apply(kind)
				if ok then
					notify(label, "Applied. Visible only to you.", "success")
					F.flashButton(strip.Apply, "success")
				else
					notify(label, tostring(err), "warn")
					F.flashButton(strip.Apply, "error")
				end
			end },
			{ text = "Reset", name = "Reset", style = "danger", width = 110, fn = function()
				F.confirm({ title = "Reset " .. label, text = "The applied look is removed and this page returns to its defaults. Saved presets and the other pages are not touched.", danger = true, confirmText = "Reset", onConfirm = function()
					Custom.reset(kind)
					preview.rebuild()
					preview.pop()
					notify(label, "Back to the default look.", "info")
				end })
			end },
		})
		local fnModel = infoLine(page, "Model drawn as", function()
			return preview.meshStatus()
		end)
		local fnRig = kind == "char" and infoLine(page, "Body binding", function()
			return Cosmetics.status().customCharRig or "not applied"
		end) or nil
		local fnStatus = infoLine(page, "Status", function()
			local st = Cosmetics.status()[STATUS_KEY[kind]] or "off"
			if Settings.get(Custom.key(kind, "enabled")) and st == "off" then
				return "waiting"
			end
			return st
		end)
		local h = Perf.every("ui.custom.status." .. kind, 2, function()
			if visible(page.id) then
				fnStatus()
				fnModel()
				if fnRig then
					fnRig()
				end
			end
		end)
		page.maid:Give(h.Cancel)
		fnStatus()
		fnModel()

		-- style categories
		page:section("Style")
		local styleIds = {}
		for _, st in ipairs(Lib.styles(kind)) do
			table.insert(styleIds, st.id)
		end
		table.insert(styleIds, "Custom")
		local refreshChips = chips(page, styleIds, function(id)
			if id ~= "Custom" then
				Custom.applyStyle(kind, id)
			else
				Settings.set(Custom.key(kind, "style"), "Custom", "custom")
			end
			preview.pop()
		end)
		page.maid:Give(Settings.observe(Custom.key(kind, "style"), refreshChips, true))
		swatchRow(page, kind)

		-- catalogue: imported real meshes first, the built-in simple shapes below as placeholders
		local function importIds(group)
			local out = {}
			for _, e in ipairs(Meshes.list(kind)) do
				if kind ~= "char" or group == nil or (group == "costume" and e.group == "costume") or (group ~= "costume" and e.group == "accessory" and e.slot == group) then
					table.insert(out, "import:" .. e.id)
				end
			end
			return out
		end
		local function builtIn(group)
			local out = {}
			for _, id in ipairs(Lib.ids(kind)) do
				if kind ~= "char" then
					table.insert(out, id)
				else
					local info = Lib.info("char", id)
					if (group == "costume" and info.group == "costume") or (group ~= "costume" and info.group ~= "costume" and info.slot == group) then
						table.insert(out, id)
					end
				end
			end
			return out
		end
		local importGrids = {}
		local function emptyNote(txt)
			page:note(txt, "textDim", 36)
		end
		if kind == "char" then
			for _, g in ipairs({ { "costume", "Costumes (full body, drawn over your avatar)" }, { "head", "Head" }, { "back", "Back" }, { "aura", "Aura" } }) do
				page:section(g[2])
				local ids = importIds(g[1])
				importGrids[g[1]] = modelGrid(page, kind, ids, preview)
				page:note("Simple built-in shapes (placeholders, not real models):", "textDim", 20)
				modelGrid(page, kind, builtIn(g[1]), preview)
			end
			page:note("Press a selected card again to take it off. A costume only hides your avatar on your own screen; nothing about your character's size, speed or collisions changes.", "textDim", 44)
		else
			page:section("Your imported models (real meshes)")
			importGrids.all = modelGrid(page, kind, importIds(), preview)
			page:note("Nothing imported yet? Convert a model you downloaded with tools/convert_mesh.py and copy the result to MM2Hub/models/ (see docs/IMPORT_MODELS.md).", "textDim", 36)
			page:section("Simple built-in shapes (placeholders)")
			modelGrid(page, kind, builtIn(nil), preview)
		end
		buttonStrip(page, {
			{ text = "Rescan imports", name = "RescanImports", style = "tinted", width = 150, fn = function()
				local n, problems = Meshes.reload()
				for g, grid in pairs(importGrids) do
					grid.set(importIds(g ~= "all" and g or nil))
				end
				if #problems > 0 then
					notify(label, tostring(problems[1]), "warn")
				else
					notify(label, n .. " imported model(s) found.", n > 0 and "success" or "info")
				end
			end },
		})

		-- colours and materials
		page:section("Colours and material")
		for _, f in ipairs({ "primary", "secondary", "grip", "detail", "glow" }) do
			auto(page, Custom.key(kind, f))
		end
		auto(page, Custom.key(kind, "material"))
		auto(page, Custom.key(kind, "glowAmount"))
		auto(page, Custom.key(kind, "decor"))
		auto(page, Custom.key(kind, "effects"))
		auto(page, "custom.useMeshes")
		fitSection(page, kind)
		-- models made elsewhere (for example in Blender and uploaded to Roblox): the older single-source skin of the Cosmetics page
		page:section("Your own model (Blender / Studio)")
		page:note("Models you made yourself: export from Blender, upload to Roblox (or save a .rbxm in MM2Hub/models/), then enter asset:<id> or file:<name.rbxm>. The hub ships no downloaded models. Scripts inside a loaded model are removed. This replaces the look above while it is in use.", "textDim", 60)
		local legacy = { gun = { "cosmetics.gunSource", "cosmetics.gunEnabled" }, knife = { "cosmetics.knifeSource", "cosmetics.knifeEnabled" }, char = { "cosmetics.charSource", "cosmetics.charEnabled" } }
		auto(page, legacy[kind][1])
		buttonStrip(page, {
			{ text = "Use imported model", name = "UseImported", style = "tinted", width = 170, fn = function()
				Settings.set(Custom.key(kind, "enabled"), false, "custom")
				Settings.set(legacy[kind][2], true, "custom")
				Cosmetics.reapply()
				notify(label, "Your own model is in use. Apply the look above to switch back.", "info")
			end },
		})
		presetsBlock(page, kind, label)
		page.maid:Give(function()
			preview.view.spin = false
		end)
	end
end

function P.gun(page)
	return buildCustom("gun", "Custom gun", "Pick a model, a style and your colours. The preview updates at once; Apply puts the look on your own gun tool (visible only to you). Damage, fire rate and accuracy are never touched.")(page)
end
function P.knife(page)
	return buildCustom("knife", "Custom knife", "Independent of the gun: own models, colours and presets. Apply puts the look on your own knife tool (visible only to you). Nothing about the knife's behaviour changes.")(page)
end
function P.char(page)
	return buildCustom("char", "Custom character", "Costumes and accessories drawn on your own avatar, visible only to you. The preview uses a separate mannequin, so your real character stays untouched until you press Apply.")(page)
end

-- Kill sounds -----------------------------------------------------------------------------------------------------------------

local ROLE_TEXT = {
	murderer = {
		title = "Murderer kill sound",
		intro = "Plays when a kill by YOU as the murderer is confirmed: another player's death shortly after you used your knife, close to you. Swinging the knife alone never plays it. This is separate from the Sheriff sound.",
	},
	sheriff = {
		title = "Sheriff kill sound",
		intro = "Plays when a kill by YOU as the sheriff is confirmed: another player's death shortly after you used your gun. Shooting alone never plays it. This is separate from the Murderer sound.",
	},
}

-- reportBox(page, title) -> setText(text): a wrapped, selectable-looking text area for the last audio check
local function reportBox(page, title)
	page:section(title)
	local card = F.surface(page.content, "card", { name = "AudioReport", props = { LayoutOrder = page:nextOrder(), AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) } })
	F.padding(card, 14, 10, 14, 10)
	local label = F.label(card, "No check run yet. Press \"Check audio\" or \"Play preview\".", { size = 11.5, token = "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
	label.AutomaticSize = Enum.AutomaticSize.Y
	return function(text)
		label.Text = text
	end
end

local function buildKill(role)
	return function(page)
		local text = ROLE_TEXT[role]
		local key = function(f) return KillSounds.key(role, f) end
		page:note(text.intro, "textDim", 64)
		page:section("Sound")
		auto(page, key("enabled"))
		auto(page, key("volume"))
		auto(page, "gameaudio.muteKill") -- about the GAME's kill sounds, shared by both roles on purpose (see the Game audio page)
		local fnApplied = infoLine(page, "Applied sound", function()
			local src = Settings.get(key("source"))
			if src == "" then
				return "none"
			end
			for _, e in ipairs(KillSounds.library(role)) do
				if e.source == src then
					return e.name
				end
			end
			return src
		end)
		page.maid:Give(Settings.observe(key("source"), fnApplied, true))
		page.maid:Give(Settings.observe(key("library"), fnApplied))
		local fnPlayed = infoLine(page, "Preview", function()
			return KillSounds.isPreviewing(role) and "playing" or "stopped"
		end)
		local h = Perf.every("ui.kill." .. role, 4, function()
			if visible(page.id) then
				fnPlayed()
			end
		end)
		page.maid:Give(h.Cancel)

		local setReport = reportBox(page, "Audio check")
		-- list
		page:section("Your sounds")
		local list
		local function render()
			local items = {}
			local pick, applied = Settings.get(key("pick")), Settings.get(key("source"))
			for i, e in ipairs(KillSounds.library(role)) do
				local d = KillSounds.duration(e.source)
				local marks = {}
				if e.source == applied then
					table.insert(marks, "APPLIED")
				end
				if e.source == pick then
					table.insert(marks, "SELECTED")
				end
				table.insert(items, {
					index = i, source = e.source, raw = true, rawValue = true, builtin = e.builtin,
					title = (e.builtin and I18n.get() == "ru" and e.ru) or e.name,
					sub = I18n.tr(e.category) .. "  ·  " .. (e.builtin and I18n.tr("bundled") or e.source) .. (d and string.format("  ·  %.1f s", d) or ""),
					value = table.concat(marks, " · "), valueToken = e.source == applied and "good" or "accent",
				})
			end
			list.set(items)
			list.empty.Visible = #items == 0
		end
		list = dataList(page, {
			rowHeight = 48, maxRows = KillSounds.MAX_ENTRIES,
			buttons = {
				{ icon = "play", tip = "Play preview", fn = function(item)
					KillSounds.pick(role, item.source)
					local ok, err = KillSounds.preview(role, function(done, msg, len, report)
						setReport(Probe.format(report))
						if not done then
							notify(text.title, msg, "warn")
						end
						render()
					end)
					if not ok then
						notify(text.title, tostring(err), "warn")
					end
				end },
				{ icon = "check", tip = "Select", fn = function(item)
					KillSounds.pick(role, item.source)
				end },
				{ icon = "trash", tip = "Remove from the list", token = "bad", show = function(item) return not item.builtin end, fn = function(item)
					KillSounds.removeSound(role, item.index)
				end },
			},
		})
		list.empty = F.label(page.content, "Your list is empty. No sounds are bundled: add a sound by asset id or file below.", { size = 12, token = "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 30) })
		list.empty.LayoutOrder = page:nextOrder()
		page.maid:Give(Settings.observe(key("library"), render))
		page.maid:Give(Settings.observe(key("pick"), render))
		page.maid:Give(Settings.observe(key("source"), render))

		-- add a sound
		page:section("Add a sound")
		local nameBox, srcBox
		local r1, h1 = page:row({ label = "Name", width = 220 })
		nameBox = F.textBox(h1, { placeholder = "Headshot", dim = UDim2.fromOffset(220, 30) }, page.maid)
		nameBox.AnchorPoint = Vector2.new(1, 0.5)
		nameBox.Position = UDim2.fromScale(1, 0.5)
		local r2, h2 = page:row({ label = "Source", desc = "asset:<id> or file:<name.mp3> (in MM2Hub/sounds/). Only audio you may use.", width = 220 })
		srcBox = F.textBox(h2, { placeholder = "asset:123456", dim = UDim2.fromOffset(220, 30) }, page.maid)
		srcBox.AnchorPoint = Vector2.new(1, 0.5)
		srcBox.Position = UDim2.fromScale(1, 0.5)
		local addBtn
		local _, strip = buttonStrip(page, {
			{ text = "Add to list", name = "Add", style = "filled", width = 130, fn = function()
				local ok, err = KillSounds.addSound(role, nameBox.Text, srcBox.Text)
				if ok then
					nameBox.Text, srcBox.Text = "", ""
					F.flashButton(addBtn, "success")
				else
					notify(text.title, tostring(err), "warn")
					F.flashButton(addBtn, "error")
				end
			end },
		})
		addBtn = strip.Add

		-- actions: each acts on THIS role only
		page:section("Actions")
		local _, acts = buttonStrip(page, {
			{ text = "Play preview", name = "PlayPreview", style = "tinted", width = 120, fn = function()
				local ok, err = KillSounds.preview(role, function(done, msg, len, report)
					setReport(Probe.format(report))
					if not done then
						notify(text.title, msg, "warn")
					end
					render()
				end)
				if not ok then
					notify(text.title, tostring(err), "warn")
				end
			end },
			{ text = "Check audio", name = "CheckAudio", style = "tinted", width = 120, fn = function()
				setReport("Checking...")
				KillSounds.check(role, function(mine, control)
					setReport(Probe.format(mine) .. "\n\n" .. Probe.format(control))
					notify(text.title, mine.ok and "The engine plays this sound." or tostring(mine.verdict), mine.ok and "success" or "warn")
				end)
			end },
			{ text = "Stop preview", name = "StopPreview", style = "tinted", width = 120, fn = function()
				KillSounds.stopPreview(role)
				fnPlayed()
			end },
			{ text = "Apply", name = "Apply", style = "filled", width = 100, fn = function()
				local ok, err = KillSounds.apply(role)
				notify(text.title, ok and "Applied. It plays on a confirmed kill." or tostring(err), ok and "success" or "warn")
				F.flashButton(acts.Apply, ok and "success" or "error")
			end },
			{ text = "Reset", name = "Reset", style = "danger", width = 100, fn = function()
				F.confirm({ title = "Reset " .. text.title, text = "Switches this sound off and clears its selection and volume. Your list and the other role are not touched.", danger = true, confirmText = "Reset", onConfirm = function()
					KillSounds.reset(role)
					notify(text.title, "Reset.", "info")
				end })
			end },
		})
		local _, tests = buttonStrip(page, {
			{ text = "Test event", name = "TestEvent", style = "tinted", width = 160, fn = function()
				-- a labelled TEST: goes through the same confirmed-kill pipeline, so it plays only when this role is on and applied
				local fired = KillEvents.simulate(role)
				if not Settings.get(key("enabled")) then
					notify(text.title, "Test event sent, but this sound is switched off.", "warn")
				elseif Settings.get(key("source")) == "" then
					notify(text.title, "Test event sent, but no sound is applied yet.", "warn")
				elseif not fired then
					notify(text.title, "Test event was ignored.", "warn")
				end
			end },
		})
		page:note("\"Test event\" is a test, not a real kill. A real event needs another player's death shortly after your own tool use; the credit is judged on your client, so treat it as a local effect, not proof.", "textDim", 48)
		page.maid:Give(function()
			KillSounds.stopPreview(role)
		end)
		render()
	end
end

function P.murderer(page)
	return buildKill("murderer")(page)
end
function P.sheriff(page)
	return buildKill("sheriff")(page)
end

return P

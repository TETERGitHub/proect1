--!nonstrict
-- ui/Window: the main hub window - glass-style frame with drawn shadow, draggable title bar,
-- search, sliding-pill sidebar, animated page transitions, resize grip, minimised quick bar,
-- floating launcher button and iOS-style toast banners (pooled cards).
-- Everything is composed from Frames/TextLabels; no Roblox image assets are used.
-- STATUS: implemented; exercised against the mock layer only.
-- Depends on: Framework, Theme, Motion, Icons, Settings, Perf, Notify, Search, Recents, Registry, Actions, Env, Pool, Maid, I18n, Services.

local import = ...
local F = import("ui/Framework")
local Theme = import("ui/Theme")
local Motion = import("ui/Motion")
local Flair = import("ui/Flair")
local Icons = import("ui/Icons")
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Notify = import("core/Notify")
local Search = import("core/Search")
local Recents = import("core/Recents")
local Registry = import("core/Registry")
local Actions = import("core/Actions")
local Env = import("core/Env")
local Pool = import("core/Pool")
local Maid = import("core/Maid")
local I18n = import("core/I18n")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local Window = {}

Window.VisibilityChanged = Signal.new("Window.VisibilityChanged")
Window.PageChanged = Signal.new("Window.PageChanged")

local MIN_W, MIN_H = 460, 320
local SIDEBAR_W, SIDEBAR_COMPACT = 178, 58

local pages = {} -- id -> def
local pageOrder = {}
local w = nil -- window state

for _, id in ipairs({
	"Window.drag", "Window.resize", "Window.savePosition", "Window.restorePosition", "Window.quickBar", "Window.keyNav",
	"Search.category", "Search.active", "Search.favorites",
}) do
	Registry.provide(id)
end

-- Page registry -----------------------------------------------------------------------------------------------

-- registerPage{id, icon, title (i18n key), build = function(page), hidden = bool}
function Window.registerPage(def)
	assert(type(def.id) == "string" and type(def.build) == "function", "bad page definition")
	assert(not pages[def.id], "duplicate page " .. def.id)
	pages[def.id] = def
	table.insert(pageOrder, def.id)
end

function Window.pageIds()
	return table.clone(pageOrder)
end

-- Navigation groups (sidebar sections). Pages that are not listed here go into a trailing "More" group.
local NAV_GROUPS = {
	{ "Hub", { "dashboard", "ui" } },
	{ "Visuals", { "esp", "crosshair", "camera", "lighting", "cosmetics" } },
	{ "Customize", { "customgun", "customknife", "customchar", "killfx", "hitfx", "watermark", "aura", "killmurderer", "killsheriff" } },
	{ "Practice", { "training", "murder", "defence" } },
	{ "Audio", { "music", "sounds", "gameaudio" } },
	{ "System", { "mobile", "perf", "tools", "keys", "configs", "diagnostics", "help", "about" } },
}

-- navGroups() -> list of { title, ids } following NAV_GROUPS, with unknown pages appended under "More"
local function navGroups()
	local seen, out = {}, {}
	for _, g in ipairs(NAV_GROUPS) do
		local ids = {}
		for _, id in ipairs(g[2]) do
			if pages[id] and not pages[id].hidden then
				table.insert(ids, id)
				seen[id] = true
			end
		end
		if #ids > 0 then
			table.insert(out, { g[1], ids })
		end
	end
	local rest = {}
	for _, id in ipairs(pageOrder) do
		if not pages[id].hidden and not seen[id] then
			table.insert(rest, id)
		end
	end
	if #rest > 0 then
		table.insert(out, { "More", rest })
	end
	return out
end

local function navIds()
	local out = {}
	for _, g in ipairs(navGroups()) do
		for _, id in ipairs(g[2]) do
			table.insert(out, id)
		end
	end
	return out
end

-- Geometry ------------------------------------------------------------------------------------------------------------

local function viewport()
	local cam = Services.Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function effectiveScale()
	local scale = Settings.get("ui.scale")
	local vp = viewport()
	local width, height = Settings.get("state.width"), Settings.get("state.height")
	-- shrink further when the window would not fit the screen (small phones, tiny windows)
	local fit = math.min((vp.X - 20) / width, (vp.Y - 60) / height)
	return math.max(0.5, math.min(scale, fit))
end

-- clampedGeometry() -> x, y, width, height in pixels (unscaled units; scale applied by UIScale)
local function geometry()
	local vp = viewport()
	local scale = effectiveScale()
	local width = math.clamp(Settings.get("state.width"), MIN_W, 1600)
	local height = math.clamp(Settings.get("state.height"), MIN_H, 1200)
	local x, y = Settings.get("state.posX"), Settings.get("state.posY")
	local sw, sh = width * scale, height * scale
	if x < 0 or y < 0 then
		x, y = (vp.X - sw) / 2, (vp.Y - sh) / 2
	end
	x = math.clamp(x, 0, math.max(0, vp.X - sw))
	y = math.clamp(y, 0, math.max(0, vp.Y - sh - 36))
	return x, y, width, height
end

local function applyGeometry()
	if not w then
		return
	end
	local x, y, width, height = geometry()
	w.root.Position = UDim2.fromOffset(x, y)
	w.root.Size = UDim2.fromOffset(width, height)
	w.scale.Scale = effectiveScale()
end

-- Pages ---------------------------------------------------------------------------------------------------------------------

local function titleOf(id)
	local def = pages[id]
	return I18n.t(def.title or ("nav." .. id))
end

local function ensurePage(id)
	local entry = w.built[id]
	if entry then
		return entry
	end
	local def = pages[id]
	local page = F.newPage(w.content, id)
	page.group.Visible = false
	page:header(titleOf(id), def.desc)
	local ok, err = xpcall(def.build, function(e)
		return tostring(e) .. "\n" .. debug.traceback("", 2)
	end, page)
	if not ok then
		Logger.error("UI", "page '%s' failed to build: %s", id, tostring(err))
		page:note("This page failed to load: " .. tostring(string.match(tostring(err), "^[^\n]*")), "bad", 60)
	end
	w.built[id] = page
	return page
end

local function highlight(row)
	if not row then
		return
	end
	-- rows have no outline of their own: flash the row background in the accent colour and let it fade
	Theme.bind(row, "BackgroundColor3", "accent")
	row.BackgroundTransparency = 0.72
	Motion.tween(row, { BackgroundTransparency = 1 }, 1.4, "smooth")
	task.delay(1.6, function()
		if row.Parent then
			Theme.bind(row, "BackgroundColor3", "highlight")
		end
	end)
end

local function movePill(id, animate)
	local btn = w.navButtons[id]
	if not btn or not w.pill then
		w.pill.Visible = false
		return
	end
	w.pill.Visible = true
	local goal = { Position = UDim2.fromOffset(0, btn.Position.Y.Offset) }
	if animate then
		Motion.tween(w.pill, goal, 0.45, "spring")
	else
		w.pill.Position = goal.Position
	end
end

-- navigate(id, anchorKey?) -> ok
function Window.navigate(id, anchorKey)
	if not w or not pages[id] then
		return false
	end
	local previous = w.current
	local page = ensurePage(id)
	local animate = Motion.enabled() and previous ~= id
	if previous ~= id then
		local old = previous and w.built[previous]
		if old then
			if animate then
				Motion.tween(old.group, { GroupTransparency = 1, Position = UDim2.fromOffset(-14, 0) }, 0.18, "exit")
				task.delay(Motion.duration(0.2), function()
					if w and w.current ~= previous and old.group.Parent then
						old.group.Visible = false
					end
				end)
			else
				old.group.Visible = false
			end
		end
		page.group.Visible = true
		if animate then
			page.group.GroupTransparency = 1
			page.group.Position = UDim2.fromOffset(18, 0)
			Motion.tween(page.group, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.42, "enter")
		else
			page.group.GroupTransparency = 0
			page.group.Position = UDim2.fromOffset(0, 0)
		end
	end
	w.current = id
	Settings.set("state.page", id, "nav")
	for pid, btn in pairs(w.navButtons) do
		local active = pid == id
		local icon = btn:FindFirstChild("IconHolder")
		if icon and icon:FindFirstChildOfClass("Frame") then
			Icons.recolor(icon:FindFirstChildOfClass("Frame"), active and "accent" or "textDim")
		end
		local label = btn:FindFirstChild("Label")
		if label then
			Theme.bind(label, "TextColor3", active and "text" or "textDim")
		end
	end
	movePill(id, previous ~= nil)
	w.titleLabel.Text = titleOf(id)
	if anchorKey and page.anchors[anchorKey] then
		local row = page.anchors[anchorKey]
		task.defer(function()
			if row.Parent and page.scroll.Parent then
				local y = row.AbsolutePosition.Y - page.content.AbsolutePosition.Y
				page.scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 20))
				highlight(row)
			end
		end)
	end
	Window.PageChanged:Fire(id)
	return true
end

function Window.currentPage()
	return w and w.current
end

function Window.nextTab(step)
	if not w then
		return
	end
	local ids = navIds()
	local idx = table.find(ids, w.current) or 0
	idx = ((idx - 1 + (step or 1)) % #ids) + 1
	Window.navigate(ids[idx])
end

function Window.prevTab()
	Window.nextTab(-1)
end

function Window.page(id)
	return w and w.built[id]
end

-- Visibility / minimise ------------------------------------------------------------------------------------------------------

function Window.isVisible()
	return w ~= nil and w.visible
end

local function updateShells()
	local minimized = Settings.get("state.minimized")
	w.window.Visible = w.visible and not minimized
	w.quick.Visible = w.visible and minimized
	w.shadow.Visible = w.visible and not minimized
end

function Window.show()
	if not w or w.visible then
		return
	end
	w.visible = true
	w.root.Visible = true
	updateShells()
	w.openScale.Scale = Motion.enabled() and 0.92 or 1
	Motion.tween(w.openScale, { Scale = 1 }, 0.45, "spring")
	Flair.sweep(w.window)
	Window.VisibilityChanged:Fire(true)
end

function Window.hide()
	if not w or not w.visible then
		return
	end
	w.visible = false
	F.closePopover()
	import("core/Input").cancelCapture()
	if Motion.enabled() then
		Motion.tween(w.openScale, { Scale = 0.94 }, 0.18, "exit")
		task.delay(Motion.duration(0.2), function()
			if w and not w.visible then
				w.root.Visible = false
			end
		end)
	else
		w.root.Visible = false
	end
	Window.VisibilityChanged:Fire(false)
end

function Window.toggle()
	if w and w.visible then
		Window.hide()
	else
		Window.show()
	end
end

function Window.minimize()
	if w then
		Settings.set("state.minimized", true, "window")
		updateShells()
		if not w.visible then
			Window.show()
		end
	end
end

function Window.expand()
	if w then
		Settings.set("state.minimized", false, "window")
		updateShells()
	end
end

function Window.isMinimized()
	return Settings.get("state.minimized")
end

-- Search ----------------------------------------------------------------------------------------------------------------------------

local CAT_PAGE = { A = "ui", B = "ui", C = "dashboard", D = "configs", E = "keys", F = "crosshair", G = "lighting", H = "camera", I = "perf", J = "diagnostics", K = "tools", L = "training" }
local SETTING_PAGE = { keys = "keys", input = "keys", state = "dashboard" }

local function pageForItem(item)
	if item.settingKey then
		local def = Settings.schema(item.settingKey)
		return SETTING_PAGE[def.category] or def.category, item.settingKey
	end
	return CAT_PAGE[item.category] or "dashboard", nil
end

Window.pageForItem = pageForItem

local function buildSearchPage()
	local page = F.newPage(w.content, "search")
	page.group.Visible = false
	w.built.search = page
	local chips = F.frame(page.content, { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 34) })
	F.list(chips, 6, true)
	local filter = { mode = "all", category = nil }
	local chipButtons = {}
	local resultsHolder = F.frame(page.content, { LayoutOrder = page:nextOrder(), AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	F.list(resultsHolder, 6)
	local pool = Pool.new({
		create = function()
			local row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = false
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 52)
			Theme.bind(row, "BackgroundColor3", "bg2")
			F.corner(row, 0)
			F.stroke(row, "stroke", 1, 0.75)
			local title = F.label(row, "", { size = 14, bold = true, dim = UDim2.new(1, -150, 0, 18) })
			title.Name = "Title"
			title.Position = UDim2.fromOffset(14, 8)
			local desc = F.label(row, "", { size = 11, token = "textDim", dim = UDim2.new(1, -150, 0, 14) })
			desc.Name = "Desc"
			desc.Position = UDim2.fromOffset(14, 28)
			local cat = F.label(row, "", { size = 11, bold = true, token = "accent", align = Enum.TextXAlignment.Right, dim = UDim2.fromOffset(120, 16) })
			cat.Name = "Cat"
			cat.AnchorPoint = Vector2.new(1, 0.5)
			cat.Position = UDim2.new(1, -14, 0.5, 0)
			return row
		end,
		reset = function(row)
			row.Parent = nil
			if row:FindFirstChild("Conn") then
				row.Conn:Destroy()
			end
		end,
		destroy = function(row)
			row:Destroy()
		end,
		max = 40,
	})
	local active = {}
	local rowMaids = {}

	local function release()
		for _, row in ipairs(active) do
			pool:Release(row)
		end
		table.clear(active)
		for _, m in ipairs(rowMaids) do
			m:Clean()
		end
		table.clear(rowMaids)
	end

	local function addRow(order, title, desc, cat, onClick)
		local row = pool:Acquire()
		row.LayoutOrder = order
		row.Title.Text = I18n.tr(title)
		row.Desc.Text = I18n.tr(desc)
		row.Cat.Text = I18n.tr(cat)
		row.Parent = resultsHolder
		local m = Maid.new("result")
		m:Give(row.Activated:Connect(function()
			F.click()
			onClick()
		end))
		m:Give(row.MouseEnter:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 0.25 }, 0.12, "smooth")
		end))
		m:Give(row.MouseLeave:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 0 }, 0.2, "smooth")
		end))
		table.insert(active, row)
		table.insert(rowMaids, m)
	end

	local empty = F.label(resultsHolder, I18n.t("search.none"), { size = 13, token = "textDim", align = Enum.TextXAlignment.Center, dim = UDim2.new(1, 0, 0, 40) })
	empty.Visible = false
	empty.LayoutOrder = 1000

	local function refresh()
		release()
		local text = w.query or ""
		local count = 0
		if string.sub(text, 1, 1) == ">" then
			for i, a in ipairs(Search.commands(string.sub(text, 2), 30)) do
				addRow(i, a.name, a.desc ~= "" and a.desc or a.id, "command", function()
					Actions.run(a.id)
				end)
				count += 1
			end
		else
			local results = Search.query(text, { onlyActive = filter.mode == "active", onlyFavorites = filter.mode == "favorites", category = filter.category, limit = 40 })
			for i, item in ipairs(results) do
				local catName = item.categoryName or item.category
				addRow(i, (I18n.get() == "ru" and item.ru and item.ru ~= "") and item.ru or I18n.tr(item.title), item.desc, catName, function()
					local id, key = pageForItem(item)
					if item.kind == "feature" then
						Recents.touch(item.id)
					end
					Window.navigate(id, key)
				end)
				count += 1
			end
		end
		empty.Visible = count == 0
	end
	w.refreshSearch = refresh

	local function chip(label, mode, category)
		local b = F.button(chips, label, function()
			filter.mode, filter.category = mode, category
			for _, c in ipairs(chipButtons) do
				Theme.bind(c.btn, "BackgroundColor3", (c.mode == filter.mode and c.category == filter.category) and "accent" or "bg3")
				Theme.bind(c.btn, "TextColor3", function()
					return (c.mode == filter.mode and c.category == filter.category) and Theme.accentText() or Theme.color("text")
				end)
			end
			refresh()
		end, "tinted", UDim2.fromOffset(math.max(56, #label * 8 + 22), 28), page.maid)
		table.insert(chipButtons, { btn = b, mode = mode, category = category })
	end
	chip(I18n.t("search.all"), "all", nil)
	chip(I18n.t("search.active"), "active", nil)
	chip(I18n.t("search.favorites"), "favorites", nil)
	local letters = {}
	for letter in pairs(Registry.CATEGORIES) do
		table.insert(letters, letter)
	end
	table.sort(letters)
	for _, letter in ipairs(letters) do
		chip(letter, "all", letter)
	end
	for _, c in ipairs(chipButtons) do
		F.tooltip(c.btn, c.category and Registry.CATEGORIES[c.category] or "", page.maid)
	end
	page.maid:Give(release)
	refresh()
	return page
end

local function runSearch(text)
	w.query = text
	if text == "" then
		if w.current == "search" then
			Window.navigate(w.lastPage or "dashboard")
		end
		return
	end
	if w.current ~= "search" then
		w.lastPage = w.current
		if not w.built.search then
			buildSearchPage()
		end
		pages.search = pages.search or { id = "search", hidden = true, title = "nav.search", build = function() end }
		w.built.search.group.Visible = false
		Window.navigate("search")
	end
	Search.invalidate()
	w.refreshSearch()
end

function Window.focusSearch()
	if w and w.searchBox then
		Window.show()
		w.searchBox:CaptureFocus()
	end
end

-- Toasts ------------------------------------------------------------------------------------------------------------------------------

local function buildToasts(maid)
	local host = Instance.new("Frame")
	host.Name = "Toasts"
	host.BackgroundTransparency = 1
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Position = UDim2.new(0.5, 0, 0, 12)
	host.Size = UDim2.fromOffset(360, 400)
	host.ZIndex = 200
	host.Parent = w.gui
	maid:Give(host)
	local list = F.list(host, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local LEVEL_ICON = { info = "info", success = "check", warn = "alert", error = "alert" }
	local pool = Pool.new({
		create = function()
			local card = F.surface(nil, "toast", { name = "Toast", sheen = 50, props = { Size = UDim2.new(0, 340, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 200 } })
			F.padding(card, 12, 11, 14, 11)
			-- level badge: a tinted disc with the level's glyph
			local badge = F.frame(card, { Name = "Badge", Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(28, 28), ZIndex = 201 }, { BackgroundColor3 = "accent" })
			badge.BackgroundTransparency = 0.8
			F.pillCorner(badge)
			local text = F.frame(card, { Name = "TextBox", Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 201 })
			F.list(text, 2)
			local title = F.label(text, "", { size = 13.5, bold = true, wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
			title.Name = "Title"
			title.AutomaticSize = Enum.AutomaticSize.Y
			title.LayoutOrder = 1
			title.ZIndex = 201
			local body = F.label(text, "", { size = 12, token = "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
			body.Name = "Text"
			body.AutomaticSize = Enum.AutomaticSize.Y
			body.LayoutOrder = 2
			body.ZIndex = 201
			local scale = Instance.new("UIScale")
			scale.Parent = card
			return card
		end,
		reset = function(card)
			card.Parent = nil
		end,
		destroy = function(card)
			card:Destroy()
		end,
		max = 8,
	})
	local live = {}
	local levelToken = { info = "accent", success = "good", warn = "warn", error = "bad" }

	maid:Give(Notify.Shown:Connect(function(item)
		local card = pool:Acquire()
		local badge = card.Badge
		card.TextBox.Title.Text = I18n.tr(item.title ~= "" and item.title or "TrollHub")
		card.TextBox.Text.Text = I18n.tr(item.text)
		local token = levelToken[item.level] or "accent"
		Theme.bind(badge, "BackgroundColor3", token)
		-- the glyph differs per level, so the meaning never depends on colour alone
		local old = badge:FindFirstChild("Glyph")
		if old then
			old:Destroy()
		end
		local glyph = Icons.draw(badge, LEVEL_ICON[item.level] or "info", 16, token)
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		card.LayoutOrder = item.id
		card.Parent = host
		local scale = card:FindFirstChildOfClass("UIScale")
		scale.Scale = Motion.enabled() and 0.94 or 1
		Motion.tween(scale, { Scale = 1 }, Motion.D.std * 1.2, "enter")
		live[item.id] = card
	end))
	local function done(item)
		local card = live[item.id]
		if card then
			live[item.id] = nil
			local scale = card:FindFirstChildOfClass("UIScale")
			Motion.tween(scale, { Scale = 0.94 }, Motion.D.std * 0.8, "exit")
			task.delay(Motion.duration(0.2), function()
				if card.Parent then
					pool:Release(card)
				end
			end)
		end
	end
	maid:Give(Notify.Expired:Connect(done))
	maid:Give(Notify.Dismissed:Connect(done))
	maid:Give(function()
		pool:Clear()
	end)
	w.toastPool = pool
end

-- Build ---------------------------------------------------------------------------------------------------------------------------------

local function buildTitleBar(maid)
	local bar = F.frame(w.window, { Name = "TitleBar", Size = UDim2.new(1, 0, 0, 52), ZIndex = 3 })
	w.titleBar = bar
	-- product mark: an accent disc with a light centre
	local logo = F.frame(bar, { Position = UDim2.fromOffset(18, 15), Size = UDim2.fromOffset(22, 22), ZIndex = 4 }, { BackgroundColor3 = "accent" })
	logo.BackgroundTransparency = 0
	F.pillCorner(logo)
	local lg = Instance.new("UIGradient")
	lg.Rotation = 90
	Theme.bind(lg, "Color", function()
		return ColorSequence.new(Theme.mix("accent", "highlight", 0.35), Theme.color("accent"))
	end)
	lg.Parent = logo
	local inner = F.frame(logo, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 0.36), ZIndex = 5 })
	inner.BackgroundTransparency = 0.05
	inner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	F.pillCorner(inner)
	local size, bold = Theme.type("app")
	local name = F.label(bar, I18n.t("app.title"), { size = size, bold = bold, dim = UDim2.fromOffset(76, 20) })
	name.Position = UDim2.fromOffset(50, 16)
	name.ZIndex = 4
	w.nameLabel = name
	-- flowing title: the colours / style / direction of the Watermark page (ui.titleFlow)
	local Shimmer = import("ui/Shimmer")
	Shimmer.attach(name, maid, function()
		if Settings.get("ui.titleFlow") then
			return import("ui/Watermark").shimmerConfig()
		end
		return { style = "Off", colors = { { r = 255, g = 255, b = 255 } } }
	end)
	-- breadcrumb: a hairline and the name of the current page
	local divider = F.frame(bar, { Position = UDim2.fromOffset(130, 18), Size = UDim2.fromOffset(1, 16), ZIndex = 4 }, { BackgroundColor3 = "stroke" })
	divider.BackgroundTransparency = 0.45
	w.titleDivider = divider
	local sep = F.label(bar, "", { size = 13, token = "textDim", dim = UDim2.fromOffset(150, 20) })
	sep.Position = UDim2.fromOffset(142, 16)
	sep.ZIndex = 4
	w.titleLabel = sep

	-- search field with a magnifier
	local box = F.textBox(bar, { placeholder = I18n.t("search.placeholder"), dim = UDim2.new(0, 250, 0, 32) }, maid)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -168, 0.5, 0)
	box.ZIndex = 4
	local pad = box:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, 34)
	end
	local mag = Icons.draw(box, "search", 14, "textDim")
	mag.AnchorPoint = Vector2.new(0, 0.5)
	mag.Position = UDim2.new(0, -24, 0.5, 0)
	w.searchBox = box
	local token = 0
	maid:Give(box:GetPropertyChangedSignal("Text"):Connect(function()
		token += 1
		local mine = token
		task.delay(0.12, function()
			if mine == token and w then
				runSearch(box.Text)
			end
		end)
	end))
	maid:Give(box.FocusLost:Connect(function(enter)
		if enter and w.query and string.sub(w.query, 1, 1) == ">" then
			local first = Search.commands(string.sub(w.query, 2), 1)[1]
			if first then
				Actions.run(first.id)
				box.Text = ""
			end
		end
	end))

	-- right controls: live FPS (real data from Perf), minimise, close
	local fps = F.label(bar, "", { size = 12, bold = true, token = "textDim", align = Enum.TextXAlignment.Right, dim = UDim2.fromOffset(62, 20) })
	fps.AnchorPoint = Vector2.new(1, 0)
	fps.Position = UDim2.new(1, -96, 0, 16)
	fps.ZIndex = 4
	w.fpsLabel = fps
	local min = F.iconButton(bar, "minus", Window.minimize, 28, maid)
	min.AnchorPoint = Vector2.new(1, 0.5)
	min.Position = UDim2.new(1, -48, 0.5, 0)
	min.ZIndex = 4
	local close = F.iconButton(bar, "close", Window.hide, 28, maid, nil, true)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -14, 0.5, 0)
	close.ZIndex = 4
	F.tooltip(min, "Minimise", maid)
	F.tooltip(close, "Hide (use the hotkey or launcher to reopen)", maid)
	-- hairline under the bar
	local line = F.frame(w.window, { Name = "BarLine", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3 }, { BackgroundColor3 = "stroke" })
	line.BackgroundTransparency = 0.6

	-- drag
	maid:Give(bar.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not Settings.get("ui.lockPosition") then
			local start = input.Position
			local x0, y0 = w.root.AbsolutePosition.X, w.root.AbsolutePosition.Y
			F.beginDrag(function(pos)
				local vp = viewport()
				local nx = math.clamp(x0 + (pos.X - start.X), 0, vp.X - 60)
				local ny = math.clamp(y0 + (pos.Y - start.Y), 0, vp.Y - 90)
				w.root.Position = UDim2.fromOffset(nx, ny)
			end, function()
				local ap = w.root.AbsolutePosition
				Settings.set("state.posX", ap.X, "window")
				Settings.set("state.posY", ap.Y, "window")
			end)
		end
	end))
end

local NAV_H, NAV_GAP, NAV_HEAD = 36, 2, 24

-- layoutNav(compact): position group headers and nav rows. The compact sidebar (icons only) drops the headers and
-- keeps a small gap between groups instead.
local function layoutNav(compact)
	local y = 0
	for gi, group in ipairs(navGroups()) do
		local head = w.navHeads[gi]
		if head then
			head.Visible = not compact
			if compact then
				y += (gi == 1 and 0 or 8)
			else
				head.Position = UDim2.fromOffset(10, y + (gi == 1 and 4 or 10))
				y += (gi == 1 and 4 or 10) + NAV_HEAD - 6
			end
		end
		for _, id in ipairs(group[2]) do
			local b = w.navButtons[id]
			if b then
				b.Position = UDim2.fromOffset(0, y)
			end
			y += NAV_H + NAV_GAP
		end
	end
	w.navInner.Size = UDim2.new(1, 0, 0, y + 4)
	if w.current and w.navButtons[w.current] then
		movePill(w.current, false)
	end
end

local function buildSidebar(maid)
	local side = F.surface(w.window, "rail", { name = "Sidebar", radius = "none", edge = false, props = { Position = UDim2.fromOffset(0, 53), Size = UDim2.new(0, SIDEBAR_W, 1, -53), ZIndex = 2 } })
	w.sidebar = side
	local edge = F.frame(side, { Name = "EdgeLine", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 3 }, { BackgroundColor3 = "stroke" })
	edge.BackgroundTransparency = 0.65
	local holder = F.frame(side, { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12) })
	local sf, smaid = F.scroller(holder)
	maid:Give(smaid)
	local inner = F.frame(sf, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	w.navInner = inner
	-- the selection pill glides between rows; a short accent bar marks the active page
	w.pill = F.frame(inner, { Size = UDim2.new(1, 0, 0, NAV_H), ZIndex = 1 }, { BackgroundColor3 = "accent" })
	w.pill.BackgroundTransparency = 0.84
	F.corner(w.pill, "control")
	local accentBar = F.frame(w.pill, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 16) }, { BackgroundColor3 = "accent" })
	accentBar.BackgroundTransparency = 0
	F.pillCorner(accentBar)

	w.navButtons, w.navHeads = {}, {}
	local y = 0
	for gi, group in ipairs(navGroups()) do
		local head = F.label(inner, I18n.upper(I18n.tr(group[1])), { size = 10, bold = true, token = "textDim", dim = UDim2.new(1, -12, 0, 14) })
		head.Name = "NavHead"
		head:SetAttribute("key", group[1])
		head.Position = UDim2.fromOffset(10, y + (gi == 1 and 4 or 10))
		head.ZIndex = 2
		table.insert(w.navHeads, head)
		y += (gi == 1 and 4 or 10) + NAV_HEAD - 6
		for _, id in ipairs(group[2]) do
			local def = pages[id]
			local b = Instance.new("TextButton")
			b.Name = "Nav_" .. id
			b.Text = ""
			b.AutoButtonColor = false
			b.BackgroundTransparency = 1
			b.BorderSizePixel = 0
			b.Position = UDim2.fromOffset(0, y)
			b.Size = UDim2.new(1, 0, 0, NAV_H)
			b.ZIndex = 2
			Theme.bind(b, "BackgroundColor3", "highlight")
			F.corner(b, "control")
			b.Parent = inner
			local holderIcon = F.frame(b, { Name = "IconHolder", Position = UDim2.fromOffset(11, 8), Size = UDim2.fromOffset(20, 20), ZIndex = 3 })
			Icons.draw(holderIcon, def.icon or "info", 20, "textDim")
			local label = F.label(b, titleOf(id), { size = 13, bold = false, token = "textDim", dim = UDim2.new(1, -46, 1, 0) })
			label.Name = "Label"
			label.Position = UDim2.fromOffset(42, 0)
			label.ZIndex = 3
			maid:Give(b.Activated:Connect(function()
				F.click()
				if w.searchBox.Text ~= "" then
					w.searchBox.Text = ""
					w.query = ""
				end
				Window.navigate(id)
			end))
			-- hover: a faint wash on rows that are not selected
			maid:Give(b.MouseEnter:Connect(function()
				if w.current ~= id then
					Motion.tween(b, { BackgroundTransparency = 0.94 }, Motion.D.fast, "smooth")
				end
			end))
			maid:Give(b.MouseLeave:Connect(function()
				Motion.tween(b, { BackgroundTransparency = 1 }, Motion.D.std, "smooth")
			end))
			F.tooltip(b, function()
				return titleOf(id)
			end, maid)
			w.navButtons[id] = b
			y += NAV_H + NAV_GAP
		end
	end
	inner.Size = UDim2.new(1, 0, 0, y + 4)
	inner.AutomaticSize = Enum.AutomaticSize.None
	layoutNav(false)
	end


local function buildResize(maid)
	local grip = Instance.new("TextButton")
	grip.Name = "Grip"
	grip.Text = ""
	grip.BackgroundTransparency = 1
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.fromScale(1, 1)
	local touch = Services.UserInputService.TouchEnabled
	grip.Size = UDim2.fromOffset(touch and 40 or 26, touch and 40 or 26)
	grip.ZIndex = 10
	grip.AutoButtonColor = false
	grip.Parent = w.window
	for i = 0, 1 do
		local bar = F.frame(grip, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 3 + i * 3, 0.5, 3 + i * 3), Size = UDim2.fromOffset(14 - i * 6, 2), Rotation = -45, ZIndex = 11 }, { BackgroundColor3 = "textDim" })
		bar.BackgroundTransparency = 0.4
		F.pillCorner(bar)
	end
	maid:Give(grip.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not Settings.get("ui.lockPosition") then
			local start = input.Position
			local w0, h0 = w.root.AbsoluteSize.X / effectiveScale(), w.root.AbsoluteSize.Y / effectiveScale()
			F.beginDrag(function(pos)
				local s = effectiveScale()
				local nw = math.clamp(w0 + (pos.X - start.X) / s, MIN_W, 1600)
				local nh = math.clamp(h0 + (pos.Y - start.Y) / s, MIN_H, 1200)
				w.root.Size = UDim2.fromOffset(nw, nh)
				w.pending = { nw, nh }
			end, function()
				if w.pending then
					Settings.set("state.width", w.pending[1], "window")
					Settings.set("state.height", w.pending[2], "window")
					w.pending = nil
				end
			end)
		end
	end))
end

local function buildShadow(parent)
	-- a soft drop shadow made of a few stacked rounded rectangles (Roblox has no blur): the transparency ramp is
	-- geometric so the layers read as one falloff instead of visible steps
	local shadow = F.frame(parent, { Name = "Shadow", Size = UDim2.fromScale(1, 1), ZIndex = 0 })
	w.shadow = shadow
	-- preferred: one smooth 9-slice shadow image (ui/Flair); the stacked layers below are the fallback without bundled images
	local soft = Flair.softShadow(shadow)
	if soft then
		Theme.bind(soft, "Visible", function()
			return Theme.effectsOn()
		end)
		return
	end
	for _, spec in ipairs({ { 4, 0.9 }, { 10, 0.935 }, { 18, 0.955 }, { 28, 0.97 }, { 40, 0.982 }, { 54, 0.99 } }) do
		local layer = Instance.new("Frame")
		layer.Name = "Layer"
		layer.BorderSizePixel = 0
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.new(0.5, 0, 0.5, 10)
		layer.Size = UDim2.new(1, spec[1] * 2, 1, spec[1] * 2)
		layer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		layer.BackgroundTransparency = spec[2]
		layer.ZIndex = 0
		local c = Instance.new("UICorner")
		Theme.bind(c, "CornerRadius", function()
			return UDim.new(0, Theme.rad("window") + spec[1])
		end)
		c.Parent = layer
		Theme.bind(layer, "Visible", function()
			return Theme.effectsOn()
		end)
		layer.Parent = shadow
	end
end

local function buildQuickBar(maid)
	local quick = F.surface(w.root, "popover", { name = "QuickBar", radius = "pill", sheen = 24, props = { Size = UDim2.new(1, 0, 1, 0), Visible = false } })
	w.quick = quick
	local logo = F.frame(quick, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(18, 18) }, { BackgroundColor3 = "accent" })
	logo.BackgroundTransparency = 0
	F.pillCorner(logo)
	local fps = F.label(quick, "", { size = 12, bold = true, token = "textDim", dim = UDim2.fromOffset(62, 18) })
	fps.AnchorPoint = Vector2.new(0, 0.5)
	fps.Position = UDim2.new(0, 40, 0.5, 0)
	w.quickFps = fps
	local favHolder = F.frame(quick, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 104, 0.5, 0), Size = UDim2.new(1, -170, 0, 28) })
	F.list(favHolder, 6, true)
	w.quickFavs = favHolder
	local expand = F.iconButton(quick, "plus", Window.expand, 28, maid)
	expand.AnchorPoint = Vector2.new(1, 0.5)
	expand.Position = UDim2.new(1, -10, 0.5, 0)
	maid:Give(quick.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not Settings.get("ui.lockPosition") then
			local start = input.Position
			local x0, y0 = w.root.AbsolutePosition.X, w.root.AbsolutePosition.Y
			F.beginDrag(function(pos)
				w.root.Position = UDim2.fromOffset(x0 + (pos.X - start.X), y0 + (pos.Y - start.Y))
			end, function()
				Settings.set("state.posX", w.root.AbsolutePosition.X, "window")
				Settings.set("state.posY", w.root.AbsolutePosition.Y, "window")
			end)
		end
	end))
end

local function refreshQuickFavs(maid)
	for _, c in ipairs(w.quickFavs:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local shown = 0
	for _, id in ipairs(Recents.favorites()) do
		local feat = Registry.get(id)
		if feat and shown < 4 then
			local text = I18n.cut(I18n.featureName(feat), 10)
			local btn = F.button(w.quickFavs, text, function()
				if feat.impl.kind == "setting" and Settings.schema(feat.impl.target).type == "bool" then
					Settings.toggle(feat.impl.target, "quick")
				elseif feat.impl.kind == "action" then
					Actions.run(feat.impl.target)
				else
					Window.expand()
					local pageId, key = pageForItem({ settingKey = feat.impl.kind == "setting" and feat.impl.target or nil, category = feat.cat })
					Window.navigate(pageId, key)
				end
			end, "tinted", UDim2.fromOffset(#text * 7 + 20, 26), maid)
			F.tooltip(btn, I18n.featureName(feat), maid)
			shown += 1
		end
	end
end

local function buildLauncher(maid)
	local b = Instance.new("TextButton")
	b.Name = "Launcher"
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(0, 10, 0.5, 0)
	b.Size = UDim2.fromOffset(46, 46)
	b.ZIndex = 50
	Theme.bind(b, "BackgroundColor3", "accent")
	F.pillCorner(b)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	Theme.bind(g, "Color", function()
		return ColorSequence.new(Theme.mix("accent", "highlight", Theme.effectsOn() and 0.3 or 0), Theme.color("accent"))
	end)
	g.Parent = b
	F.edge(b, "popover")
	local dot = F.frame(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 51 })
	dot.BackgroundTransparency = 0.04
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	F.pillCorner(dot)
	b.Parent = w.gui
	Theme.bind(b, "Visible", function()
		return Settings.get("ui.showLauncher")
	end)
	Motion.pressable(b, maid, 0.1)
	maid:Give(b.MouseEnter:Connect(function()
		Motion.tween(dot, { Size = UDim2.fromOffset(20, 20) }, Motion.D.fast, "smooth")
	end))
	maid:Give(b.MouseLeave:Connect(function()
		Motion.tween(dot, { Size = UDim2.fromOffset(16, 16) }, Motion.D.std, "smooth")
	end))
	maid:Give(b.Activated:Connect(function()
		F.click()
		Window.toggle()
	end))
	maid:Give(b)
	w.launcher = b
	maid:Give(Settings.observe("ui.showLauncher", function(v)
		b.Visible = v
	end, true))
	return b
end

-- start(ctx) builds the ScreenGui. Pages must be registered before this is called.
function Window.start(ctx)
	assert(w == nil, "Window already started")
	local parent, how = Env.guiParent()
	if not parent then
		error("no GUI container available (gethui/CoreGui/PlayerGui all failed)")
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2Hub"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	ctx.maid:Give(gui)
	Logger.info("Window", "GUI container: %s", how)

	w = { gui = gui, built = {}, current = nil, visible = false, query = "", navButtons = {}, maid = ctx.maid }
	ctx.maid:Give(function()
		F.closePopover()
		if w then
			for _, page in pairs(w.built) do
				page:destroy()
			end
		end
		w = nil
	end)

	F.init({ gui = gui, maid = ctx.maid })
	ctx.maid:Give(I18n.Changed:Connect(function()
		Window.relocalize()
	end))
	Theme.start(ctx.maid)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	w.root = root
	w.scale = Instance.new("UIScale")
	w.scale.Parent = root
	w.openScale = Instance.new("UIScale")
	w.openScale.Parent = root
	buildShadow(root)

	local window = F.surface(root, "window", { name = "Window", props = { Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 1 } })
	w.window = window
	-- colour pooling: a very faint accent wash from the top-left corner (effects on only)
	local ambient = F.frame(window, { Name = "Ambient", Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { BackgroundColor3 = "accent" })
	ambient.BackgroundTransparency = 0
	local ag = Instance.new("UIGradient")
	ag.Rotation = 35
	Theme.bind(ag, "Transparency", function()
		return NumberSequence.new(0.9 + (1 - Theme.glassAmount()) * 0.1, 1)
	end)
	ag.Parent = ambient
	Theme.bind(ambient, "Visible", function()
		return Theme.effectsOn()
	end)

	-- the menu's own picture layers: chrome waves backdrop, frosted grain, glass highlight (ui/Flair)
	Flair.backdrop(window, ctx.maid, function()
		return w ~= nil and w.visible and not Settings.get("state.minimized")
	end)
	-- specular sheen + animated accent line (decor)
	F.sheen(window, 170)
	local line = F.frame(window, { Name = "AccentLine", Size = UDim2.new(1, 0, 0, 1), ZIndex = 6 })
	line.BackgroundTransparency = 0
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	local lg = Instance.new("UIGradient")
	lg.Transparency = NumberSequence.new(1, 0.35)
	Theme.bind(lg, "Color", function()
		return ColorSequence.new(Theme.color("accent"), Theme.color("accent"))
	end)
	lg.Parent = line
	w.lineGradient = lg
	local decorHandle = Perf.every("ui.decor", 20, function(dt)
		if Settings.get("ui.decor") and Theme.effectsOn() and w.visible and not Settings.get("state.minimized") then
			w.decorPhase = ((w.decorPhase or 0) + dt * 0.35) % 2
			local p = w.decorPhase
			lg.Offset = Vector2.new(p < 1 and (p * 2 - 1) or ((2 - p) * 2 - 1), 0)
			line.Visible = true
		else
			line.Visible = false
		end
	end, { visual = true })
	ctx.maid:Give(decorHandle.Cancel)

	buildTitleBar(ctx.maid)
	buildSidebar(ctx.maid)
	w.content = F.frame(window, { Name = "Content", Position = UDim2.fromOffset(SIDEBAR_W + 10, 60), Size = UDim2.new(1, -SIDEBAR_W - 20, 1, -68), ZIndex = 2 })
	buildResize(ctx.maid)
	buildQuickBar(ctx.maid)
	buildToasts(ctx.maid)
	buildLauncher(ctx.maid)
	refreshQuickFavs(ctx.maid)
	ctx.maid:Give(Settings.observe("state.favorites", function()
		if w then
			refreshQuickFavs(ctx.maid)
		end
	end))

	-- compact sidebar on narrow windows
	local function relayout()
		if not w then
			return
		end
		local width = w.root.AbsoluteSize.X / math.max(0.1, w.scale.Scale)
		local compact = width < 600
		local sw = compact and SIDEBAR_COMPACT or SIDEBAR_W
		w.sidebar.Size = UDim2.new(0, sw, 1, -53)
		w.content.Position = UDim2.fromOffset(sw + 10, 60)
		w.content.Size = UDim2.new(1, -sw - 20, 1, -68)
		for _, b in pairs(w.navButtons) do
			local l = b:FindFirstChild("Label")
			if l then
				l.Visible = not compact
			end
		end
		if w.navCompact ~= compact then
			w.navCompact = compact
			layoutNav(compact)
		end
		w.searchBox.PlaceholderText = compact and I18n.tr("Search") or I18n.tr(I18n.t("search.placeholder"))
		w.titleLabel.Visible = width > 700
		w.titleDivider.Visible = width > 700
		w.searchBox.Size = UDim2.new(0, compact and 150 or 250, 0, 32)
	end
	ctx.maid:Give(w.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))

	for _, key in ipairs({ "state.width", "state.height", "ui.scale", "state.posX", "state.posY" }) do
		ctx.maid:Give(Settings.observe(key, applyGeometry))
	end
	local cam = Services.Workspace.CurrentCamera
	if cam then
		ctx.maid:Give(cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyGeometry))
	end
	ctx.maid:Give(Settings.observe("state.minimized", function()
		if w then
			updateShells()
			-- the quick bar is a slim pill; the window uses its saved size
			if Settings.get("state.minimized") then
				w.root.Size = UDim2.fromOffset(330, 46)
				w.quickFps.Text = ""
			else
				applyGeometry()
			end
		end
	end))

	-- live FPS badges (2 text writes per update at 4 Hz)
	local fpsHandle = Perf.every("ui.fps", 4, function()
		if not w or not w.visible then
			return
		end
		local text = string.format("%d FPS", Perf.fps() + 0.5)
		if Settings.get("ui.showFpsBadge") then
			w.fpsLabel.Text = text
			w.quickFps.Text = text
		else
			w.fpsLabel.Text = ""
			w.quickFps.Text = ""
		end
	end, { visual = true })
	ctx.maid:Give(fpsHandle.Cancel)

	applyGeometry()
	relayout()
	local first = Settings.get("state.page")
	if not pages[first] or pages[first].hidden then
		first = "dashboard"
	end
	Window.navigate(first)
	w.visible = false
	Window.show()
	Flair.loading(w.root, Theme.rad("window"), ctx.maid)
	Flair.sticker(w.root, ctx.maid)
	Flair.cursor(gui, ctx.maid, function()
		return w ~= nil and w.visible and not Settings.get("state.minimized")
	end)
	if Settings.get("state.minimized") then
		w.root.Size = UDim2.fromOffset(330, 46)
		updateShells()
	end
	ctx.maid:Give(w.openScale)
end

-- relocalize(): rebuild texts after the language changed (pages are rebuilt lazily from the new language).
function Window.relocalize()
	if not w then
		return
	end
	for _, page in pairs(w.built) do
		page:destroy()
	end
	w.built = {}
	w.refreshSearch = nil
	w.nameLabel.Text = I18n.t("app.title")
	w.searchBox.PlaceholderText = I18n.tr(I18n.t("search.placeholder"))
	for id, btn in pairs(w.navButtons) do
		local label = btn:FindFirstChild("Label")
		if label then
			label.Text = titleOf(id)
		end
	end
	for _, head in ipairs(w.navHeads) do
		head.Text = I18n.upper(I18n.tr(head:GetAttribute("key") or ""))
	end
	refreshQuickFavs(w.maid)
	local cur = w.current
	w.current = nil
	if not cur or cur == "search" or not pages[cur] then
		cur = "dashboard"
	end
	w.query = ""
	w.searchBox.Text = ""
	Window.navigate(cur)
end

function Window.isRunning()
	return w ~= nil
end

function Window.builtPageCount()
	if not w then
		return 0
	end
	local n = 0
	for _ in pairs(w.built) do
		n += 1
	end
	return n
end

function Window._reset()
	table.clear(pages)
	table.clear(pageOrder)
end

return Window

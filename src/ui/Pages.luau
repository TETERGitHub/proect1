--!nonstrict
-- ui/Pages: every page of the hub. Settings pages are generated from the schema so each control is
-- bound to real state; pages with live data (dashboard, performance, diagnostics, music, tools,
-- configs, training, cosmetics) add their own sections on top.
-- Depends on: Framework, Window, Theme, Motion, Icons, Settings, Config, Input, Actions, Notify, Perf,
--   Recents, Registry, Version, Env, Diagnostics, Core, Logger, Maid, Pool, I18n and all feature modules.

local import = ...
local F = import("ui/Framework")
local Window = import("ui/Window")
local Theme = import("ui/Theme")
local Settings = import("core/Settings")
local Actions = import("core/Actions")
local Perf = import("core/Perf")
local Recents = import("core/Recents")
local Registry = import("core/Registry")
local I18n = import("core/I18n")
local Layout = import("features/CrosshairLayout")
local Tools = import("features/Tools")
local Search = import("core/Search")

local Pages = {}

for _, id in ipairs({ "Pages.dashboard", "Pages.hotkeys", "Pages.help", "Pages.about", "Pages.history", "Pages.diagnostics", "Pages.performance", "Recents", "Favorites", "Perf.fps", "Perf.ping", "Pool.reuse" }) do
	Registry.provide(id)
end

local Kit = import("ui/PageKit")
local notify, visible, auto, section, resetButton, dataList, infoLine = Kit.notify, Kit.visible, Kit.auto, Kit.section, Kit.resetButton, Kit.dataList, Kit.infoLine

-- Dashboard -------------------------------------------------------------------------------------------------------

local function buildDashboard(page)
	local update = page:stats({
		{ title = I18n.t("dash.session"), value = "00:00" },
		{ title = I18n.t("dash.fps"), value = "—" },
		{ title = I18n.t("dash.ping"), value = "—" },
		{ title = I18n.t("dash.active"), value = "0" },
	})

	local conflictsNote, conflictsLabel = page:note("", "warn", 40)
	conflictsNote.Visible = false

	page:section(I18n.t("dash.quick"))
	local grid = F.frame(page.content, { LayoutOrder = page:nextOrder(), AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.333, -8, 0, 40)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	local quick = {
		{ "Crosshair", "crosshair.toggle" },
		{ "Training range", "training.toggle" },
		{ "Low load profile", "lowprofile.toggle" },
		{ "Save profile", "config.save" },
		{ "Minimise", "window.minimize" },
	}
	for i, q in ipairs(quick) do
		local b = F.button(grid, q[1], function()
			if Actions.has(q[2]) then
				Actions.run(q[2])
			end
		end, i <= 3 and "filled" or "tinted", UDim2.fromOffset(100, 40), page.maid)
		b.LayoutOrder = i
	end

	page:section(I18n.t("dash.favorites"))
	local favList = dataList(page, {
		rowHeight = 40,
		maxRows = 12,
		buttons = {
			{ icon = "chevron", tip = "Open", fn = function(item)
				local feat = Registry.get(item.id)
				if feat then
					local pageId, key = Window.pageForItem({ settingKey = feat.impl.kind == "setting" and feat.impl.target or nil, category = feat.cat })
					Window.navigate(pageId, key)
				end
			end },
		},
	})
	page:section(I18n.t("dash.recent"))
	local recentList = dataList(page, {
		rowHeight = 40,
		maxRows = 8,
		buttons = {
			{ icon = "chevron", tip = "Open", fn = function(item)
				local feat = Registry.get(item.id)
				if feat then
					local pageId, key = Window.pageForItem({ settingKey = feat.impl.kind == "setting" and feat.impl.target or nil, category = feat.cat })
					Window.navigate(pageId, key)
				end
			end },
		},
	})

	local function featureItems(ids)
		local out = {}
		for _, id in ipairs(ids) do
			local feat = Registry.get(id)
			if feat then
				local value = ""
				if feat.impl.kind == "setting" and Settings.has(feat.impl.target) then
					local v = Settings.get(feat.impl.target)
					value = type(v) == "boolean" and (v and "ON" or "off") or (type(v) == "table" and "" or tostring(v))
				end
				table.insert(out, { id = id, title = I18n.featureName(feat), value = value, valueToken = value == "ON" and "good" or "textDim" })
			end
		end
		return out
	end
	local function renderLists()
		favList.set(featureItems(Recents.favorites()))
		recentList.set(featureItems(Recents.recent()))
	end
	page.maid:Give(Settings.observe("state.favorites", renderLists))
	page.maid:Give(Settings.observe("state.recent", renderLists))
	renderLists()

	local handle = Perf.every("ui.dashboard", 2, function()
		if not visible("dashboard") then
			return
		end
		update(1, Tools.formatTime(Tools.sessionSeconds()))
		update(2, string.format("%d", Perf.fps() + 0.5), Perf.fps() < 30 and "warn" or "text")
		local ping = Perf.ping()
		update(3, ping and string.format("%d ms", ping) or "n/a")
		local active = 0
		for _, item in ipairs(Search.query("", { onlyActive = true })) do
			if item.kind == "feature" then
				active += 1
			end
		end
		update(4, tostring(active))
		local conflicts = Settings.conflicts()
		conflictsNote.Visible = #conflicts > 0
		if #conflicts > 0 then
			conflictsLabel.Text = "⚠ " .. conflicts[1].message .. (#conflicts > 1 and string.format("  (+%d more in Diagnostics)", #conflicts - 1) or "")
		end
	end)
	page.maid:Give(handle.Cancel)
end

-- Settings pages generated from the schema ---------------------------------------------------------------------------------

local function buildInterface(page)
	resetButton(page, "Interface")
	section(page, "Appearance", { "ui.theme", "ui.useThemeAccent", "ui.accent", "ui.opacity", "ui.cornerRadius", "ui.density", "ui.textScale", "ui.scale" })
	section(page, "Motion", { "ui.animSpeed", "ui.decor" })
	section(page, "On-screen buttons", { "ui.screenButtons", "ui.screenButtonSize", "ui.screenButtonOpacity" })
	section(page, "Behaviour", { "ui.compact", "ui.lockPosition", "ui.showTooltips", "ui.showLauncher", "ui.showFpsBadge", "ui.notifications", "ui.notifyDuration" })
	page:section("Language")
	page:enum({ key = "ui.language" })
	page:note("Window position and size are saved automatically with your profile state.", "textDim", 30)
end

local function buildCrosshair(page)
	-- live preview card, drawn with the same layout maths as the in-game crosshair
	local card = page:card(150)
	local stage = F.frame(card, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 1, -24), ClipsDescendants = true })
	Theme.bind(stage, "BackgroundColor3", "bg0")
	stage.BackgroundTransparency = 0
	F.corner(stage, -2)
	local center = F.frame(stage, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0) })
	local parts = {}
	for _, id in ipairs({ "top", "bottom", "left", "right", "ring", "dot" }) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Visible = false
		f.Parent = center
		local st = Instance.new("UIStroke")
		st.Thickness = 1
		st.Parent = f
		parts[id] = { frame = f, stroke = st }
	end
	local corner1 = Instance.new("UICorner")
	corner1.CornerRadius = UDim.new(0.5, 0)
	corner1.Parent = parts.ring.frame
	local corner2 = Instance.new("UICorner")
	corner2.CornerRadius = UDim.new(0.5, 0)
	corner2.Parent = parts.dot.frame
	local function preview()
		local function s(n)
			return Settings.get("crosshair." .. n)
		end
		local layout = Layout.compute({ style = s("style"), size = s("size"), thickness = s("thickness"), gap = s("gap"), centerDot = s("centerDot"), dotSize = s("dotSize"), spread = 0 })
		local c = s("color")
		local color = Color3.fromRGB(c.r, c.g, c.b)
		local tr = 1 - s("opacity")
		for _, p in pairs(parts) do
			p.frame.Visible = false
		end
		for _, r in ipairs(layout.rects) do
			local p = parts[r.id]
			p.frame.Visible = true
			p.frame.Size = UDim2.fromOffset(r.w, r.h)
			p.frame.Position = UDim2.fromOffset(r.x, r.y)
			p.frame.BackgroundColor3 = color
			p.frame.BackgroundTransparency = tr
			p.stroke.Enabled = s("outline")
			p.stroke.Transparency = math.min(1, tr + 0.15)
			p.stroke.Color = Color3.fromRGB(0, 0, 0)
		end
		if layout.circle then
			local p = parts.ring
			p.frame.Visible = true
			p.frame.BackgroundTransparency = 1
			p.frame.Size = UDim2.fromOffset(layout.circle.radius * 2, layout.circle.radius * 2)
			p.frame.Position = UDim2.fromOffset(0, 0)
			p.stroke.Enabled = true
			p.stroke.Color = color
			p.stroke.Thickness = layout.circle.thickness
			p.stroke.Transparency = tr
		end
		if layout.dot then
			local p = parts.dot
			p.frame.Visible = true
			p.frame.Size = UDim2.fromOffset(layout.dot.size, layout.dot.size)
			p.frame.Position = UDim2.fromOffset(0, 0)
			p.frame.BackgroundColor3 = color
			p.frame.BackgroundTransparency = tr
			p.stroke.Enabled = s("outline")
			p.stroke.Color = Color3.fromRGB(0, 0, 0)
		end
	end
	for _, key in ipairs(Settings.keys({ category = "crosshair" })) do
		page.maid:Give(Settings.observe(key, preview))
	end
	preview()
	resetButton(page, "Crosshair")
	section(page, "General", { "crosshair.enabled", "crosshair.style", "crosshair.color", "crosshair.opacity" })
	section(page, "Shape", { "crosshair.size", "crosshair.thickness", "crosshair.gap", "crosshair.centerDot", "crosshair.dotSize", "crosshair.outline" })
	section(page, "Dynamic", { "crosshair.dynamic", "crosshair.dynamicAmount" })
	section(page, "Position", { "crosshair.offsetX", "crosshair.offsetY", "crosshair.hideCursor" })
end

local function buildCamera(page)
	page:action({
		label = "Reset camera",
		desc = "Resets every camera setting and restores the original zoom limits, FOV and mouse sensitivity.",
		text = "Reset",
		style = "danger",
		onClick = function()
			Actions.run("camera.reset")
			notify("Camera", "Camera reset.", "success")
		end,
	})
	section(page, "Zoom", { "camera.zoomEnabled", "camera.zoomSpeed", "camera.minZoom", "camera.maxZoom", "camera.rememberZoom", "camera.preferredZoom" })
	section(page, "View", { "camera.mode", "camera.fovEnabled", "camera.fov", "camera.smoothing" })
	section(page, "Mouse", { "camera.sensitivityEnabled", "camera.sensitivity" })
	section(page, "Effects", { "camera.bobIntensity", "camera.ownOpacity", "camera.disableEffects" })
	section(page, "Ghost - local invisibility (your screen only)", { "ghost.enabled", "ghost.opacity", "ghost.fadeTime", "ghost.includeAccessories", "ghost.includeFace", "ghost.includeTools", "ghost.hideName", "ghost.restoreOnDeath" })
	page:note("Ghost fades your character on your own screen only. Roblox does not replicate LocalTransparencyModifier, so every other player still sees you and can hit you normally. While Ghost is on it takes over the own-character opacity setting above.", "textDim", 62)
	page:note("Camera features write standard Roblox properties. Some games re-apply their own camera values; the hub keeps re-applying what you enabled, and restores originals when you switch a feature off or unload.", "textDim", 56)
end

local function buildLighting(page)
	page:action({
		label = "Reset graphics",
		desc = "Resets all lighting settings and restores the original Lighting values.",
		text = "Reset",
		style = "danger",
		onClick = function()
			Actions.run("lighting.reset")
			notify("Environment", "Graphics reset.", "success")
		end,
	})
	section(page, "Time & brightness", { "lighting.timePreset", "lighting.brightnessEnabled", "lighting.brightness" })
	section(page, "Colour correction", { "lighting.colorEnabled", "lighting.filter", "lighting.saturation", "lighting.contrast", "lighting.exposure", "lighting.tint" })
	section(page, "Blur", { "lighting.blurEnabled", "lighting.blurSize" })
	section(page, "Bloom", { "lighting.bloomEnabled", "lighting.bloomIntensity", "lighting.bloomSize", "lighting.bloomThreshold" })
	page:note("All effects are local to your screen. Blur and bloom switch off automatically in the low load profile.", "textDim", 40)
end

-- registerAll(): registers every page with the window in navigation order.
function Pages.registerAll()
	local Game = import("ui/PagesGame")
	local System = import("ui/PagesSystem")
	local list = {
		{ "dashboard", "home", buildDashboard },
		{ "ui", "sliders", buildInterface },
		{ "crosshair", "target", buildCrosshair },
		{ "camera", "camera", buildCamera },
		{ "lighting", "sun", buildLighting },
		{ "training", "bolt", Game.training },
		{ "defence", "shield", Game.defence },
		{ "cosmetics", "shirt", Game.cosmetics },
		{ "music", "music", Game.music },
		{ "sounds", "speaker", Game.sounds },
		{ "perf", "gauge", System.perf },
		{ "tools", "wrench", System.tools },
		{ "keys", "keyboard", System.keys },
		{ "configs", "folder", System.configs },
		{ "diagnostics", "bug", System.diagnostics },
		{ "help", "help", System.help },
		{ "about", "info", System.about },
	}
	for _, p in ipairs(list) do
		Window.registerPage({ id = p[1], icon = p[2], title = "nav." .. p[1], build = p[3] })
	end
end

return Pages

--!nonstrict
-- ui/Flair: the decorative layer of the menu: the loading screen inside the window on first open, a light sweep across the
-- glass when the window opens, a custom cursor while the menu is open, and the mascot sticker on the top-right corner.
-- All of it is cosmetic and local; every piece has its own switch (Interface page) and is skipped with reduced effects,
-- the low load profile or animation speed 0. The sticker image is bundled (data/UiPack) and needs writefile + getcustomasset;
-- without them a text badge is shown instead. Only checked against the mock layer, not in Roblox.
-- Depends on: Settings, Services, Theme, Motion, Perf, Env, Codec, Logger, UiPack.

local import = ...
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Codec = import("core/Codec")
local Logger = import("core/Logger")
local Theme = import("ui/Theme")
local Motion = import("ui/Motion")
local UiPack = import("data/UiPack")

local Flair = {}

local images = {} -- name -> url | false

-- image(name) -> rbxasset url or nil. Writes MM2Hub/ui/<name> once, then serves it through getcustomasset.
function Flair.image(name)
	if images[name] ~= nil then
		return images[name] or nil
	end
	local e = UiPack[name]
	if not e or not Env.persistent() or not Env.has("getcustomasset") then
		images[name] = false
		return nil
	end
	local path = Env.ROOT .. "/ui/" .. name
	local existing = Env.read(path)
	if not existing or #existing ~= e.bytes then
		local raw = Codec.b64decode(e.data)
		if not raw or #raw ~= e.bytes or not Env.write(path, raw) then
			images[name] = false
			return nil
		end
	end
	local url = Env.customAsset(path)
	images[name] = url or false
	if not url then
		Logger.warn("Flair", "could not load %s", name)
	end
	return url
end

local function fancy()
	return Motion.enabled() and Theme.effectsOn()
end

local function corner(inst, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = inst
	return c
end

local function rim(inst, thickness, top, bottom)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = Color3.fromRGB(255, 255, 255)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new(top, bottom)
	g.Color = Theme.edgeColors()
	g.Parent = s
	s.Parent = inst
	return s
end

-- mascot(parent, size) -> ImageLabel (or a text badge when the executor cannot show bundled images)
function Flair.mascot(parent, size)
	local url = Flair.image("sticker.png")
	local m
	if url then
		m = Instance.new("ImageLabel")
		m.Image = url
		m.ScaleType = Enum.ScaleType.Fit
		m.BackgroundTransparency = 1
	else
		m = Instance.new("TextLabel")
		m.Text = "MM2"
		m.Font = Enum.Font.GothamBlack
		m.TextScaled = true
		m.TextColor3 = Color3.fromRGB(10, 10, 14)
		m.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		m.BackgroundTransparency = 0
		corner(m, math.floor(size * 0.3))
	end
	m.Name = "Mascot"
	m.Active = false
	m.Size = UDim2.fromOffset(size, size)
	m.Parent = parent
	return m
end

-- Window layers ---------------------------------------------------------------------------------------------------------------

-- backdrop(window, maid, isOpen): the menu's own picture layers, all behind the content:
--   chrome waves (ui.background) tinted to the theme or your menu colour, drifting very slowly while the menu is open;
--   a fine frosted-glass grain and a soft diagonal highlight (ui.grain).
-- Each layer needs the bundled image (writefile + getcustomasset); without it the layer is simply not created.
function Flair.backdrop(window, maid, isOpen)
	local bgUrl, grainUrl, sheenUrl = Flair.image("bg_chrome.jpg"), Flair.image("grain.png"), Flair.image("sheen.png")
	local layers = {}
	if bgUrl then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Backdrop"
		bg.BackgroundTransparency = 1
		bg.Image = bgUrl
		bg.ScaleType = Enum.ScaleType.Crop
		bg.AnchorPoint = Vector2.new(0.5, 0.5)
		bg.Position = UDim2.fromScale(0.5, 0.5)
		bg.Size = UDim2.fromScale(1.12, 1.12) -- a margin to drift in
		bg.ZIndex = 1
		bg.Active = false
		bg.Parent = window
		maid:Give(bg)
		Theme.bind(bg, "ImageColor3", function()
			if Settings.get("ui.tint") then
				local c = Settings.get("ui.tintColor")
				local peak = math.max(c.r, c.g, c.b, 1)
				return Color3.fromRGB(math.floor(c.r / peak * 255), math.floor(c.g / peak * 255), math.floor(c.b / peak * 255))
			end
			return Theme.mix("highlight", "accent", 0.18)
		end)
		Theme.bind(bg, "ImageTransparency", function()
			return 1 - Settings.get("ui.backgroundStrength") * 0.55
		end)
		Theme.bind(bg, "Visible", function()
			return Settings.get("ui.background") ~= "Off" and Theme.effectsOn()
		end)
		layers.bg = bg
	end
	if grainUrl then
		local g = Instance.new("ImageLabel")
		g.Name = "Grain"
		g.BackgroundTransparency = 1
		g.Image = grainUrl
		g.ScaleType = Enum.ScaleType.Tile
		g.TileSize = UDim2.fromOffset(128, 128)
		g.ImageTransparency = 0.955
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = 1
		g.Active = false
		g.Parent = window
		maid:Give(g)
		Theme.bind(g, "Visible", function()
			return Settings.get("ui.grain") and Theme.effectsOn()
		end)
		layers.grain = g
	end
	if sheenUrl then
		local sh = Instance.new("ImageLabel")
		sh.Name = "GlassHighlight"
		sh.BackgroundTransparency = 1
		sh.Image = sheenUrl
		sh.Size = UDim2.new(0.75, 0, 0, 260)
		sh.ZIndex = 1
		sh.Active = false
		sh.Parent = window
		maid:Give(sh)
		Theme.bind(sh, "ImageTransparency", function()
			return 1 - 0.1 * Theme.glassAmount()
		end)
		Theme.bind(sh, "Visible", function()
			return Settings.get("ui.grain") and Theme.effectsOn()
		end)
		layers.sheen = sh
	end
	if layers.bg then
		local t = 0
		local handle = Perf.every("ui.backdrop", 15, function(dt)
			if not isOpen() or not Motion.enabled() then
				return
			end
			t += dt
			layers.bg.Position = UDim2.new(0.5 + math.sin(t * 0.07) * 0.035, 0, 0.5 + math.cos(t * 0.05) * 0.03, 0)
		end, { visual = true })
		maid:Give(handle.Cancel)
	end
	return layers
end

-- softShadow(parent, radius) -> ImageLabel | nil: one smooth 9-slice drop shadow (shadow.png) instead of stacked frames
function Flair.softShadow(parent)
	local url = Flair.image("shadow.png")
	if not url then
		return nil
	end
	local s = Instance.new("ImageLabel")
	s.Name = "SoftShadow"
	s.BackgroundTransparency = 1
	s.Image = url
	s.ScaleType = Enum.ScaleType.Slice
	s.SliceCenter = Rect.new(60, 60, 68, 68)
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.new(0.5, 0, 0.5, 12)
	s.Size = UDim2.new(1, 70, 1, 70)
	s.ImageTransparency = 0.25
	s.ZIndex = 0
	s.Active = false
	s.Parent = parent
	return s
end

-- Loading screen --------------------------------------------------------------------------------------------------------------

-- loading(root, radius, maid, onDone): covers the window with black glass, the mascot, the name and a progress bar, then dissolves.
-- The window is already open underneath, so nothing waits on it. Skipped (onDone at once) when the effects are off.
function Flair.loading(root, radius, maid, onDone)
	if not Settings.get("ui.splash") or not fancy() then
		if onDone then
			onDone()
		end
		return nil
	end
	local cover = Instance.new("CanvasGroup")
	cover.Name = "Loading"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	cover.BackgroundTransparency = 0.04
	cover.BorderSizePixel = 0
	cover.ZIndex = 60
	cover.Active = true -- clicks do not fall through to half-drawn pages
	cover.Parent = root
	corner(cover, radius)
	rim(cover, 2.5, 0.05, 0.5)
	local sheen = Instance.new("Frame")
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sheen.Size = UDim2.fromScale(1, 0.45)
	sheen.ZIndex = 61
	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	sg.Transparency = NumberSequence.new(0.9, 1)
	sg.Parent = sheen
	sheen.Parent = cover

	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(240, 184)
	box.ZIndex = 62
	box.Parent = cover
	local boxScale = Instance.new("UIScale")
	boxScale.Scale = 0.8
	boxScale.Parent = box

	local m = Flair.mascot(box, 84)
	m.AnchorPoint = Vector2.new(0.5, 0)
	m.Position = UDim2.new(0.5, 0, 0, 0)
	m.ZIndex = 63
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = "TrollHub"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Position = UDim2.fromOffset(0, 96)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.ZIndex = 63
	title.Parent = box
	local tg = Instance.new("UIGradient")
	tg.Color = Theme.edgeColors()
	tg.Parent = title

	-- troll taglines (memes, the same in every language)
	local TAGS = { "Problem?", "U mad?", "Trololo~", "Gotcha!", "Mission: troll" }
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Text = TAGS[math.random(1, #TAGS)]
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 13
	tag.TextColor3 = Color3.fromRGB(170, 170, 182)
	tag.Position = UDim2.fromOffset(0, 124)
	tag.Size = UDim2.new(1, 0, 0, 16)
	tag.ZIndex = 63
	tag.Parent = box

	local track = Instance.new("Frame")
	track.BorderSizePixel = 0
	track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	track.BackgroundTransparency = 0.86
	track.Position = UDim2.fromOffset(30, 150)
	track.Size = UDim2.new(1, -60, 0, 6)
	track.ZIndex = 63
	track.Parent = box
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 64
	fill.Parent = track
	corner(fill, 3)
	local fg = Instance.new("UIGradient")
	fg.Color = Theme.edgeColors()
	fg.Parent = fill
	local pct = Instance.new("TextLabel")
	pct.BackgroundTransparency = 1
	pct.Text = "0%"
	pct.Font = Enum.Font.GothamBold
	pct.TextSize = 12
	pct.TextColor3 = Color3.fromRGB(190, 190, 200)
	pct.Position = UDim2.fromOffset(0, 162)
	pct.Size = UDim2.new(1, 0, 0, 16)
	pct.ZIndex = 63
	pct.Parent = box

	Motion.tween(boxScale, { Scale = 1 }, 0.55, "spring")
	Motion.tween(fill, { Size = UDim2.fromScale(1, 1) }, 1.1, "smooth")
	local started = os.clock()
	local finished = false
	local handle
	handle = Perf.every("ui.loading", 30, function()
		if finished then
			return
		end
		local p = math.clamp((os.clock() - started) / Motion.duration(1.1), 0, 1)
		pct.Text = string.format("%d%%", math.floor(p * 100 + 0.5))
		m.Rotation = math.sin((os.clock() - started) * 9) * 6 * (1 - p)
	end, { visual = true })
	local function finish()
		if finished then
			return
		end
		finished = true
		handle.Cancel()
		pct.Text = "100%"
		Motion.tween(cover, { GroupTransparency = 1 }, 0.35, "smooth")
		Motion.tween(boxScale, { Scale = 1.08 }, 0.35, "smooth")
		task.delay(Motion.duration(0.4), function()
			cover:Destroy()
		end)
		if onDone then
			onDone()
		end
	end
	maid:Give(function()
		if not finished then
			finished = true -- the hub unloaded while loading: stop the ticker (its name must be free for the next run)
			handle.Cancel()
		end
	end)
	task.delay(Motion.duration(1.25), finish)
	return { cover = cover, finish = finish }
end

-- Opening sweep ---------------------------------------------------------------------------------------------------------------

-- sweep(window): a soft diagonal band of light that crosses the glass once when the window opens.
function Flair.sweep(window)
	if not window or not fancy() or not Settings.get("ui.decor") then
		return
	end
	local band = Instance.new("Frame")
	band.Name = "OpenSweep"
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	band.Active = false
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(-0.3, 0.5)
	band.Size = UDim2.fromScale(0.28, 2.2)
	band.Rotation = 18
	band.ZIndex = 40
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = band
	band.Parent = window
	Motion.tween(band, { Position = UDim2.fromScale(1.3, 0.5) }, 0.8, "smooth")
	task.delay(Motion.duration(0.85), function()
		band:Destroy()
	end)
end

-- Sticker ---------------------------------------------------------------------------------------------------------------------

-- sticker(root, maid): the animated mascot on the window's top-right corner. A laughing Trollface: 8 sprite frames (jaw opens,
-- head rocks; assets/ui/sticker_anim.png) played at 10 fps, a gentle bob, a springy "pop" every few seconds, and a faster
-- laugh with a wiggle while the pointer is over it. It sits mostly outside the window and takes no clicks, so it never covers
-- the title-bar buttons. Without bundled-image support a static text badge is shown.
local FRAMES, CELL, COLS = 8, 128, 4

function Flair.sticker(root, maid)
	local holder = Instance.new("Frame")
	holder.Name = "Sticker"
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(1, 20, 0, -18)
	holder.Size = UDim2.fromOffset(66, 66)
	holder.ZIndex = 30
	holder.Parent = root
	maid:Give(holder)
	local url = Flair.image("sticker_anim.png")
	local m
	if url then
		m = Instance.new("ImageLabel")
		m.Name = "Mascot"
		m.Image = url
		m.BackgroundTransparency = 1
		m.Active = false
		m.ImageRectSize = Vector2.new(CELL, CELL)
		m.ImageRectOffset = Vector2.new(0, 0)
		m.Size = UDim2.fromScale(1, 1)
		m.Parent = holder
	else
		m = Flair.mascot(holder, 66)
	end
	m.ZIndex = 30
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local hover = false
	maid:Give(m.MouseEnter:Connect(function()
		hover = true
		Motion.tween(scale, { Scale = 1.18 }, 0.25, "spring")
	end))
	maid:Give(m.MouseLeave:Connect(function()
		hover = false
		Motion.tween(scale, { Scale = 1 }, 0.25, "smooth")
	end))
	local t, frameClock, frame, nextPop = 0, 0, 0, 3
	local handle = Perf.every("ui.sticker", 30, function(dt)
		local on = Settings.get("ui.sticker")
		holder.Visible = on
		if not on then
			return
		end
		if not Motion.enabled() then
			m.Rotation = 10
			return
		end
		t += dt
		-- sprite frames: 10 fps, 22 fps while hovered (laughs harder)
		if url then
			frameClock += dt * (hover and 22 or 10)
			local f = math.floor(frameClock) % FRAMES
			if f ~= frame then
				frame = f
				m.ImageRectOffset = Vector2.new((f % COLS) * CELL, (f // COLS) * CELL)
			end
		end
		m.Rotation = 10 + math.sin(t * 1.7) * 4 + (hover and math.sin(t * 24) * 6 or 0)
		m.Position = UDim2.fromOffset(0, math.sin(t * 2.3) * 2.5)
		if t >= nextPop and not hover then
			nextPop = t + 4 + (t * 7.3) % 3 -- every 4-7 s
			scale.Scale = 1.14
			Motion.tween(scale, { Scale = 1 }, 0.5, "spring")
		end
	end, { visual = true })
	maid:Give(handle.Cancel)
	return holder
end

-- Cursor ----------------------------------------------------------------------------------------------------------------------

-- cursor(gui, maid, isOpen): while the menu is open (and the game is not locking the mouse) the system arrow is replaced by a
-- glossy ring with a dot; the ring trails slightly behind. The previous MouseIconEnabled value is restored when the menu
-- closes or the hub unloads. Not shown on touch-only devices.
function Flair.cursor(gui, maid, isOpen)
	local uis = Services.UserInputService
	if not uis or (uis.TouchEnabled and not uis.KeyboardEnabled) then
		return nil
	end
	local layer = Instance.new("Frame")
	layer.Name = "Cursor"
	layer.BackgroundTransparency = 1
	layer.Active = false
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 200
	layer.Visible = false
	layer.Parent = gui
	maid:Give(layer)
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(26, 26)
	ring.ZIndex = 200
	ring.Parent = layer
	corner(ring, 13)
	rim(ring, 2, 0.05, 0.35)
	local dot = Instance.new("Frame")
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(7, 7)
	dot.ZIndex = 201
	dot.Parent = layer
	corner(dot, 4)
	local ds = Instance.new("UIStroke")
	ds.Color = Color3.fromRGB(0, 0, 0)
	ds.Transparency = 0.4
	ds.Parent = dot

	local hidden = false -- true while we have the system icon switched off
	local before = true
	local function restore()
		if hidden then
			pcall(function()
				uis.MouseIconEnabled = before
			end)
			hidden = false
		end
		layer.Visible = false
	end
	maid:Give(restore)
	local rx, ry = nil, nil
	local handle = Perf.every("ui.cursor", 60, function(dt)
		local locked = uis.MouseBehavior ~= Enum.MouseBehavior.Default and uis.MouseBehavior ~= "Default"
		local want = Settings.get("ui.cursor") and isOpen() and not locked
		if not want then
			restore()
			return
		end
		if not hidden then
			before = uis.MouseIconEnabled
			pcall(function()
				uis.MouseIconEnabled = false
			end)
			hidden = true
		end
		layer.Visible = true
		local pos = uis:GetMouseLocation()
		local inset = Vector2.new(0, 0)
		local gs = Services.GuiService
		if gs and not gui.IgnoreGuiInset then
			local ok, a = pcall(function()
				return gs:GetGuiInset()
			end)
			if ok and a then
				inset = a
			end
		end
		local x, y = pos.X - inset.X, pos.Y - inset.Y
		dot.Position = UDim2.fromOffset(x, y)
		local k = Motion.enabled() and math.clamp(dt * 18, 0, 1) or 1
		rx = rx and rx + (x - rx) * k or x
		ry = ry and ry + (y - ry) * k or y
		ring.Position = UDim2.fromOffset(rx, ry)
	end, { visual = true })
	maid:Give(handle.Cancel)
	return layer
end

return Flair

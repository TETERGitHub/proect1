--!nonstrict
-- ui/Framework: component library for the hub (all drawn from Frames/TextLabels, no image
-- assets). Provides iOS-style switches, sliders, segmented controls, popovers, an HSV colour
-- picker, key capture boxes, sheets, tooltips and a custom scroll indicator.
-- Roblox objects are only created inside functions; nothing happens at load time.
-- Depends on: Theme, Motion, Icons, Settings, Input, Recents, Registry, Maid, Pool, Services, ColorUtil.

local import = ...
local Theme = import("ui/Theme")
local Motion = import("ui/Motion")
local Icons = import("ui/Icons")
local Settings = import("core/Settings")
local Input = import("core/Input")
local Recents = import("core/Recents")
local Registry = import("core/Registry")
local Maid = import("core/Maid")
local Services = import("core/Services")
local ColorUtil = import("core/ColorUtil")
local I18n = import("core/I18n")
local Notify = import("core/Notify")

local F = {}

local ctx = nil -- { gui, overlay, maid }
local clickHandler = nil
local drag = nil
local tooltip = { label = nil, token = 0 }

-- Lifecycle ---------------------------------------------------------------------------

function F.setClickHandler(fn)
	clickHandler = fn
end

local function click()
	if clickHandler then
		pcall(clickHandler)
	end
end
F.click = click

-- init{gui = ScreenGui, maid = Maid}: creates the overlay layer and the shared drag manager.
function F.init(context)
	ctx = context
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 100
	overlay.Active = false
	overlay.Parent = context.gui
	ctx.overlay = overlay
	context.maid:Give(overlay)

	local uis = Services.UserInputService
	context.maid:Give(uis.InputChanged:Connect(function(input)
		if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			drag.move(input.Position)
		end
	end))
	context.maid:Give(uis.InputEnded:Connect(function(input)
		if drag and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local d = drag
			drag = nil
			if d.done then
				d.done()
			end
		end
	end))

	local tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.Visible = false
	tip.ZIndex = 300
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Size = UDim2.fromOffset(0, 0)
	tip.BorderSizePixel = 0
	tip.TextWrapped = true
	tip.RichText = false
	Theme.bind(tip, "BackgroundColor3", "bg3")
	Theme.bind(tip, "TextColor3", "text")
	Theme.bind(tip, "Font", function()
		return Theme.font(false)
	end)
	Theme.bind(tip, "TextSize", function()
		return Theme.textSize(12)
	end)
	F.padding(tip, 8, 6, 8, 6)
	F.corner(tip, -2)
	F.stroke(tip, "stroke", 1, 0.4)
	tip.Parent = ctx.overlay
	tooltip.label = tip
end

function F.context()
	return ctx
end

function F.beginDrag(onMove, onDone)
	drag = { move = onMove, done = onDone }
end

function F.isDragging()
	return drag ~= nil
end

function F.cancelDrag()
	drag = nil
end

-- Small builders -----------------------------------------------------------------------------

-- corner(inst, radius): radius is a scale name ("window", "card", "control", "small", "none") from Theme.rad, or a
-- number of pixels relative to the corner-radius setting (older call sites)
function F.corner(inst, extra)
	local c = Instance.new("UICorner")
	if type(extra) == "string" then
		Theme.bind(c, "CornerRadius", function()
			return UDim.new(0, Theme.rad(extra))
		end)
	else
		Theme.bind(c, "CornerRadius", function()
			return UDim.new(0, Theme.radius(extra))
		end)
	end
	c.Parent = inst
	return c
end

function F.pillCorner(inst)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = inst
	return c
end

function F.stroke(inst, token, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Theme.bind(s, "Color", token or "stroke")
	s.Parent = inst
	return s
end

-- edge(inst): the thin light edge of a glass surface - a stroke whose transparency runs from a brighter top
-- to a fainter bottom. With effects off it is a plain faint outline.
function F.edge(inst, level)
local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Theme.bind(s, "Color", function()
		return Theme.effectsOn() and Theme.color("edge") or Theme.color("stroke")
	end)
	s.Parent = inst
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	Theme.bind(g, "Transparency", function()
		local top, bottom = Theme.edge(level)
		return NumberSequence.new(top, bottom)
	end)
	g.Parent = s
	return s
end

-- sheen(inst, height): a faint white wash over the top part of a large surface (hidden when effects are off)
function F.sheen(inst, height)
	local f = Instance.new("Frame")
	f.Name = "Sheen"
	f.BorderSizePixel = 0
	f.Active = false
	f.Size = UDim2.new(1, 0, 0, height or 120)
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.BackgroundTransparency = 0
	f.ZIndex = 1
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	Theme.bind(g, "Transparency", function()
		return NumberSequence.new(Theme.sheen(), 1)
	end)
	g.Parent = f
	Theme.bind(f, "Visible", function()
		return Theme.effectsOn()
	end)
	f.Parent = inst
	return f
end

local LEVEL_RADIUS = { window = "window", rail = "none", card = "card", control = "control", popover = "card", modal = "window", toast = "card" }

-- surface(parent, level, opts{name, props, radius, edge, sheen}) -> Frame
-- level: window | rail | card | control | popover | modal | toast (see Theme.surface for the translucency ladder)
function F.surface(parent, level, opts)
	opts = opts or {}
	local f = Instance.new("Frame")
	f.Name = opts.name or "Surface"
	f.BorderSizePixel = 0
	for k, v in pairs(opts.props or {}) do
		f[k] = v
	end
	Theme.bind(f, "BackgroundColor3", function()
		return Theme.color((Theme.surface(level)))
	end)
	Theme.bind(f, "BackgroundTransparency", function()
		return select(2, Theme.surface(level))
	end)
	if opts.radius ~= false then
		F.corner(f, opts.radius or LEVEL_RADIUS[level] or "card")
	end
	if opts.edge ~= false then
		F.edge(f, level)
	end
	if opts.sheen then
		F.sheen(f, opts.sheen)
	end
	f.Parent = parent
	return f
end

function F.padding(inst, l, t, r, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = inst
	return p
end

function F.list(inst, padding, horizontal)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	if type(padding) == "function" then
		Theme.bind(l, "Padding", function()
			return UDim.new(0, padding())
		end)
	else
		l.Padding = UDim.new(0, padding or 0)
	end
	l.Parent = inst
	return l
end

-- frame(parent, props, bindings): bindings maps property -> colour token or function
function F.frame(parent, props, bindings)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	for prop, src in pairs(bindings or {}) do
		Theme.bind(f, prop, src)
	end
	f.Parent = parent
	return f
end

-- fitText(inst, base): a single-line text shrinks (down to 70 %, at least 9 px) instead of being cut when a translation is longer
-- than its box. Roblox does this with TextScaled + UITextSizeConstraint; the normal size stays the maximum.
local function fitText(inst, base)
	inst.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	Theme.bind(c, "MaxTextSize", function()
		return math.floor(Theme.textSize(base) + 0.5)
	end)
	Theme.bind(c, "MinTextSize", function()
		return math.max(9, math.floor(Theme.textSize(base) * 0.7))
	end)
	c.Parent = inst
end
F.fitText = fitText

-- label(parent, text, opts{size,bold,token,align,wrap,size2d})
function F.label(parent, text, opts)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = I18n.tr(text or "")
	l.TextXAlignment = opts.align or Enum.TextXAlignment.Left
	l.TextYAlignment = opts.valign or Enum.TextYAlignment.Center
	l.TextWrapped = opts.wrap or false
	l.TextTruncate = opts.wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	l.Size = opts.dim or UDim2.new(1, 0, 0, Theme.textSize(opts.size or 13) + 4)
	local base = opts.size or 13
	Theme.bind(l, "TextSize", function()
		return Theme.textSize(base)
	end)
	Theme.bind(l, "Font", function()
		return Theme.font(opts.bold)
	end)
	Theme.bind(l, "TextColor3", opts.token or "text")
	if not opts.wrap then
		fitText(l, base)
	end
	l.Parent = parent
	return l
end

-- Tooltips -----------------------------------------------------------------------------------

function F.tooltip(inst, textOrFn, maid)
	if not ctx or not inst.MouseEnter then
		return
	end
	local function show()
		if not Settings.get("ui.showTooltips") or not tooltip.label then
			return
		end
		local text = type(textOrFn) == "function" and textOrFn() or textOrFn
		if not text or text == "" then
			return
		end
		text = I18n.tr(text)
		tooltip.token += 1
		local mine = tooltip.token
		task.delay(0.45, function()
			if tooltip.token ~= mine or not tooltip.label then
				return
			end
			local loc = Services.UserInputService:GetMouseLocation()
			local inset = Services.GuiService:GetGuiInset()
			local o = ctx.overlay.AbsolutePosition
			local size = ctx.overlay.AbsoluteSize
			tooltip.label.Text = text
			tooltip.label.Size = UDim2.fromOffset(0, 0)
			tooltip.label.Position = UDim2.fromOffset(
				math.clamp(loc.X - o.X + 14, 4, math.max(4, size.X - 220)),
				math.clamp(loc.Y - inset.Y - o.Y + 18, 4, math.max(4, size.Y - 60))
			)
			tooltip.label.Visible = true
		end)
	end
	local function hide()
		tooltip.token += 1
		if tooltip.label then
			tooltip.label.Visible = false
		end
	end
	local a = inst.MouseEnter:Connect(show)
	local b = inst.MouseLeave:Connect(hide)
	if maid then
		maid:Give(a)
		maid:Give(b)
	end
end

-- Scroll container with a custom iOS-style indicator ---------------------------------------------

-- scroller(parent) -> ScrollingFrame, maid. The default scroll bar is disabled; a thin rounded
-- indicator fades in while scrolling and out after 0.8 s.
function F.scroller(parent)
	local maid = Maid.new("scroller")
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "Scroller"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = UDim2.fromScale(1, 1)
	sf.ScrollBarThickness = 0
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.ElasticBehavior = Enum.ElasticBehavior.Always
	sf.Parent = parent

	local thumb = Instance.new("Frame")
	thumb.Name = "Indicator"
	thumb.AnchorPoint = Vector2.new(1, 0)
	thumb.Size = UDim2.fromOffset(4, 30)
	thumb.Position = UDim2.new(1, -2, 0, 0)
	thumb.BackgroundTransparency = 1
	thumb.BorderSizePixel = 0
	thumb.ZIndex = 5
	Theme.bind(thumb, "BackgroundColor3", "textDim")
	F.pillCorner(thumb)
	thumb.Parent = parent
	maid:Give(thumb)

	local fadeToken = 0
	local function sync()
		local view = sf.AbsoluteWindowSize.Y
		local canvas = sf.AbsoluteCanvasSize.Y
		if canvas <= view + 1 or view <= 0 then
			thumb.Visible = false
			return
		end
		thumb.Visible = true
		local h = math.max(28, view * view / canvas)
		local maxScroll = canvas - view
		local frac = math.clamp(sf.CanvasPosition.Y / maxScroll, 0, 1)
		thumb.Size = UDim2.fromOffset(4, h)
		thumb.Position = UDim2.new(1, -2, 0, frac * (view - h))
		thumb.BackgroundTransparency = 0.35
		fadeToken += 1
		local mine = fadeToken
		task.delay(0.8, function()
			if mine == fadeToken and thumb.Parent then
				Motion.tween(thumb, { BackgroundTransparency = 1 }, 0.35, "smooth")
			end
		end)
	end
	maid:Give(sf:GetPropertyChangedSignal("CanvasPosition"):Connect(sync))
	maid:Give(sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if thumb.Parent then
			thumb.BackgroundTransparency = 1
			local view = sf.AbsoluteWindowSize.Y
			thumb.Visible = sf.AbsoluteCanvasSize.Y > view + 1
		end
	end))
	return sf, maid
end

-- Buttons ---------------------------------------------------------------------------------------------------------

-- Styles: primary (filled accent), secondary (control surface), tertiary (text only), destructive (red text).
-- The old names filled / tinted / plain / danger still work.
local STYLE_ALIAS = {
	primary = "filled", filled = "filled",
	secondary = "tinted", tinted = "tinted",
	tertiary = "plain", plain = "plain",
	destructive = "danger", danger = "danger",
}

local buttonStates = setmetatable({}, { __mode = "k" })

-- Target look of a button for its current state: background colour, background transparency, text colour, text transparency.
local function buttonLook(st)
	local style = st.style
	local _, controlT = Theme.surface("control")
	local bg, bgT, tc
	if style == "filled" then
		bg, bgT, tc = Theme.color("accent"), 0, Theme.accentText()
		if st.down then
			bg = Theme.mix("accent", "bg0", 0.22)
		elseif st.hover then
			bg = Theme.mix("accent", "highlight", 0.14)
		end
	elseif style == "plain" then
		bg, bgT, tc = Theme.color("accent"), 1, Theme.color("accent")
		if st.down then
			bgT = 0.82
		elseif st.hover then
			bgT = 0.9
		end
	elseif style == "danger" then
		bg, bgT, tc = Theme.color("bg3"), controlT, Theme.color("bad")
		if st.down then
			bg, bgT = Theme.mix("bg3", "bad", 0.34), 0.1
		elseif st.hover then
			bg, bgT = Theme.mix("bg3", "bad", 0.2), 0
		end
	else
		bg, bgT, tc = Theme.color("bg3"), controlT, Theme.color("text")
		if st.down then
			bg, bgT = Theme.mix("bg3", "bg0", 0.2), 0
		elseif st.hover then
			bg, bgT = Theme.mix("bg3", "highlight", 0.1), math.min(controlT, 0.15)
		end
	end
	local textT = 0
	if not st.enabled then
		bgT = bgT + (1 - bgT) * 0.55
		textT = 0.55
	elseif st.loading then
		textT = 0.35
	end
	return bg, bgT, tc, textT
end

-- button(parent, text, onClick, style, dim, maid) -> TextButton
-- States: normal, hover, pressed, disabled (F.setButtonEnabled) and loading (F.setButtonLoading). A disabled or loading
-- button ignores presses, so an operation that is still running cannot be started a second time.
function F.button(parent, text, onClick, style, dim, maid)
	maid = maid or (ctx and ctx.maid) or Maid.new("button")
	local st = { style = STYLE_ALIAS[style or "tinted"] or "tinted", enabled = true, loading = false, hover = false, down = false, label = I18n.tr(text) }
	local b = Instance.new("TextButton")
	buttonStates[b] = st
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = st.label
	b.Size = dim or UDim2.fromOffset(110, 32)
	b.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.bind(b, "TextSize", function()
		return Theme.textSize(13)
	end)
	fitText(b, 13)
	Theme.bind(b, "Font", function()
		return Theme.font(true)
	end)
	Theme.bind(b, "BackgroundColor3", function()
		return (buttonLook(st))
	end)
	Theme.bind(b, "BackgroundTransparency", function()
		return select(2, buttonLook(st))
	end)
	Theme.bind(b, "TextColor3", function()
		return select(3, buttonLook(st))
	end)
	Theme.bind(b, "TextTransparency", function()
		return select(4, buttonLook(st))
	end)
	F.corner(b, "control")
	if st.style ~= "plain" then
		F.edge(b, "control")
	end
	b.Parent = parent
	local scale = Motion.pressable(b, maid, 0.03)
	st.scale = scale

	local function paint(animate)
		local bg, bgT, tc, tT = buttonLook(st)
		local goal = { BackgroundColor3 = bg, BackgroundTransparency = bgT, TextColor3 = tc, TextTransparency = tT }
		if animate then
			Motion.tween(b, goal, Motion.D.fast, "smooth")
		else
			for k, v in pairs(goal) do
				b[k] = v
			end
		end
	end
	st.paint = paint
	maid:Give(b.MouseEnter:Connect(function()
		st.hover = true
		paint(true)
	end))
	maid:Give(b.MouseLeave:Connect(function()
		st.hover, st.down = false, false
		paint(true)
	end))
	maid:Give(b.MouseButton1Down:Connect(function()
		st.down = true
		paint(true)
	end))
	maid:Give(b.MouseButton1Up:Connect(function()
		st.down = false
		paint(true)
	end))
	maid:Give(b.Activated:Connect(function()
		if not st.enabled or st.loading then
			return
		end
		click()
		if onClick then
			local ok, err = pcall(onClick)
			if not ok then
				import("core/Logger").error("UI", "button '%s' failed: %s", tostring(text), tostring(err))
			end
		end
	end))
	return b
end

function F.setButtonEnabled(btn, enabled)
	local st = buttonStates[btn]
	if st and st.enabled ~= (enabled and true or false) then
		st.enabled = enabled and true or false
		btn.Active = st.enabled
		st.paint(true)
	end
end

-- setButtonLoading(btn, loading, label?): while loading the button shows `label` (default "...") and ignores presses
function F.setButtonLoading(btn, loading, label)
	local st = buttonStates[btn]
	if not st then
		return
	end
	st.loading = loading and true or false
	btn.Text = st.loading and I18n.tr(label or "…") or st.label
	st.paint(true)
end

-- setButtonStyle(btn, style): switch between primary / secondary / tertiary / destructive at run time (for toggle chips)
function F.setButtonStyle(btn, style)
local st = buttonStates[btn]
local resolved = STYLE_ALIAS[style or "tinted"] or "tinted"
if st and st.style ~= resolved then
	st.style = resolved
	st.paint(true)
end
end

function F.buttonState(btn)
	local st = buttonStates[btn]
	if not st then
		return nil
	end
	return { enabled = st.enabled, loading = st.loading, style = st.style }
end

-- flashButton(btn, "success"|"error"): a brief confirmation tint; call it only when the outcome is known
function F.flashButton(btn, kind)
	local token = kind == "error" and "bad" or "good"
	Motion.tween(btn, { BackgroundColor3 = Theme.color(token) }, Motion.D.fast, "smooth")
	task.delay(Motion.duration(0.7), function()
		local st = buttonStates[btn]
		if st and btn.Parent then
			st.paint(true)
		end
	end)
end

-- iconButton(parent, iconName, onClick, px, maid, token, danger): borderless round icon button with hover and press states
function F.iconButton(parent, iconName, onClick, px, maid, token, danger, fill)
maid = maid or ctx.maid
	px = px or 28
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(px, px)
	Theme.bind(b, "BackgroundColor3", fill or (danger and "bad" or "highlight"))
	b.BackgroundTransparency = fill and 0 or 1
	F.pillCorner(b)
	local icon = Icons.draw(b, iconName, math.floor(px * 0.6), token or "textDim")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	b.Parent = parent
	Motion.pressable(b, maid, 0.08)
	local rest = fill and 0.12 or (danger and 0.82 or 0.9)
	local idle = fill and 0 or 1
	maid:Give(b.MouseEnter:Connect(function()
		Motion.tween(b, { BackgroundTransparency = rest }, Motion.D.fast, "smooth")
	end))
	maid:Give(b.MouseLeave:Connect(function()
		Motion.tween(b, { BackgroundTransparency = idle }, Motion.D.std, "smooth")
	end))
	maid:Give(b.MouseButton1Down:Connect(function()
		Motion.tween(b, { BackgroundTransparency = fill and 0.25 or rest - 0.1 }, Motion.D.fast, "smooth")
	end))
	maid:Give(b.Activated:Connect(function()
		click()
		if onClick then
			pcall(onClick)
		end
	end))
	return b, icon
end

-- textBox(parent, opts{placeholder,text,dim,onSubmit,clear,multiline}) -> TextBox
-- States: normal, focused (accent ring) and invalid (F.setInvalid, red ring).
local invalidBoxes = setmetatable({}, { __mode = "k" })

local function boxStroke(t, focused)
	local s = invalidBoxes[t]
	if s and s.invalid then
		return "bad", 0
	elseif focused then
		return "accent", 0
	end
	return "stroke", 0.55
end

function F.setInvalid(box, invalid)
	local s = invalidBoxes[box]
	if s then
		s.invalid = invalid and true or false
		s.refresh(true)
	end
end

function F.textBox(parent, opts, maid)
	maid = maid or ctx.maid
	local t = Instance.new("TextBox")
	t.BorderSizePixel = 0
	t.ClearTextOnFocus = opts.clear == true
	t.PlaceholderText = I18n.tr(opts.placeholder or "")
	t.Text = opts.text or ""
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = opts.multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	t.MultiLine = opts.multiline == true
	t.TextWrapped = opts.multiline == true
	t.Size = opts.dim or UDim2.fromOffset(160, 32)
	Theme.bind(t, "BackgroundColor3", "bg3")
	Theme.bind(t, "BackgroundTransparency", function()
		return select(2, Theme.surface("control"))
	end)
	Theme.bind(t, "TextColor3", "text")
	Theme.bind(t, "PlaceholderColor3", "textDim")
	Theme.bind(t, "Font", function()
		return Theme.font(false)
	end)
	Theme.bind(t, "TextSize", function()
		return Theme.textSize(13)
	end)
	F.corner(t, "control")
	F.padding(t, 12, 4, 12, 4)
	local stroke = F.stroke(t, "stroke", 1, 0.55)
	local st = { invalid = false, focused = false }
	invalidBoxes[t] = st
	st.refresh = function(animate)
		local token, tr = boxStroke(t, st.focused)
		Theme.bind(stroke, "Color", token)
		stroke.Thickness = (token == "stroke") and 1 or 1.5
		if animate then
			Motion.tween(stroke, { Transparency = tr }, Motion.D.fast, "smooth")
		else
			stroke.Transparency = tr
		end
	end
	maid:Give(t.Focused:Connect(function()
		st.focused = true
		st.refresh(true)
	end))
	maid:Give(t.FocusLost:Connect(function(enter)
		st.focused = false
		st.refresh(true)
		if opts.onSubmit then
			pcall(opts.onSubmit, t.Text, enter)
		end
	end))
	t.Parent = parent
	return t
end

-- Popovers --------------------------------------------------------------------------------------------

local popover = nil

function F.closePopover()
	if popover then
		local p = popover
		popover = nil
		if p.catcher then
			p.catcher:Destroy()
		end
		local frame = p.frame
		if frame and frame.Parent then
			Motion.tween(frame, { Size = UDim2.fromOffset(p.width, 0) }, Motion.D.std * 0.8, "exit")
			task.delay(Motion.enabled() and Motion.duration(0.2) or 0, function()
				if frame.Parent then
					frame:Destroy()
				end
			end)
		end
		if p.maid then
			p.maid:Clean()
		end
		if p.onClose then
			pcall(p.onClose)
		end
	end
end

function F.hasPopover()
	return popover ~= nil
end

-- openPopover(anchor, width, height, onClose) -> content Frame, maid. Closes any open popover first.
function F.openPopover(anchor, width, height, onClose)
	F.closePopover()
	local overlay = ctx.overlay
	local catcher = Instance.new("TextButton")
	catcher.Name = "PopoverCatcher"
	catcher.Text = ""
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = 110
	catcher.AutoButtonColor = false
	catcher.Parent = overlay
	local frame = Instance.new("Frame")
	frame.Name = "Popover"
	frame.ZIndex = 120
	frame.ClipsDescendants = true
	frame.BorderSizePixel = 0
	Theme.bind(frame, "BackgroundColor3", function()
		return Theme.color((Theme.surface("popover")))
	end)
	Theme.bind(frame, "BackgroundTransparency", function()
		return select(2, Theme.surface("popover"))
	end)
	F.corner(frame, "card")
	F.edge(frame, "popover")
	local ap, as, op, os = anchor.AbsolutePosition, anchor.AbsoluteSize, overlay.AbsolutePosition, overlay.AbsoluteSize
	local x = math.clamp(ap.X - op.X + as.X - width, 6, math.max(6, os.X - width - 6))
	local y = ap.Y - op.Y + as.Y + 6
	if y + height > os.Y - 6 then
		y = math.max(6, ap.Y - op.Y - height - 6)
	end
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, 0)
	frame.Parent = overlay
	local maid = Maid.new("popover")
	popover = { frame = frame, catcher = catcher, maid = maid, width = width, onClose = onClose }
	catcher.Activated:Connect(F.closePopover)
	Motion.tween(frame, { Size = UDim2.fromOffset(width, height) }, Motion.D.slow * 0.75, "enter")
	return frame, maid
end

-- Sheet / confirm ---------------------------------------------------------------------------------------

-- confirm{title, text, confirmText, danger, onConfirm}
function F.confirm(opts)
	F.closePopover()
	local overlay = ctx.overlay
	local maid = Maid.new("sheet")
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "SheetBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 150
	backdrop.Parent = overlay
	maid:Give(backdrop)
	Motion.tween(backdrop, { BackgroundTransparency = 0.5 }, Motion.D.std, "smooth")

	local sheet = F.surface(backdrop, "modal", { name = "Sheet", sheen = 90 })
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.fromScale(0.5, 0.5)
	sheet.Size = UDim2.fromOffset(340, 168)
	sheet.ZIndex = 160
	F.padding(sheet, 20, 18, 20, 16)
	local scale = Instance.new("UIScale")
	scale.Scale = Motion.enabled() and 0.94 or 1
	scale.Parent = sheet
	Motion.tween(scale, { Scale = 1 }, Motion.D.slow * 0.8, "enter")

	local t = F.label(sheet, opts.title or "", { size = 17, bold = true })
	local msg = F.label(sheet, opts.text or "", { size = 13, token = "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 56), valign = Enum.TextYAlignment.Top })
	msg.Position = UDim2.fromOffset(0, 30)
	local function close()
		maid:Clean()
	end
	local row = F.frame(sheet, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34) })
	F.list(row, 10, true)
	local cancel = F.button(row, I18n.t("btn.cancel"), close, "secondary", UDim2.new(0.5, -5, 1, 0), maid)
	cancel.LayoutOrder = 1
	local ok = F.button(row, opts.confirmText or I18n.t("btn.confirm"), function()
		close()
		if opts.onConfirm then
			opts.onConfirm()
		end
	end, opts.danger and "destructive" or "primary", UDim2.new(0.5, -5, 1, 0), maid)
	ok.LayoutOrder = 2
	maid:Give(backdrop.Activated:Connect(function() end)) -- swallow clicks outside the sheet
	return close
end

-- Pages and rows ------------------------------------------------------------------------------------------

local Page = {}
Page.__index = Page
F.Page = Page

-- newPage(parent) -> page. Content is built lazily by the caller and cached by the window.
function F.newPage(parent, id)
	local maid = Maid.new("page:" .. tostring(id))
	local group = Instance.new("CanvasGroup")
	group.Name = "Page_" .. tostring(id)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 0
	group.Parent = parent
	maid:Give(group)
	local sf, smaid = F.scroller(group)
	maid:Give(smaid)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, 0, 0, 0)
	content.Parent = sf
	F.list(content, function()
		return Theme.pad() - 1
	end)
	F.padding(content, 4, 6, 10, 20)
	return setmetatable({ id = id, group = group, scroll = sf, content = content, maid = maid, anchors = {}, order = 0 }, Page)
end

function Page:nextOrder()
	self.order += 1
	return self.order
end

function Page:destroy()
	self.maid:Clean()
end

local function bindSetting(page, key, fn)
	page.maid:Give(Settings.observe(key, fn, true))
end

-- row(opts{label, desc, key, width, tip}) -> row Frame, holder Frame (right side)
-- Rows live inside a grouped card (one card per section) separated by hairlines, so a page reads as a few
-- surfaces instead of a stack of identical boxes. A group is opened by Page:section() or automatically
-- when a row follows something that is not a row.
function Page:openGroup()
	local g = Instance.new("Frame")
	g.Name = "Group"
	g.BorderSizePixel = 0
	g.LayoutOrder = self:nextOrder()
	g.Size = UDim2.new(1, 0, 0, 0)
	g.AutomaticSize = Enum.AutomaticSize.Y
	Theme.bind(g, "BackgroundColor3", function()
		return Theme.color((Theme.surface("card")))
	end)
	Theme.bind(g, "BackgroundTransparency", function()
		return select(2, Theme.surface("card"))
	end)
	F.corner(g, "card")
	F.edge(g, "card")
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = g
	g.Parent = self.content
	self.card, self.cardOrder, self.cardCount = g, self.order, 0
	return g
end

local function rowParent(self)
	if not self.card or self.order ~= self.cardOrder then
		self:openGroup()
	end
	self.cardCount += 1
	return self.card, self.cardCount
end

function Page:row(opts)
	local feat = opts.key and Registry.forSetting(opts.key) or nil
	local hasDesc = opts.desc and opts.desc ~= ""
	local parent, index = rowParent(self)
	local row = Instance.new("Frame")
	row.Name = opts.key or opts.label or "Row"
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.BackgroundTransparency = 1
	Theme.bind(row, "BackgroundColor3", "highlight")
	row.AutomaticSize = Enum.AutomaticSize.Y
	Theme.bind(row, "Size", function()
		return UDim2.new(1, 0, 0, Theme.rowHeight())
	end)
	row.Parent = parent
	if index > 1 then
		local div = F.frame(row, { Name = "Divider", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 1), ZIndex = 2 }, { BackgroundColor3 = "stroke" })
		div.BackgroundTransparency = 0.72
	end
	if opts.key then
		self.anchors[opts.key] = row
	end

	local starW = feat and 26 or 0
	local textBox = F.frame(row, { Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y })
	textBox.Size = UDim2.new(1, -(opts.width or 0) - 34 - starW, 0, 0)
	F.padding(textBox, 0, 9, 0, 9)
	local tl = F.list(textBox, 2)
	local title = F.label(textBox, opts.label or "", { size = 14, bold = true })
	title.LayoutOrder = 1
	if hasDesc then
		local d = F.label(textBox, opts.desc, { size = 11.5, token = "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.LayoutOrder = 2
		Theme.bind(d, "Visible", function()
			return not Settings.get("ui.compact")
		end)
		F.tooltip(row, opts.tip or opts.desc, self.maid)
	end

	local holder = F.frame(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12 - starW, 0.5, 0), Size = UDim2.fromOffset(opts.width or 0, 32) })

	-- hover wash (very faint) so the row under the pointer is easy to find
	self.maid:Give(row.MouseEnter:Connect(function()
		Motion.tween(row, { BackgroundTransparency = 0.965 }, Motion.D.fast, "smooth")
	end))
	self.maid:Give(row.MouseLeave:Connect(function()
		Motion.tween(row, { BackgroundTransparency = 1 }, Motion.D.std, "smooth")
	end))

	if feat then
		local star = F.iconButton(row, "star", nil, 24, self.maid, "textDim")
		star.AnchorPoint = Vector2.new(1, 0.5)
		star.Position = UDim2.new(1, -8, 0.5, 0)
		star.ZIndex = 3
		local icon = star:FindFirstChildOfClass("Frame")
		local hovered = false
		local touch = Services.UserInputService.TouchEnabled
		local function paint()
			local fav = Recents.isFavorite(feat.id)
			if icon then
				Icons.recolor(icon, fav and "warn" or "textDim")
			end
			-- a star that is not a favourite only shows while the row is hovered (always on touch screens)
			star.Visible = fav or hovered or touch
		end
		self.maid:Give(row.MouseEnter:Connect(function()
			hovered = true
			paint()
		end))
		self.maid:Give(row.MouseLeave:Connect(function()
			hovered = false
			paint()
		end))
		self.maid:Give(star.Activated:Connect(function()
			local ok = Recents.toggleFavorite(feat.id)
			if not ok then
				-- the only failure users can hit is the limit; a silent star is indistinguishable from a broken one
				Notify.push({ title = I18n.tr("Favourites"), text = I18n.tr("Favourite limit reached. Press the star of another feature to remove it first."), level = "warn" })
			end
			paint()
		end))
		self.maid:Give(Settings.observe("state.favorites", paint, true))
	end
	return row, holder, feat
end

local function touch(feat)
	if feat then
		Recents.touch(feat.id)
	end
end

-- section(title): small caption above a new grouped card; the rows that follow go into that card
function Page:section(title)
	local h = Instance.new("Frame")
	h.Name = "SectionHeader"
	h.BackgroundTransparency = 1
	h.BorderSizePixel = 0
	h.LayoutOrder = self:nextOrder()
	h.Size = UDim2.new(1, 0, 0, 28)
	local size, bold, token = Theme.type("section")
	local l = F.label(h, I18n.upper(I18n.tr(title)), { size = size, bold = bold, token = token })
	l.Position = UDim2.fromOffset(Theme.space.s, 10)
	l.Size = UDim2.new(1, -Theme.space.s, 0, 16)
	h.Parent = self.content
	self.card = nil
	return h
end

-- note(text, token): free text block
function Page:note(text, token, height)
	local frame = F.frame(self.content, { Name = "Note", LayoutOrder = self:nextOrder(), Size = UDim2.new(1, 0, 0, height or 40), AutomaticSize = Enum.AutomaticSize.Y })
	F.padding(frame, Theme.space.s, 2, Theme.space.s, 6)
	local l = F.label(frame, text, { size = 11.5, token = token or "textDim", wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
	l.AutomaticSize = Enum.AutomaticSize.Y
	return frame, l
end

-- custom(height) -> Frame (card surface) for arbitrary content
function Page:card(height)
	local card = F.surface(self.content, "card", { name = "Card", props = { LayoutOrder = self:nextOrder(), Size = UDim2.new(1, 0, 0, height) } })
	return card
end

-- header(title, subtitle): the page heading shown above the first section. Actions (for example "Reset page")
-- are added with Page:addHeaderAction and sit on the right of the heading.
function Page:header(title, subtitle)
	local frame = F.frame(self.content, { Name = "PageHeader", LayoutOrder = self:nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	F.padding(frame, Theme.space.s, 4, 0, Theme.space.s)
	local size, bold, token = Theme.type("page")
	local text = F.frame(frame, { Name = "Text", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	F.list(text, 2)
	local t = F.label(text, title, { size = size, bold = bold, token = token })
	t.LayoutOrder = 1
	if subtitle and subtitle ~= "" then
		local s, _, tk = Theme.type("caption")
		local d = F.label(text, subtitle, { size = s + 0.5, token = tk, wrap = true, dim = UDim2.new(1, 0, 0, 0), valign = Enum.TextYAlignment.Top })
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.LayoutOrder = 2
	end
	local actions = F.frame(frame, { Name = "Actions", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 0, 0, 30) })
	local al = F.list(actions, 8, true)
	al.HorizontalAlignment = Enum.HorizontalAlignment.Right
	self.headerText, self.headerActions, self.headerActionW = text, actions, 0
	self.card = nil
	return frame
end

-- addHeaderAction(text, onClick, style, width) -> button
function Page:addHeaderAction(text, onClick, style, width)
	if not self.headerActions then
		return nil
	end
	width = width or 104
	local b = F.button(self.headerActions, text, onClick, style or "tertiary", UDim2.fromOffset(width, 30), self.maid)
	b.LayoutOrder = #self.headerActions:GetChildren()
	self.headerActionW += width + 8
	self.headerActions.Size = UDim2.new(0, self.headerActionW, 0, 30)
	self.headerText.Size = UDim2.new(1, -(self.headerActionW + 8), 0, 0)
	return b
end

-- Toggle (iOS switch) -----------------------------------------------------------------------------------------

function Page:toggle(opts)
	local row, holder, feat = self:row({ label = opts.label, desc = opts.desc, key = opts.key, width = 54, tip = opts.tip })
	local state = false
	local function onColor()
		return Theme.color(Theme.switchToken())
	end
	local track = Instance.new("TextButton")
	track.Text = ""
	track.AutoButtonColor = false
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromOffset(50, 30)
	F.pillCorner(track)
	Theme.bind(track, "BackgroundColor3", function()
		return state and onColor() or Theme.color("bg3")
	end)
	track.Parent = holder
	local knob = Instance.new("Frame")
	knob.BorderSizePixel = 0
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(26, 26)
	knob.Position = UDim2.new(0, 2, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	F.pillCorner(knob)
	local ks = Instance.new("UIStroke")
	ks.Thickness = 1
	ks.Transparency = 0.82
	ks.Color = Color3.fromRGB(0, 0, 0)
	ks.Parent = knob
	knob.Parent = track

	local pressed = false
	local function layout(animate)
		local w = pressed and 32 or 26
		local x = state and (50 - w - 2) or 2
		local goal = { Size = UDim2.fromOffset(w, 26), Position = UDim2.new(0, x, 0.5, 0) }
		if animate then
			Motion.tween(knob, goal, 0.35, "spring")
			Motion.tween(track, { BackgroundColor3 = state and onColor() or Theme.color("bg3") }, 0.25, "smooth")
		else
			knob.Size, knob.Position = goal.Size, goal.Position
			track.BackgroundColor3 = state and onColor() or Theme.color("bg3")
		end
	end
	local function set(v, animate)
		state = v and true or false
		layout(animate)
	end
	self.maid:Give(track.MouseButton1Down:Connect(function()
		pressed = true
		layout(true)
	end))
	local function release()
		if pressed then
			pressed = false
			layout(true)
		end
	end
	self.maid:Give(track.MouseButton1Up:Connect(release))
	self.maid:Give(track.MouseLeave:Connect(release))
	self.maid:Give(track.Activated:Connect(function()
		click()
		touch(feat)
		if opts.key then
			Settings.set(opts.key, not Settings.get(opts.key), "ui")
		elseif opts.set then
			opts.set(not opts.get())
			set(opts.get(), true)
		end
	end))
	if opts.key then
		local first = true
		bindSetting(self, opts.key, function(v)
			set(v, not first)
			first = false
		end)
	else
		set(opts.get and opts.get() or false, false)
	end
	return row, set
end

-- Slider ---------------------------------------------------------------------------------------------------------

local function decimals(step)
	if not step or step >= 1 then
		return 0
	end
	local d = 0
	local s = step
	while d < 4 and math.abs(s * 10 ^ d - math.floor(s * 10 ^ d + 0.5)) > 1e-6 do
		d += 1
	end
	return math.max(d, 1)
end

function Page:slider(opts)
	local def = Settings.schema(opts.key)
	local row, holder, feat = self:row({ label = opts.label or def.label, desc = opts.desc or def.desc, key = opts.key, width = 230 })
	local fmt = opts.format or string.format("%%.%df", decimals(def.step))
	local valueLabel = F.label(holder, "", { size = 12, bold = true, token = "textDim", align = Enum.TextXAlignment.Right, dim = UDim2.fromOffset(54, 20) })
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.fromScale(1, 0.5)

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0, 0.5)
	hit.Position = UDim2.fromScale(0, 0.5)
	hit.Size = UDim2.new(1, -62, 0, 30)
	hit.Parent = holder
	local bar = F.frame(hit, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6) })
	Theme.bind(bar, "BackgroundColor3", function()
		return Theme.mix("bg3", "highlight", 0.08)
	end)
	bar.BackgroundTransparency = 0
	F.pillCorner(bar)
	local fill = F.frame(bar, { Size = UDim2.fromScale(0, 1) }, { BackgroundColor3 = "accent" })
	fill.BackgroundTransparency = 0
	F.pillCorner(fill)
	local knob = Instance.new("Frame")
	knob.BorderSizePixel = 0
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	F.pillCorner(knob)
	local ks = Instance.new("UIStroke")
	ks.Thickness = 1
	ks.Transparency = 0.8
	ks.Color = Color3.fromRGB(0, 0, 0)
	ks.Parent = knob
	knob.Parent = bar
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Thickness = 3
	ring.Transparency = 1
	Theme.bind(ring, "Color", "accent")
	ring.Parent = knob

	local span = def.max - def.min
	local function show(v, animate)
		local frac = span > 0 and (v - def.min) / span or 0
		valueLabel.Text = string.format(fmt, v) .. (opts.suffix or "")
		if animate then
			Motion.tween(fill, { Size = UDim2.fromScale(frac, 1) }, 0.12, "smooth")
			Motion.tween(knob, { Position = UDim2.fromScale(frac, 0.5) }, 0.12, "smooth")
		else
			fill.Size = UDim2.fromScale(frac, 1)
			knob.Position = UDim2.fromScale(frac, 0.5)
		end
	end
	local dragging = false
	local function fromX(x)
		local w = bar.AbsoluteSize.X
		if w <= 0 then
			return
		end
		local frac = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
		Settings.set(opts.key, def.min + frac * span, "ui")
	end
	self.maid:Give(hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			touch(feat)
			Motion.tween(knob, { Size = UDim2.fromOffset(22, 22) }, Motion.D.fast, "smooth")
			Motion.tween(ring, { Transparency = 0.65 }, Motion.D.fast, "smooth")
			fromX(input.Position.X)
			F.beginDrag(function(pos)
				fromX(pos.X)
			end, function()
				dragging = false
				Motion.tween(knob, { Size = UDim2.fromOffset(18, 18) }, Motion.D.std, "smooth")
				Motion.tween(ring, { Transparency = 1 }, Motion.D.std, "smooth")
			end)
		end
	end))
	local first = true
	bindSetting(self, opts.key, function(v)
		show(v, not first and not dragging)
		first = false
	end)
	return row
end

-- Segmented control / dropdown for enums ----------------------------------------------------------------------------

function Page:enum(opts)
	local def = Settings.schema(opts.key)
	local options = def.options
	local maxLen = 0
	for _, o in ipairs(options) do
		maxLen = math.max(maxLen, #o)
	end
	local segmented = #options <= 4 and maxLen * #options <= 28
	if segmented then
		local segW = math.max(54, maxLen * 8 + 18)
		local total = segW * #options + 6
		local row, holder, feat = self:row({ label = opts.label or def.label, desc = opts.desc or def.desc, key = opts.key, width = total })
		local box = F.frame(holder, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(total, 32) }, { BackgroundColor3 = "bg3" })
		box.BackgroundTransparency = 0
		F.pillCorner(box)
		local pill = F.frame(box, { Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(segW, 26) })
		Theme.bind(pill, "BackgroundColor3", function()
			return Theme.mix("bg3", "highlight", 0.24)
		end)
		pill.BackgroundTransparency = 0
		F.pillCorner(pill)
		local buttons = {}
		for i, o in ipairs(options) do
			local b = Instance.new("TextButton")
			b.Text = I18n.tr(o)
			b.AutoButtonColor = false
			b.BackgroundTransparency = 1
			b.BorderSizePixel = 0
			b.Position = UDim2.fromOffset(3 + (i - 1) * segW, 3)
			b.Size = UDim2.fromOffset(segW, 26)
			b.ZIndex = 2
			Theme.bind(b, "Font", function()
				return Theme.font(true)
			end)
			Theme.bind(b, "TextSize", function()
				return Theme.textSize(12)
			end)
			b.Parent = box
			buttons[o] = b
			self.maid:Give(b.Activated:Connect(function()
				click()
				touch(feat)
				Settings.set(opts.key, o, "ui")
			end))
		end
		local first = true
		bindSetting(self, opts.key, function(v)
			local idx = table.find(options, v) or 1
			local goal = { Position = UDim2.fromOffset(3 + (idx - 1) * segW, 3) }
			if first then
				pill.Position = goal.Position
			else
				Motion.tween(pill, goal, Motion.D.slow, "enter")
			end
			for o, b in pairs(buttons) do
				Theme.bind(b, "TextColor3", function()
					return o == Settings.get(opts.key) and Theme.color("text") or Theme.color("textDim")
				end)
			end
			first = false
		end)
		return row
	end

	local row, holder, feat = self:row({ label = opts.label or def.label, desc = opts.desc or def.desc, key = opts.key, width = 170 })
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.fromScale(1, 0.5)
	btn.Size = UDim2.fromOffset(170, 32)
	Theme.bind(btn, "BackgroundColor3", "bg3")
	Theme.bind(btn, "BackgroundTransparency", function()
		return select(2, Theme.surface("control"))
	end)
	F.corner(btn, "control")
	F.edge(btn)
	btn.Parent = holder
	local text = F.label(btn, "", { size = 13, bold = true, dim = UDim2.new(1, -34, 1, 0) })
	text.Position = UDim2.fromOffset(12, 0)
	local chev = Icons.draw(btn, "chevron", 14, "textDim")
	chev.AnchorPoint = Vector2.new(0.5, 0.5)
	chev.Position = UDim2.new(1, -16, 0.5, 0)
	chev.Rotation = 270
	Motion.pressable(btn, self.maid, 0.03)
	bindSetting(self, opts.key, function(v)
		text.Text = I18n.tr(tostring(v))
	end)
	self.maid:Give(btn.Activated:Connect(function()
		click()
		local itemH = 32
		local height = math.min(#options * itemH + 12, 240)
		local frame, pmaid = F.openPopover(btn, 190, height)
		local sf, smaid = F.scroller(frame)
		pmaid:Give(smaid)
		local inner = F.frame(sf, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
		F.list(inner, 2)
		F.padding(inner, 6, 6, 6, 6)
		for i, o in ipairs(options) do
			local item = Instance.new("TextButton")
			item.Text = ""
			item.AutoButtonColor = false
			item.BorderSizePixel = 0
			item.LayoutOrder = i
			item.Size = UDim2.new(1, 0, 0, itemH - 2)
			item.BackgroundTransparency = 1
			Theme.bind(item, "BackgroundColor3", "highlight")
			F.corner(item, "small")
			local sel = Settings.get(opts.key) == o
			local l = F.label(item, I18n.tr(tostring(o)), { size = 13, bold = sel, token = sel and "accent" or "text", dim = UDim2.new(1, -34, 1, 0) })
			l.Position = UDim2.fromOffset(10, 0)
			if sel then
				local ck = Icons.draw(item, "check", 14, "accent")
				ck.AnchorPoint = Vector2.new(1, 0.5)
				ck.Position = UDim2.new(1, -10, 0.5, 0)
			end
			item.Parent = inner
			pmaid:Give(item.MouseEnter:Connect(function()
				Motion.tween(item, { BackgroundTransparency = 0.9 }, Motion.D.fast, "smooth")
			end))
			pmaid:Give(item.MouseLeave:Connect(function()
				Motion.tween(item, { BackgroundTransparency = 1 }, Motion.D.std, "smooth")
			end))
			pmaid:Give(item.Activated:Connect(function()
				click()
				touch(feat)
				Settings.set(opts.key, o, "ui")
				F.closePopover()
			end))
		end
	end))
	return row
end

-- Colour picker (HSV) ----------------------------------------------------------------------------------------------------

local function hueSequence()
	local pts = {}
	for i = 0, 6 do
		pts[#pts + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))
	end
	return ColorSequence.new(pts)
end

function Page:color(opts)
	local def = Settings.schema(opts.key)
	local row, holder, feat = self:row({ label = opts.label or def.label, desc = opts.desc or def.desc, key = opts.key, width = 120 })
	local swatch = Instance.new("TextButton")
	swatch.Text = ""
	swatch.AutoButtonColor = false
	swatch.BorderSizePixel = 0
	swatch.AnchorPoint = Vector2.new(1, 0.5)
	swatch.Position = UDim2.fromScale(1, 0.5)
	swatch.Size = UDim2.fromOffset(110, 30)
	F.corner(swatch, "control")
	F.stroke(swatch, "stroke", 1, 0.2)
	swatch.Parent = holder
	local hex = F.label(swatch, "", { size = 12, bold = true, align = Enum.TextXAlignment.Center, dim = UDim2.fromScale(1, 1) })
	Motion.pressable(swatch, self.maid, 0.04)
	bindSetting(self, opts.key, function(c)
		swatch.BackgroundColor3 = Color3.fromRGB(c.r, c.g, c.b)
		hex.Text = ColorUtil.toHex(c)
		local dark = ColorUtil.luminance(c) > 0.35
		Theme.bind(hex, "TextColor3", function()
			return dark and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
		end)
	end)

	self.maid:Give(swatch.Activated:Connect(function()
		click()
		local frame, pmaid = F.openPopover(swatch, 232, 250)
		F.padding(frame, 16, 16, 16, 16)
		local cur = Settings.get(opts.key)
		local h, sat, val = ColorUtil.toHSV(cur.r, cur.g, cur.b)

		local sv = Instance.new("Frame")
		sv.Size = UDim2.new(1, 0, 0, 132)
		sv.BorderSizePixel = 0
		sv.ClipsDescendants = true
		F.corner(sv, -2)
		sv.Parent = frame
		local white = Instance.new("Frame")
		white.Size = UDim2.fromScale(1, 1)
		white.BorderSizePixel = 0
		white.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		white.Parent = sv
		local wg = Instance.new("UIGradient")
		wg.Transparency = NumberSequence.new(0, 1)
		wg.Parent = white
		local black = Instance.new("Frame")
		black.Size = UDim2.fromScale(1, 1)
		black.BorderSizePixel = 0
		black.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		black.Parent = sv
		local bg = Instance.new("UIGradient")
		bg.Rotation = 90
		bg.Transparency = NumberSequence.new(1, 0)
		bg.Parent = black
		local cursor = Instance.new("Frame")
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Size = UDim2.fromOffset(14, 14)
		cursor.BackgroundTransparency = 1
		cursor.BorderSizePixel = 0
		cursor.ZIndex = 3
		F.pillCorner(cursor)
		local cs = Instance.new("UIStroke")
		cs.Thickness = 2
		cs.Color = Color3.fromRGB(255, 255, 255)
		cs.Parent = cursor
		cursor.Parent = sv

		local hueBar = Instance.new("Frame")
		hueBar.Position = UDim2.fromOffset(0, 144)
		hueBar.Size = UDim2.new(1, 0, 0, 14)
		hueBar.BorderSizePixel = 0
		hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		F.pillCorner(hueBar)
		local hg = Instance.new("UIGradient")
		hg.Color = hueSequence()
		hg.Parent = hueBar
		hueBar.Parent = frame
		local hueKnob = Instance.new("Frame")
		hueKnob.AnchorPoint = Vector2.new(0.5, 0.5)
		hueKnob.Size = UDim2.fromOffset(18, 18)
		hueKnob.BorderSizePixel = 0
		hueKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		hueKnob.ZIndex = 3
		F.pillCorner(hueKnob)
		local hk = Instance.new("UIStroke")
		hk.Thickness = 1
		hk.Transparency = 0.7
		hk.Parent = hueKnob
		hueKnob.Parent = hueBar

		local input
		local function paint(fromInput)
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			cursor.Position = UDim2.fromScale(sat, 1 - val)
			hueKnob.Position = UDim2.fromScale(h, 0.5)
			if not fromInput and input then
				local r, g, b = ColorUtil.fromHSV(h, sat, val)
				input.Text = ColorUtil.toHex({ r = r, g = g, b = b })
			end
		end
		local function commit()
			local r, g, b = ColorUtil.fromHSV(h, sat, val)
			touch(feat)
			Settings.set(opts.key, { r = r, g = g, b = b }, "ui")
		end
		pmaid:Give(sv.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				local function upd(pos)
					local ap, as = sv.AbsolutePosition, sv.AbsoluteSize
					sat = math.clamp((pos.X - ap.X) / math.max(1, as.X), 0, 1)
					val = 1 - math.clamp((pos.Y - ap.Y) / math.max(1, as.Y), 0, 1)
					paint()
					commit()
				end
				upd(inp.Position)
				F.beginDrag(upd)
			end
		end))
		pmaid:Give(hueBar.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				local function upd(pos)
					local ap, as = hueBar.AbsolutePosition, hueBar.AbsoluteSize
					h = math.clamp((pos.X - ap.X) / math.max(1, as.X), 0, 0.999)
					paint()
					commit()
				end
				upd(inp.Position)
				F.beginDrag(upd)
			end
		end))
		input = F.textBox(frame, {
			text = ColorUtil.toHex(cur),
			dim = UDim2.new(1, 0, 0, 32),
			onSubmit = function(text)
				local c = ColorUtil.fromHex(text)
				if c then
					h, sat, val = ColorUtil.toHSV(c.r, c.g, c.b)
					paint(true)
					touch(feat)
					Settings.set(opts.key, c, "ui")
				else
					input.Text = ColorUtil.toHex(Settings.get(opts.key))
				end
			end,
		}, pmaid)
		input.Position = UDim2.fromOffset(0, 170)
		paint()
	end))
	return row
end

-- Key binding box ---------------------------------------------------------------------------------------------------------------

function Page:keybind(opts)
	local b = nil
	for _, item in ipairs(Input.list()) do
		if item.id == opts.actionId then
			b = item
		end
	end
	assert(b, "keybind: no binding for " .. tostring(opts.actionId))
	local key = b.settingKey
	local row, holder = self:row({ label = opts.label or b.name, desc = opts.desc or (b.hubOnly and "Works only while the hub is open." or nil), key = key, width = 170 })
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -30, 0.5, 0)
	btn.Size = UDim2.fromOffset(130, 30)
	Theme.bind(btn, "BackgroundColor3", "bg3")
	F.corner(btn, "control")
	local stroke = F.stroke(btn, "stroke", 1, 0.5)
	btn.Parent = holder
	local text = F.label(btn, "", { size = 12, bold = true, align = Enum.TextXAlignment.Center, dim = UDim2.fromScale(1, 1) })
	local clear = F.iconButton(holder, "close", function()
		Input.clear(opts.actionId)
	end, 24, self.maid)
	clear.AnchorPoint = Vector2.new(1, 0.5)
	clear.Position = UDim2.fromScale(1, 0.5)
	Motion.pressable(btn, self.maid, 0.03)
	local capturing = false
	local function refresh()
		local current = Settings.get(key)
		local conflict = false
		for _, c in ipairs(Input.conflicts()) do
			if table.find(c.actions, opts.actionId) then
				conflict = true
			end
		end
		if capturing then
			text.Text = I18n.t("keys.press")
			Theme.bind(text, "TextColor3", "accent")
			Theme.bind(stroke, "Color", "accent")
			stroke.Transparency = 0
		else
			text.Text = current == "None" and "—" or current
			Theme.bind(text, "TextColor3", conflict and "bad" or "text")
			Theme.bind(stroke, "Color", conflict and "bad" or "stroke")
			stroke.Transparency = conflict and 0 or 0.5
		end
	end
	self.maid:Give(btn.Activated:Connect(function()
		click()
		capturing = true
		refresh()
		Input.startCapture(function(newKey)
			capturing = false
			if newKey then
				local ok, err, other = Input.rebind(opts.actionId, newKey, false)
				if not ok and other then
					-- conflict: steal only after explicit second press of the same key
					F.confirm({
						title = I18n.t("keys.conflict"),
						text = err .. ". Move it to this action?",
						confirmText = I18n.t("btn.confirm"),
						onConfirm = function()
							Input.rebind(opts.actionId, newKey, true)
						end,
					})
				end
			end
			refresh()
		end)
	end))
	self.maid:Give(Settings.Changed:Connect(function(k)
		if string.sub(k, 1, 5) == "keys." then
			refresh()
		end
	end))
	self.maid:Give(function()
		Input.cancelCapture()
	end)
	refresh()
	return row
end

-- Action row ------------------------------------------------------------------------------------------------------------------------

-- action{label, desc, text, style, onClick}
function Page:action(opts)
	local row, holder = self:row({ label = opts.label, desc = opts.desc, width = (opts.width or 120) })
	local b = F.button(holder, opts.text, opts.onClick, opts.style or "tinted", UDim2.fromOffset(opts.width or 120, 32), self.maid)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.fromScale(1, 0.5)
	return row, b
end

-- text input row
function Page:input(opts)
	local row, holder = self:row({ label = opts.label, desc = opts.desc, width = (opts.width or 200) + 0 })
	local box = F.textBox(holder, { placeholder = opts.placeholder, text = opts.text, dim = UDim2.fromOffset(opts.width or 200, 30), onSubmit = opts.onSubmit }, self.maid)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.fromScale(1, 0.5)
	return row, box
end

-- stat tiles: row of equal cards, each {title, value, token}. Returns update function(i, text)
function Page:stats(items)
	local frame = F.frame(self.content, { LayoutOrder = self:nextOrder(), Size = UDim2.new(1, 0, 0, 76) })
	local layout = F.list(frame, 8, true)
	local labels = {}
	for i, item in ipairs(items) do
		local card = F.surface(frame, "card", { name = "Stat", props = { Size = UDim2.new(1 / #items, -8 * (#items - 1) / #items, 1, 0), LayoutOrder = i } })
		F.padding(card, 14, 10, 14, 8)
		local t = F.label(card, I18n.upper(I18n.tr(item.title)), { size = 10.5, bold = true, token = "textDim" })
		local v = F.label(card, item.value or "—", { size = 22, bold = true, token = item.token or "text", dim = UDim2.new(1, 0, 0, 32) })
		v.Position = UDim2.fromOffset(0, 22)
		labels[i] = v
	end
	return function(i, text, token)
		local l = labels[i]
		text = I18n.tr(text)
		if l and l.Text ~= text then
			l.Text = text
		end
		if l and token then
			Theme.bind(l, "TextColor3", token)
		end
	end, frame, layout
end

return F

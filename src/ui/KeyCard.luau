--!nonstrict
-- ui/KeyCard: the licence-key window used by both the in-script gate (ui/LicenseGate) and the standalone loader
-- (loader/main). It imports nothing but plain Roblox objects, because it must work before any setting exists and
-- ships inside the tiny loader. Glass look = translucent card + thin light edge + faint sheen + soft shadow (no
-- real blur: Roblox offers none to scripts).
-- States: idle, focused (accent ring), busy (button shows a progress label and ignores presses), error (red ring and
-- message), success (green message). All motion is TweenService with short durations; everything is destroyed by close().

local KeyCard = {}

-- built on first use: Roblox datatypes must not be created while the module loads
local function palette()
	return {
		card = Color3.fromRGB(30, 30, 33),
		field = Color3.fromRGB(58, 58, 62),
		text = Color3.fromRGB(255, 255, 255),
		dim = Color3.fromRGB(174, 174, 178),
		accent = Color3.fromRGB(10, 132, 255),
		good = Color3.fromRGB(48, 209, 88),
		bad = Color3.fromRGB(255, 69, 58),
	}
end

local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function tween(inst, goal, t, style)
	local ok, tw = pcall(function()
		return game:GetService("TweenService"):Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	end)
	if ok and tw then
		tw:Play()
	else
		for k, v in pairs(goal) do
			pcall(function()
				inst[k] = v
			end)
		end
	end
end

local function corner(parent, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

-- edge(parent): light top edge fading to a faint bottom edge
local function edge(parent, thickness)
	local s = make("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.5, 0.9) }, s)
	return s
end

-- build(parent, opts) -> card
--   opts = { title, prompt, placeholder, button, busy = "label while working", onSubmit = fn(text) }
-- card = { gui parts..., setStatus(text, kind), setBusy(bool), focus(), destroy() }
function KeyCard.build(parent, opts)
	local PAL = palette()
	local conns = {}
	local function connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(conns, c)
		return c
	end

	local back = make("TextButton", { Name = "KeyCardBackdrop", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 }, parent)
	tween(back, { BackgroundTransparency = 0.5 }, 0.3)

	-- soft shadow: stacked rounded rectangles with a geometric transparency ramp
	local stack = make("Frame", { Name = "Stack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 262), BackgroundTransparency = 1 }, back)
	for _, spec in ipairs({ { 6, 0.9 }, { 16, 0.95 }, { 30, 0.975 }, { 46, 0.99 } }) do
		local layer = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 10), Size = UDim2.new(1, spec[1] * 2, 1, spec[1] * 2), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = spec[2], BorderSizePixel = 0 }, stack)
		corner(layer, 22 + spec[1])
	end
	local card = make("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAL.card, BackgroundTransparency = 0.04, BorderSizePixel = 0, ClipsDescendants = true }, stack)
	corner(card, 22)
	edge(card)
	local sheen = make("Frame", { Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, card)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.94, 1) }, sheen)
	local scale = make("UIScale", { Scale = 0.94 }, stack)
	tween(scale, { Scale = 1 }, 0.35)

	-- header: product mark + title + prompt
	local mark = make("Frame", { Position = UDim2.fromOffset(26, 24), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = PAL.accent, BorderSizePixel = 0 }, card)
	corner(mark, 17)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(110, 185, 255), PAL.accent) }, mark)
	local dot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, mark)
	corner(dot, 6)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(72, 22), Size = UDim2.new(1, -98, 0, 22), Text = opts.title, Font = Enum.Font.GothamBold, TextSize = 19, TextColor3 = PAL.text, TextXAlignment = Enum.TextXAlignment.Left }, card)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(72, 45), Size = UDim2.new(1, -98, 0, 30), Text = opts.prompt, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = PAL.dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true }, card)

	-- key field with focus / error ring
	local box = make("TextBox", { Name = "KeyBox", Position = UDim2.fromOffset(26, 100), Size = UDim2.new(1, -52, 0, 44), BackgroundColor3 = PAL.field, BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "", PlaceholderText = opts.placeholder, PlaceholderColor3 = Color3.fromRGB(140, 140, 145), TextColor3 = PAL.text, Font = Enum.Font.GothamMedium, TextSize = 14, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, card)
	corner(box, 12)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, box)
	local ring = make("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.82, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	local state = { focused = false, invalid = false, busy = false }
	local function paintRing()
		if state.invalid then
			ring.Color, ring.Thickness = PAL.bad, 1.5
			tween(ring, { Transparency = 0 }, 0.15)
		elseif state.focused then
			ring.Color, ring.Thickness = PAL.accent, 1.5
			tween(ring, { Transparency = 0 }, 0.15)
		else
			ring.Color, ring.Thickness = Color3.fromRGB(255, 255, 255), 1
			tween(ring, { Transparency = 0.82 }, 0.2)
		end
	end
	connect(box.Focused, function()
		state.focused = true
		paintRing()
	end)
	connect(box.FocusLost, function()
		state.focused = false
		paintRing()
	end)

	-- status line: a glyph + text. Kind: error | ok | info
	local statusDot = make("Frame", { Position = UDim2.fromOffset(28, 161), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = PAL.bad, BackgroundTransparency = 1, BorderSizePixel = 0 }, card)
	corner(statusDot, 4)
	local status = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(44, 154), Size = UDim2.new(1, -70, 0, 22), Text = "", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = PAL.dim, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center }, card)

	-- primary button: hover, press, busy
	local button = make("TextButton", { Name = "Submit", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, -52, 0, 46), BackgroundColor3 = PAL.accent, BorderSizePixel = 0, Text = opts.button, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255), AutoButtonColor = false }, card)
	corner(button, 14)
	local bscale = make("UIScale", { Scale = 1 }, button)
	local function paintButton(down, hover)
		local color = PAL.accent
		if down then
			color = Color3.fromRGB(8, 100, 200)
		elseif hover then
			color = Color3.fromRGB(46, 150, 255)
		end
		tween(button, { BackgroundColor3 = color, TextTransparency = state.busy and 0.35 or 0 }, 0.12)
		tween(bscale, { Scale = down and 0.98 or 1 }, 0.12)
	end
	connect(button.MouseEnter, function()
		paintButton(false, true)
	end)
	connect(button.MouseLeave, function()
		paintButton(false, false)
	end)
	connect(button.MouseButton1Down, function()
		paintButton(true, true)
	end)
	connect(button.MouseButton1Up, function()
		paintButton(false, true)
	end)

	local obj = { gui = back, box = box, button = button, status = status }

	-- setStatus(text, kind): "" clears the line
	function obj.setStatus(text, kind)
		status.Text = text or ""
		local color = kind == "error" and PAL.bad or (kind == "ok" and PAL.good or PAL.dim)
		status.TextColor3 = color
		statusDot.BackgroundColor3 = color
		statusDot.BackgroundTransparency = (text and text ~= "") and 0 or 1
		state.invalid = kind == "error"
		paintRing()
	end

	-- setBusy(true): the button shows opts.busy, input is disabled; the card stays on screen until close()
	function obj.setBusy(busy)
		state.busy = busy and true or false
		box.TextEditable = not state.busy
		button.Text = state.busy and (opts.busy or "…") or opts.button
		button.Active = not state.busy
		paintButton(false, false)
	end

	function obj.focus()
		pcall(function()
			box:CaptureFocus()
		end)
	end

	function obj.isBusy()
		return state.busy
	end

	local function submit()
		if state.busy then
			return
		end
		if opts.onSubmit then
			opts.onSubmit(box.Text)
		end
	end
	connect(button.Activated, submit)
	connect(box.FocusLost, function(enter)
		if enter then
			submit()
		end
	end)
	-- typing again clears an old error
	connect(box:GetPropertyChangedSignal("Text"), function()
		if state.invalid then
			obj.setStatus("", "info")
		end
	end)

	function obj.destroy()
		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(conns)
		pcall(function()
			back:Destroy()
		end)
	end
	return obj
end

return KeyCard

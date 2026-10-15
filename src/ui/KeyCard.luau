--!nonstrict
-- ui/KeyCard: the licence-key window used by both the in-script gate (ui/LicenseGate) and the standalone loader
-- (loader/main). It imports nothing but plain Roblox objects, because it must work before any setting exists and
-- ships inside the tiny loader. iOS 27 look: black glass card, a thick glossy chrome rim with a slowly travelling
-- highlight, a white glossy button, and a local BlurEffect on the game world behind it (Roblox cannot blur GUI, only
-- the 3D view; the blur exists only on this client and is removed with the card).
-- States: idle, focused (accent ring), busy (button shows a progress label and ignores presses), error (red ring and
-- message), success (green message). All motion is TweenService with short durations; everything is destroyed by close().

local KeyCard = {}

-- built on first use: Roblox datatypes must not be created while the module loads
local function palette()
	return {
		card = Color3.fromRGB(6, 6, 9),
		field = Color3.fromRGB(26, 26, 32),
		text = Color3.fromRGB(255, 255, 255),
		dim = Color3.fromRGB(186, 186, 196),
		accent = Color3.fromRGB(240, 242, 248),
		accentText = Color3.fromRGB(8, 8, 12),
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
local function chrome()
	local K, rgb = ColorSequenceKeypoint.new, Color3.fromRGB
	return ColorSequence.new({ K(0, rgb(255, 255, 255)), K(0.22, rgb(150, 154, 164)), K(0.45, rgb(250, 251, 255)),
		K(0.62, rgb(96, 100, 110)), K(0.8, rgb(232, 235, 242)), K(1, rgb(170, 174, 184)) })
end

-- edge(parent, thickness) -> stroke, gradient: thick glossy chrome rim, bright at the top
local function edge(parent, thickness)
	local s = make("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = thickness or 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
	local g = make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.05, 0.45), Color = chrome() }, s)
	return s, g
end

-- build(parent, opts) -> card
--   opts = { title, prompt, placeholder, button, busy = "label while working", onSubmit = fn(text),
--            sticker = { image = url, frames = n, cols = n, cell = px, period = seconds } (optional animated mascot) }
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
	tween(back, { BackgroundTransparency = 0.45 }, 0.3)
	-- blur the game world behind the card (local only; removed in destroy)
	local blur
	pcall(function()
		blur = Instance.new("BlurEffect")
		blur.Name = "MM2HubKeyBlur"
		blur.Size = 0
		blur.Parent = game:GetService("Lighting")
		tween(blur, { Size = 16 }, 0.4)
	end)

	-- soft shadow: stacked rounded rectangles with a geometric transparency ramp
	local stack = make("Frame", { Name = "Stack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 262), BackgroundTransparency = 1 }, back)
	for _, spec in ipairs({ { 6, 0.9 }, { 16, 0.95 }, { 30, 0.975 }, { 46, 0.99 } }) do
		local layer = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 10), Size = UDim2.new(1, spec[1] * 2, 1, spec[1] * 2), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = spec[2], BorderSizePixel = 0 }, stack)
		corner(layer, 22 + spec[1])
	end
	local card = make("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAL.card, BackgroundTransparency = 0.08, BorderSizePixel = 0, ClipsDescendants = true }, stack)
	corner(card, 26)
	local _, rimGradient = edge(card, 2.5)
	local sheen = make("Frame", { Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, card)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.88, 1) }, sheen)
	local scale = make("UIScale", { Scale = 0.86 }, stack)
	tween(scale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
	-- the chrome highlight travels slowly round the rim
	pcall(function()
		local t0 = os.clock()
		local c = game:GetService("RunService").Heartbeat:Connect(function()
			rimGradient.Rotation = 90 + math.sin((os.clock() - t0) * 0.9) * 60
		end)
		table.insert(conns, c)
	end)

	-- animated mascot on the card's top-right corner: the Trollface slowly opens its mouth wide and slowly closes it again
	-- (sprite frames played forward then backward with an ease, one full cycle per opts.sticker.period seconds)
	if opts.sticker and opts.sticker.image then
		local st = opts.sticker
		local cell, cols, frames = st.cell or 128, st.cols or 5, st.frames or 10
		local img = make("ImageLabel", { Name = "Sticker", BackgroundTransparency = 1, Image = st.image, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(92, 92), Rotation = 12, ZIndex = 5,
			ImageRectSize = Vector2.new(cell, cell), ImageRectOffset = Vector2.new(0, 0) }, stack)
		local sscale = make("UIScale", { Scale = 0 }, img)
		tween(sscale, { Scale = 1 }, 0.6, Enum.EasingStyle.Back)
		pcall(function()
			local t0, last = os.clock(), -1
			local c = game:GetService("RunService").Heartbeat:Connect(function()
				local t = (os.clock() - t0) / (st.period or 4.8)
				local open = 0.5 - 0.5 * math.cos(t * 2 * math.pi) -- 0 closed .. 1 widest, smooth both ways
				local f = math.clamp(math.floor(open * (frames - 1) + 0.5), 0, frames - 1)
				if f ~= last then
					last = f
					img.ImageRectOffset = Vector2.new((f % cols) * cell, (f // cols) * cell)
				end
				img.Rotation = 12 + math.sin(t * 2 * math.pi) * 3
			end)
			table.insert(conns, c)
		end)
	end

	-- header: product mark + title + prompt
	local mark = make("Frame", { Position = UDim2.fromOffset(26, 24), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, card)
	corner(mark, 17)
	make("UIGradient", { Rotation = 35, Color = chrome() }, mark)
	edge(mark, 1.5)
	local dot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(8, 8, 12), BorderSizePixel = 0 }, mark)
	corner(dot, 6)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(72, 22), Size = UDim2.new(1, -98, 0, 22), Text = opts.title, Font = Enum.Font.MontserratBold, TextSize = 19, TextColor3 = PAL.text, TextXAlignment = Enum.TextXAlignment.Left }, card)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(72, 45), Size = UDim2.new(1, -98, 0, 30), Text = opts.prompt, Font = Enum.Font.MontserratMedium, TextSize = 12, TextColor3 = PAL.dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true }, card)

	-- key field with focus / error ring
	local box = make("TextBox", { Name = "KeyBox", Position = UDim2.fromOffset(26, 100), Size = UDim2.new(1, -52, 0, 44), BackgroundColor3 = PAL.field, BackgroundTransparency = 0.15, BorderSizePixel = 0, Text = "", PlaceholderText = opts.placeholder, PlaceholderColor3 = Color3.fromRGB(140, 140, 145), TextColor3 = PAL.text, Font = Enum.Font.MontserratMedium, TextSize = 14, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, card)
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
	local status = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(44, 154), Size = UDim2.new(1, -70, 0, 22), Text = "", Font = Enum.Font.MontserratMedium, TextSize = 12, TextColor3 = PAL.dim, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center }, card)

	-- primary button: hover, press, busy
	local button = make("TextButton", { Name = "Submit", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, -52, 0, 46), BackgroundColor3 = PAL.accent, BorderSizePixel = 0, Text = opts.button, Font = Enum.Font.MontserratBold, TextSize = 15, TextColor3 = PAL.accentText, AutoButtonColor = false }, card)
	corner(button, 23)
	-- glossy white pill: a light-to-silver gradient and a bright top edge
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 200, 210)) }, button)
	edge(button, 1.5)
	local bscale = make("UIScale", { Scale = 1 }, button)
	local function paintButton(down, hover)
		local color = PAL.accent
		if down then
			color = Color3.fromRGB(190, 194, 204)
		elseif hover then
			color = Color3.fromRGB(255, 255, 255)
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
		if kind == "error" then
			-- a short sideways shake, like a wrong passcode on iOS
			pcall(function()
				local x0 = UDim2.fromScale(0.5, 0.5) -- fixed rest position, so overlapping shakes never drift
				for i, dx in ipairs({ -10, 9, -6, 4, 0 }) do
					task.delay(i * 0.05, function()
						stack.Position = x0 + UDim2.fromOffset(dx, 0)
					end)
				end
			end)
		end
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
		if blur then
			pcall(function()
				blur:Destroy()
			end)
		end
	end
	return obj
end

return KeyCard

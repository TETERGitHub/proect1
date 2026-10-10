--[[
	AdminBhopClient (LocalScript)

	Бхоп в стиле CS/Source: автопрыжок, air-strafe (набор скорости стрейфами + мышью),
	авто-стрейф, перфект-хоп окно, трение, буст, FOV от скорости, спидометр.
	Всё настраивается в меню (по умолчанию RightShift), вкл/выкл — клавиша B.

	Этот скрипт лежит в ServerStorage, сервер копирует его только админам.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("AdminBhopSettings", 10)

-- ======================================================================
-- НАСТРОЙКИ
-- ======================================================================

local SCHEMA = {
	{ section = "Основное" },
	{ key = "Enabled", kind = "bool", default = true, label = "Бхоп включён" },
	{ key = "AutoHop", kind = "bool", default = true, label = "Автопрыжок (держать пробел)" },
	{ key = "PreserveSpeed", kind = "bool", default = true, label = "Сохранять скорость при приземлении" },
	{ key = "HopWindow", kind = "number", default = 0.1, min = 0, max = 0.5, step = 0.01, label = "Окно перфект-хопа (сек)" },
	{ key = "JumpVelocity", kind = "number", default = 50, min = 10, max = 200, step = 1, label = "Сила прыжка" },
	{ key = "HopBoost", kind = "number", default = 0, min = 0, max = 50, step = 0.5, label = "Буст за прыжок (%)" },
	{ key = "MaxSpeed", kind = "number", default = 120, min = 16, max = 1000, step = 1, label = "Макс. скорость" },

	{ section = "Стрейфы (воздух)" },
	{ key = "AirStrafe", kind = "bool", default = true, label = "Air-strafe" },
	{ key = "AutoStrafe", kind = "bool", default = false, label = "Авто-стрейф (только мышь)" },
	{ key = "AirAccel", kind = "number", default = 100, min = 0, max = 1000, step = 1, label = "Air accelerate" },
	{ key = "AirWishCap", kind = "number", default = 2.5, min = 0.1, max = 50, step = 0.1, label = "Air speed cap" },

	{ section = "Земля" },
	{ key = "GroundAccel", kind = "number", default = 10, min = 0, max = 100, step = 0.5, label = "Ускорение на земле" },
	{ key = "GroundFriction", kind = "number", default = 6, min = 0, max = 30, step = 0.1, label = "Трение" },
	{ key = "StopSpeed", kind = "number", default = 5, min = 0, max = 50, step = 0.5, label = "Stop speed" },
	{ key = "OverrideWalkSpeed", kind = "bool", default = false, label = "Свой WalkSpeed" },
	{ key = "WalkSpeed", kind = "number", default = 16, min = 0, max = 200, step = 1, label = "WalkSpeed" },

	{ section = "Визуал" },
	{ key = "Speedometer", kind = "bool", default = true, label = "Спидометр" },
	{ key = "FovScale", kind = "bool", default = true, label = "FOV от скорости" },
	{ key = "BaseFov", kind = "number", default = 70, min = 30, max = 120, step = 1, label = "Обычный FOV" },
	{ key = "MaxFov", kind = "number", default = 95, min = 30, max = 120, step = 1, label = "FOV на макс. скорости" },
	{ key = "Notifications", kind = "bool", default = true, label = "Уведомления" },

	{ section = "Клавиши" },
	{ key = "ToggleKey", kind = "key", default = "B", label = "Вкл/выкл бхоп" },
	{ key = "MenuKey", kind = "key", default = "RightShift", label = "Открыть меню" },
}

local PRESETS = {
	{
		name = "Легит",
		values = { AirAccel = 12, AirWishCap = 1.5, MaxSpeed = 40, HopBoost = 0, GroundFriction = 6, AutoStrafe = false, JumpVelocity = 50 },
	},
	{
		name = "CS:S",
		values = { AirAccel = 100, AirWishCap = 2.5, MaxSpeed = 120, HopBoost = 0, GroundFriction = 6, AutoStrafe = false, JumpVelocity = 50 },
	},
	{
		name = "Безумие",
		values = { AirAccel = 500, AirWishCap = 8, MaxSpeed = 400, HopBoost = 8, GroundFriction = 4, AutoStrafe = true, JumpVelocity = 60 },
	},
}

local S = {}
local schemaByKey = {}
for _, e in ipairs(SCHEMA) do
	if e.key then
		S[e.key] = e.default
		schemaByKey[e.key] = e
	end
end

local function roundStep(v, step)
	return math.floor(v / step + 0.5) * step
end

local function validate(key, value)
	local e = schemaByKey[key]
	if not e then
		return nil
	end
	if e.kind == "bool" then
		return typeof(value) == "boolean" and value or nil
	elseif e.kind == "number" then
		if typeof(value) ~= "number" or value ~= value then
			return nil
		end
		return math.clamp(roundStep(value, e.step), e.min, e.max)
	elseif e.kind == "key" then
		if typeof(value) ~= "string" then
			return nil
		end
		local ok = pcall(function()
			return Enum.KeyCode[value]
		end)
		return ok and value or nil
	end
	return nil
end

local listeners = {}
local onChanged -- объявлена ниже

local function set(key, value)
	value = validate(key, value)
	if value == nil then
		return
	end
	S[key] = value
	for _, fn in ipairs(listeners[key] or {}) do
		fn(value)
	end
	if onChanged then
		onChanged(key, value)
	end
end

local function listen(key, fn)
	listeners[key] = listeners[key] or {}
	table.insert(listeners[key], fn)
	fn(S[key])
end

-- ======================================================================
-- GUI
-- ======================================================================

local C = {
	bg = Color3.fromRGB(22, 22, 28),
	panel = Color3.fromRGB(32, 32, 40),
	accent = Color3.fromRGB(120, 90, 255),
	text = Color3.fromRGB(235, 235, 245),
	dim = Color3.fromRGB(150, 150, 165),
	off = Color3.fromRGB(70, 70, 82),
}

local function make(class, props)
	local o = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(parent, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent })
end

local gui = make("ScreenGui", {
	Name = "AdminBhopGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = player:WaitForChild("PlayerGui"),
})

-- --- уведомления ---
local toast = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(0, 32),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 1,
	TextTransparency = 1,
	TextColor3 = C.text,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	Text = "",
	Parent = gui,
})
corner(toast)
make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = toast })

local toastId = 0
local function notify(text)
	if not S.Notifications then
		return
	end
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.BackgroundTransparency = 0.15
	toast.TextTransparency = 0
	task.delay(1.6, function()
		if id ~= toastId then
			return
		end
		local info = TweenInfo.new(0.4)
		TweenService:Create(toast, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	end)
end

-- --- спидометр ---
local speedo = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.fromOffset(320, 28),
	BackgroundTransparency = 1,
	TextColor3 = C.text,
	TextStrokeTransparency = 0.5,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	Text = "",
	Parent = gui,
})
local speedoSub = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -72),
	Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1,
	TextColor3 = C.dim,
	TextStrokeTransparency = 0.6,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	Text = "",
	Parent = gui,
})
listen("Speedometer", function(v)
	speedo.Visible = v
	speedoSub.Visible = v
end)

-- --- окно меню ---
local win = make("Frame", {
	Size = UDim2.fromOffset(340, 460),
	Position = UDim2.new(0.5, -170, 0.5, -230),
	BackgroundColor3 = C.bg,
	Visible = false,
	Active = true,
	Parent = gui,
})
corner(win, 10)
make("UIStroke", { Color = C.accent, Thickness = 1.5, Transparency = 0.4, Parent = win })

local titleBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = C.panel,
	Parent = win,
})
corner(titleBar, 10)
make("TextLabel", {
	Size = UDim2.new(1, -50, 1, 0),
	Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1,
	Text = "BHOP  •  админ",
	TextColor3 = C.text,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = titleBar,
})
local closeBtn = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = C.off,
	Text = "×",
	TextColor3 = C.text,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	Parent = titleBar,
})
corner(closeBtn)
closeBtn.MouseButton1Click:Connect(function()
	win.Visible = false
end)

-- перетаскивание окна
do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, win.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 44),
	Size = UDim2.new(1, -20, 1, -54),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = win,
})
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
make("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = list })

local order = 0
local function row(height)
	order += 1
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.panel,
		LayoutOrder = order,
		Parent = list,
	})
	corner(f)
	return f
end

local function rowLabel(parent, text, y)
	return make("TextLabel", {
		Position = UDim2.fromOffset(10, y or 0),
		Size = UDim2.new(1, -90, 0, 30),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

local function addSection(text)
	order += 1
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = string.upper(text),
		TextColor3 = C.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = list,
	})
end

local function addToggle(e)
	local f = row(30)
	rowLabel(f, e.label)
	local sw = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(42, 20),
		BackgroundColor3 = C.off,
		Text = "",
		AutoButtonColor = false,
		Parent = f,
	})
	corner(sw, 10)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.text,
		Parent = sw,
	})
	corner(knob, 8)
	listen(e.key, function(v)
		sw.BackgroundColor3 = v and C.accent or C.off
		knob.Position = v and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	end)
	sw.MouseButton1Click:Connect(function()
		set(e.key, not S[e.key])
	end)
end

local function formatNum(v, step)
	if step >= 1 then
		return tostring(math.floor(v + 0.5))
	end
	local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function addSlider(e)
	local f = row(48)
	rowLabel(f, e.label, -2)
	local box = make("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 5),
		Size = UDim2.fromOffset(64, 20),
		BackgroundColor3 = C.bg,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		ClearTextOnFocus = false,
		Text = "",
		Parent = f,
	})
	corner(box, 4)
	local bar = make("TextButton", {
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 0, 6),
		BackgroundColor3 = C.off,
		Text = "",
		AutoButtonColor = false,
		Parent = f,
	})
	corner(bar, 3)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, Parent = bar })
	corner(fill, 3)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.text,
		Parent = bar,
	})
	corner(knob, 7)

	listen(e.key, function(v)
		local a = (v - e.min) / (e.max - e.min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		box.Text = formatNum(v, e.step)
	end)

	local dragging = false
	local function fromX(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		set(e.key, e.min + (e.max - e.min) * a)
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	box.FocusLost:Connect(function()
		local n = tonumber((box.Text:gsub(",", ".")))
		if n then
			set(e.key, n)
		end
		box.Text = formatNum(S[e.key], e.step)
	end)
end

local waitingForKey = nil -- ключ настройки, для которого ждём нажатие
local function addKeybind(e)
	local f = row(30)
	rowLabel(f, e.label)
	local btn = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(100, 22),
		BackgroundColor3 = C.bg,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Parent = f,
	})
	corner(btn, 4)
	listen(e.key, function(v)
		btn.Text = v
	end)
	btn.MouseButton1Click:Connect(function()
		waitingForKey = e.key
		btn.Text = "нажми клавишу..."
	end)
end

local function addButtons(buttons)
	local f = row(34)
	f.BackgroundTransparency = 1
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		Parent = f,
	})
	local w = 1 / #buttons
	for _, b in ipairs(buttons) do
		local btn = make("TextButton", {
			Size = UDim2.new(w, -6 + 6 / #buttons, 1, 0),
			BackgroundColor3 = b.color or C.panel,
			Text = b.text,
			TextColor3 = C.text,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			Parent = f,
		})
		corner(btn)
		btn.MouseButton1Click:Connect(b.fn)
	end
end

-- пресеты сверху
addSection("Пресеты")
do
	local buttons = {}
	for _, p in ipairs(PRESETS) do
		table.insert(buttons, {
			text = p.name,
			fn = function()
				for k, v in pairs(p.values) do
					set(k, v)
				end
				notify("Пресет: " .. p.name)
			end,
		})
	end
	addButtons(buttons)
end

for _, e in ipairs(SCHEMA) do
	if e.section then
		addSection(e.section)
	elseif e.kind == "bool" then
		addToggle(e)
	elseif e.kind == "number" then
		addSlider(e)
	elseif e.kind == "key" then
		addKeybind(e)
	end
end

local function serialize()
	local t = {}
	for k, v in pairs(S) do
		t[k] = v
	end
	return t
end

addSection("Профиль")
addButtons({
	{
		text = "Сохранить",
		color = C.accent,
		fn = function()
			if not remote then
				notify("Нет связи с сервером")
				return
			end
			local ok, _, b = pcall(remote.InvokeServer, remote, "save", serialize())
			notify(ok and tostring(b) or "Ошибка сохранения")
		end,
	},
	{
		text = "Сбросить",
		fn = function()
			for _, e in ipairs(SCHEMA) do
				if e.key then
					set(e.key, e.default)
				end
			end
			notify("Настройки сброшены")
		end,
	},
})

-- кнопка меню для телефона
if UserInputService.TouchEnabled then
	local mobileBtn = make("TextButton", {
		Position = UDim2.new(0, 10, 0.4, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.2,
		Text = "BH",
		TextColor3 = C.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Parent = gui,
	})
	corner(mobileBtn, 23)
	mobileBtn.MouseButton1Click:Connect(function()
		win.Visible = not win.Visible
	end)
end

-- загрузка сохранённых настроек
if remote then
	task.spawn(function()
		local ok, success, data = pcall(remote.InvokeServer, remote, "load")
		if ok and success and typeof(data) == "table" then
			for k, v in pairs(data) do
				set(k, v)
			end
			notify("Настройки бхопа загружены")
		end
	end)
end

-- ======================================================================
-- ФИЗИКА БХОПА
-- ======================================================================

local vel = Vector3.zero -- наша горизонтальная скорость
local controlling = false -- переопределяем ли мы скорость Humanoid'а
local wasGrounded = true
local groundTime = 0
local lastJumpPress = -math.huge
local lastLook = nil
local topSpeed = 0
local hops = 0
local lastHumanoid = nil

local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Классическая функция ускорения из Quake/Source.
-- В воздухе wishSpeed режется до cap, но прирост считается от полного wishSpeed —
-- именно это даёт набор скорости стрейфами.
local function accelerate(v, wishDir, wishSpeed, accel, dt, cap)
	local capped = cap and math.min(wishSpeed, cap) or wishSpeed
	local current = v:Dot(wishDir)
	local add = capped - current
	if add <= 0 then
		return v
	end
	local accelSpeed = math.min(accel * wishSpeed * dt, add)
	return v + wishDir * accelSpeed
end

local function applyFriction(v, dt)
	local speed = v.Magnitude
	if speed < 0.01 then
		return Vector3.zero
	end
	local drop = math.max(speed, S.StopSpeed) * S.GroundFriction * dt
	local newSpeed = math.max(speed - drop, 0)
	return v * (newSpeed / speed)
end

local function clampSpeed(v)
	local m = v.Magnitude
	if m > S.MaxSpeed then
		return v * (S.MaxSpeed / m)
	end
	return v
end

local function jumpHeld(hum)
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	return UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		or (UserInputService.TouchEnabled and hum.Jump)
end

local BLOCKED_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local function release()
	controlling = false
end

local function doHop(hum, root, cur)
	local h = S.PreserveSpeed and (controlling and vel or horizontal(cur)) or horizontal(cur)
	h = clampSpeed(h * (1 + S.HopBoost / 100))
	vel = h
	controlling = true
	lastJumpPress = -math.huge
	hops += 1
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = Vector3.new(h.X, S.JumpVelocity, h.Z)
end

local currentFov = nil
local function updateFov(speed, dt, walk)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local target = S.BaseFov
	if S.FovScale and S.Enabled then
		local a = math.clamp((speed - walk) / math.max(S.MaxSpeed - walk, 1), 0, 1)
		target = S.BaseFov + (S.MaxFov - S.BaseFov) * a
	end
	currentFov = currentFov or camera.FieldOfView
	currentFov += (target - currentFov) * math.min(dt * 8, 1)
	camera.FieldOfView = currentFov
end

local function step(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then
		release()
		return
	end
	if hum ~= lastHumanoid then
		lastHumanoid = hum
		release()
		topSpeed, hops = 0, 0
	end

	local cur = root.AssemblyLinearVelocity
	local speedNow = horizontal(cur).Magnitude

	if S.OverrideWalkSpeed and hum.WalkSpeed ~= S.WalkSpeed then
		hum.WalkSpeed = S.WalkSpeed
	end
	local walk = hum.WalkSpeed

	updateFov(speedNow, dt, walk)
	if S.Speedometer then
		topSpeed = math.max(topSpeed, speedNow)
		local a = math.clamp((speedNow - walk) / math.max(S.MaxSpeed - walk, 1), 0, 1)
		speedo.Text = string.format("%d", math.floor(speedNow + 0.5))
		speedo.TextColor3 = C.text:Lerp(Color3.fromRGB(255, 80, 80), a)
		speedoSub.Text = string.format("макс %d   •   прыжков %d%s", math.floor(topSpeed + 0.5), hops, S.Enabled and "" or "   •   ВЫКЛ")
	end

	if not S.Enabled or BLOCKED_STATES[hum:GetState()] or hum.Sit then
		release()
		wasGrounded = true
		return
	end

	-- врезались в стену: берём реальную скорость, иначе будем «липнуть»
	if controlling then
		local actual = horizontal(cur)
		local m = vel.Magnitude
		if m > 5 and actual:Dot(vel.Unit) < m * 0.75 then
			vel = actual
		end
	end

	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local move = hum.MoveDirection
	local now = os.clock()

	if grounded then
		if not wasGrounded then
			groundTime = 0
		end
		groundTime += dt
		wasGrounded = true

		local buffered = now - lastJumpPress <= S.HopWindow
		local wantsHop = (S.AutoHop and jumpHeld(hum)) or buffered

		if wantsHop and groundTime <= math.max(S.HopWindow, dt * 2) + dt then
			doHop(hum, root, cur)
			return
		end

		if controlling then
			if groundTime > S.HopWindow or not S.PreserveSpeed then
				vel = applyFriction(vel, dt)
			end
			if move.Magnitude > 0.01 then
				vel = accelerate(vel, move.Unit, walk * move.Magnitude, S.GroundAccel, dt)
			end
			-- скорость упала до обычной — отдаём управление Humanoid'у
			if vel.Magnitude <= walk + 0.5 then
				release()
			else
				root.AssemblyLinearVelocity = Vector3.new(vel.X, cur.Y, vel.Z)
			end
		end
	else
		wasGrounded = false
		if not controlling then
			vel = horizontal(cur)
			controlling = true
		end

		local camera = workspace.CurrentCamera
		local look = camera and horizontal(camera.CFrame.LookVector)
		local wish = move

		if S.AutoStrafe and move.Magnitude < 0.01 and vel.Magnitude > 1 and look and lastLook and look.Magnitude > 0 then
			local turn = lastLook:Cross(look).Y
			if math.abs(turn) > 1e-5 then
				local right = Vector3.new(-vel.Z, 0, vel.X).Unit
				wish = right * (turn < 0 and 1 or -1)
			end
		end

		if S.AirStrafe and wish.Magnitude > 0.01 then
			vel = accelerate(vel, wish.Unit, walk * math.min(wish.Magnitude, 1), S.AirAccel, dt, S.AirWishCap)
		end
		vel = clampSpeed(vel)
		root.AssemblyLinearVelocity = Vector3.new(vel.X, cur.Y, vel.Z)
		lastLook = look
		return
	end

	local camera = workspace.CurrentCamera
	lastLook = camera and horizontal(camera.CFrame.LookVector) or nil
end

RunService.Heartbeat:Connect(step)

-- ======================================================================
-- ВВОД
-- ======================================================================

local function keyIs(input, name)
	return input.KeyCode == Enum.KeyCode[name]
end

UserInputService.InputBegan:Connect(function(input, processed)
	if waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
		local key = waitingForKey
		waitingForKey = nil
		if input.KeyCode == Enum.KeyCode.Escape then
			set(key, S[key]) -- отмена, просто перерисовать
		else
			set(key, input.KeyCode.Name)
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		if not UserInputService:GetFocusedTextBox() then
			lastJumpPress = os.clock()
		end
	end

	if processed or UserInputService:GetFocusedTextBox() then
		return
	end

	if keyIs(input, S.MenuKey) then
		win.Visible = not win.Visible
	elseif keyIs(input, S.ToggleKey) then
		set("Enabled", not S.Enabled)
	end
end)

-- прыжок с мобильной кнопки (она GUI, поэтому InputBegan её не ловит)
do
	local lastReq = 0
	UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		if UserInputService.TouchEnabled and now - lastReq > 0.15 then
			lastJumpPress = now
		end
		lastReq = now
	end)
end

onChanged = function(key, value)
	if key == "Enabled" then
		notify(value and "Бхоп: ВКЛ" or "Бхоп: ВЫКЛ")
		if not value then
			release()
		end
	end
end

notify(("Бхоп загружен • меню: %s • вкл/выкл: %s"):format(S.MenuKey, S.ToggleKey))

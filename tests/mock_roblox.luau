--!nonstrict
-- tests/mock_roblox: a small stand-in for the Roblox engine so that the UI and feature
-- modules can be executed (not merely compiled) under the standalone Luau CLI.
-- It records property writes, emulates the Instance tree, events and tweens, and
-- provides just enough datatype maths. It is NOT a faithful engine simulation:
-- passing against it proves the code runs and drives the API consistently,
-- not that it renders correctly in a real client.

local import = ...
local M = {}

local realTypeof = typeof
local EVENTS = {}
for _, n in ipairs({
	"InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "MouseButton1Click", "MouseButton1Down",
	"MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "Activated", "Deactivated", "FocusLost", "Focused", "Changed", "ChildAdded",
	"ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying", "AncestryChanged", "Touched", "TouchEnded", "Heartbeat",
	"RenderStepped", "Stepped", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "Died", "WindowFocusReleased",
	"WindowFocused", "Completed", "Ended", "Played", "Paused", "Loaded", "Equipped", "Unequipped", "MouseWheelForward", "MouseWheelBackward",
	"TextChanged", "ViewportSizeChanged", "SelectionGained", "SelectionLost",
}) do
	EVENTS[n] = true
end

local function newSignal()
	local s = { _h = {} }
	function s:Connect(fn)
		local c = { Connected = true }
		c.fn = fn
		function c:Disconnect()
			self.Connected = false
		end
		table.insert(self._h, c)
		return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function s:Wait()
		return nil
	end
	function s:Fire(...)
		for _, c in ipairs(table.clone(self._h)) do
			if c.Connected then
				c.fn(...)
			end
		end
	end
	function s:Count()
		local n = 0
		for _, c in ipairs(self._h) do
			if c.Connected then
				n += 1
			end
		end
		return n
	end
	return s
end
M.newSignal = newSignal

-- Datatypes -------------------------------------------------------------------------

local Vec3 = {}
Vec3.__index = function(t, k)
	if k == "X" then return t.x elseif k == "Y" then return t.y elseif k == "Z" then return t.z end
	if k == "Magnitude" then return math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z) end
	if k == "Unit" then
		local m = math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z)
		if m == 0 then return setmetatable({ x = 0, y = 0, z = 0 }, Vec3) end
		return setmetatable({ x = t.x / m, y = t.y / m, z = t.z / m }, Vec3)
	end
	if k == "Dot" then return function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end end
	if k == "Cross" then return function(a, b) return setmetatable({ x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }, Vec3) end end
	if k == "Lerp" then return function(a, b, f) return setmetatable({ x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = a.z + (b.z - a.z) * f }, Vec3) end end
	return rawget(Vec3, k)
end
local function v3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec3) end
Vec3.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
Vec3.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec3.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.x, a * b.y, a * b.z) end
	if type(b) == "number" then return v3(a.x * b, a.y * b, a.z * b) end
	return v3(a.x * b.x, a.y * b.y, a.z * b.z)
end
Vec3.__div = function(a, b) return v3(a.x / b, a.y / b, a.z / b) end
Vec3.__unm = function(a) return v3(-a.x, -a.y, -a.z) end
Vec3.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end

local Vec2 = {}
Vec2.__index = function(t, k)
	if k == "X" then return t.x elseif k == "Y" then return t.y end
	if k == "Magnitude" then return math.sqrt(t.x * t.x + t.y * t.y) end
	return rawget(Vec2, k)
end
local function v2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, Vec2) end
Vec2.__add = function(a, b) return v2(a.x + b.x, a.y + b.y) end
Vec2.__sub = function(a, b) return v2(a.x - b.x, a.y - b.y) end
Vec2.__mul = function(a, b) if type(b) == "number" then return v2(a.x * b, a.y * b) end if type(a) == "number" then return v2(a * b.x, a * b.y) end return v2(a.x * b.x, a.y * b.y) end
Vec2.__div = function(a, b) return v2(a.x / b, a.y / b) end
Vec2.__eq = function(a, b) return a.x == b.x and a.y == b.y end

local function plain(name)
	return setmetatable({}, { __index = function(_, k) return k end, __tostring = function() return name end })
end

local function makeCFrame(x, y, z)
	local cf = { Position = v3(x, y, z), X = x, Y = y, Z = z }
	cf.LookVector = v3(0, 0, -1)
	cf.UpVector = v3(0, 1, 0)
	cf.RightVector = v3(1, 0, 0)
	setmetatable(cf, {
		__mul = function(a, b)
			if rawget(b, "x") ~= nil then return v3(a.X + b.x, a.Y + b.y, a.Z + b.z) end
			return makeCFrame(a.X + (b.X or 0), a.Y + (b.Y or 0), a.Z + (b.Z or 0))
		end,
		__add = function(a, b) return makeCFrame(a.X + b.x, a.Y + b.y, a.Z + b.z) end,
		__index = function(t, k)
			if k == "Inverse" then return function(self) return makeCFrame(-self.X, -self.Y, -self.Z) end end
			if k == "ToEulerAnglesYXZ" then return function() return 0, 0, 0 end end
			if k == "Lerp" then return function(self, other, f) return makeCFrame(self.X + (other.X - self.X) * f, self.Y + (other.Y - self.Y) * f, self.Z + (other.Z - self.Z) * f) end end
			if k == "PointToWorldSpace" then return function(self, p) return v3(self.X + p.x, self.Y + p.y, self.Z + p.z) end end
			return nil
		end,
	})
	return cf
end

-- Instance -------------------------------------------------------------------------

local GUI_CLASSES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, CanvasGroup = true, ViewportFrame = true }
local PART_CLASSES = { Part = true, MeshPart = true, WedgePart = true, UnionOperation = true, SpawnLocation = true, TrussPart = true }

local createdCount = 0
M.liveCount = 0

local function makeInstance(class)
	createdCount += 1
	M.liveCount += 1
	local props = { Name = class, ClassName = class, Parent = nil, Visible = true, Archivable = true }
	local children = {}
	local events = {}
	local attrs = {}
	local changed = {}
	local inst = {}
	local methods = {}

	local function fireChanged(k)
		local s = changed[k]
		if s then s:Fire() end
		if events.Changed then events.Changed:Fire(k) end
	end

	local function detach()
		local p = props.Parent
		if p then
			local list = p.__children
			for i, c in ipairs(list) do
				if c == inst then
					table.remove(list, i)
					break
				end
			end
			if p.__events.ChildRemoved then p.__events.ChildRemoved:Fire(inst) end
			local anc = p
			while anc do
				if anc.__events.DescendantRemoving then anc.__events.DescendantRemoving:Fire(inst) end
				anc = anc.Parent
			end
		end
	end

	function methods.Destroy()
		if props.__destroyed then return end
		props.__destroyed = true
		if events.Destroying then events.Destroying:Fire() end
		for _, c in ipairs(table.clone(children)) do c:Destroy() end
		detach()
		props.Parent = nil
		M.liveCount -= 1
	end
	function methods.ClearAllChildren()
		for _, c in ipairs(table.clone(children)) do c:Destroy() end
	end
	function methods.GetChildren() return table.clone(children) end
	function methods.GetDescendants()
		local out = {}
		local function walk(n) for _, c in ipairs(n.__children) do table.insert(out, c); walk(c) end end
		walk(inst)
		return out
	end
	function methods.FindFirstChild(_, name, recursive)
		for _, c in ipairs(children) do if c.Name == name then return c end end
		if recursive then
			for _, c in ipairs(children) do local r = c:FindFirstChild(name, true); if r then return r end end
		end
		return nil
	end
	function methods.WaitForChild(self, name) return self:FindFirstChild(name) end
	function methods.FindFirstChildOfClass(_, cls)
		for _, c in ipairs(children) do if c.ClassName == cls then return c end end
		return nil
	end
	function methods.FindFirstChildWhichIsA(_, cls)
		for _, c in ipairs(children) do if c:IsA(cls) then return c end end
		return nil
	end
	function methods.IsA(_, cls)
		if props.ClassName == cls then return true end
		if cls == "GuiObject" then return GUI_CLASSES[props.ClassName] == true end
		if cls == "BasePart" then return PART_CLASSES[props.ClassName] == true end
		if cls == "PVInstance" or cls == "Instance" then return true end
		if cls == "GuiButton" then return props.ClassName == "TextButton" or props.ClassName == "ImageButton" end
		if cls == "LayerCollector" then return props.ClassName == "ScreenGui" end
		return false
	end
	function methods.IsDescendantOf(_, other)
		local p = props.Parent
		while p do
			if p == other then return true end
			p = p.Parent
		end
		return false
	end
	function methods.SetAttribute(_, k, v) attrs[k] = v end
	function methods.GetAttribute(_, k) return attrs[k] end
	function methods.GetPropertyChangedSignal(_, k)
		changed[k] = changed[k] or newSignal()
		return changed[k]
	end
	function methods.Clone()
		local c = makeInstance(class)
		for k, v in pairs(props) do
			if k ~= "Parent" and k ~= "__destroyed" then c[k] = v end
		end
		for _, ch in ipairs(children) do ch:Clone().Parent = c end
		return c
	end
	function methods.Play() props.IsPlaying = true; if events.Played then events.Played:Fire() end end
	function methods.Stop() props.IsPlaying = false; props.TimePosition = 0 end
	function methods.Pause() props.IsPlaying = false end
	function methods.Resume() props.IsPlaying = true end
	function methods.CaptureFocus() props.__focused = true end
	function methods.ReleaseFocus() props.__focused = false end
	function methods.GetMass() return props.__mass or 1 end
	function methods.ApplyImpulse(_, v) props.__impulse = v; props.AssemblyLinearVelocity = v end
	function methods.SetPrimaryPartCFrame(_, cf) props.__pivot = cf end
	function methods.PivotTo(_, cf) props.CFrame = cf; props.Position = cf.Position end
	function methods.GetPivot() return props.CFrame or makeCFrame(0, 0, 0) end
	function methods.GetBoundingBox() return makeCFrame(0, 0, 0), v3(4, 4, 4) end
	function methods.TweenSize() end
	function methods.GetRootPart() return props.HumanoidRootPart end

	setmetatable(inst, {
		__index = function(t, k)
			if k == "__isInstance" then return true end
			if k == "__children" then return children end
			if k == "__props" then return props end
			if k == "__events" then return events end
			local v = props[k]
			if v ~= nil then return v end
			if EVENTS[k] then
				events[k] = events[k] or newSignal()
				return events[k]
			end
			local m = methods[k]
			if m then return function(self, ...) return m(self, ...) end end
			for _, c in ipairs(children) do
				if rawget(c, "Name") == nil and c.Name == k then return c end
			end
			if PART_CLASSES[props.ClassName] then
				if k == "Transparency" or k == "LocalTransparencyModifier" then return 0 end
				if k == "CFrame" then return makeCFrame(0, 0, 0) end
				if k == "Position" then return v3(0, 0, 0) end
				if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then return v3(0, 0, 0) end
			if k == "Size" then return v3(4, 1, 2) end
			if k == "Shape" then return "Block" end
			if k == "CanCollide" then return true end
			end
			if k == "AbsoluteSize" then return v2(props.__w or 200, props.__h or 40) end
			if k == "AbsolutePosition" then return v2(0, 0) end
			if k == "TextBounds" then return v2(#(tostring(props.Text or "")) * 7, 14) end
			if k == "AbsoluteContentSize" then return v2(0, 100) end
			if k == "AbsoluteWindowSize" then return v2(props.__w or 200, props.__h or 300) end
			if k == "AbsoluteCanvasSize" then return v2(props.__w or 200, 600) end
			if k == "CanvasPosition" then return v2(0, 0) end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "Parent" then
				if v == props.Parent then return end
				detach()
				props.Parent = v
				if v then
					table.insert(v.__children, inst)
					if v.__events.ChildAdded then v.__events.ChildAdded:Fire(inst) end
					-- like the engine, DescendantAdded fires on every ancestor
					local anc = v
					while anc do
						if anc.__events.DescendantAdded then anc.__events.DescendantAdded:Fire(inst) end
						anc = rawget(anc, "__noparent") and nil or anc.Parent
					end
				end
				return
			end
			if k == "Name" and type(v) ~= "string" then error("Name must be string") end
			props[k] = v
			if k == "CFrame" and type(v) == "table" and rawget(v, "Position") then props.Position = v.Position end
			if k == "Position" and type(v) == "table" and rawget(v, "x") ~= nil and props.ClassName ~= "Attachment" then props.CFrame = makeCFrame(v.x, v.y, v.z) end
			fireChanged(k)
		end,
	})
	return inst
end

-- Services ---------------------------------------------------------------------------

local function newGame()
	local game = {}
	local services = {}
	local function svc(name)
		local s = services[name]
		if s then return s end
		s = makeInstance(name)
		services[name] = s
		return s
	end
	local players = svc("Players")
	local lp = makeInstance("Player")
	lp.Name = "LocalPlayer"
	lp.UserId = 1
	lp.CameraMaxZoomDistance = 128
	lp.CameraMinZoomDistance = 0.5
	lp.CameraMode = "Classic"
	lp.GetNetworkPing = function() return 0.045 end
	local backpack = makeInstance("Backpack"); backpack.Parent = lp
	lp.Backpack = backpack
	players.LocalPlayer = lp
	players.GetPlayers = function() return { lp } end

	local char = makeInstance("Model"); char.Name = "Character"
	local hum = makeInstance("Humanoid"); hum.Parent = char; hum.WalkSpeed = 16; hum.CameraOffset = v3(0, 0, 0); hum.MoveDirection = v3(0, 0, 0)
	hum.Health = 100; hum.MaxHealth = 100
	local hrp = makeInstance("Part"); hrp.Name = "HumanoidRootPart"; hrp.Parent = char; hrp.CFrame = makeCFrame(0, 5, 0); hrp.Position = v3(0, 5, 0); hrp.AssemblyLinearVelocity = v3(0, 0, 0)
	local head = makeInstance("Part"); head.Name = "Head"; head.Parent = char
	local torso = makeInstance("Part"); torso.Name = "UpperTorso"; torso.Parent = char
	char.PrimaryPart = hrp
	char.Parent = svc("Workspace")
	lp.Character = char

	local ws = svc("Workspace")
	local cam = makeInstance("Camera")
	cam.ViewportSize = v2(1280, 720)
	cam.CFrame = makeCFrame(0, 10, 20)
	cam.Focus = makeCFrame(0, 5, 0)
	cam.FieldOfView = 70
	cam.CameraType = "Custom"
	cam.Parent = ws
	ws.CurrentCamera = cam
	ws.Raycast = function() return nil end
	ws.GetPartBoundsInRadius = function(_, pos, radius, params)
		local out = {}
		local scene = params and params.FilterDescendantsInstances and params.FilterDescendantsInstances[1]
		if scene then
			for _, d in ipairs(scene:GetDescendants()) do
				if d:IsA("BasePart") then
					local dp = d.Position
					local dx, dy, dz = dp.X - pos.X, dp.Y - pos.Y, dp.Z - pos.Z
					local half = (d.Size and d.Size.X or 1) / 2
					if math.sqrt(dx * dx + dy * dy + dz * dz) <= radius + half then table.insert(out, d) end
				end
			end
		end
		return out
	end
	ws.Gravity = 196.2
	cam.ViewportPointToRay = function(_, x, y) return { Origin = v3(0, 10, 20), Direction = v3(0, 0, -1) } end
	cam.WorldToViewportPoint = function(self, p)
		local c = self.CFrame.Position
		local depth = c.z - p.z -- the mock camera always looks down -Z
		if depth <= 0.001 then return v3(0, 0, depth), false end
		local f = 800
		local x, y = 640 + (p.x - c.x) / depth * f, 360 - (p.y - c.y) / depth * f
		return v3(x, y, depth), x >= 0 and x <= 1280 and y >= 0 and y <= 720
	end

	local lighting = svc("Lighting")
	lighting.Brightness = 2; lighting.ClockTime = 14; lighting.Ambient = { r = 0 }; lighting.OutdoorAmbient = {}; lighting.FogEnd = 100000

	local uis = svc("UserInputService")
	uis.MouseDeltaSensitivity = 1
	uis.MouseIconEnabled = true
	uis.GetFocusedTextBox = function() return nil end
	uis.GetMouseLocation = function() return v2(640, 360) end
	uis.IsKeyDown = function() return false end
	uis.TouchEnabled = false
	uis.KeyboardEnabled = true
	uis.MouseBehavior = "Default"

	local rs = svc("RunService")
	rs.BindToRenderStep = function() end
	rs.UnbindFromRenderStep = function() end
	rs.IsStudio = function() return false end

	local ts = svc("TweenService")
	ts.Create = function(_, inst, info, goal)
		local tw = { PlaybackState = "Begin" }
		tw.Completed = newSignal()
		function tw:Play()
			for k, v in pairs(goal) do inst[k] = v end
			self.Completed:Fire("Completed")
		end
		function tw:Cancel() end
		function tw:Pause() end
		function tw:Destroy() end
		return tw
	end

	local sg = svc("StarterGui")
	sg.SetCore = function() end
	local cas = svc("ContextActionService")
	cas.BindActionAtPriority = function(_, name, fn) cas.__bound = cas.__bound or {}; cas.__bound[name] = fn end
	cas.UnbindAction = function(_, name) if cas.__bound then cas.__bound[name] = nil end end
	svc("CoreGui"); svc("SoundService"); svc("HttpService"); svc("Debris"); svc("TextService"); svc("GuiService")
	svc("Debris").AddItem = function(self, item) self.__items = self.__items or {}; table.insert(self.__items, item) end
	svc("TextService").GetTextSize = function(_, text, size) return v2(#text * size * 0.5, size) end
	svc("GuiService").GetGuiInset = function() return v2(0, 36), v2(0, 0) end
	players.LocalPlayer.PlayerGui = makeInstance("PlayerGui")
	players.LocalPlayer.PlayerGui.Parent = lp

	game.GetService = function(_, name) return svc(name) end
	game.GetObjects = function(_, url)
		if string.find(url, "bad") then error("asset could not be loaded") end
		local model = makeInstance("Model"); model.Name = "Loaded"
		local part = makeInstance("Part"); part.Name = "Body"; part.Parent = model
		return { model }
	end
	game.Players = players
	game.Workspace = ws
	game.Lighting = lighting
	game.PlaceId = 142823291 -- MM2 place id is irrelevant to the mock
	game.IsLoaded = function() return true end
	game.__services = services
	return game
end

-- install / uninstall ----------------------------------------------------------------------

local GLOBALS = {}
local saved = {}
local installed = false

function M.install()
	if installed then return M.game end
	installed = true
	local game = newGame()
	M.game = game
	local Enum = setmetatable({}, {
		__index = function(t, enumName)
			local items = setmetatable({}, {
				__index = function(it, itemName)
					local v = setmetatable({ Name = itemName, EnumType = enumName, Value = 0 }, { __tostring = function() return enumName .. "." .. itemName end })
					rawset(it, itemName, v)
					return v
				end,
			})
			rawset(t, enumName, items)
			return items
		end,
	})
	local function UDim2New(sx, ox, sy, oy) return { X = { Scale = sx or 0, Offset = ox or 0 }, Y = { Scale = sy or 0, Offset = oy or 0 }, kind = "UDim2" } end
	local function color(r, g, b)
		local c = { R = r, G = g, B = b, r = r, g = g, b = b, kind = "Color3" }
		c.Lerp = function(a, o, f) return color(a.R + (o.R - a.R) * f, a.G + (o.G - a.G) * f, a.B + (o.B - a.B) * f) end
		return c
	end
	GLOBALS = {
		game = game,
		workspace = game.Workspace,
		Enum = Enum,
		Instance = { new = function(class, parent) local i = makeInstance(class); if parent then i.Parent = parent end return i end },
		Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), yAxis = v3(0, 1, 0), xAxis = v3(1, 0, 0), zAxis = v3(0, 0, 1) },
		Vector2 = { new = v2, zero = v2(0, 0) },
		UDim2 = { new = UDim2New, fromOffset = function(x, y) return UDim2New(0, x, 0, y) end, fromScale = function(x, y) return UDim2New(x, 0, y, 0) end },
		UDim = { new = function(s, o) return { Scale = s, Offset = o } end },
		Color3 = {
			new = color, fromRGB = function(r, g, b) return color(r / 255, g / 255, b / 255) end,
			fromHSV = function(h, s, v) return color(h, s, v) end,
		},
		CFrame = {
			new = function(x, y, z) if type(x) == "table" then return makeCFrame(x.x, x.y, x.z) end return makeCFrame(x or 0, y or 0, z or 0) end,
			Angles = function() return makeCFrame(0, 0, 0) end,
			lookAt = function(a, b) local c = makeCFrame(a.x, a.y, a.z); c.LookVector = (b - a).Unit; return c end,
			identity = makeCFrame(0, 0, 0),
			fromMatrix = function(pos) return makeCFrame(pos.x, pos.y, pos.z) end, -- translation-only like the rest of the mock
		},
		TweenInfo = { new = function(t, style, dir) return { Time = t, EasingStyle = style, EasingDirection = dir } end },
		ColorSequence = { new = function(...) return { kind = "ColorSequence", ... } end },
		ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end },
		NumberSequence = { new = function(...) return { kind = "NumberSequence", ... } end },
		NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end },
		NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end },
		Rect = { new = function(a, b, c, d) return { a, b, c, d } end },
		RaycastParams = { new = function() return {} end },
		OverlapParams = { new = function() return {} end },
		Random = { new = function() return { NextNumber = function(_, a, b) return (a or 0) + math.random() * ((b or 1) - (a or 0)) end, NextInteger = function(_, a, b) return math.random(a, b) end } end },
		Font = { fromEnum = function(e) return e end, new = function() return {} end },
		PhysicalProperties = { new = function() return {} end },
		Region3 = { new = function() return {} end },
		tick = function() return os.clock() end,
		warn = function() end,
	}
	GLOBALS.typeof = function(v)
		if type(v) == "table" then
			if rawget(v, "__isInstance") ~= nil or (getmetatable(v) and v.__isInstance) then return "Instance" end
			if getmetatable(v) == Vec3 then return "Vector3" end
			if getmetatable(v) == Vec2 then return "Vector2" end
		end
		return realTypeof(v)
	end
	for k, v in pairs(GLOBALS) do
		saved[k] = rawget(getfenv(), k)
		getfenv()[k] = v
	end
	return game
end

function M.uninstall()
	if not installed then return end
	installed = false
	for k in pairs(GLOBALS) do
		getfenv()[k] = saved[k]
	end
	GLOBALS, saved = {}, {}
	import("core/Services").clear()
end

function M.makeInstance(class)
	return GLOBALS.Instance.new(class)
end

M.v3 = v3
M.v2 = v2
return M

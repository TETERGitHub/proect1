--!nonstrict
-- features/Crosshair: draws the custom crosshair from six reusable Frames (4 arms, ring, dot).
-- Objects are created once and only their properties change; a single Perf task handles
-- the optional dynamic spread. Geometry comes from the pure CrosshairLayout module.
-- STATUS: implemented; verified against the mock layer only.
-- Depends on: Settings, Perf, Env, Services, CrosshairLayout.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Services = import("core/Services")
local Layout = import("features/CrosshairLayout")
local CI = import("features/CrosshairImage")
local MouseIcon = import("core/MouseIcon")
local Logger = import("core/Logger")

local Crosshair = {}

local KEYS = {
	"enabled", "style", "size", "thickness", "gap", "color", "opacity", "centerDot", "dotSize",
	"outline", "dynamic", "dynamicAmount", "offsetX", "offsetY", "hideCursor", "design", "imageSize", "spin", "pulse", "glow",
}

local state = nil

local function s(name)
	return Settings.get("crosshair." .. name)
end

local function makeFrame(parent, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Visible = false
	f.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = f
	return f, stroke
end

local function localSpeed()
	local player = Services.Players.LocalPlayer
	local char = player and player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return 0, 16
	end
	local v = root.AssemblyLinearVelocity
	local hum = char:FindFirstChildOfClass("Humanoid")
	return math.sqrt(v.X * v.X + v.Z * v.Z), hum and hum.WalkSpeed or 16
end

-- render(spread): positions every element for the current settings.
local function render(spread)
	local st = state
	if not st then
		return
	end
	local enabled = s("enabled")
	st.root.Visible = enabled
	if not enabled then
		return
	end
	local c = s("color")
	local color = Color3.fromRGB(c.r, c.g, c.b)
	local transparency = 1 - s("opacity")
	local outline = s("outline")
	st.root.Position = UDim2.new(0.5, s("offsetX"), 0.5, s("offsetY"))
	-- a drawn design (our own textures): replaces the line crosshair while it can be shown
	local design = s("design")
	if CI.has(design) and CI.apply(st.images, {
		design = design, size = s("imageSize") + spread * 2, color = color, transparency = transparency, outline = outline,
		glow = s("glow"), rotation = (st.t * s("spin")) % 360, scale = s("pulse") and (1 + 0.08 * math.sin(st.t * 5)) or 1,
	}) then
		for _, e in pairs(st.elements) do
			e.frame.Visible = false
		end
		return
	end
	CI.hide(st.images)
	local layout = Layout.compute({
		style = s("style"), size = s("size"), thickness = s("thickness"), gap = s("gap"),
		centerDot = s("centerDot"), dotSize = s("dotSize"), spread = spread,
	})

	for _, id in ipairs({ "top", "bottom", "left", "right" }) do
		st.elements[id].frame.Visible = false
	end
	for _, r in ipairs(layout.rects) do
		local e = st.elements[r.id]
		e.frame.Visible = true
		e.frame.Size = UDim2.fromOffset(r.w, r.h)
		e.frame.Position = UDim2.fromOffset(r.x, r.y)
		e.frame.BackgroundColor3 = color
		e.frame.BackgroundTransparency = transparency
		e.stroke.Enabled = outline
		e.stroke.Transparency = math.min(1, transparency + 0.15)
	end
	local ring = st.elements.ring
	if layout.circle then
		local d = layout.circle.radius * 2
		ring.frame.Visible = true
		ring.frame.Size = UDim2.fromOffset(d, d)
		ring.frame.Position = UDim2.fromOffset(0, 0)
		ring.frame.BackgroundTransparency = 1
		ring.stroke.Enabled = true
		ring.stroke.Color = color
		ring.stroke.Thickness = layout.circle.thickness
		ring.stroke.Transparency = transparency
	else
		ring.frame.Visible = false
	end
	local dot = st.elements.dot
	if layout.dot then
		local d = layout.dot.size
		dot.frame.Visible = true
		dot.frame.Size = UDim2.fromOffset(d, d)
		dot.frame.Position = UDim2.fromOffset(0, 0)
		dot.frame.BackgroundColor3 = color
		dot.frame.BackgroundTransparency = transparency
		dot.stroke.Enabled = outline
		dot.stroke.Transparency = math.min(1, transparency + 0.15)
	else
		dot.frame.Visible = false
	end
end

-- the game's own crosshair / mouse icon goes away while ours is on. While the menu is open the system icon stays (unless the
-- menu draws its own cursor), so you can still click.
local function applyCursor()
	local want = s("enabled") and s("hideCursor") and not (MouseIcon.menuOpen and not Settings.get("ui.cursor"))
	MouseIcon.hide("crosshair", want == true)
	if want then
		MouseIcon.enforce() -- MM2 / shift-lock switch the icon back on when you equip a gun or turn the camera
	end
end

-- start(ctx{maid})
function Crosshair.start(ctx)
	assert(state == nil, "Crosshair already started")
	local parent, how = Env.guiParent()
	if not parent then
		error("no GUI container available for the crosshair")
	end
	Logger.info("Crosshair", "GUI container: %s", how)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubCrosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	ctx.maid:Give(gui)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(0, 0)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Visible = false
	root.Parent = gui

	local elements = {}
	for _, id in ipairs({ "top", "bottom", "left", "right", "ring", "dot" }) do
		local f, stroke = makeFrame(root, id)
		elements[id] = { frame = f, stroke = stroke }
	end
	elements.ring.stroke.Enabled = true
	elements.dot.frame.BackgroundTransparency = 0
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = elements.dot.frame
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = elements.ring.frame

	state = { gui = gui, root = root, elements = elements, images = CI.new(root), spread = 0, t = 0, dirty = true }
	ctx.maid:Give(function()
		MouseIcon.hide("crosshair", false)
		state = nil
	end)

	for _, k in ipairs(KEYS) do
		ctx.maid:Give(Settings.observe("crosshair." .. k, function()
			state.dirty = true
			applyCursor()
		end))
	end

	local handle = Perf.every("crosshair", 60, function(dt)
		local st = state
		if not st then
			return
		end
		local enabled = s("enabled")
		st.t += dt
		applyCursor()
		if enabled and CI.has(s("design")) and (s("spin") ~= 0 or s("pulse")) then
			st.dirty = true -- turning / pulsing design
		end
		if enabled and s("dynamic") then
			local speed, max = localSpeed()
			local target = Layout.spread(speed, max, s("dynamicAmount"))
			local prev = st.spread
			st.spread = prev + (target - prev) * math.min(1, dt * 12)
			if math.abs(st.spread - prev) > 0.02 then
				st.dirty = true
			end
		elseif st.spread ~= 0 then
			st.spread = 0
			st.dirty = true
		end
		if st.dirty then
			st.dirty = false
			render(st.spread)
		end
	end, { visual = true })
	ctx.maid:Give(handle.Cancel)

	applyCursor()
	render(0)
end

-- Test/diagnostic helpers ---------------------------------------------------------------------

function Crosshair.isRunning()
	return state ~= nil
end

function Crosshair.elementCount()
	if not state or not state.root.Visible then
		return 0
	end
	local n = 0
	for _, e in pairs(state.elements) do
		if e.frame.Visible then
			n += 1
		end
	end
	for _, im in pairs(state.images) do
		if im.Visible then
			n += 1
		end
	end
	return n
end

function Crosshair.refresh()
	if state then
		state.dirty = true
	end
end

return Crosshair

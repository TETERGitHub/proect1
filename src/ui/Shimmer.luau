--!nonstrict
-- ui/Shimmer: animated ("flowing") colour for a text label or any GUI object, through a UIGradient on it.
-- Styles: Off (one plain colour), Wave (your colours flow across the text), Rainbow (the full spectrum flows), Pulse (the whole
-- text breathes between your colours), Chrome (silver bands slide over it), Neon (bright colour with a flickering glow band).
-- Directions: Right, Left, Up, Down, Diagonal, Spin (the gradient turns round). Speed is a factor (1 = one pass in ~2.5 s).
-- A config is read every frame through getConfig(), so changing a setting takes effect at once. Frozen (but still coloured) when
-- animations are off or in the low load profile.
-- Depends on: Perf, Motion.

local import = ...
local Perf = import("core/Perf")
local Motion = import("ui/Motion")

local Shimmer = {}

Shimmer.STYLES = { "Off", "Wave", "Rainbow", "Pulse", "Chrome", "Neon" }
Shimmer.DIRECTIONS = { "Right", "Left", "Up", "Down", "Diagonal", "Spin" }

local ROTATION = { Right = 0, Left = 180, Down = 90, Up = 270, Diagonal = 35, Spin = 0 }
local nextId = 0

local function c3(c)
	if typeof and typeof(c) == "Color3" then
		return c
	end
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- sequence(style, colors, phase) -> ColorSequence. colors = list of Color3 (1..3). phase 0..1 for Pulse.
function Shimmer.sequence(style, colors, phase)
	local K = ColorSequenceKeypoint.new
	local a, b, c = colors[1], colors[2] or colors[1], colors[3] or colors[2] or colors[1]
	if style == "Rainbow" then
		local pts = {}
		for i = 0, 6 do
			table.insert(pts, K(i / 6, Color3.fromHSV((i / 6) % 1, 0.75, 1)))
		end
		return ColorSequence.new(pts)
	elseif style == "Chrome" then
		local rgb = Color3.fromRGB
		return ColorSequence.new({ K(0, rgb(255, 255, 255)), K(0.25, rgb(140, 144, 154)), K(0.5, rgb(255, 255, 255)),
			K(0.75, rgb(110, 114, 124)), K(1, rgb(255, 255, 255)) })
	elseif style == "Pulse" then
		local t = 0.5 - 0.5 * math.cos((phase or 0) * 2 * math.pi)
		local col = a:Lerp(b, t)
		return ColorSequence.new(col, col)
	elseif style == "Neon" then
		local white = Color3.fromRGB(255, 255, 255)
		return ColorSequence.new({ K(0, a), K(0.42, a), K(0.5, a:Lerp(white, 0.75)), K(0.58, a), K(1, a) })
	elseif style == "Wave" then
		-- periodic: starts and ends with the first colour so the loop has no seam
		return ColorSequence.new({ K(0, a), K(0.25, b), K(0.5, c), K(0.75, b), K(1, a) })
	end
	return ColorSequence.new(a, a)
end

-- attach(inst, maid, getConfig) -> UIGradient
-- getConfig() -> { style = "Wave", direction = "Right", speed = 1, colors = { Color3 or {r,g,b}, ... } }
-- For a TextLabel set TextColor3 to white yourself: the gradient multiplies it.
function Shimmer.attach(inst, maid, getConfig)
	local g = Instance.new("UIGradient")
	g.Name = "Shimmer"
	g.Parent = inst
	maid:Give(g)
	nextId += 1
	local t = 0
	local lastKey = nil
	local handle = Perf.every("ui.shimmer." .. nextId, 30, function(dt)
		local cfg = getConfig()
		local colors = {}
		for i, col in ipairs(cfg.colors or {}) do
			colors[i] = c3(col)
		end
		if #colors == 0 then
			colors[1] = Color3.fromRGB(255, 255, 255)
		end
		local style = cfg.style or "Off"
		local moving = Motion.enabled() and style ~= "Off"
		if moving then
			t += dt * (cfg.speed or 1) * 0.4
		end
		local phase = t % 1
		-- rebuild the colour sequence only when it changes (Pulse changes every frame, the others only on a setting change)
		local key = style .. "|" .. tostring(colors[1]) .. tostring(colors[2]) .. tostring(colors[3])
		if style == "Pulse" or key ~= lastKey then
			lastKey = key
			g.Color = Shimmer.sequence(style, colors, phase)
		end
		local dir = cfg.direction or "Right"
		if dir == "Spin" then
			g.Rotation = (phase * 360) % 360
			g.Offset = Vector2.new(0, 0)
		else
			g.Rotation = ROTATION[dir] or 0
			if style == "Off" or style == "Pulse" then
				g.Offset = Vector2.new(0, 0)
			else
				-- slide from -1 to 1: at both ends the text shows the sequence's edge colour, so the jump back is invisible
				g.Offset = Vector2.new(phase * 2 - 1, 0)
			end
		end
	end, { visual = true })
	maid:Give(handle.Cancel)
	return g
end

return Shimmer

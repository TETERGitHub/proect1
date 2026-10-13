--!nonstrict
-- ui/Icons: renders icons from data/IconData primitives using plain Frames (no image assets).
-- Depends on: IconData, Theme.

local import = ...
local IconData = import("data/IconData")
local Theme = import("ui/Theme")

local Icons = {}

local drawn = setmetatable({}, { __mode = "k" }) -- container -> list of {inst, prop}

function Icons.names()
	local out = {}
	for name in pairs(IconData) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

function Icons.has(name)
	return IconData[name] ~= nil
end

local function bindColor(inst, prop, token)
	Theme.bind(inst, prop, token)
end

-- draw(parent, name, px, token) -> container Frame (px x px, transparent)
function Icons.draw(parent, name, px, token)
	local prims = IconData[name] or IconData.info
	local k = px / 24
	local box = Instance.new("Frame")
	box.Name = "Icon_" .. name
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(px, px)
	local parts = {}
	for _, p in ipairs(prims) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(p[2] * k, p[3] * k)
		if p[1] == "r" then
			f.Size = UDim2.fromOffset(math.max(1, p[4] * k), math.max(1, p[5] * k))
			f.Rotation = p[6] or 0
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, (p[7] or 0) * k)
			c.Parent = f
			bindColor(f, "BackgroundColor3", token)
			table.insert(parts, { f, "BackgroundColor3" })
		elseif p[1] == "d" then
			f.Size = UDim2.fromOffset(p[4] * k, p[4] * k)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			bindColor(f, "BackgroundColor3", token)
			table.insert(parts, { f, "BackgroundColor3" })
		else -- ring
			f.Size = UDim2.fromOffset(p[4] * k, p[4] * k)
			f.BackgroundTransparency = 1
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			local s = Instance.new("UIStroke")
			s.Thickness = math.max(1, p[5] * k)
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = f
			bindColor(s, "Color", token)
			table.insert(parts, { s, "Color" })
		end
		f.Parent = box
	end
	drawn[box] = parts
	box.Parent = parent
	return box
end

-- recolor(container, token): re-bind every shape to another colour token (active/inactive states)
function Icons.recolor(container, token)
	local parts = drawn[container]
	if not parts then
		return
	end
	for _, part in ipairs(parts) do
		bindColor(part[1], part[2], token)
	end
end

return Icons

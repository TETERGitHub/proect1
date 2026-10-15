--!nonstrict
-- ui/Icons: draws the hub icons: the detailed sprite sheet when bundled images load, else data/IconData primitives (plain Frames).
-- Depends on: IconData, IconSheet, Theme, Flair (sheet image).

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
-- The detailed icons: one anti-aliased sprite sheet drawn by tools/make_icons.py (data/IconSheet + assets/ui/icons.png in
-- data/UiPack). Used whenever the executor can show bundled images; otherwise the primitive shapes below are drawn.
local Sheet = import("data/IconSheet")

local function sheetUrl()
	local ok, url = pcall(function()
		return import("ui/Flair").image("icons.png")
	end)
	return ok and url or nil
end

function Icons.draw(parent, name, px, token)
	local idx = Sheet.index[name] or (not IconData[name] and Sheet.index.info) or nil
	local url = idx and sheetUrl()
	if url then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon_" .. name
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Size = UDim2.fromOffset(px, px)
		img.Image = url
		img.ImageRectSize = Vector2.new(Sheet.cell, Sheet.cell)
		img.ImageRectOffset = Vector2.new((idx % Sheet.cols) * Sheet.cell, (idx // Sheet.cols) * Sheet.cell)
		img.ScaleType = Enum.ScaleType.Fit
		bindColor(img, "ImageColor3", token)
		drawn[img] = { { img, "ImageColor3" } }
		img.Parent = parent
		return img
	end
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
	if p[1] == "b" then
		-- rounded-rectangle outline
		f.Size = UDim2.fromOffset(p[4] * k, p[5] * k)
		f.BackgroundTransparency = 1
		f.Rotation = p[8] or 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, (p[7] or 0) * k)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Thickness = math.max(1, p[6] * k)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		bindColor(s, "Color", token)
		table.insert(parts, { s, "Color" })
	elseif p[1] == "a" then
		-- half ring: a full ring inside a clipping frame that shows only one half
		local d = p[4] * k
		local side = p[6] or "r"
		f.BackgroundTransparency = 1
		f.ClipsDescendants = true
		local horizontal = side == "r" or side == "l"
		f.Size = horizontal and UDim2.fromOffset(d / 2 + p[5] * k, d + 2 * p[5] * k) or UDim2.fromOffset(d + 2 * p[5] * k, d / 2 + p[5] * k)
		-- the frame is centred on the half it shows
		local shift = d / 4 + p[5] * k / 2
		if side == "r" then
			f.Position = UDim2.fromOffset(p[2] * k + shift, p[3] * k)
		elseif side == "l" then
			f.Position = UDim2.fromOffset(p[2] * k - shift, p[3] * k)
		elseif side == "t" then
			f.Position = UDim2.fromOffset(p[2] * k, p[3] * k - shift)
		else
			f.Position = UDim2.fromOffset(p[2] * k, p[3] * k + shift)
		end
		local ring = Instance.new("Frame")
		ring.BorderSizePixel = 0
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Size = UDim2.fromOffset(d, d)
		-- place the ring's centre on the ring centre (the clip frame's own centre is shift away from it)
		local ox = side == "r" and -shift or (side == "l" and shift or 0)
		local oy = side == "b" and -shift or (side == "t" and shift or 0)
		ring.Position = UDim2.new(0.5, ox, 0.5, oy)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ring
		local s = Instance.new("UIStroke")
		s.Thickness = math.max(1, p[5] * k)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = ring
		bindColor(s, "Color", token)
		table.insert(parts, { s, "Color" })
		ring.Parent = f
	elseif p[1] == "t" then
		-- a single bold glyph
		f.Size = UDim2.fromOffset(p[4] * k * 1.4, p[4] * k * 1.4)
		f.BackgroundTransparency = 1
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Text = p[5]
		l.TextSize = math.max(8, math.floor(p[4] * k))
		l.Font = Enum.Font.GothamBold
		bindColor(l, "TextColor3", token)
		table.insert(parts, { l, "TextColor3" })
		l.Parent = f
	elseif p[1] == "r" then
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

--!nonstrict
-- features/CrosshairImage: the textured crosshair designs (setting crosshair.design), drawn for this project by
-- tools/make_crosshairs.py into three sheets of 4 x 3 cells (crosshairs.png, crosshairs_outline.png, crosshairs_glow.png in
-- data/FxPack). One set of three ImageLabels (glow behind, dark outline, the shape tinted with your colour) shows one cell.
-- Used by the in-game crosshair (features/Crosshair) and by the preview card on the Crosshair page, so both look the same.
-- Without getcustomasset the images cannot be shown; apply() then returns false and the caller draws the line crosshair.
-- Depends on: FxKit.

local import = ...
local FxKit = import("features/FxKit")

local CI = {}

-- order = the cells of the sheets (tools/make_crosshairs.py NAMES)
CI.DESIGNS = { "Sniper", "Tactical", "Diamond", "Chevron", "Hexagon", "Star", "Brackets", "Tri", "Segments", "Scope", "Heart", "X" }
local CELL, COLS = 256, 4

local index = {}
for i, n in ipairs(CI.DESIGNS) do
	index[n] = i
end

function CI.has(design)
	return index[design] ~= nil
end

local function label(parent, name, z)
	local im = Instance.new("ImageLabel")
	im.Name = name
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.ImageRectSize = Vector2.new(CELL, CELL)
	im.ZIndex = z
	im.Visible = false
	im.Parent = parent
	return im
end

-- new(parent) -> set of image labels centred on parent
function CI.new(parent)
	return { glow = label(parent, "XhGlow", 1), outline = label(parent, "XhOutline", 2), main = label(parent, "XhMain", 3) }
end

function CI.hide(set)
	set.glow.Visible, set.outline.Visible, set.main.Visible = false, false, false
end

-- apply(set, o) -> true when the design is shown. o: design, size (px, whole crosshair), color (Color3), transparency (0-1),
-- outline (bool), glow (bool), rotation (degrees), scale (multiplier, pulse / spread)
function CI.apply(set, o)
	local i = index[o.design or ""]
	local main, outl, glow = FxKit.asset("crosshairs.png"), FxKit.asset("crosshairs_outline.png"), FxKit.asset("crosshairs_glow.png")
	if not i or not main then
		CI.hide(set)
		return false
	end
	local off = Vector2.new(((i - 1) % COLS) * CELL, math.floor((i - 1) / COLS) * CELL)
	local px = math.max(4, (o.size or 48) * (o.scale or 1))
	local tr = math.clamp(o.transparency or 0, 0, 1)
	local function put(im, url, color, t, on)
		im.Visible = on and url ~= nil
		if not im.Visible then
			return
		end
		im.Image = url
		im.ImageRectOffset = off
		im.Size = UDim2.fromOffset(px, px)
		im.Rotation = o.rotation or 0
		im.ImageColor3 = color
		im.ImageTransparency = t
	end
	put(set.main, main, o.color or Color3.fromRGB(255, 255, 255), tr, true)
	put(set.outline, outl, Color3.fromRGB(0, 0, 0), math.min(1, tr + 0.25), o.outline == true)
	put(set.glow, glow, o.color or Color3.fromRGB(255, 255, 255), math.min(1, 0.35 + tr * 0.65), o.glow == true)
	return true
end

return CI

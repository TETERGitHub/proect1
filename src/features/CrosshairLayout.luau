--!nonstrict
-- features/CrosshairLayout: pure geometry of the crosshair (no Roblox APIs).
-- All coordinates are pixels relative to the crosshair centre.

local Layout = {}

local function round(n)
	return math.floor(n + 0.5)
end

-- spread(speed, maxSpeed, amount) -> extra gap in pixels
function Layout.spread(speed, maxSpeed, amount)
	if maxSpeed <= 0 then
		return 0
	end
	return amount * math.max(0, math.min(1, speed / maxSpeed))
end

-- compute(cfg) -> {rects = {{id,x,y,w,h}}, circle = {radius, thickness}|nil, dot = {size}|nil}
-- cfg = {style, size, thickness, gap, centerDot, dotSize, spread}
function Layout.compute(cfg)
	local style = cfg.style
	local t = math.max(1, round(cfg.thickness))
	local size = math.max(1, round(cfg.size))
	local gap = round(cfg.gap + (cfg.spread or 0))
	local out = { rects = {}, circle = nil, dot = nil }

	local function arms()
		local d = gap + size / 2
		table.insert(out.rects, { id = "top", x = 0, y = -d, w = t, h = size })
		table.insert(out.rects, { id = "bottom", x = 0, y = d, w = t, h = size })
		table.insert(out.rects, { id = "left", x = -d, y = 0, w = size, h = t })
		table.insert(out.rects, { id = "right", x = d, y = 0, w = size, h = t })
	end

	if style == "Cross" then
		arms()
	elseif style == "CrossCircle" then
		arms()
		out.circle = { radius = gap + size + t + 2, thickness = t }
	elseif style == "Circle" then
		out.circle = { radius = math.max(2, size + gap), thickness = t }
	elseif style == "Dot" then
		out.dot = { size = math.max(cfg.dotSize, t) }
	end
	if cfg.centerDot and style ~= "Dot" then
		out.dot = { size = math.max(1, round(cfg.dotSize)) }
	end
	return out
end

-- Number of Frame-like elements the layout needs (for object budgeting).
function Layout.elementCount(layout)
	return #layout.rects + (layout.circle and 1 or 0) + (layout.dot and 1 or 0)
end

return Layout

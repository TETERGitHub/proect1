--!nonstrict
-- data/ShahedSpec: procedural delta-wing loitering-drone model, described as plain data.
-- Built only from Part primitives (no meshes, no uploaded assets). Coordinates are model-local
-- studs: the nose points toward -Z, +Y is up, +X is the right wing.
--   part = {name, shape, size{x,y,z}, pos{x,y,z}, rot{x,y,z degrees}, color{r,g,b}, material, accent?, spin?, glow?}
-- shape: "Block" | "Ball" | "Cylinder" (a Cylinder's length is along X before rotation; rot.y=90 aligns it to Z)

local BODY = { 178, 174, 160 }
local WING = { 168, 165, 152 }
local DARK = { 58, 60, 66 }

local parts = {}
local function add(p)
	table.insert(parts, p)
end

local function cyl(name, length, diameter, z, color, material, extra)
	local p = { name = name, shape = "Cylinder", size = { length, diameter, diameter }, pos = { 0, 0, z }, rot = { 0, 90, 0 }, color = color, material = material or "Metal" }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	add(p)
end

-- fuselage and ogive nose (stepped cylinders + tip)
cyl("Fuselage", 8.6, 0.95, 0.2, BODY)
cyl("NoseA", 1.3, 0.8, -4.55, BODY)
cyl("NoseB", 1.1, 0.58, -5.75, BODY)
add({ name = "NoseTip", shape = "Ball", size = { 0.42, 0.42, 0.42 }, pos = { 0, 0, -6.4 }, rot = { 0, 0, 0 }, color = { 10, 132, 255 }, material = "Neon", accent = true })

-- dark identification bands
cyl("BandA", 0.32, 0.99, -1.4, DARK, "SmoothPlastic")
cyl("BandB", 0.32, 0.99, 1.7, DARK, "SmoothPlastic")

-- delta wing: stepped strips with a straight trailing edge, mirrored left/right
local STRIPS = 16
for i = 0, STRIPS - 1 do
	local chord = 6.1 * (1 - i / (STRIPS + 0.5))
	local x = 0.45 + i * 0.22
	local z = 4.7 - chord / 2
	for _, side in ipairs({ 1, -1 }) do
		add({ name = (side > 0 and "WingR" or "WingL") .. i, shape = "Block", size = { 0.22, 0.1, chord }, pos = { x * side, 0.04, z }, rot = { 0, 0, 0 }, color = WING, material = "Metal" })
	end
end

-- wingtip fins, angled outward
for _, side in ipairs({ 1, -1 }) do
	add({ name = side > 0 and "FinR" or "FinL", shape = "Block", size = { 0.09, 1.25, 1.5 }, pos = { 4.0 * side, 0.55, 3.9 }, rot = { 0, 0, -12 * side }, color = WING, material = "Metal" })
	-- navigation lights: left red, right green
	add({ name = side > 0 and "NavR" or "NavL", shape = "Ball", size = { 0.24, 0.24, 0.24 }, pos = { 4.05 * side, 0.1, 4.55 }, rot = { 0, 0, 0 }, color = side > 0 and { 60, 255, 120 } or { 255, 70, 70 }, material = "Neon", glow = true })
end

-- engine, exhaust glow and pusher propeller
cyl("Engine", 1.0, 0.55, 5.2, DARK, "Metal")
add({ name = "Exhaust", shape = "Ball", size = { 0.34, 0.34, 0.34 }, pos = { 0, 0, 5.8 }, rot = { 0, 0, 0 }, color = { 255, 150, 60 }, material = "Neon", glow = true })
add({ name = "PropHub", shape = "Ball", size = { 0.26, 0.26, 0.26 }, pos = { 0, 0, 5.95 }, rot = { 0, 0, 0 }, color = DARK, material = "Metal" })
add({ name = "PropA", shape = "Block", size = { 1.9, 0.1, 0.08 }, pos = { 0, 0, 6.0 }, rot = { 0, 0, 0 }, color = DARK, material = "SmoothPlastic", spin = true })
add({ name = "PropB", shape = "Block", size = { 0.1, 1.9, 0.08 }, pos = { 0, 0, 6.0 }, rot = { 0, 0, 0 }, color = DARK, material = "SmoothPlastic", spin = true })

return { parts = parts, length = 12.4, wingspan = 8.1 }

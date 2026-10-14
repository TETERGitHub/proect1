--!nonstrict
-- data/ModelKit: how a customisation model is described and turned into plain part data.
-- A model is a list of parts written with a builder (box, ball, cylX/cylY/cylZ, wedge). Every part carries a ROLE
-- ("primary", "secondary", "grip", "detail", "glow" follow the user's colours; "steel", "black", ... are fixed), so one
-- geometry can be recoloured without touching its shape. resolve() turns a model plus a "look" into pure data
-- (no Roblox objects), which the in-game builder (features/Cosmetics), the preview and the offline renderer
-- (tools/model_render.py) all read. All models here are original, hand-built from Part primitives.
--
-- Conventions: units are studs, +Y up, a weapon points toward -Z. Euler angles are degrees in Roblox's CFrame.Angles
-- order. Cylinders have their length along X (Roblox's own rule); cylY/cylZ add the 90 degree turn for you.
-- A wedge is a right-triangle prism: vertical face at +Z, slope falling toward -Z (check in Studio: unverified).
--
-- Depends on: nothing.

local Kit = {}

-- Fixed role colours (the neutral materials of a weapon or costume). Looks recolour only the role names in Kit.CUSTOM_ROLES.
Kit.FIXED = {
	steel = { 176, 182, 192 },
	gunmetal = { 62, 66, 76 },
	black = { 20, 21, 25 },
	rubber = { 34, 34, 38 },
	brass = { 196, 154, 72 },
	glass = { 150, 205, 235 },
	white = { 240, 240, 244 },
	skin = { 238, 190, 150 },
	wood = { 126, 84, 48 },
	bark = { 96, 64, 38 },
	leaf = { 70, 160, 80 },
	red = { 220, 60, 60 },
}
Kit.CUSTOM_ROLES = { "primary", "secondary", "grip", "detail", "glow" }

-- materials a user may pick for primary/secondary parts; anything else is refused by CustomLogic
Kit.MATERIALS = { "SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "Foil", "Glass", "Marble", "Slate", "Wood" }

local Builder = {}
Builder.__index = Builder

function Kit.new()
	return setmetatable({ parts = {} }, Builder)
end

local function add(b, name, shape, role, sx, sy, sz, x, y, z, rx, ry, rz)
	local p = {
		n = name, s = shape, role = role,
		sz = { sx, sy, sz },
		p = { x or 0, y or 0, z or 0 },
		r = { rx or 0, ry or 0, rz or 0 },
		m = "SmoothPlastic",
	}
	b.parts[#b.parts + 1] = p
	return p
end

-- box(name, role, sx,sy,sz, x,y,z, rx,ry,rz) -> part (set .m material, .decor, .glowPart on the result)
function Builder:box(name, role, sx, sy, sz, x, y, z, rx, ry, rz)
	return add(self, name, "Block", role, sx, sy, sz, x, y, z, rx, ry, rz)
end
function Builder:ball(name, role, d, x, y, z)
	return add(self, name, "Ball", role, d, d, d, x, y, z)
end
function Builder:wedge(name, role, sx, sy, sz, x, y, z, rx, ry, rz)
	return add(self, name, "Wedge", role, sx, sy, sz, x, y, z, rx, ry, rz)
end
-- cylX(name, role, length, dia, x,y,z, rx,ry,rz): length along X
function Builder:cylX(name, role, len, dia, x, y, z, rx, ry, rz)
	return add(self, name, "Cylinder", role, len, dia, dia, x, y, z, rx, ry, rz)
end
function Builder:cylY(name, role, len, dia, x, y, z, rx, ry, rz)
	return add(self, name, "Cylinder", role, len, dia, dia, x, y, z, rx, ry, (rz or 0) + 90)
end
function Builder:cylZ(name, role, len, dia, x, y, z, rx, ry, rz)
	return add(self, name, "Cylinder", role, len, dia, dia, x, y, z, rx, (ry or 0) + 90, rz)
end
-- ring(count, radius, fn(i, angleRadians, x, z)): helper for parts placed round a circle in the XZ plane
function Builder:ring(count, radius, fn)
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		fn(i, a, math.cos(a) * radius, math.sin(a) * radius)
	end
end
-- mirror(fn): call fn(side) for side = 1 and -1 (left/right symmetric parts)
function Builder:mirror(fn)
	fn(1)
	fn(-1)
end
-- a part written as {n=..} copied with a new name suffix, for repeated detail
function Builder:last()
	return self.parts[#self.parts]
end

-- A look: the user's choices. colours are {r,g,b} 0-255.
function Kit.defaultLook()
	return {
		primary = { 120, 124, 134 }, secondary = { 60, 64, 72 }, grip = { 40, 40, 46 }, detail = { 200, 204, 212 }, glow = { 60, 200, 255 },
		material = "Metal", glowAmount = 0.5, decor = 0, effects = true,
	}
end

local function clamp255(v)
	return math.clamp(math.floor((tonumber(v) or 0) + 0.5), 0, 255)
end

local function scaleColor(c, k)
	return { clamp255(c[1] * k), clamp255(c[2] * k), clamp255(c[3] * k) }
end

-- resolve(model, look) -> list of plain parts:
--   { name, shape ("Block"|"Ball"|"Cylinder"|"Wedge"), size = {x,y,z}, pos = {x,y,z}, rot = {x,y,z} (deg), color = {r,g,b},
--     material (string), transparency (0..0.6), neon (bool) }
-- Glow parts become Neon only while look.glowAmount > 0.05; otherwise a dimmed plastic so the shape still reads.
function Kit.resolve(model, look)
	look = look or Kit.defaultLook()
	local out = {}
	local glowAmount = look.glowAmount or 0
	for _, p in ipairs(model.parts) do
		local color, material, transparency, neon = nil, p.m, 0, false
		local role = p.role
		if role == "glow" then
			local c = look.glow or { 60, 200, 255 }
			if glowAmount > 0.05 then
				color, material, neon = { clamp255(c[1]), clamp255(c[2]), clamp255(c[3]) }, "Neon", true
			else
				color, material = scaleColor(c, 0.45), "SmoothPlastic"
			end
		elseif role == "primary" or role == "secondary" or role == "grip" or role == "detail" then
			local c = look[role] or Kit.FIXED.steel
			color = { clamp255(c[1]), clamp255(c[2]), clamp255(c[3]) }
			if p.m == "mat" then
				material = look.material or "SmoothPlastic"
			end
		else
			local c = Kit.FIXED[role] or Kit.FIXED.steel
			color = { c[1], c[2], c[3] }
		end
		if material == "mat" then
			material = "SmoothPlastic"
		end
		if p.decor then
			transparency = math.clamp(look.decor or 0, 0, 0.6)
		end
		out[#out + 1] = {
			name = p.n, shape = p.s, size = { p.sz[1], p.sz[2], p.sz[3] }, pos = { p.p[1], p.p[2], p.p[3] },
			rot = { p.r[1], p.r[2], p.r[3] }, color = color, material = material, transparency = transparency, neon = neon,
		}
	end
	return out
end

-- bounds(model) -> min {x,y,z}, max {x,y,z} of the axis-aligned boxes of every part (rotation ignored: a size estimate only)
function Kit.bounds(model)
	local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
	for _, p in ipairs(model.parts) do
		for i = 1, 3 do
			local half = p.sz[i] / 2
			lo[i] = math.min(lo[i], p.p[i] - half)
			hi[i] = math.max(hi[i], p.p[i] + half)
		end
	end
	return lo, hi
end

return Kit

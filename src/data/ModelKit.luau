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
-- Triangles and polygons ------------------------------------------------------------------------------------------------
-- A side profile is the most important thing about a weapon, so outlines are drawn as polygons: points are {z, y} pairs
-- (z along the weapon, -z = forward; y up) and the polygon is extruded `thick` studs along X, centred on x. A polygon is
-- cut into triangles (ear clipping) and every triangle into two right-triangle wedges, the standard way to draw an arbitrary
-- triangle with WedgeParts. The result is a true silhouette instead of a stack of boxes.

local function cross(ay, az, by, bz)
	return ay * bz - az * by
end

-- rightWedge(b, name, role, thick, x, vy, vz, ay, az, by, bz): right triangle with the right angle at V=(vy,vz) and legs A, B
-- (vectors in the (y, z) plane, perpendicular). Returns the part or nil when degenerate.
local function rightWedge(b, name, role, thick, x, vy, vz, ay, az, by, bz)
	local la, lb = math.sqrt(ay * ay + az * az), math.sqrt(by * by + bz * bz)
	if la < 0.04 or lb < 0.04 then
		return nil
	end
	-- the wedge's own legs: A along local -z, B along local +y; B must be A turned +90 degrees, otherwise swap them
	if cross(ay, az, by, bz) < 0 then
		ay, az, by, bz = by, bz, ay, az
		la, lb = lb, la
	end
	local theta = math.atan2(ay / la, -az / la)
	local cy, cz = vy + (ay + by) / 2, vz + (az + bz) / 2
	local p = add(b, name, "Wedge", role, math.max(thick, 0.05), lb, la, x, cy, cz, math.deg(theta), 0, 0)
	p.tri = true
	return p
end

-- tri(name, role, thick, x, A, B, C): arbitrary triangle, points {z, y}
function Builder:tri(name, role, thick, x, A, B, C)
	local pts = { { A[2], A[1] }, { B[2], B[1] }, { C[2], C[1] } } -- to (y, z)
	-- longest side is the base so the altitude's foot lies inside it
	local best, bi = -1, 1
	for i = 1, 3 do
		local p, q = pts[i], pts[i % 3 + 1]
		local d = (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2
		if d > best then
			best, bi = d, i
		end
	end
	local P, Q, R = pts[bi], pts[bi % 3 + 1], pts[(bi + 1) % 3 + 1]
	local dy, dz = Q[1] - P[1], Q[2] - P[2]
	local t = ((R[1] - P[1]) * dy + (R[2] - P[2]) * dz) / best
	local fy, fz = P[1] + dy * t, P[2] + dz * t
	local first = rightWedge(self, name .. "a", role, thick, x, fy, fz, P[1] - fy, P[2] - fz, R[1] - fy, R[2] - fz)
	local second = rightWedge(self, name .. "b", role, thick, x, fy, fz, Q[1] - fy, Q[2] - fz, R[1] - fy, R[2] - fz)
	return first or second
end

-- ear clipping; pts = { {z, y}, ... } in any winding. Returns a list of index triples.
local function triangulate(pts)
	local n = #pts
	local area = 0
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		area += a[1] * b[2] - b[1] * a[2]
	end
	local idx = {}
	for i = 1, n do
		idx[i] = area >= 0 and i or (n - i + 1)
	end
	local out, guard = {}, 0
	while #idx > 3 and guard < 400 do
		guard += 1
		local m, clipped = #idx, false
		for i = 1, m do
			local ia, ib, ic = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			local a, b, c = pts[ia], pts[ib], pts[ic]
			if (b[1] - a[1]) * (c[2] - b[2]) - (b[2] - a[2]) * (c[1] - b[1]) > 1e-9 then
				local inside = false
				for _, j in ipairs(idx) do
					if j ~= ia and j ~= ib and j ~= ic then
						local p = pts[j]
						local d1 = (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1])
						local d2 = (c[1] - b[1]) * (p[2] - b[2]) - (c[2] - b[2]) * (p[1] - b[1])
						local d3 = (a[1] - c[1]) * (p[2] - c[2]) - (a[2] - c[2]) * (p[1] - c[1])
						if d1 >= 0 and d2 >= 0 and d3 >= 0 then
							inside = true
							break
						end
					end
				end
				if not inside then
					table.insert(out, { ia, ib, ic })
					table.remove(idx, i)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			break
		end
	end
	if #idx == 3 then
		table.insert(out, { idx[1], idx[2], idx[3] })
	end
	return out
end

-- poly(name, role, thick, x, pts, material?) -> number of triangles. All parts share role and material ("mat" = the user's material).
function Builder:poly(name, role, thick, x, pts, material)
	local tris = triangulate(pts)
	for i, t in ipairs(tris) do
		local before = #self.parts
		self:tri(name .. i, role, thick, x, pts[t[1]], pts[t[2]], pts[t[3]])
		for k = before + 1, #self.parts do
			self.parts[k].m = material or "SmoothPlastic"
			self.parts[k].poly = name
		end
	end
	return #tris
end

-- stroke(name, role, thick, x, pts, width, material?): a polyline of thin boxes along the points ({z, y}); used for frames,
-- trigger guards and other outlines that are lines rather than areas
function Builder:stroke(name, role, thick, x, pts, width, material)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dz, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dz * dz + dy * dy)
		if len > 0.01 then
			local theta = math.deg(math.atan2(-dy, dz))
			local p = add(self, name .. i, "Block", role, thick, width, len + width * 0.5, x, (a[2] + b[2]) / 2, (a[1] + b[1]) / 2, theta, 0, 0)
			p.m = material or "SmoothPlastic"
		end
	end
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
function Kit.resolve(model, look, opts)
	look = look or Kit.defaultLook()
	local flip = opts and opts.wedgeFlip or false
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
			flip = (p.s == "Wedge" and flip) or nil,
		}
	end
	return out
end

-- Euler (degrees, Roblox CFrame.Angles order Rx*Ry*Rz) -> rotation applied to a vector
local function rotate(v, rx, ry, rz)
	rx, ry, rz = math.rad(rx), math.rad(ry), math.rad(rz)
	local x, y, z = v[1], v[2], v[3]
	-- Rz first, then Ry, then Rx (matrix product Rx*Ry*Rz applied to a column vector)
	x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
	x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
	y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
	return { x, y, z }
end
Kit.rotate = rotate

-- bounds(parts) -> min {x,y,z}, max {x,y,z} of the rotated boxes of resolved parts (a slight over-estimate for balls and wedges)
function Kit.bounds(parts)
	local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
	for _, p in ipairs(parts) do
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local c = rotate({ sx * p.size[1] / 2, sy * p.size[2] / 2, sz * p.size[3] / 2 }, p.rot[1], p.rot[2], p.rot[3])
					for i = 1, 3 do
						local v = c[i] + p.pos[i]
						lo[i], hi[i] = math.min(lo[i], v), math.max(hi[i], v)
					end
				end
			end
		end
	end
	return lo, hi
end

return Kit

--!strict
-- features/Geometry: pure 3D intersection tests used by the hitbox lab (no Roblox APIs).
-- Vectors are {x,y,z} tables; boxes are axis-aligned (centre + half extents).

local Geometry = {}

export type V3 = { x: number, y: number, z: number }

-- raySphere: distance along the (unit) ray to the first intersection, or nil. Origin inside -> 0.
function Geometry.raySphere(o: V3, d: V3, c: V3, r: number): number?
	local lx, ly, lz = c.x - o.x, c.y - o.y, c.z - o.z
	local dist2 = lx * lx + ly * ly + lz * lz
	if dist2 <= r * r then
		return 0
	end
	local tca = lx * d.x + ly * d.y + lz * d.z
	if tca < 0 then
		return nil
	end
	local d2 = dist2 - tca * tca
	if d2 > r * r then
		return nil
	end
	return tca - math.sqrt(r * r - d2)
end

-- rayBox: slab method. Returns entry distance (0 if the origin is inside) or nil.
function Geometry.rayBox(o: V3, d: V3, c: V3, half: V3): number?
	local tmin, tmax = -math.huge, math.huge
	local axes = { "x", "y", "z" }
	for _, a in ipairs(axes) do
		local oa, da, ca, ha = (o :: any)[a], (d :: any)[a], (c :: any)[a], (half :: any)[a]
		local lo, hi = ca - ha, ca + ha
		if math.abs(da) < 1e-12 then
			if oa < lo or oa > hi then
				return nil
			end
		else
			local t1, t2 = (lo - oa) / da, (hi - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmax < 0 then
		return nil
	end
	return math.max(tmin, 0)
end

-- closestApproach: smallest distance between the ray (t >= 0) and a point. Useful as a "near miss" readout.
function Geometry.closestApproach(o: V3, d: V3, p: V3): number
	local lx, ly, lz = p.x - o.x, p.y - o.y, p.z - o.z
	local t = math.max(0, lx * d.x + ly * d.y + lz * d.z)
	local dx, dy, dz = lx - d.x * t, ly - d.y * t, lz - d.z * t
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Geometry.sphereSphere(c1: V3, r1: number, c2: V3, r2: number): boolean
	local dx, dy, dz = c1.x - c2.x, c1.y - c2.y, c1.z - c2.z
	local rr = r1 + r2
	return dx * dx + dy * dy + dz * dz <= rr * rr
end

function Geometry.sphereBox(c: V3, r: number, bc: V3, half: V3): boolean
	local function clampAxis(v: number, centre: number, h: number): number
		return math.max(centre - h, math.min(v, centre + h))
	end
	local qx, qy, qz = clampAxis(c.x, bc.x, half.x), clampAxis(c.y, bc.y, half.y), clampAxis(c.z, bc.z, half.z)
	local dx, dy, dz = c.x - qx, c.y - qy, c.z - qz
	return dx * dx + dy * dy + dz * dz <= r * r
end

function Geometry.boxBox(c1: V3, h1: V3, c2: V3, h2: V3): boolean
	return math.abs(c1.x - c2.x) <= h1.x + h2.x and math.abs(c1.y - c2.y) <= h1.y + h2.y and math.abs(c1.z - c2.z) <= h1.z + h2.z
end

function Geometry.distance(a: V3, b: V3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ballisticAim: pitch compensation so a projectile launched at `speed` reaches `target` despite gravity g.
-- Returns the aim point raised by the expected drop.
function Geometry.ballisticAim(origin: V3, target: V3, speed: number, g: number): V3
	local dist = Geometry.distance(origin, target)
	local t = dist / math.max(speed, 1e-6)
	return { x = target.x, y = target.y + 0.5 * g * t * t, z = target.z }
end

return Geometry

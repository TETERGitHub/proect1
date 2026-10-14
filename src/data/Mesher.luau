--!nonstrict
-- data/Mesher: turns a model (data/ModelKit) into SMOOTH triangle meshes, one per role/material group, written as OBJ text.
--   box       -> rounded box (bevelled edges with smooth normals)
--   cylinder  -> lathe with bevelled ends, ball -> ellipsoid, wedge -> prism
--   outline   -> a polygon from ModelKit:poly is extruded with rounded edges (true silhouette, no wedge seams)
-- Meshes are grouped by role and material class, NOT by colour, so one OBJ serves every look: the colour, material, neon and
-- transparency of a group are applied to its MeshPart at run time (ModelKit.partLook). Pure Lua, deterministic, no Roblox objects.
-- Triangle winding is counter-clockwise seen from outside; normals are unit length. Units are studs.
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local Mesher = {}
Mesher.VERSION = 3

local sqrt, sin, cos, pi, min, max = math.sqrt, math.sin, math.cos, math.pi, math.min, math.max

local function new()
	return { v = {}, n = {}, f = {} }
end

local function vtx(m, p, n)
	local l = sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
	if l < 1e-9 then
		n, l = { 0, 1, 0 }, 1
	end
	m.v[#m.v + 1] = { p[1], p[2], p[3] }
	m.n[#m.n + 1] = { n[1] / l, n[2] / l, n[3] / l }
	return #m.v
end

-- tri(m, a, b, c): add a triangle; flipped when its geometric normal disagrees with the vertex normals (keeps every face outward)
local function tri(m, a, b, c)
	local pa, pb, pc = m.v[a], m.v[b], m.v[c]
	local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
	local wx, wy, wz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
	local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
	if nx * nx + ny * ny + nz * nz < 1e-14 then
		return -- degenerate
	end
	local na, nb, nc = m.n[a], m.n[b], m.n[c]
	local d = nx * (na[1] + nb[1] + nc[1]) + ny * (na[2] + nb[2] + nc[2]) + nz * (na[3] + nb[3] + nc[3])
	if d < 0 then
		b, c = c, b
	end
	m.f[#m.f + 1] = { a, b, c }
end

local function quad(m, a, b, c, d)
	tri(m, a, b, c)
	tri(m, a, c, d)
end

-- Primitives (built centred at the origin, +X = cylinder axis) -----------------------------------------------------------------

local function roundedBox(m, sx, sy, sz, bevel)
	local h = { sx / 2, sy / 2, sz / 2 }
	local r = min(bevel, 0.45 * min(h[1], h[2], h[3]))
	if r < 0.002 then
		r = 0.002
	end
	local stops = {}
	for a = 1, 3 do
		stops[a] = { -h[a], -h[a] + r, h[a] - r, h[a] }
	end
	for axis = 1, 3 do
		for sign = -1, 1, 2 do
			local b, c = axis % 3 + 1, (axis + 1) % 3 + 1
			local idx = {}
			for i = 1, 4 do
				idx[i] = {}
				for j = 1, 4 do
					local q = {}
					q[axis], q[b], q[c] = sign * h[axis], stops[b][i], stops[c][j]
					local p, n = {}, {}
					local len = 0
					for k = 1, 3 do
						local inner = max(-(h[k] - r), min(h[k] - r, q[k]))
						n[k] = q[k] - inner
						len += n[k] * n[k]
						p[k] = inner
					end
					len = sqrt(len)
					for k = 1, 3 do
						n[k] /= len
						p[k] += n[k] * r
					end
					idx[i][j] = vtx(m, p, n)
				end
			end
			for i = 1, 3 do
				for j = 1, 3 do
					quad(m, idx[i][j], idx[i + 1][j], idx[i + 1][j + 1], idx[i][j + 1])
				end
			end
		end
	end
end

-- lathe(profile): rings of (x, r, nx, nr) revolved about the X axis; ry/rz scale the radius (ellipse)
local function lathe(m, profile, seg, ry, rz)
	local rings = {}
	for pi_, pt in ipairs(profile) do
		local ring = {}
		for i = 0, seg - 1 do
			local a = i / seg * pi * 2
			local ca, sa = cos(a), sin(a)
			ring[i + 1] = vtx(m, { pt[1], pt[2] * ca * ry, pt[2] * sa * rz }, { pt[3], pt[4] * ca / max(ry, 1e-6), pt[4] * sa / max(rz, 1e-6) })
		end
		rings[pi_] = ring
	end
	for j = 1, #profile - 1 do
		if profile[j][2] > 1e-6 or profile[j + 1][2] > 1e-6 then
			for i = 1, seg do
				local i2 = i % seg + 1
				quad(m, rings[j][i], rings[j + 1][i], rings[j + 1][i2], rings[j][i2])
			end
		end
	end
end

local function cylinder(m, len, dy, dz, bevel)
	local R = max(dy, dz) / 2
	local seg = R < 0.08 and 10 or (R > 0.5 and 26 or 18)
	local b = min(bevel, 0.35 * R, 0.2 * len)
	local L = len / 2
	local c1 = 0.2929
	lathe(m, {
		{ -L, 0, -1, 0 }, { -L, 1 - b / R, -1, 0 }, { -L + c1 * b, 1 - c1 * b / R, -0.7071, 0.7071 }, { -L + b, 1, 0, 1 },
		{ L - b, 1, 0, 1 }, { L - c1 * b, 1 - c1 * b / R, 0.7071, 0.7071 }, { L, 1 - b / R, 1, 0 }, { L, 0, 1, 0 },
	}, seg, dy / 2, dz / 2)
end

local function sphere(m, sx, sy, sz)
	local lat, lon = 10, 16
	local rx, ry, rz = sx / 2, sy / 2, sz / 2
	local rows = {}
	for i = 0, lat do
		local th = i / lat * pi
		local row = {}
		for j = 0, lon - 1 do
			local ph = j / lon * pi * 2
			local nx, ny, nz = cos(th), sin(th) * cos(ph), sin(th) * sin(ph) -- axis along X like the cylinder
			row[j + 1] = vtx(m, { nx * rx, ny * ry, nz * rz }, { nx / max(rx, 1e-6), ny / max(ry, 1e-6), nz / max(rz, 1e-6) })
		end
		rows[i + 1] = row
	end
	for i = 1, lat do
		for j = 1, lon do
			local j2 = j % lon + 1
			quad(m, rows[i][j], rows[i + 1][j], rows[i + 1][j2], rows[i][j2])
		end
	end
end

-- wedge: right-triangle prism, right angle at (y = -h, z = +d) (see data/ModelKit); flat shaded
local function wedge(m, sx, sy, sz)
	local hx, hy, hz = sx / 2, sy / 2, sz / 2
	local a0, a1 = { -hx, -hy, -hz }, { hx, -hy, -hz }
	local b0, b1 = { -hx, -hy, hz }, { hx, -hy, hz }
	local c0, c1 = { -hx, hy, hz }, { hx, hy, hz }
	local function face(n, ...)
		local ids = {}
		for _, p in ipairs({ ... }) do
			ids[#ids + 1] = vtx(m, p, n)
		end
		for k = 2, #ids - 1 do
			tri(m, ids[1], ids[k], ids[k + 1])
		end
	end
	local sl = sqrt(sy * sy + sz * sz)
	face({ -1, 0, 0 }, a0, b0, c0)
	face({ 1, 0, 0 }, a1, c1, b1)
	face({ 0, -1, 0 }, a0, a1, b1, b0)
	face({ 0, 0, 1 }, b0, b1, c1, c0)
	face({ 0, -sz / sl, sy / sl }, a0, c0, c1, a1)
end

-- Extruded outline with rounded edges ------------------------------------------------------------------------------------------

local function dedupe(pts)
	local out = {}
	for _, p in ipairs(pts) do
		local last = out[#out]
		if not last or (p[1] - last[1]) ^ 2 + (p[2] - last[2]) ^ 2 > 1e-8 then
			out[#out + 1] = { p[1], p[2] }
		end
	end
	if #out > 1 then
		local a, b = out[1], out[#out]
		if (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 <= 1e-8 then
			out[#out] = nil
		end
	end
	return out
end

local function outline(m, pts, thick, bevel)
	pts = dedupe(pts)
	local n = #pts
	if n < 3 then
		return
	end
	local area = 0
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		area += a[1] * b[2] - b[1] * a[2]
	end
	if area < 0 then
		local rev = {}
		for i = n, 1, -1 do
			rev[#rev + 1] = pts[i]
		end
		pts = rev
	end
	local r = min(bevel, 0.4 * thick)
	local hx = thick / 2
	-- edge normals (z, y) of a counter-clockwise outline point away from the inside
	local en = {}
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		local dz, dy = b[1] - a[1], b[2] - a[2]
		local l = sqrt(dz * dz + dy * dy)
		en[i] = { dy / l, -dz / l }
	end
	-- vertex normal: smooth between neighbouring edges unless the corner is sharp (> ~40 degrees)
	local function cornerNormal(i, which)
		local e1, e2 = en[(i - 2) % n + 1], en[i]
		local d = e1[1] * e2[1] + e1[2] * e2[2]
		if d >= 0.766 then
			local nz, ny = e1[1] + e2[1], e1[2] + e2[2]
			local l = sqrt(nz * nz + ny * ny)
			return { nz / l, ny / l }
		end
		return which == "prev" and e1 or e2
	end
	-- inset polygon: every outline point moved inward by r along the bisector
	local inset = {}
	for i = 1, n do
		local e1, e2 = en[(i - 2) % n + 1], en[i]
		local nz, ny = e1[1] + e2[1], e1[2] + e2[2]
		local l = sqrt(nz * nz + ny * ny)
		if l < 1e-6 then
			nz, ny, l = e2[1], e2[2], 1
		end
		nz, ny = nz / l, ny / l
		local k = max(0.45, nz * e2[1] + ny * e2[2])
		inset[i] = { pts[i][1] - nz * r / k, pts[i][2] - ny * r / k }
	end
	-- walls and the two rounded rims
	for i = 1, n do
		local i2 = i % n + 1
		local na, nb = cornerNormal(i, "next"), cornerNormal(i2, "prev")
		local pa, pb = pts[i], pts[i2]
		for _, side in ipairs({ 1, -1 }) do
			local x0 = side * (hx - r)
			local x1 = side * hx
			-- wall strip between the two rim lines is built once (for side = 1 spanning -x..+x)
			if side == 1 then
				local a0 = vtx(m, { -x0, pa[2], pa[1] }, { 0, na[2], na[1] })
				local b0 = vtx(m, { -x0, pb[2], pb[1] }, { 0, nb[2], nb[1] })
				local b1 = vtx(m, { x0, pb[2], pb[1] }, { 0, nb[2], nb[1] })
				local a1 = vtx(m, { x0, pa[2], pa[1] }, { 0, na[2], na[1] })
				quad(m, a0, b0, b1, a1)
			end
			-- rim: wall point -> 45 degree point -> cap point, for both ends of the edge
			local ia, ib = inset[i], inset[i2]
			local function arc(p, nrm, ins)
				local cz, cy = ins[1], ins[2] -- arc centre in the plane
				local mz, my = nrm[1] + 0, nrm[2] + 0
				local l = sqrt(mz * mz + my * my + 1)
				local mid = { { cz + nrm[1] * r * 0.7071, cy + nrm[2] * r * 0.7071 }, nil }
				return {
					{ { x0, p[2], p[1] }, { 0, nrm[2], nrm[1] } },
					{ { side * (hx - r + r * 0.7071), cy + nrm[2] * r * 0.7071, cz + nrm[1] * r * 0.7071 }, { side * 0.7071, nrm[2] * 0.7071, nrm[1] * 0.7071 } },
					{ { x1, ins[2], ins[1] }, { side, 0, 0 } },
				}
			end
			local A, B = arc(pa, na, ia), arc(pb, nb, ib)
			for k = 1, 2 do
				local v1 = vtx(m, A[k][1], A[k][2])
				local v2 = vtx(m, B[k][1], B[k][2])
				local v3 = vtx(m, B[k + 1][1], B[k + 1][2])
				local v4 = vtx(m, A[k + 1][1], A[k + 1][2])
				quad(m, v1, v2, v3, v4)
			end
		end
	end
	-- the two flat caps
	local tris = Kit.triangulate(inset)
	for _, side in ipairs({ 1, -1 }) do
		local ids = {}
		for i = 1, n do
			ids[i] = vtx(m, { side * hx, inset[i][2], inset[i][1] }, { side, 0, 0 })
		end
		for _, t in ipairs(tris) do
			tri(m, ids[t[1]], ids[t[2]], ids[t[3]])
		end
	end
end

-- Assembly ------------------------------------------------------------------------------------------------------------------------

local function transform(m, from, rot, pos, flip)
	for i = from + 1, #m.v do
		local p, n = m.v[i], m.n[i]
		if flip then
			p, n = Kit.rotate(p, 0, 180, 0), Kit.rotate(n, 0, 180, 0)
		end
		p, n = Kit.rotate(p, rot[1], rot[2], rot[3]), Kit.rotate(n, rot[1], rot[2], rot[3])
		m.v[i] = { p[1] + pos[1], p[2] + pos[2], p[3] + pos[3] }
		m.n[i] = n
	end
end

-- build(model, opts) -> groups: list of { key, role, material (raw part material), decor, mesh = {v, n, f} }
-- opts.bevel (default 0.03) is the rounding radius for boxes and cylinders; outlines use opts.outlineBevel (default 0.025).
function Mesher.build(model, opts)
	opts = opts or {}
	local bevel, obevel = opts.bevel or 0.03, opts.outlineBevel or 0.025
	local groups, order = {}, {}
	local function group(role, pmat, decor)
		local key = role .. "|" .. tostring(pmat) .. (decor and "|decor" or "")
		local g = groups[key]
		if not g then
			g = { key = key, role = role, material = pmat, decor = decor and true or false, mesh = new() }
			groups[key] = g
			order[#order + 1] = g
		end
		return g
	end
	for _, p in ipairs(model.parts) do
		if not p.poly then
			local g = group(p.role, p.m, p.decor)
			local from = #g.mesh.v
			local sx, sy, sz = p.sz[1], p.sz[2], p.sz[3]
			if p.s == "Block" then
				roundedBox(g.mesh, sx, sy, sz, bevel)
			elseif p.s == "Cylinder" then
				cylinder(g.mesh, sx, sy, sz, bevel)
			elseif p.s == "Ball" then
				sphere(g.mesh, sx, sy, sz)
			elseif p.s == "Wedge" then
				wedge(g.mesh, sx, sy, sz)
			end
			transform(g.mesh, from, p.r, p.p, false)
		end
	end
	for _, sh in ipairs(model.shapes or {}) do
		if sh.kind == "poly" then
			local g = group(sh.role, sh.m, sh.decor)
			local from = #g.mesh.v
			outline(g.mesh, sh.pts, sh.thick, obevel)
			transform(g.mesh, from, { 0, 0, 0 }, { sh.x, 0, 0 }, false)
		end
	end
	local out = {}
	for _, g in ipairs(order) do
		if #g.mesh.f > 0 then
			out[#out + 1] = g
		end
	end
	return out
end

-- bounds(mesh) -> center {x,y,z}, size {x,y,z}
function Mesher.bounds(mesh)
	local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
	for _, p in ipairs(mesh.v) do
		for i = 1, 3 do
			lo[i], hi[i] = min(lo[i], p[i]), max(hi[i], p[i])
		end
	end
	return { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }, { max(hi[1] - lo[1], 0.05), max(hi[2] - lo[2], 0.05), max(hi[3] - lo[3], 0.05) }
end

-- toObj(mesh) -> obj text (vertices re-centred on the bounding box, so a MeshPart placed at `center` shows it in the right spot), center, size
function Mesher.toObj(mesh)
	local center, size = Mesher.bounds(mesh)
	local lines = { "# MM2 Hub generated mesh v" .. Mesher.VERSION, "vt 0 0" }
	for _, p in ipairs(mesh.v) do
		lines[#lines + 1] = string.format("v %.4f %.4f %.4f", p[1] - center[1], p[2] - center[2], p[3] - center[3])
	end
	for _, n in ipairs(mesh.n) do
		lines[#lines + 1] = string.format("vn %.3f %.3f %.3f", n[1], n[2], n[3])
	end
	for _, f in ipairs(mesh.f) do
		lines[#lines + 1] = string.format("f %d/1/%d %d/1/%d %d/1/%d", f[1], f[1], f[2], f[2], f[3], f[3])
	end
	return table.concat(lines, "\n") .. "\n", center, size
end

function Mesher.triangleCount(groups)
	local n = 0
	for _, g in ipairs(groups) do
		n += #g.mesh.f
	end
	return n
end

return Mesher

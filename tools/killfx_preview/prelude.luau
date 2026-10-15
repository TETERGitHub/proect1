-- minimal Roblox-like world with real rotation maths, for recording KillFX frames offline
local V = {}
V.__index = function(t, k)
	if k == "X" then return t.x elseif k == "Y" then return t.y elseif k == "Z" then return t.z end
	if k == "Magnitude" then return math.sqrt(t.x*t.x+t.y*t.y+t.z*t.z) end
	if k == "Unit" then local m = math.sqrt(t.x*t.x+t.y*t.y+t.z*t.z); if m == 0 then return t end return Vector3.new(t.x/m,t.y/m,t.z/m) end
	if k == "Cross" then return function(a,b) return Vector3.new(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) end end
	if k == "Dot" then return function(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end end
	if k == "Lerp" then return function(a,b,f) return Vector3.new(a.x+(b.x-a.x)*f, a.y+(b.y-a.y)*f, a.z+(b.z-a.z)*f) end end
end
V.__add = function(a,b) return Vector3.new(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__sub = function(a,b) return Vector3.new(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__mul = function(a,b)
	if type(a) == "number" then return Vector3.new(b.x*a,b.y*a,b.z*a) end
	if type(b) == "number" then return Vector3.new(a.x*b,a.y*b,a.z*b) end
	return Vector3.new(a.x*b.x,a.y*b.y,a.z*b.z)
end
V.__div = function(a,b) return Vector3.new(a.x/b,a.y/b,a.z/b) end
V.__unm = function(a) return Vector3.new(-a.x,-a.y,-a.z) end
Vector3 = { new = function(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, V) end }

local C = {}
local function mk(p, m) return setmetatable({p=p, m=m}, C) end
local function mmul(a,b)
	local r = {}
	for i=0,2 do for j=0,2 do
		local s = 0
		for k=0,2 do s += a[i*3+k+1]*b[k*3+j+1] end
		r[i*3+j+1] = s
	end end
	return r
end
local function mv(m, v) return Vector3.new(m[1]*v.x+m[2]*v.y+m[3]*v.z, m[4]*v.x+m[5]*v.y+m[6]*v.z, m[7]*v.x+m[8]*v.y+m[9]*v.z) end
local I = {1,0,0,0,1,0,0,0,1}
C.__index = function(t,k)
	if k == "Position" then return t.p end
	if k == "Rotation" then return mk(Vector3.new(0,0,0), t.m) end
	if k == "LookVector" then return Vector3.new(-t.m[3], -t.m[6], -t.m[9]) end
	if k == "X" then return t.p.x elseif k == "Y" then return t.p.y elseif k == "Z" then return t.p.z end
end
C.__mul = function(a,b)
	if getmetatable(b) == V then return a.p + mv(a.m, b) end
	return mk(a.p + mv(a.m, b.p), mmul(a.m, b.m))
end
C.__add = function(a,v) return mk(a.p + v, a.m) end
C.__sub = function(a,v) return mk(a.p - v, a.m) end
CFrame = {
	new = function(x,y,z)
		if type(x) == "table" then return mk(x, I) end
		return mk(Vector3.new(x or 0,y or 0,z or 0), I)
	end,
	Angles = function(rx,ry,rz)
		local cx,sx,cy,sy,cz,sz = math.cos(rx),math.sin(rx),math.cos(ry),math.sin(ry),math.cos(rz),math.sin(rz)
		local X = {1,0,0, 0,cx,-sx, 0,sx,cx}
		local Y = {cy,0,sy, 0,1,0, -sy,0,cy}
		local Z = {cz,-sz,0, sz,cz,0, 0,0,1}
		return mk(Vector3.new(0,0,0), mmul(mmul(X,Y),Z))
	end,
	lookAt = function(at, target)
		local f = (target - at).Unit
		local up = Vector3.new(0,1,0)
		if math.abs(f.y) > 0.999 then up = Vector3.new(0,0,1) end
		local r = f:Cross(up).Unit
		local u = r:Cross(f).Unit
		-- columns: right, up, back(-look)
		return mk(at, { r.x, u.x, -f.x, r.y, u.y, -f.y, r.z, u.z, -f.z })
	end,
}
local Cm = {}
Cm.__index = function(t,k)
	if k == "Lerp" then return function(a,b,f) return Color3.new(a.R+(b.R-a.R)*f, a.G+(b.G-a.G)*f, a.B+(b.B-a.B)*f) end end
end
Color3 = {
	new = function(r,g,b) return setmetatable({R=r,G=g,B=b}, Cm) end,
	fromRGB = function(r,g,b) return setmetatable({R=r/255,G=g/255,B=b/255}, Cm) end,
	fromHSV = function(h,s,v)
		local i = math.floor(h*6); local f = h*6-i; local p,q,t = v*(1-s), v*(1-f*s), v*(1-(1-f)*s)
		local r,g,b = ({ {v,t,p},{q,v,p},{p,v,t},{p,q,v},{t,p,v},{v,p,q} })[i%6+1][1], ({ {v,t,p},{q,v,p},{p,v,t},{p,q,v},{t,p,v},{v,p,q} })[i%6+1][2], ({ {v,t,p},{q,v,p},{p,v,t},{p,q,v},{t,p,v},{v,p,q} })[i%6+1][3]
		return setmetatable({R=r,G=g,B=b}, Cm)
	end,
}
Enum = setmetatable({}, { __index = function(_, cat) return setmetatable({}, { __index = function(_, item) return item end }) end })
RaycastParams = { new = function() return {} end }

local Inst = {}
EMITTERS = {}
local function newInst(class)
	local o = { ClassName = class, Name = class, _children = {}, Transparency = 0, Shape = "Block", Material = "Plastic", Color = Color3.new(0.6,0.6,0.6), Size = Vector3.new(1,1,1), CFrame = CFrame.new() }
	setmetatable(o, Inst)
	if class == "ParticleEmitter" then
		o._acc = 0
		table.insert(EMITTERS, o)
	end
	return o
end
local methods = {}
function methods.GetChildren(self) local out = {} for _, c in ipairs(self._children) do table.insert(out, c) end return out end
function methods.GetDescendants(self)
	local out = {}
	local function walk(o) for _, c in ipairs(o._children) do table.insert(out, c); walk(c) end end
	walk(self); return out
end
function methods.IsA(self, c)
	if c == "BasePart" then return self.ClassName == "Part" or self.ClassName == "WedgePart" or self.ClassName == "MeshPart" end
	return self.ClassName == c
end
function methods.Destroy(self)
	if self._parent then
		local list = self._parent._children
		for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
	end
	self._parent = nil; self._dead = true
end
function methods.Clone(self)
	local o = newInst(self.ClassName)
	for k, v in pairs(self) do if k ~= "_children" and k ~= "_parent" then o[k] = v end end
	o._children = {}; o._parent = nil
	return o
end
function methods.FindFirstChild(self, n) for _, c in ipairs(self._children) do if c.Name == n then return c end end end
function methods.FindFirstChildOfClass(self, n) for _, c in ipairs(self._children) do if c.ClassName == n then return c end end end
function methods.GetPivot(self) return self.CFrame end
Inst.__index = function(t, k)
	if methods[k] then return methods[k] end
	if k == "Parent" then return rawget(t, "_parent") end
	if k == "Position" and rawget(t, "CFrame") then return rawget(t, "CFrame").p end
	return nil
end
Inst.__newindex = function(t, k, v)
	if k == "Parent" then
		if rawget(t, "_parent") then methods.Destroy(t); rawset(t, "_dead", nil) end
		rawset(t, "_parent", v)
		if v then table.insert(v._children, t) end
		return
	end
	rawset(t, k, v)
end
Instance = { new = newInst }

-- sequences, ranges and the particle emitter (Emit spawns simulated sprites into SPRITES)
local function seq(kind, a, b)
	if type(a) == "table" and a[1] ~= nil then return { _type = kind, points = a } end
	return { _type = kind, points = { { Time = 0, Value = a }, { Time = 1, Value = b == nil and a or b } } }
end
NumberSequence = { new = function(a, b) return seq("NumberSequence", a, b) end }
ColorSequence = { new = function(a, b) return seq("ColorSequence", a, b) end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
Vector2 = { new = function(x, y) return { X = x, Y = y, x = x, y = y } end }
UDim2 = { new = function(a, b, c, d) return { X = { Scale = a, Offset = b }, Y = { Scale = c, Offset = d } } end,
	fromScale = function(a, b) return { X = { Scale = a, Offset = 0 }, Y = { Scale = b, Offset = 0 } } end,
	fromOffset = function(a, b) return { X = { Scale = 0, Offset = a }, Y = { Scale = 0, Offset = b } } end }
local rawTypeof = typeof
typeof = function(v)
	if type(v) == "table" and rawget(v, "_type") then return v._type end
	if type(v) == "table" and getmetatable(v) == Cm then return "Color3" end
	return rawTypeof(v)
end
SPRITES = {}
methods.Emit = function(self, n)
	local holder = self._parent
	local cf = holder.CFrame
	local up = Vector3.new(cf.m[2], cf.m[5], cf.m[8])
	for _ = 1, n do
		local origin = cf.p
		if self.Shape ~= nil then
			-- surface of the holder box: pick a face weighted by area, then a point on it
			local sz = holder.Size
			local hx, hy, hz = sz.x / 2, sz.y / 2, sz.z / 2
			local axis = math.random(1, 3)
			local sgn = math.random() < 0.5 and -1 or 1
			local lx, ly, lz = (math.random() * 2 - 1) * hx, (math.random() * 2 - 1) * hy, (math.random() * 2 - 1) * hz
			local volume = self.ShapeStyle ~= nil and tostring(self.ShapeStyle):find("Volume") ~= nil
			if not volume then
				if axis == 1 then lx = sgn * hx elseif axis == 2 then ly = sgn * hy else lz = sgn * hz end
			end
			origin = cf * Vector3.new(lx, ly, lz)
		end
		local sx, sy = math.rad(self.SpreadAngle.X), math.rad(self.SpreadAngle.Y)
		local a1, a2 = (math.random() * 2 - 1) * sx, (math.random() * 2 - 1) * sy
		local d = (cf.Rotation * CFrame.Angles(a1, 0, a2)) * Vector3.new(0, 1, 0)
		local sp = self.Speed.Min + math.random() * (self.Speed.Max - self.Speed.Min)
		table.insert(SPRITES, {
			tex = self.Texture, pos = origin, vel = d * sp, acc = self.Acceleration or Vector3.new(0, 0, 0), drag = self.Drag or 0,
			life = self.Lifetime.Min + math.random() * (self.Lifetime.Max - self.Lifetime.Min), age = 0,
			size = self.Size, tr = self.Transparency, col = self.Color, light = self.LightEmission or 0,
			rot = self.Rotation.Min + math.random() * (self.Rotation.Max - self.Rotation.Min),
			spin = self.RotSpeed.Min + math.random() * (self.RotSpeed.Max - self.RotSpeed.Min), squash = self.Orientation ~= nil,
			owner = holder,
			-- flipbook: one 4x4 cell per particle (Random = fixed random cell, Loop = advancing with age), as Roblox shows it
			flip = self.FlipbookLayout ~= nil, flipRandom = self.FlipbookMode ~= nil and tostring(self.FlipbookMode):find("Random") ~= nil,
			fps = self.FlipbookFramerate and self.FlipbookFramerate.Min or 24, cell0 = math.random(0, 15),
		})
	end
end
local function sample(s, t)
	local pts = s.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		if t <= b.Time then
			local f = (t - a.Time) / math.max(1e-6, b.Time - a.Time)
			if type(a.Value) == "number" then return a.Value + (b.Value - a.Value) * f end
			return a.Value:Lerp(b.Value, f)
		end
	end
	return pts[#pts].Value
end
function STEP_SPRITES(dt)
	for _, e in ipairs(EMITTERS) do
		local h = e._parent
		if h and not h._dead and not e._dead and (e.Rate or 0) > 0 then
			e._acc += e.Rate * dt
			local n = math.floor(e._acc)
			if n > 0 then
				e._acc -= n
				methods.Emit(e, n)
			end
		end
	end
	for i = #SPRITES, 1, -1 do
		local p = SPRITES[i]
		p.age += dt
		if p.age >= p.life or p.owner._dead then
			table.remove(SPRITES, i)
		else
			p.vel = (p.vel + p.acc * dt) * math.exp(-p.drag * dt)
			p.pos = p.pos + p.vel * dt
			p.rot += p.spin * dt
		end
	end
end
function DUMP_SPRITES(frame)
	for _, p in ipairs(SPRITES) do
		local f = p.age / p.life
		local c = sample(p.col, f)
		local texname = p.tex
		if p.flip then
			local cell = p.flipRandom and p.cell0 or (p.cell0 + math.floor(p.age * p.fps)) % 16
			texname = texname .. "#" .. cell
		end
		print(string.format("S %d %s %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.2f %.1f %d %.3f %.3f %.3f", frame, texname, p.pos.x, p.pos.y, p.pos.z,
			sample(p.size, f), sample(p.tr, f), c.R, c.G, c.B, p.light, p.rot, p.squash and 1 or 0, p.vel.x, p.vel.y, p.vel.z))
	end
end

-- trails and beams: dump their attachment positions every frame (the renderer keeps trail history itself)
local fxId = 0
function DUMP_FX(frame, root)
	for _, o in ipairs(root:GetDescendants()) do
		if o.ClassName == "BillboardGui" and o.Adornee and not o.Adornee._dead then
			local face, cap = methods.FindFirstChild(o, "Face"), methods.FindFirstChild(o, "Caption")
			local img = face or o._children[1]
			local off = o.StudsOffset or Vector3.new(0, 0, 0)
			local pos = o.Adornee.CFrame.p + off
			local rx, ry, tr = 0, 0, 0
			if img and img.ImageRectOffset then rx, ry = img.ImageRectOffset.x, img.ImageRectOffset.y end
			if img and img.ImageTransparency then tr = img.ImageTransparency end
			local file = img and img.Image and string.match(tostring(img.Image), "[^:/]+$") or "-"
			print(string.format("G %d %.3f %.3f %.3f %.3f %d %d %.3f %s %s", frame, pos.x, pos.y, pos.z, o.Size.X.Scale, rx, ry, tr,
				cap and cap.Text and (string.gsub(cap.Text, " ", "_")) or "-", file))
		end
		if (o.ClassName == "Trail" or o.ClassName == "Beam") and o.Attachment0 and o.Attachment1 then
			if not rawget(o, "_id") then fxId += 1; rawset(o, "_id", fxId) end
			local p0 = o.Attachment0._parent.CFrame * o.Attachment0.Position
			local p1 = o.Attachment1._parent.CFrame * o.Attachment1.Position
			local c0, c1 = sample(o.Color, 0), sample(o.Color, 1)
			local t0, t1 = sample(o.Transparency, 0), sample(o.Transparency, 1)
			if o.ClassName == "Trail" then
				print(string.format("T %d %d %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f", frame, o._id, p0.x, p0.y, p0.z,
					p1.x, p1.y, p1.z, c0.R, c0.G, c0.B, c1.R, c1.G, c1.B, t0, t1, o.Lifetime or 0.4, sample(o.WidthScale, 1)))
			else
				print(string.format("B %d %s %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f", frame, tostring(o.Texture), p0.x, p0.y, p0.z,
					p1.x, p1.y, p1.z, o.Width0 or 0.5, o.Width1 or 0.5, c0.R, c0.G, c0.B, t0, t1))
			end
		end
	end
end

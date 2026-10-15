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
local function newInst(class)
	local o = { ClassName = class, Name = class, _children = {}, Transparency = 0, Shape = "Block", Material = "Plastic", Color = Color3.new(0.6,0.6,0.6), Size = Vector3.new(1,1,1), CFrame = CFrame.new() }
	return setmetatable(o, Inst)
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
function methods.GetPivot(self) return self.CFrame end
Inst.__index = function(t, k)
	if methods[k] then return methods[k] end
	if k == "Parent" then return rawget(t, "_parent") end
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

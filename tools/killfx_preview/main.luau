-- record: every frame, every part of the effect -> one line of numbers
local DEFAULTS = { ["killfx.enabled"] = true, ["killfx.effect"] = "Lightning", ["killfx.scale"] = 1, ["killfx.detail"] = 1,
	["killfx.customColor"] = false, ["killfx.color"] = { r = 178, g = 120, b = 255 }, ["killfx.hideBody"] = false,
	["killfx.onMurderer"] = true, ["killfx.onSheriff"] = true, ["ui.reduceEffects"] = false }
local tick
local ws = Instance.new("Workspace")
ws.CurrentCamera = Instance.new("Camera")
ws.Raycast = function(_, origin) return { Position = Vector3.new(origin.x, 0, origin.z) } end
ws.BulkMoveTo = function(_, parts, cfs) for i, p in ipairs(parts) do p.CFrame = cfs[i] end end
local stubs = {
	["core/Settings"] = { get = function(k) return DEFAULTS[k] end },
	["core/Services"] = { Workspace = ws, Players = { LocalPlayer = nil } },
	["core/Perf"] = { every = function(_, _, fn) tick = fn; return { Cancel = function() end } end, isLow = function() return false end },
	["core/Logger"] = { info = function() end, warn = function(_, f, ...) print("WARN " .. string.format(f, ...)) end },
	["features/KillEvents"] = { Confirmed = { Connect = function() return {} end } },
	["core/Env"] = { ROOT = "MM2Hub", persistent = function() return true end, has = function() return true end, read = function() return nil end,
		write = function() return true end, customAsset = function(path) return "fx:" .. string.match(path, "[^/]+$") end },
	["core/Codec"] = { b64decode = function(s) return s end },
	["data/FxPack"] = setmetatable({}, { __index = function(_, k) return { bytes = 0, data = "" } end }),
}
workspace = ws
local loaded = {}
local function import(name)
	if stubs[name] then return stubs[name] end
	if not loaded[name] then loaded[name] = MODULES[name](import) end
	return loaded[name]
end
local KillFX = import("features/KillFX")
KillFX.start({ maid = { Give = function() end } })

-- the victim: a classic Roblox dummy (stand-in for any avatar)
local function dummy()
	local m = Instance.new("Model")
	local skin, shirt, pants = Color3.fromRGB(245, 205, 48), Color3.fromRGB(13, 105, 172), Color3.fromRGB(39, 70, 45)
	local spec = {
		{ "Head", 2, 1, 1, 0, 4.5, 0, skin }, { "Torso", 2, 2, 1, 0, 3, 0, shirt },
		{ "Left Arm", 1, 2, 1, -1.5, 3, 0, skin }, { "Right Arm", 1, 2, 1, 1.5, 3, 0, skin },
		{ "Left Leg", 1, 2, 1, -0.5, 1, 0, pants }, { "Right Leg", 1, 2, 1, 0.5, 1, 0, pants },
	}
	for _, s in ipairs(spec) do
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = s[1], Vector3.new(s[2], s[3], s[4]), CFrame.new(s[5], s[6], s[7]), s[8]
		p.Parent = m
	end
	m.CFrame = CFrame.new(0, 3, 0)
	return m
end

local name = EFFECT_NAME
math.randomseed(7)
local fx = KillFX.play(dummy(), { effect = name, hide = false })
local frameNo = 0
local function dump()
	for _, p in ipairs(fx.folder:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.995 then
			local cf, s, c = p.CFrame, p.Size, p.Color
			local m = cf.m
			local sm = p:FindFirstChild("FxMesh")
			local meshTag = sm and string.format(" M %s %.3f %.3f %.3f", string.sub(sm.MeshId, 4), sm.Scale.x, sm.Scale.y, sm.Scale.z) or ""
			print(string.format("P %d %s %s %s %.3f %.3f %.3f %.3f %.3f %.3f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %.3f",
				frameNo, p.ClassName, tostring(p.Shape), tostring(p.Material), s.x, s.y, s.z, cf.p.x, cf.p.y, cf.p.z,
				m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], c.R, c.G, c.B, p.Transparency) .. meshTag)
		end
	end
	DUMP_SPRITES(frameNo)
	DUMP_FX(frameNo, fx.folder)
	print("F " .. frameNo)
end
-- a few frames of the intact body first
for _ = 1, 6 do dump(); frameNo += 1 end
while not fx.done and frameNo < 160 do
	tick(1 / 30)
	STEP_SPRITES(1 / 30)
	dump()
	frameNo += 1
end

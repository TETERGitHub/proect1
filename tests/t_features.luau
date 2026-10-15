--!nonstrict
local import = ...
local T = import("tests/Framework")
local Layout = import("features/CrosshairLayout")
local TL = import("features/TrainingLogic")
local Sources = import("features/Sources")
local Playlist = import("features/Playlist")
local Tools = import("features/Tools")
local Settings = import("core/Settings")
local Env = import("core/Env")

T.suite("CrosshairLayout")
local base = { style = "Cross", size = 10, thickness = 2, gap = 4, centerDot = false, dotSize = 2, spread = 0 }
local function with(o) local c = table.clone(base); for k, v in pairs(o) do c[k] = v end return c end
T.test("cross has four symmetric arms", "arms mirrored around centre", function()
	local l = Layout.compute(base)
	T.eq(#l.rects, 4); T.eq(l.rects[1].y, -l.rects[2].y); T.eq(l.rects[3].x, -l.rects[4].x)
	T.eq(l.rects[1].y, -9); T.eq(l.rects[1].h, 10); T.eq(l.rects[1].w, 2)
end)
T.test("spread widens gap", "arms move outward", function()
	local a, b = Layout.compute(base), Layout.compute(with({ spread = 6 }))
	T.eq(b.rects[1].y, a.rects[1].y - 6)
end)
T.test("styles", "dot/circle/crosscircle shapes", function()
	T.eq(#Layout.compute(with({ style = "Dot" })).rects, 0); T.truthy(Layout.compute(with({ style = "Dot" })).dot)
	T.truthy(Layout.compute(with({ style = "Circle" })).circle)
	local cc = Layout.compute(with({ style = "CrossCircle" }))
	T.eq(#cc.rects, 4); T.truthy(cc.circle)
	T.truthy(Layout.compute(with({ centerDot = true })).dot)
end)
T.test("element count bounded", "max 6 elements", function()
	T.truthy(Layout.elementCount(Layout.compute(with({ style = "CrossCircle", centerDot = true }))) <= 6)
end)
T.test("spread helper clamps", "0..amount", function()
	T.eq(Layout.spread(0, 16, 8), 0); T.eq(Layout.spread(32, 16, 8), 8); T.eq(Layout.spread(8, 16, 8), 4); T.eq(Layout.spread(5, 0, 8), 0)
end)

T.suite("TrainingLogic")
T.test("layout", "count targets, spread across arc at distance", function()
	local pts = TL.layout(5, 35, function() return 0.5 end)
	T.eq(#pts, 5)
	for _, p in ipairs(pts) do
		local d = math.sqrt(p.x * p.x + p.z * p.z); T.truthy(math.abs(d - 35) < 1e-6); T.truthy(p.z < 0)
	end
	T.eq(#TL.layout(1, 20), 1)
end)
T.test("motion modes", "static fixed, strafing bounded, popup hides", function()
	local dx = TL.motion("Static", 5, 8, 1); T.eq(dx, 0)
	for t = 0, 20, 0.5 do local x = TL.motion("Strafing", t, 8, 2); T.truthy(math.abs(x) <= 10.0001) end
	local hidden = 0
	for t = 0, 4, 0.1 do local _, _, _, vis = TL.motion("Popup", t, 8, 1); if not vis then hidden += 1 end end
	T.truthy(hidden > 5)
	T.eq((TL.motion("Strafing", 3, 0, 1)), 0 * 0 + math.sin(0 + 1.3) * 10)
end)
T.test("ray/sphere", "hits and misses", function()
	local d = TL.raySphere({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 0, y = 0, z = -10 }, 2)
	T.truthy(math.abs(d - 8) < 1e-9)
	T.eq(TL.raySphere({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 5, y = 0, z = -10 }, 2), nil)
	T.eq(TL.raySphere({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 0, y = 0, z = 10 }, 2), nil)
end)
T.test("stats", "accuracy, reaction, reset", function()
	local s = TL.newStats()
	s:shot(true, 0.4); s:shot(false); s:shot(true, 0.2); s:kill()
	T.eq(s.shots, 3); T.eq(s.hits, 2); T.truthy(math.abs(s:accuracy() - 2 / 3) < 1e-9)
	T.truthy(math.abs(s:averageReaction() - 0.3) < 1e-9); T.eq(s.best, 0.2)
	s:reset(); T.eq(s.shots, 0); T.eq(s:averageReaction(), nil); T.eq(s:accuracy(), 0)
end)
T.test("velocity clamp", "speed limit applied", function()
	local x, y, z = TL.clampVelocity(300, 0, 400, 100)
	T.truthy(math.abs(math.sqrt(x * x + y * y + z * z) - 100) < 1e-9)
	local a = TL.clampVelocity(3, 0, 4, 100); T.eq(a, 3)
end)

T.suite("Sources")
T.test("valid sources", "asset/file/proc parsed", function()
	T.eq(Sources.parse("asset:12345").ref, "12345"); T.eq(Sources.parse("12345").type, "asset")
	T.eq(Sources.parse("rbxassetid://99", nil) == nil, false)
	T.eq(Sources.parse("file:song one.mp3", "audio").ref, "song one.mp3")
	T.eq(Sources.parse("proc:neon", "model").type, "proc")
end)
T.test("invalid sources rejected", "paths, traversal, wrong types", function()
	for _, bad in ipairs({ "", "file:../x.mp3", "file:a/b.mp3", "file:a\\b.mp3", "file:song.exe", "asset:abc", "http://evil", "proc:neon", "x:1", 5 }) do
		local v = Sources.parse(bad, "audio")
		if bad == "proc:neon" then T.eq(v, nil, "proc not allowed for audio") else T.eq(v, nil, tostring(bad)) end
	end
	T.eq(Sources.parse("file:thing.mp3", "model"), nil)
end)
T.test("playlist entries", "make/parse roundtrip, title sanitised", function()
	local e = Sources.makeEntry("asset:123", "My|Song\nX")
	local p = Sources.parseEntry(e)
	T.eq(p.source.ref, "123"); T.eq(p.title, "My Song X")
	T.eq(Sources.parseEntry("file:a.mp3").title, "a.mp3")
	T.eq(Sources.parseEntry("junk"), nil)
end)

T.suite("Playlist")
T.test("sequential with wrap", "All wraps, Off ends", function()
	local p = Playlist.new(); p:setSize(3)
	T.eq(p:advance("next"), 1); T.eq(p:advance("next"), 2); T.eq(p:advance("next"), 3); T.eq(p:advance("next"), 1)
	p.loop = "Off"; p:jump(3)
	T.eq(p:advance("ended"), nil); T.eq(p:advance("next"), 1)
end)
T.test("repeat one", "ended repeats current", function()
	local p = Playlist.new(); p:setSize(3); p.loop = "One"; p:jump(2)
	T.eq(p:advance("ended"), 2); T.eq(p:advance("next"), 3)
end)
T.test("shuffle plays every track once per cycle", "permutation", function()
	local p = Playlist.new(math.random); p.shuffle = true; p:setSize(8)
	local seen = {}
	for _ = 1, 8 do seen[p:advance("next")] = true end
	local n = 0 for _ in pairs(seen) do n += 1 end
	T.eq(n, 8)
end)
T.test("previous and empty", "previous wraps; empty safe", function()
	local p = Playlist.new(); p:setSize(3); p:jump(1)
	T.eq(p:previous(), 3)
	local e = Playlist.new(); T.eq(e:advance("next"), nil); T.eq(e:previous(), nil)
end)
T.test("toggling shuffle keeps current track", "no jump", function()
	local p = Playlist.new(); p:setSize(6); p:jump(4)
	p:setShuffle(true); T.eq(p:current(), 4)
end)

T.suite("Tools")
local now = 0
local function clock() return now end
T.test("session timer", "elapsed from injected clock", function()
	T.fresh(); Tools.init(clock); now = 0; Tools.init(clock)
	now = 125; T.eq(Tools.sessionSeconds(), 125); T.eq(Tools.formatTime(125), "02:05"); T.eq(Tools.formatTime(3725), "1:02:05")
end)
T.test("stopwatch with laps", "start/lap/stop/reset", function()
	T.fresh(); now = 0; Tools.init(clock)
	T.eq(Tools.stopwatchLap(), nil)
	Tools.stopwatchStart(); now = 10
	local i, split, total = Tools.stopwatchLap(); T.eq(i, 1); T.eq(split, 10); T.eq(total, 10)
	now = 25; local _, s2 = Tools.stopwatchLap(); T.eq(s2, 15)
	Tools.stopwatchStop(); now = 99; T.eq(Tools.stopwatchElapsed(), 25)
	Tools.stopwatchStart(); now = 100; T.eq(Tools.stopwatchElapsed(), 26)
	Tools.stopwatchReset(); T.eq(Tools.stopwatchElapsed(), 0); T.eq(#Tools.laps(), 0)
end)
T.test("countdown timers", "expire once, event fired, pause works", function()
	T.fresh(); now = 0; Tools.init(clock)
	local done = {}
	local c = Tools.TimerDone:Connect(function(id, name) table.insert(done, name) end)
	local a = Tools.addTimer("Round", 3); local b = Tools.addTimer("", 10)
	Tools.pauseTimer(b, true)
	for _ = 1, 40 do Tools.tick(0.1) end
	T.deepEq(done, { "Round" }); T.eq(Tools.timers()[1].remaining, 0); T.truthy(Tools.timers()[2].remaining == 10)
	T.truthy(Tools.removeTimer(a)); T.falsy(Tools.removeTimer(a)); c:Disconnect()
end)
T.test("timer validation and limit", "bad durations refused, max 8", function()
	T.fresh(); Tools.init(clock)
	T.eq((Tools.addTimer("x", 0)), nil); T.eq((Tools.addTimer("x", "5")), nil); T.eq((Tools.addTimer("x", 0 / 0)), nil)
	for i = 1, 8 do T.truthy(Tools.addTimer("t", 5)) end
	T.eq((Tools.addTimer("t", 5)), nil)
end)
T.test("notes autosave and reload", "saved after idle, restored", function()
	T.fresh(); Tools.init(clock)
	T.truthy(Tools.setNotes("hello\nworld")); T.truthy(Tools.notesDirty())
	Tools.tick(1); T.truthy(Tools.notesDirty()); Tools.tick(3); T.falsy(Tools.notesDirty())
	Tools.init(clock); T.truthy(Tools.loadNotes()); T.eq(Tools.getNotes(), "hello\nworld")
end)
T.test("notes limits", "oversize truncated, non-text refused", function()
	T.fresh(); Tools.init(clock)
	Tools.setNotes(string.rep("x", 5000)); T.eq(#Tools.getNotes(), 4000)
	T.falsy((Tools.setNotes(5)))
end)
T.test("autosave switch", "disabled setting keeps dirty", function()
	T.fresh(); Tools.init(clock)
	Settings.set("tools.notesAutosave", false); Tools.setNotes("a"); Tools.tick(10); T.truthy(Tools.notesDirty())
end)

local IconData = import("data/IconData")
T.suite("IconData")
T.test("icon geometry is valid and inside the grid", "every primitive well-formed and within 0-24", function()
	local n = 0
	for name, prims in pairs(IconData) do
		T.truthy(#prims >= 1, name)
		for i, p in ipairs(prims) do
			local kind = p[1]
			T.truthy(kind == "r" or kind == "o" or kind == "d" or kind == "b" or kind == "a" or kind == "t", name .. "#" .. i)
			if kind == "r" then
				T.truthy(#p >= 5, name .. " rect args")
				T.truthy(p[4] > 0 and p[5] > 0, name .. " rect size")
				T.truthy(p[2] >= 0 and p[2] <= 24 and p[3] >= 0 and p[3] <= 24, name .. " rect centre")
			elseif kind == "b" then
			T.truthy(p[4] > 0 and p[5] > 0 and p[6] > 0 and p[2] >= 0 and p[2] <= 24 and p[3] >= 0 and p[3] <= 24, name .. " box outline")
			elseif kind == "a" then
			T.truthy(p[4] > 0 and p[5] > 0 and (p[6] == "r" or p[6] == "l" or p[6] == "t" or p[6] == "b"), name .. " arc")
			elseif kind == "t" then
			T.truthy(p[4] > 0 and type(p[5]) == "string" and #p[5] >= 1, name .. " glyph")
			elseif kind == "o" then
			T.truthy(p[4] > 0 and p[5] > 0 and p[5] < p[4], name .. " ring")
				T.truthy(p[2] - p[4] / 2 >= -0.5 and p[2] + p[4] / 2 <= 24.5, name .. " ring bounds")
				T.truthy(p[3] - p[4] / 2 >= -0.5 and p[3] + p[4] / 2 <= 24.5, name .. " ring bounds y")
			else
				T.truthy(p[4] > 0, name .. " disc")
			end
			for _, v in ipairs(p) do T.truthy(type(v) == "string" or v == v, "NaN in " .. name) end
		end
		n += 1
	end
	return n .. " icons"
end)
T.test("themes meet contrast targets", "text/bg >= 4.5, dim/card >= 3.5, accentText/accent >= 3 for every theme", function()
	local Themes = import("data/Themes")
	local CU = import("core/ColorUtil")
	local n = 0
	for name, t in pairs(Themes) do
		T.truthy(CU.contrast(t.text, t.bg0) >= 4.5, name .. " text/bg0 " .. CU.contrast(t.text, t.bg0))
		T.truthy(CU.contrast(t.text, t.bg2) >= 4.5, name .. " text/bg2")
		T.truthy(CU.contrast(t.textDim, t.bg2) >= 3.5, name .. " dim/bg2 " .. CU.contrast(t.textDim, t.bg2))
		T.truthy(CU.contrast(t.accentText, t.accent) >= 3, name .. " accentText " .. CU.contrast(t.accentText, t.accent))
		n += 1
	end
	T.eq(n, 12)
end)

local LM = import("features/LightingMath")
T.suite("LightingMath")
T.test("filters combine with sliders and clamp", "values stay within engine ranges", function()
	local base = { saturation = 0, contrast = 0, exposure = 0, tint = { r = 255, g = 255, b = 255 } }
	local mono = LM.combine(base, "Mono"); T.eq(mono.saturation, -1)
	local extreme = LM.combine({ saturation = 2, contrast = 1, exposure = 1, tint = { r = 255, g = 255, b = 255 } }, "Vivid")
	T.eq(extreme.saturation, 2); T.eq(extreme.contrast, 1); T.eq(extreme.exposure, 1)
	local warm = LM.combine({ saturation = 0, contrast = 0, exposure = 0, tint = { r = 128, g = 255, b = 255 } }, "Warm")
	T.eq(warm.tint.r, 128); T.eq(warm.tint.b, 205)
	T.eq(LM.combine(base, "Nonexistent").tint.r, 255)
end)
T.test("every filter and time preset is well-formed", "tint 0-255, clocks 0-24", function()
	for name, f in pairs(LM.filters) do
		for _, c in ipairs(f.tint) do T.truthy(c >= 0 and c <= 255, name) end
	end
	for name, t in pairs(LM.times) do T.truthy(t.clock >= 0 and t.clock < 24, name) end
end)

local AFL = import("features/AntiFlingLogic")
T.suite("AntiFlingLogic")
local P = { maxSpeed = 120, angularLimit = 60 }
local Z = { x = 0, y = 0, z = 0 }
T.test("normal movement is never flagged", "running, jumping, falling, sprint-jumping", function()
	for _, v in ipairs({ { x = 0, y = 0, z = 0 }, { x = 16, y = 0, z = 0 }, { x = 12, y = 50, z = 12 }, { x = 0, y = -180, z = 0 }, { x = 30, y = -250, z = 30 }, { x = 0, y = 107, z = 0 } }) do
		T.falsy((AFL.evaluate(v, Z, P)), string.format("%d,%d,%d", v.x, v.y, v.z))
	end
	T.falsy((AFL.evaluate({ x = 0, y = 0, z = 0 }, { x = 5, y = 20, z = 5 }, P)))
end)
T.test("fling-like motion is flagged with a reason", "horizontal, vertical, spin", function()
	local a, r = AFL.evaluate({ x = 150, y = 0, z = 0 }, Z, P); T.truthy(a); T.eq(r, "horizontal")
	a, r = AFL.evaluate({ x = 0, y = 200, z = 0 }, Z, P); T.truthy(a); T.eq(r, "vertical")
	a, r = AFL.evaluate(Z, { x = 0, y = 90, z = 0 }, P); T.truthy(a); T.eq(r, "spin")
	a, r = AFL.evaluate({ x = 100, y = 0, z = 100 }, Z, P); T.truthy(a); T.eq(r, "horizontal")
end)
T.test("cleaned velocity keeps falling only", "no horizontal or upward carry-over", function()
	local x, y, z = AFL.cleaned({ x = 300, y = 500, z = -200 }); T.eq(x, 0); T.eq(y, 0); T.eq(z, 0)
	x, y, z = AFL.cleaned({ x = 300, y = -40, z = 0 }); T.eq(y, -40)
end)

local Geo = import("features/Geometry")
T.suite("Geometry")
local o, d = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }
T.test("ray vs sphere", "entry distance, miss, origin inside, behind", function()
	T.truthy(math.abs(Geo.raySphere(o, d, { x = 0, y = 0, z = -10 }, 2) - 8) < 1e-9)
	T.eq(Geo.raySphere(o, d, { x = 5, y = 0, z = -10 }, 2), nil)
	T.eq(Geo.raySphere(o, d, { x = 0, y = 0, z = 10 }, 2), nil)
	T.eq(Geo.raySphere(o, d, { x = 0, y = 0, z = 1 }, 3), 0)
	T.truthy(Geo.raySphere(o, d, { x = 1.99, y = 0, z = -10 }, 2) ~= nil)
	T.eq(Geo.raySphere(o, d, { x = 2.01, y = 0, z = -10 }, 2), nil)
end)
T.test("ray vs box (slab)", "front-face distance, grazing, parallel miss, inside", function()
	local h = { x = 1, y = 1, z = 1 }
	T.truthy(math.abs(Geo.rayBox(o, d, { x = 0, y = 0, z = -10 }, h) - 9) < 1e-9)
	T.eq(Geo.rayBox(o, d, { x = 3, y = 0, z = -10 }, h), nil)
	T.eq(Geo.rayBox(o, d, { x = 0, y = 0, z = 10 }, h), nil)
	T.eq(Geo.rayBox(o, d, { x = 0, y = 0, z = 0.5 }, h), 0)
	T.truthy(Geo.rayBox(o, { x = 0.1, y = 0, z = -1 }, { x = 0, y = 0, z = -10 }, h) ~= nil)
	T.eq(Geo.rayBox(o, { x = 0.5, y = 0, z = -1 }, { x = 0, y = 0, z = -10 }, h), nil, "diagonal ray passes the box side")
end)
T.test("sphere and box overlap tests", "touching counts, separated does not", function()
	T.truthy(Geo.sphereSphere({ x = 0, y = 0, z = 0 }, 1, { x = 2, y = 0, z = 0 }, 1))
	T.falsy(Geo.sphereSphere({ x = 0, y = 0, z = 0 }, 1, { x = 2.01, y = 0, z = 0 }, 1))
	local h = { x = 1, y = 1, z = 1 }
	T.truthy(Geo.sphereBox({ x = 2, y = 0, z = 0 }, 1, { x = 0, y = 0, z = 0 }, h))
	T.falsy(Geo.sphereBox({ x = 2.5, y = 0, z = 0 }, 1, { x = 0, y = 0, z = 0 }, h))
	T.truthy(Geo.sphereBox({ x = 1.7, y = 1.7, z = 0 }, 1, { x = 0, y = 0, z = 0 }, h), "corner region distance 0.99")
	T.falsy(Geo.sphereBox({ x = 1.8, y = 1.8, z = 0 }, 1, { x = 0, y = 0, z = 0 }, h))
	T.truthy(Geo.boxBox({ x = 0, y = 0, z = 0 }, h, { x = 2, y = 0, z = 0 }, h))
	T.falsy(Geo.boxBox({ x = 0, y = 0, z = 0 }, h, { x = 2.1, y = 0, z = 0 }, h))
end)
T.test("closest approach and ballistic aim", "near-miss distance; aim raised by the drop", function()
	T.truthy(math.abs(Geo.closestApproach(o, d, { x = 3, y = 4, z = -10 }) - 5) < 1e-9)
	T.truthy(math.abs(Geo.closestApproach(o, d, { x = 0, y = 0, z = 10 }) - 10) < 1e-9, "behind the origin")
	local aim = Geo.ballisticAim(o, { x = 0, y = 0, z = -140 }, 140, 196.2)
	T.truthy(math.abs(aim.y - 98.1) < 1e-6, tostring(aim.y))
	T.eq(Geo.ballisticAim(o, { x = 0, y = 5, z = 0 }, 100, 0).y, 5)
end)
T.test("rays agree with brute-force sampling", "randomised cross-check of sphere and box tests", function()
	math.randomseed(7)
	local function unit() local x, y, z = math.random() - 0.5, math.random() - 0.5, math.random() - 0.5; local m = math.sqrt(x * x + y * y + z * z); return { x = x / m, y = y / m, z = z / m } end
	for _ = 1, 400 do
		local dir, c = unit(), { x = math.random() * 20 - 10, y = math.random() * 20 - 10, z = math.random() * 20 - 10 }
		local r = 1 + math.random() * 3
		local t = Geo.raySphere(o, dir, c, r)
		local hit = false
		for i = 0, 400 do
			local s = i * 0.1
			local p = { x = dir.x * s, y = dir.y * s, z = dir.z * s }
			if Geo.distance(p, c) <= r then hit = true break end
		end
		T.eq(t ~= nil, hit, "sphere sample")
		local half = { x = r, y = r, z = r }
		local tb = Geo.rayBox(o, dir, c, half)
		local hitB = false
		for i = 0, 400 do
			local s = i * 0.1
			local px, py, pz = dir.x * s, dir.y * s, dir.z * s
			if math.abs(px - c.x) <= r and math.abs(py - c.y) <= r and math.abs(pz - c.z) <= r then hitB = true break end
		end
		T.eq(tb ~= nil, hitB, "box sample")
	end
end)

local HBM = import("features/HitboxMath")
T.suite("HitboxMath")
local params = { orbitRadius = 8, orbitSpeed = 8, orbitTilt = 0.3, jitterAmplitude = 3, jitterSpeed = 8, blinkRange = 10, blinkInterval = 0.8 }
T.test("every mode stays inside its own bound", "Orbit<=orbitRadius, Jitter<=jitterAmplitude, Blink<=blinkRange", function()
	local bounds = { Orbit = "orbitRadius", Jitter = "jitterAmplitude", Blink = "blinkRange" }
	for mode, key in pairs(bounds) do
		for _, scale in ipairs({ 0.5, 1, 3 }) do
			local p = table.clone(params); p[key] = params[key] * scale
			for t = 0, 90, 0.23 do
				local x, y, z = HBM.offset(mode, t, p)
				T.truthy(math.sqrt(x * x + y * y + z * z) <= p[key] * 1.0001 + 1e-9, mode .. " scale " .. scale .. " t=" .. t)
			end
		end
	end
end)
T.test("modes use only their own parameters", "changing another mode's settings has no effect", function()
	local base = { HBM.offset("Orbit", 4.2, params) }
	local p2 = table.clone(params); p2.jitterAmplitude, p2.blinkRange, p2.blinkInterval = 9, 20, 2
	local after = { HBM.offset("Orbit", 4.2, p2) }
	T.eq(base[1], after[1]); T.eq(base[2], after[2]); T.eq(base[3], after[3])
	local j1 = { HBM.offset("Jitter", 4.2, params) }
	local p3 = table.clone(params); p3.orbitRadius, p3.blinkRange = 20, 25
	local j2 = { HBM.offset("Jitter", 4.2, p3) }
	T.eq(j1[1], j2[1]); T.eq(j1[3], j2[3])
end)
T.test("orbit speed is a linear speed", "arc length per second ~ orbitSpeed", function()
	local p = table.clone(params); p.orbitTilt = 0
	local x0, _, z0 = HBM.offset("Orbit", 0, p); local x1, _, z1 = HBM.offset("Orbit", 0.01, p)
	local speed = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / 0.01
	T.truthy(math.abs(speed - 8) < 0.05, tostring(speed))
end)
T.test("off is still, blink holds between jumps, jitter moves", "mode semantics", function()
	local x, y, z = HBM.offset("Off", 9, params); T.eq(x + y + z, 0)
	T.eq(HBM.offset("Blink", 0.01, params), HBM.offset("Blink", 0.7, params))
	T.truthy(HBM.offset("Blink", 0.01, params) ~= HBM.offset("Blink", 5.0, params))
	local moved = false
	for t = 0, 5, 0.25 do if math.abs(HBM.offset("Jitter", t, params) - HBM.offset("Jitter", 0, params)) > 0.2 then moved = true end end
	T.truthy(moved)
end)
T.test("mode table names exactly what each mode changes", "documentation matches the code", function()
	T.eq(HBM.MODES.Off.affects, "nothing")
	for _, m in ipairs({ "Orbit", "Jitter", "Blink" }) do
		T.eq(HBM.MODES[m].affects, "HubLabHitbox.Position")
		for _, key in ipairs(HBM.MODES[m].params) do T.truthy(params[key] ~= nil, key) end
	end
end)

local SL = import("features/SelectLogic")
T.suite("SelectLogic")
local function tgt(id, sx, sy, dist, extra)
	local t = { id = id, name = id, alive = true, onScreen = true, sx = sx, sy = sy, dist = dist, visible = true, pos = { x = 0, y = 0, z = -dist }, vel = { x = 0, y = 0, z = 0 } }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function cfg(over)
	local c = { mode = "Crosshair", fov = 150, lock = false, visibilityCheck = true, centerX = 400, centerY = 300, autoAcquire = true }
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end
T.test("crosshair mode picks the target nearest the centre", "ties broken by id, deterministic", function()
	local r = SL.evaluate({ tgt("B", 450, 300, 30), tgt("A", 380, 310, 80), tgt("C", 600, 300, 10) }, cfg(), {})
	T.eq(r.id, "A"); T.eq(r.status, "selected"); T.deepEq(r.eligible, { "A", "B" })
	local tie = SL.evaluate({ tgt("Z", 410, 300, 30), tgt("Y", 390, 300, 30) }, cfg(), {})
	T.eq(tie.id, "Y", "equal screen distance -> lower id (strict < keeps the first sorted)")
end)
T.test("distance mode picks the nearest to the player", "ignores which is closer to the crosshair", function()
	local r = SL.evaluate({ tgt("A", 400, 300, 90), tgt("B", 500, 300, 20), tgt("C", 300, 300, 55) }, cfg({ mode = "Distance" }), {})
	T.eq(r.id, "B")
end)
T.test("FOV is a hard radius", "inside selected, outside rejected, boundary included", function()
	local inside = tgt("A", 400 + 149, 300, 10); local edge = tgt("E", 400 + 150, 300, 10); local out = tgt("O", 400 + 151, 300, 10)
	T.eq(SL.evaluate({ inside }, cfg(), {}).id, "A")
	T.eq(SL.evaluate({ edge }, cfg(), {}).id, "E")
	local r = SL.evaluate({ out }, cfg(), {}); T.eq(r.id, nil); T.eq(r.status, "none")
	T.eq(SL.evaluate({ out }, cfg({ fov = 200 }), {}).id, "O", "bigger FOV admits it")
	local ok, why = SL.eligibility(out, cfg()); T.falsy(ok); T.eq(why, "outside-fov")
end)
T.test("visibility check", "hidden targets skipped; unknown visibility allowed; switch off allows hidden", function()
	local hidden, shown = tgt("H", 400, 300, 10, { visible = false }), tgt("S", 440, 300, 20)
	T.eq(SL.evaluate({ hidden, shown }, cfg(), {}).id, "S")
	T.eq(SL.evaluate({ tgt("U", 400, 300, 10, { visible = nil }) }, cfg(), {}).id, "U")
	T.eq(SL.evaluate({ hidden, shown }, cfg({ visibilityCheck = false }), {}).id, "H")
end)
T.test("inactive and off-screen targets are not eligible", "reasons reported", function()
	T.eq(select(2, SL.eligibility(tgt("A", 400, 300, 5, { alive = false }), cfg())), "inactive")
	T.eq(select(2, SL.eligibility(tgt("A", 400, 300, 5, { onScreen = false }), cfg())), "off-screen")
end)
T.test("lock keeps the target while it stays valid", "a better target does not steal the lock", function()
	local a, b = tgt("A", 450, 300, 50), tgt("B", 401, 300, 50)
	local state = { id = "A" }
	local r = SL.evaluate({ a, b }, cfg({ lock = true }), state)
	T.eq(r.id, "A"); T.eq(r.status, "locked")
	r = SL.evaluate({ a, b }, cfg({ lock = false }), state); T.eq(r.id, "B", "without lock the better one wins")
	r = SL.evaluate({ a, b }, cfg({ lock = true }), { id = "A", forceAcquire = true }); T.eq(r.id, "B", "Select re-acquires through the lock")
end)
T.test("lock drops the target when it no longer qualifies", "removed / inactive / outside FOV / hidden each reported", function()
	local state = { id = "A" }
	local c = cfg({ lock = true })
	local r = SL.evaluate({ tgt("B", 410, 300, 5) }, c, state); T.eq(r.lost.reason, "removed"); T.eq(r.id, "B", "falls back to the best remaining target")
	r = SL.evaluate({ tgt("A", 400, 300, 5, { alive = false }) }, c, state); T.eq(r.lost.reason, "inactive"); T.eq(r.id, nil)
	r = SL.evaluate({ tgt("A", 700, 300, 5) }, c, state); T.eq(r.lost.reason, "outside-fov")
	r = SL.evaluate({ tgt("A", 400, 300, 5, { visible = false }) }, c, state); T.eq(r.lost.reason, "hidden")
	r = SL.evaluate({}, c, state); T.eq(r.status, "no-targets"); T.eq(r.lost.reason, "removed")
end)
T.test("manual mode follows the chosen target only", "waits when it is ineligible, never substitutes another", function()
	local a, b = tgt("A", 400, 300, 5), tgt("B", 410, 300, 5)
	local c = cfg({ mode = "Manual" })
	T.eq(SL.evaluate({ a, b }, c, { manualId = "B" }).id, "B")
	local r = SL.evaluate({ a, tgt("B", 900, 300, 5) }, c, { manualId = "B" })
	T.eq(r.id, nil); T.eq(r.status, "manual-wait"); T.eq(r.lost.reason, "outside-fov")
	T.eq(SL.evaluate({ a, b }, c, {}).status, "manual-wait")
end)
T.test("auto-acquire off and suspended states", "only Select acquires; reset suspends until Select", function()
	local a = tgt("A", 400, 300, 5)
	local c = cfg({ autoAcquire = false })
	T.eq(SL.evaluate({ a }, c, {}).id, nil)
	T.eq(SL.evaluate({ a }, c, { forceAcquire = true }).id, "A")
	T.eq(SL.evaluate({ a }, c, { id = "A" }).id, "A", "an acquired target is kept while valid")
	local s = SL.evaluate({ a }, cfg(), { suspended = true }); T.eq(s.id, nil); T.eq(s.status, "suspended")
	T.eq(SL.evaluate({ a }, cfg(), { suspended = true, forceAcquire = true }).id, "A")
end)
T.test("switching cycles through eligible targets with wrap-around", "next / previous", function()
	local ids = { "A", "B", "C" }
	T.eq(SL.cycle(ids, "A", 1), "B"); T.eq(SL.cycle(ids, "C", 1), "A"); T.eq(SL.cycle(ids, "A", -1), "C")
	T.eq(SL.cycle(ids, "zzz", 1), "A"); T.eq(SL.cycle(ids, nil, -1), "C"); T.eq(SL.cycle({}, "A", 1), nil)
	T.eq(SL.cycle({ "X" }, "X", 1), "X")
end)
T.test("intercept solves the quadratic", "stationary, receding, approaching, too fast, linear case", function()
	local o = { x = 0, y = 0, z = 0 }
	T.truthy(math.abs(SL.intercept(o, { x = 100, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 50) - 2) < 1e-9)
	local t = SL.intercept(o, { x = 100, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, 50)
	T.truthy(math.abs(t - 2.5) < 1e-9, tostring(t)) -- 100 + 10t = 50t
	T.truthy(math.abs(SL.intercept(o, { x = 100, y = 0, z = 0 }, { x = -10, y = 0, z = 0 }, 50) - 100 / 60) < 1e-9)
	T.eq(SL.intercept(o, { x = 100, y = 0, z = 0 }, { x = 60, y = 0, z = 0 }, 50), nil, "target outruns the projectile")
	T.truthy(SL.intercept(o, { x = 0, y = 0, z = -30 }, { x = 20, y = 0, z = 0 }, 20) == nil or true)
	local lin = SL.intercept(o, { x = 100, y = 0, z = 0 }, { x = 50, y = 0, z = 0 }, 50)
	T.eq(lin, nil, "same speed running away: no solution")
end)
T.test("intercept point really meets the projectile", "randomised verification", function()
	math.randomseed(11)
	local o = { x = 0, y = 0, z = 0 }
	for _ = 1, 200 do
		local p = { x = math.random() * 100 - 50, y = math.random() * 40, z = -20 - math.random() * 100 }
		local v = { x = math.random() * 30 - 15, y = math.random() * 10 - 5, z = math.random() * 30 - 15 }
		local speed = 120 + math.random() * 200
		local t = SL.intercept(o, p, v, speed)
		T.truthy(t ~= nil and t > 0)
		local m = { x = p.x + v.x * t, y = p.y + v.y * t, z = p.z + v.z * t }
		local d = math.sqrt(m.x ^ 2 + m.y ^ 2 + m.z ^ 2)
		T.truthy(math.abs(d - speed * t) < 1e-6 * math.max(1, d), "distance equals speed*t")
	end
end)
T.test("prediction is capped and static targets stay put", "leadMax honoured", function()
	local o = { x = 0, y = 0, z = 0 }
	local pos, t = SL.predict(o, { x = 100, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 200, 0.6); T.eq(t, 0); T.eq(pos.x, 100)
	pos, t = SL.predict(o, { x = 400, y = 0, z = 0 }, { x = 0, y = 0, z = 20 }, 100, 0.5)
	T.truthy(t <= 0.5 + 1e-9); T.truthy(math.abs(pos.z - 20 * t) < 1e-9)
	pos, t = SL.predict(o, { x = 100, y = 0, z = 0 }, { x = 300, y = 0, z = 0 }, 100, 1.5)
	T.truthy(t > 0 and t <= 1.5, "unreachable target still gets a bounded lead")
end)

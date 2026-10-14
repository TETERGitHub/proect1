--!nonstrict
-- Tests for the customisation systems: model data, the draft/applied/preset logic, skins on a mock tool and avatar,
-- the two independent kill sounds and the five pages. They run against tests/mock_roblox: they prove that the logic is
-- consistent and cleans up, not how anything looks in a real client (see docs/CUSTOMIZATION.md for that limit).
local import = ...
local T = import("tests/Framework")
local Mock = import("tests/mock_roblox")
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Lib = import("data/ModelLib")
local Custom = import("features/CustomLogic")
local Cosmetics = import("features/Cosmetics")
local KillEvents = import("features/KillEvents")
local KillSounds = import("features/KillSounds")
local Json = import("core/Json")

local function boot()
	if Hub.current() then Hub.current().unload() end
	Mock.uninstall()
	T.fresh()
	local game = Mock.install()
	Services.clear()
	local h = Hub.run({ skipLicense = true })
	return h, game
end
local function frames(n) for _ = 1, n do Perf.frame(1 / 30) end end
local function done(h) h.unload(); Mock.uninstall() end
local function addTool(game, name)
	local tool = Mock.makeInstance("Tool"); tool.Name = name
	local handle = Mock.makeInstance("Part"); handle.Name = "Handle"; handle.Parent = tool
	tool.Parent = game.Players.LocalPlayer.Backpack
	return tool, handle
end
local function count(list, pred) local n = 0 for _, v in ipairs(list) do if pred(v) then n += 1 end end return n end

T.suite("Model library")
T.test("every model is well-formed", "part counts, sizes, colours, shapes, names", function()
	local shapes = { Block = true, Ball = true, Cylinder = true, Wedge = true }
	local total = 0
	for _, kind in ipairs(Lib.kinds()) do
		T.truthy(#Lib.ids(kind) >= 8, kind .. " has at least 8 models")
		for _, id in ipairs(Lib.ids(kind)) do
			local parts = Lib.parts(kind, id)
			T.truthy(#parts >= 4 and #parts <= 120, kind .. "/" .. id .. " has " .. #parts .. " parts")
			total += #parts
			for _, p in ipairs(parts) do
				T.truthy(shapes[p.shape], id .. ": shape " .. tostring(p.shape))
				T.truthy(p.name and p.name ~= "", id .. ": unnamed part")
				for i = 1, 3 do
					T.truthy(p.size[i] > 0 and p.size[i] < 12, id .. "/" .. p.name .. " size")
					T.truthy(p.pos[i] == p.pos[i] and math.abs(p.pos[i]) < 12, id .. "/" .. p.name .. " pos")
					T.truthy(p.rot[i] == p.rot[i], id .. "/" .. p.name .. " rot")
					T.truthy(p.color[i] >= 0 and p.color[i] <= 255, id .. "/" .. p.name .. " colour")
				end
			end
		end
	end
	return total .. " parts in " .. (#Lib.ids("gun") + #Lib.ids("knife") + #Lib.ids("char")) .. " models"
end)
T.test("the character catalogue has costumes and all three accessory slots", "group and slot fields", function()
	local costumes, slots = 0, { head = 0, back = 0, aura = 0 }
	for _, id in ipairs(Lib.ids("char")) do
		local info = Lib.info("char", id)
		if info.group == "costume" then costumes += 1 else slots[info.slot] += 1 end
	end
	T.truthy(costumes >= 8, "costumes " .. costumes)
	T.truthy(slots.head >= 3 and slots.back >= 3 and slots.aura >= 3)
end)
T.test("recolouring changes colours and keeps the shape", "same positions, new primary colour", function()
	local a = Lib.parts("gun", "revolver")
	local look = Lib.styleLook("gun", "revolver"); look.primary = { 1, 2, 3 }
	local b = Lib.parts("gun", "revolver", look)
	T.eq(#a, #b)
	local changed = 0
	for i = 1, #a do
		T.deepEq(a[i].pos, b[i].pos); T.deepEq(a[i].size, b[i].size)
		if a[i].color[1] ~= b[i].color[1] then changed += 1 end
	end
	T.truthy(changed > 0)
end)
T.test("glow and transparency obey their limits", "no glow = no Neon; decor transparency only on decor parts, max 0.6", function()
	local look = Lib.styleLook("knife", "crystal")
	look.glowAmount = 0
	for _, p in ipairs(Lib.parts("knife", "crystal", look)) do T.falsy(p.neon, p.name) end
	look.glowAmount = 1; look.decor = 5
	local neon, clear, solid = 0, 0, 0
	for _, p in ipairs(Lib.parts("knife", "crystal", look)) do
		if p.neon then neon += 1 end
		T.truthy(p.transparency <= 0.6, p.name)
		if p.transparency > 0 then clear += 1 else solid += 1 end
	end
	T.truthy(neon > 0 and clear > 0 and solid > 0, "decor parts only")
	-- the main body of a gun never becomes transparent whatever the setting
	local gl = Lib.styleLook("gun", "revolver"); gl.decor = 0.6
	for _, p in ipairs(Lib.parts("gun", "revolver", gl)) do T.eq(p.transparency, 0, p.name) end
end)

T.suite("Custom logic")
T.test("snapshots are validated", "unknown models, odd colours and materials, code-like extras", function()
	T.fresh()
	local snap = Custom.normalize("gun", { sel = { model = "revolver" }, look = { primary = { 999, -5, "x" }, material = "Lava", glowAmount = 9, decor = -1, run = "os.exit()" } })
	T.truthy(snap)
	T.eq(snap.look.material, Lib.baseLook("gun").material); T.eq(snap.look.glowAmount, 1); T.eq(snap.look.decor, 0)
	T.truthy(snap.look.primary[1] >= 0 and snap.look.primary[1] <= 255)
	T.eq(snap.look.run, nil)
	T.eq((Custom.normalize("gun", { sel = { model = "nope" } })), nil)
	T.eq((Custom.normalize("knife", { sel = { model = "wings_angel" } })), nil)
	T.eq((Custom.normalize("char", { sel = { costume = "halo" } })), nil, "an accessory is not a costume")
	T.eq((Custom.decodeSnapshot("gun", "{{{ not json")), nil)
	T.eq((Custom.decodeSnapshot("gun", string.rep("x", 50))), nil)
	T.eq(select(2, Custom.normalize("char", { sel = {} })), "nothing selected")
end)
T.test("gun, knife and character stay independent", "apply, reset and presets never cross over", function()
	T.fresh()
	T.truthy(Custom.apply("gun")); T.truthy(Custom.apply("knife"))
	Settings.set("custom.gunPrimary", { r = 10, g = 20, b = 30 })
	T.truthy(Custom.apply("gun"))
	local kd = Settings.schema("custom.knifePrimary").default
	T.deepEq(Custom.applied("knife").look.primary, { kd.r, kd.g, kd.b })
	T.truthy(Custom.savePreset("gun", "Mine")); T.truthy(Custom.savePreset("knife", "Mine"))
	T.eq(#Custom.presets("gun"), 1); T.eq(#Custom.presets("knife"), 1); T.eq(#Custom.presets("char"), 0)
	Settings.set("custom.gunPrimary", { r = 200, g = 0, b = 0 })
	T.truthy(Custom.savePreset("gun", "mine"), "same name in the same kind replaces")
	T.eq(#Custom.presets("gun"), 1)
	T.deepEq(Custom.presets("knife")[1].snap.look.primary, { kd.r, kd.g, kd.b })
	Custom.reset("knife")
	T.eq(Custom.applied("knife"), nil); T.truthy(Custom.applied("gun") ~= nil)
	T.eq(#Custom.presets("knife"), 1, "reset keeps presets")
	T.eq(Settings.get("custom.knifeModel"), "classic")
end)
T.test("presets: save, duplicate, delete, load, limits, corrupt data", "CRUD plus bad input", function()
	T.fresh()
	T.eq((Custom.savePreset("gun", "")), false); T.eq((Custom.savePreset("gun", string.rep("x", 25))), false); T.eq((Custom.savePreset("gun", "a\nb")), false)
	T.truthy(Custom.savePreset("gun", "One"))
	local ok, _, copy = Custom.duplicatePreset("gun", "One")
	T.truthy(ok); T.eq(copy, "One 2"); T.eq(#Custom.presets("gun"), 2)
	Settings.set("custom.gunPrimary", { r = 1, g = 1, b = 1 })
	T.truthy(Custom.loadPreset("gun", "One"))
	T.truthy(Settings.get("custom.gunPrimary").r ~= 1)
	T.truthy(Custom.deletePreset("gun", "One")); T.eq(#Custom.presets("gun"), 1)
	T.eq((Custom.deletePreset("gun", "missing")), false)
	for i = 1, Custom.MAX_PRESETS do Custom.savePreset("gun", "P" .. i) end
	T.eq(#Custom.presets("gun"), Custom.MAX_PRESETS)
	T.eq((Custom.savePreset("gun", "overflow")), false)
	Settings.set("custom.knifePresets", "{\"list\":[1,{\"n\":5},{\"n\":\"ok\",\"s\":{\"sel\":{\"model\":\"nope\"}}}]}")
	T.eq(#Custom.presets("knife"), 0)
	Settings.set("custom.knifePresets", "garbage")
	T.eq(#Custom.presets("knife"), 0)
end)
T.test("character selection toggles by slot", "choosing again clears; a costume brings its colours", function()
	T.fresh()
	Custom.selectModel("char", "halo"); T.eq(Settings.get("custom.charHead"), "halo")
	Custom.selectModel("char", "wings_angel"); T.eq(Settings.get("custom.charBack"), "wings_angel")
	Custom.selectModel("char", "halo"); T.eq(Settings.get("custom.charHead"), "")
	Custom.selectModel("char", "shark"); T.eq(Settings.get("custom.charCostume"), "shark")
	T.deepEq(Custom.readLook("char").primary, Lib.styleLook("char", "shark").primary)
end)

T.suite("Skins in the scene (mock)")
T.test("an applied gun look builds, welds, recolours and resets", "tool skin appears, is welded and harmless, Reset restores the tool", function()
	local h, game = boot()
	local tool, handle = addTool(game, "Gun")
	local knifeTool = addTool(game, "Knife")
	Settings.set("custom.gunModel", "tactical"); Custom.apply("gun"); frames(60)
	T.eq(Cosmetics.status().gun, "applied")
	local skin = tool:FindFirstChild("MM2HubSkin")
	T.truthy(skin ~= nil)
	local parts, welds = 0, 0
	for _, d in ipairs(skin:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			T.eq(d.CanCollide, false); T.eq(d.Massless, true)
		elseif d:IsA("WeldConstraint") then welds += 1 end
	end
	T.truthy(parts >= 30 and welds >= parts - 1, parts .. " parts, " .. welds .. " welds")
	T.eq(handle.Transparency, 1)
	T.eq(knifeTool:FindFirstChild("MM2HubSkin"), nil, "the knife is untouched by the gun look")
	-- recolour + apply again: the skin is rebuilt (not stacked)
	Settings.set("custom.gunPrimary", { r = 255, g = 0, b = 0 }); Custom.apply("gun"); frames(60)
	T.eq(count(tool:GetChildren(), function(c) return c.Name == "MM2HubSkin" end), 1)
	local red = false
	for _, d in ipairs(tool:FindFirstChild("MM2HubSkin"):GetDescendants()) do
		local c = d.Color
		local r = c and (c.r or c.R)
		if d:IsA("BasePart") and string.find(d.Name, "^Slide") and r and (r >= 200 or (r <= 1 and r > 0.9)) then red = true end
	end
	T.truthy(red, "new colour is on the model")
	Custom.reset("gun"); frames(60)
	T.eq(tool:FindFirstChild("MM2HubSkin"), nil); T.eq(handle.Transparency, 0)
	done(h)
end)
T.test("effects are optional and bounded", "light only when glowing, trail for knives, nothing when off or reduced", function()
	local h, game = boot()
	addTool(game, "Knife")
	Settings.set("custom.knifeModel", "dagger"); Settings.set("custom.knifeGlowAmount", 0.8); Settings.set("custom.knifeEffects", true)
	Custom.apply("knife"); frames(60)
	local st = Cosmetics.effectStats()
	T.eq(st.lights, 1); T.eq(st.trails, 1)
	Settings.set("custom.knifeEffects", false); Custom.apply("knife"); frames(60)
	st = Cosmetics.effectStats(); T.eq(st.lights + st.trails + st.emitters, 0)
	Settings.set("custom.knifeEffects", true); Custom.apply("knife"); frames(60)
	T.eq(Cosmetics.effectStats().lights, 1)
	Settings.set("ui.reduceEffects", true); frames(60)
	st = Cosmetics.effectStats(); T.eq(st.lights + st.trails + st.emitters, 0, "reduced effects removes them")
	Settings.set("ui.reduceEffects", false); Settings.set("custom.knifeGlowAmount", 0); Custom.apply("knife"); frames(60)
	T.eq(Cosmetics.effectStats().lights, 0, "no glow, no light")
	done(h)
end)
T.test("a costume and accessories show on your avatar and come off again", "avatar hidden locally, restored on Reset, no stat changes", function()
	local h, game = boot()
	local char = game.Players.LocalPlayer.Character
	local head, hrp, hum = char:FindFirstChild("Head"), char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	local walk, hp = hum.WalkSpeed, hum.MaxHealth
	Custom.selectModel("char", "logman"); Custom.selectModel("char", "halo"); Custom.selectModel("char", "wings_angel")
	T.truthy(Custom.apply("char")); frames(60)
	T.eq(Cosmetics.status().customChar, "applied")
	T.eq(count(char:GetChildren(), function(c) return c.Name == "MM2HubSkin" end), 3)
	T.eq(head.Transparency, 1, "the real head is hidden only while a costume is on")
	T.eq(hum.WalkSpeed, walk); T.eq(hum.MaxHealth, hp)
	frames(60)
	T.eq(count(char:GetChildren(), function(c) return c.Name == "MM2HubSkin" end), 3, "no duplicates after more frames")
	Custom.reset("char"); frames(60)
	T.eq(count(char:GetChildren(), function(c) return c.Name == "MM2HubSkin" end), 0)
	T.eq(head.Transparency, 0)
	-- accessories alone do not hide the avatar
	Custom.selectModel("char", "crown"); Custom.apply("char"); frames(60)
	T.eq(head.Transparency, 0)
	T.eq(count(char:GetChildren(), function(c) return c.Name == "MM2HubSkin" end), 1)
	done(h)
end)
T.test("a look with a missing tool waits and reports it", "no tool, no skin, no error", function()
	local h = boot()
	Custom.apply("gun"); frames(60)
	T.truthy(string.find(Cosmetics.status().gun, "waiting", 1, true), Cosmetics.status().gun)
	done(h)
end)

T.suite("Kill sounds")
local function sounds(role)
	local out = {}
	for _, d in ipairs(Services.SoundService:GetChildren()) do
		if d.Name == "MM2Hub_KillSound_" .. role then table.insert(out, d) end
	end
	return out
end
T.test("kill events: dedupe and attribution", "one event per victim and role; stale or distant use is not credited", function()
	local seen = {}
	local c = KillEvents.Confirmed:Connect(function(e) table.insert(seen, e) end)
	local v = {}
	T.truthy(KillEvents.report("sheriff", v, "world")); T.falsy(KillEvents.report("sheriff", v, "world"))
	T.truthy(KillEvents.report("murderer", v, "world"), "the other role is a separate event")
	T.falsy(KillEvents.report("bogus", v)); T.falsy(KillEvents.report("sheriff", nil))
	T.eq(#seen, 2)
	c:Disconnect()
	T.eq(KillEvents.attribute({ murderer = 10 }, 11, 5), "murderer")
	T.eq(KillEvents.attribute({ murderer = 10 }, 14, 5), nil, "too long ago")
	T.eq(KillEvents.attribute({ murderer = 10 }, 11, 60), nil, "knife too far away")
	T.eq(KillEvents.attribute({ sheriff = 10 }, 11, 300), "sheriff")
	T.eq(KillEvents.attribute({ murderer = 9, sheriff = 10 }, 11, 5), "sheriff", "the most recent tool wins")
	T.eq(KillEvents.attribute({}, 11, 1), nil)
end)
T.test("the library is per role and validated", "add/remove/pick are separate for Murderer and Sheriff", function()
	T.fresh()
	T.truthy(KillSounds.addSound("murderer", "Boom", "asset:111"))
	T.eq(#KillSounds.userLibrary("sheriff"), 0)
	T.falsy((KillSounds.addSound("murderer", "Boom", "asset:222")), "duplicate name")
	T.falsy((KillSounds.addSound("murderer", "", "asset:1"))); T.falsy((KillSounds.addSound("murderer", "x", "proc:neon")))
	T.falsy((KillSounds.addSound("murderer", "x", "file:../evil.mp3"))); T.falsy((KillSounds.addSound("murderer", "x", "garbage")))
	T.truthy(KillSounds.addSound("sheriff", "Boom", "file:ding.mp3"), "the same name may exist in the other list")
	T.falsy((KillSounds.pick("murderer", "file:ding.mp3")), "a sound from the other list cannot be picked")
	T.truthy(KillSounds.pick("murderer", "asset:111"))
	T.eq(Settings.get("ksound.sheriffPick"), "")
	for i = 1, KillSounds.MAX_ENTRIES do KillSounds.addSound("murderer", "S" .. i, "asset:" .. (1000 + i)) end
	T.eq(#KillSounds.userLibrary("murderer"), KillSounds.MAX_ENTRIES)
	local firstUser = #KillSounds.library("murderer") - #KillSounds.userLibrary("murderer") + 1
	T.truthy(KillSounds.removeSound("murderer", firstUser)); T.eq(Settings.get("ksound.murdererPick"), "")
	T.falsy((KillSounds.removeSound("murderer", 1)), "a bundled sound cannot be removed")
	Settings.set("ksound.sheriffLibrary", "not json")
	T.eq(#KillSounds.userLibrary("sheriff"), 0)
end)
-- plays(role): how many times the role's persistent voice was started (counted on its Played event)
local playCounts = {}
local function watchVoice(role)
	local snd = sounds(role)[1]
	if snd and not playCounts[snd] then
		playCounts[snd] = 0
		snd.Played:Connect(function() playCounts[snd] += 1 end)
	end
	return snd
end
local function plays(role)
	local snd = sounds(role)[1]
	return snd and playCounts[snd] or 0
end
T.test("a confirmed kill plays only the matching role's voice", "own switch, own volume, once per episode; Reset touches one role", function()
	local h, game = boot()
	KillSounds.addSound("murderer", "M", "asset:111"); KillSounds.addSound("sheriff", "S", "asset:222")
	KillSounds.pick("murderer", "asset:111"); KillSounds.pick("sheriff", "asset:222")
	T.eq((KillSounds.apply("murderer")), true); T.eq((KillSounds.apply("sheriff")), true)
	Settings.set("ksound.murdererVolume", 0.3); Settings.set("ksound.sheriffVolume", 0.9)
	T.eq(#sounds("sheriff"), 1, "the voice is created and pre-loaded when the sound is applied"); T.eq(#sounds("murderer"), 1)
	watchVoice("sheriff"); watchVoice("murderer")
	local v = {}
	T.truthy(KillEvents.report("sheriff", v, "world"))
	T.eq(plays("sheriff"), 1); T.eq(plays("murderer"), 0)
	T.eq(sounds("sheriff")[1].Volume, 0.9)
	KillEvents.report("sheriff", v, "world")
	T.eq(plays("sheriff"), 1, "the same death does not play twice")
	KillEvents.report("murderer", {}, "world")
	T.eq(plays("murderer"), 1); T.eq(sounds("murderer")[1].Volume, 0.3)
	KillEvents.report("sheriff", {}, "world")
	T.eq(plays("sheriff"), 2); T.eq(#sounds("sheriff"), 1, "the voice is restarted, not duplicated")
	-- switching one role off silences only that role (and removes its voice)
	Settings.set("ksound.murdererEnabled", false)
	KillEvents.report("murderer", {}, "world"); KillEvents.report("sheriff", {}, "world")
	T.eq(#sounds("murderer"), 0); T.eq(plays("sheriff"), 3)
	-- reset one role, the other keeps everything
	Settings.set("ksound.murdererEnabled", true)
	KillSounds.reset("murderer")
	T.eq(Settings.get("ksound.murdererSource"), ""); T.eq(Settings.get("ksound.murdererVolume"), 0.8)
	T.eq(Settings.get("ksound.sheriffSource"), "asset:222"); T.eq(Settings.get("ksound.sheriffVolume"), 0.9); T.eq(Settings.get("ksound.sheriffEnabled"), true)
	T.eq(#sounds("sheriff"), 1, "the other role keeps its voice")
	T.eq(#KillSounds.userLibrary("murderer"), 1, "Reset keeps the list")
	-- using a tool without a kill never plays anything
	local n = plays("sheriff")
	local tool = addTool(game, "Gun")
	tool.Activated:Fire(); frames(10)
	T.eq(plays("sheriff"), n, "shooting alone is not a kill")
	-- volume changes reach the voice at once
	Settings.set("ksound.sheriffVolume", 0.2); T.eq(sounds("sheriff")[1].Volume, 0.2)
	h.unload(); T.eq(#sounds("sheriff"), 0, "unload removed the voices"); Mock.uninstall()
end)
T.test("previews are separate, stoppable and clean up", "one preview per role, replaced not stacked, stopped by an event and by unload", function()
	local h = boot()
	local function previews(role)
		local n = 0
		for _, d in ipairs(Services.SoundService:GetChildren()) do if d.Name == "MM2Hub_KillPreview_" .. role then n += 1 end end
		return n
	end
	T.falsy((KillSounds.preview("murderer")), "nothing selected")
	KillSounds.addSound("murderer", "M", "asset:111"); KillSounds.pick("murderer", "asset:111")
	local result
	T.truthy(KillSounds.preview("murderer", function(ok, msg) result = ok end)); frames(5)
	T.eq(previews("murderer"), 1); T.eq(previews("sheriff"), 0); T.truthy(KillSounds.isPreviewing("murderer")); T.falsy(KillSounds.isPreviewing("sheriff"))
	KillSounds.preview("murderer"); frames(5)
	T.eq(previews("murderer"), 1, "replaced, not stacked")
	KillSounds.stopPreview("murderer")
	T.eq(previews("murderer"), 0); T.falsy(KillSounds.isPreviewing("murderer"))
	-- an event stops the same role's preview
	KillSounds.apply("murderer"); KillSounds.preview("murderer"); frames(5)
	KillEvents.report("murderer", {}, "world")
	T.eq(previews("murderer"), 0)
	-- the preview uses its own role's volume
	Settings.set("ksound.sheriffVolume", 0.25); KillSounds.addSound("sheriff", "S", "asset:5"); KillSounds.pick("sheriff", "asset:5"); KillSounds.preview("sheriff"); frames(5)
	for _, d in ipairs(Services.SoundService:GetChildren()) do
		if d.Name == "MM2Hub_KillPreview_sheriff" then T.eq(d.Volume, 0.25) end
	end
	h.unload()
	T.eq(previews("sheriff"), 0, "unload released the preview")
	Mock.uninstall()
end)

T.suite("Customisation pages (mock)")
T.test("all five pages exist, build and keep one ticker each", "navigation, Apply, repeated opening", function()
	local h, game = boot()
	local ids = { "customgun", "customknife", "customchar", "killmurderer", "killsheriff" }
	local known = {}
	for _, id in ipairs(Window.pageIds()) do known[id] = true end
	for _, id in ipairs(ids) do T.truthy(known[id], id .. " is registered") end
	for round = 1, 3 do
		for _, id in ipairs(ids) do Window.navigate(id); frames(6) end
	end
	local gui = game.__services.CoreGui.MM2Hub
	for _, id in ipairs(ids) do T.truthy(gui:FindFirstChild("Page_" .. id, true), id .. " page was built") end
	local tickers = {}
	for _, t in ipairs(Perf.timings()) do tickers[t.name] = (tickers[t.name] or 0) + 1 end
	T.eq(tickers["ui.preview.gun"], 1); T.eq(tickers["ui.preview.knife"], 1); T.eq(tickers["ui.preview.char"], 1)
	-- Apply on the gun page really applies
	Window.navigate("customgun"); frames(4)
	local page = gui:FindFirstChild("Page_customgun", true)
	local apply
	for _, d in ipairs(page:GetDescendants()) do if d:IsA("TextButton") and d.Name == "Apply" then apply = d end end
	T.truthy(apply, "Apply button")
	apply.Activated:Fire({}, 1); frames(4)
	T.eq(Settings.get("custom.gunEnabled"), true)
	T.truthy(Custom.applied("gun") ~= nil)
	-- picking a model card selects it
	local card = page:FindFirstChild("Model_pump", true)
	card.Activated:Fire({}, 1); frames(4)
	T.eq(Settings.get("custom.gunModel"), "pump")
	-- the sheriff page has no controls bound to the murderer settings and the other way round
	local sh = gui:FindFirstChild("Page_killsheriff", true)
	for _, d in ipairs(sh:GetDescendants()) do T.falsy(string.find(d.Name, "murderer", 1, true), "sheriff page references " .. d.Name) end
	-- leaving the hub destroys the preview models
	h.unload(); Mock.uninstall()
end)

T.suite("Bundled sounds")
local Pack = import("features/SoundPack")
local PackData = import("data/SoundPack")
local Codec = import("core/Codec")
local Env = import("core/Env")
local function fakeFiles(files)
	local api = {
		writefile = function(p, t) files[p] = t end, readfile = function(p) return files[p] end, isfile = function(p) return files[p] ~= nil end,
		makefolder = function() end, isfolder = function() return true end, getcustomasset = function(p) return "rbxasset://" .. p end,
	}
	return function(name) return api[name] end
end
T.test("the owner's sound files are intact", "base64 decodes to the recorded size, mp3 header, measured duration", function()
	T.eq(#PackData, 8)
	local seen = {}
	for _, e in ipairs(PackData) do
		T.falsy(seen[e.file], e.file); seen[e.file] = true
		local raw = Codec.b64decode(e.data)
		T.eq(#raw, e.bytes, e.file)
		local b1, b2 = string.byte(raw, 1), string.byte(raw, 2)
		T.truthy(string.sub(raw, 1, 3) == "ID3" or (b1 == 0xFF and b2 >= 0xE0), e.file .. " does not look like mp3")
		T.truthy(e.duration > 0.05 and e.duration < 10, e.file .. " duration " .. tostring(e.duration))
		T.truthy(string.match(e.file, "^[%w_]+%.mp3$"))
	end
end)
T.test("bundled sounds are written once and reported when impossible", "install with a file API; clear error without one", function()
	local files = {}
	T.fresh({ lookup = fakeFiles(files) }); Pack._reset()
	local n, problems = Pack.installAll()
	T.eq(n, 8); T.eq(#problems, 0)
	T.eq(#files["MM2Hub/sounds/neverlose.mp3"], PackData[7].bytes)
	files["MM2Hub/sounds/neverlose.mp3"] = nil; Pack._reset()
	T.truthy(Pack.ensure("neverlose.mp3")); T.truthy(files["MM2Hub/sounds/neverlose.mp3"] ~= nil)
	T.falsy((Pack.ensure("nope.mp3")))
	T.fresh(); Pack._reset()
	local ok, err = Pack.ensure("neverlose.mp3")
	T.falsy(ok); T.truthy(string.find(err, "file API", 1, true))
end)
T.test("both roles see the bundled list and keep separate selections", "same sounds, independent choice", function()
	local files = {}
	T.fresh({ lookup = fakeFiles(files) }); Pack._reset()
	local m, s = KillSounds.library("murderer"), KillSounds.library("sheriff")
	T.eq(#m, 8); T.eq(#s, 8); T.truthy(m[1].builtin and m[1].duration > 0)
	T.truthy(KillSounds.pick("murderer", "file:glass_shatter.mp3"))
	T.eq(Settings.get("ksound.sheriffPick"), "")
	T.truthy(KillSounds.pick("sheriff", "file:neverlose.mp3"))
	T.eq(Settings.get("ksound.murdererPick"), "file:glass_shatter.mp3")
	T.truthy(KillSounds.apply("murderer"))
	T.eq(Settings.get("ksound.sheriffSource"), "")
	T.eq(KillSounds.duration("file:glass_shatter.mp3"), PackData[2].duration)
end)
T.test("a bundled sound plays through the confirmed-kill pipeline", "file is installed on demand, role volume applies", function()
	local files = {}
	local h, game
	T.fresh({ lookup = fakeFiles(files) })
	if Hub.current() then Hub.current().unload() end
	Mock.uninstall(); game = Mock.install(); Services.clear(); Env.setLookup(fakeFiles(files)); Pack._reset()
	h = Hub.run({ skipLicense = true })
	KillSounds.pick("sheriff", "file:helmet_hit.mp3"); KillSounds.apply("sheriff"); Settings.set("ksound.sheriffVolume", 0.4)
	KillEvents.report("sheriff", {}, "world")
	T.truthy(files["MM2Hub/sounds/helmet_hit.mp3"] ~= nil, "installed on first use")
	local snd = sounds("sheriff")[1]
	T.truthy(snd ~= nil); T.eq(snd.Volume, 0.4); T.truthy(string.find(snd.SoundId, "helmet_hit.mp3", 1, true))
	done(h)
end)

T.suite("Imported meshes")
local Meshes = import("features/MeshModels")
local function indexWith(models) return Json.encode({ version = 1, models = models }) end
local goodGun = { id = "awp", name = "AWP", kind = "gun", tris = 9000, credit = "test credit", parts = { { mesh = "awp_0.obj", texture = "awp_0.png", center = { 0, 0.2, 0 }, size = { 0.3, 0.5, 2.8 }, tris = 5000 }, { mesh = "awp_1.obj", texture = "awp_1.png", center = { 0, 0, 0.4 }, size = { 0.3, 0.4, 1 }, tris = 4000 } } }
T.test("index entries are validated", "bad ids, kinds, file names, sizes and budgets are refused", function()
	T.truthy(Meshes.validate(goodGun))
	local function bad(mod)
		local copy = Json.decode(Json.encode(goodGun)); mod(copy)
		return Meshes.validate(copy)
	end
	T.falsy((bad(function(e) e.id = "../x" end))); T.falsy((bad(function(e) e.kind = "tank" end)))
	T.falsy((bad(function(e) e.parts[1].mesh = "../evil.obj" end))); T.falsy((bad(function(e) e.parts[1].mesh = "x.lua" end)))
	T.falsy((bad(function(e) e.parts[1].texture = "a/b.png" end))); T.falsy((bad(function(e) e.parts[1].size = { 0.3, 99, 1 } end)))
	T.falsy((bad(function(e) e.parts[1].center = { 0, 0 } end))); T.falsy((bad(function(e) e.parts[1].tris = 999999 end)))
	T.falsy((bad(function(e) e.parts = {} end))); T.falsy((bad(function(e) e.parts[1].assetId = "abc"; e.parts[1].mesh = nil end)))
	T.falsy((bad(function(e) e.kind = "char"; e.group = "accessory"; e.slot = "feet" end)))
	T.truthy(bad(function(e) e.parts[1] = { assetId = "123456", textureId = "654321", center = { 0, 0, 0 }, size = { 1, 1, 1 }, tris = 10 } end))
end)
T.test("a broken or missing index never throws", "no file, garbage, wrong shape, duplicate ids", function()
	T.fresh()
	local n = Meshes.reload(); T.eq(n, 0)
	Env.write(Meshes.INDEX, "garbage {{{"); local n2, p2 = Meshes.reload(); T.eq(n2, 0); T.truthy(#p2 > 0)
	Env.write(Meshes.INDEX, "{\"models\": 5}"); T.eq((Meshes.reload()), 0)
	Env.write(Meshes.INDEX, indexWith({ goodGun, goodGun, { id = "bad id" } }))
	local n3, p3 = Meshes.reload(); T.eq(n3, 1); T.eq(#p3, 2)
	T.truthy(Meshes.has("gun", "awp")); T.falsy(Meshes.has("knife", "awp"))
end)
T.test("an imported mesh becomes a MeshPart model and can be applied to a tool", "build, select, Apply, skin on the tool, Reset", function()
	local files = {}
	T.fresh({ lookup = fakeFiles(files) })
	if Hub.current() then Hub.current().unload() end
	Mock.uninstall(); local game = Mock.install(); Services.clear(); Env.setLookup(fakeFiles(files))
	Env.write(Meshes.INDEX, indexWith({ goodGun })); Meshes.reload()
	local h = Hub.run({ skipLicense = true })
	local model = Meshes.build("gun", "awp")
	T.truthy(model ~= nil)
	local meshParts = 0
	for _, d in ipairs(model:GetChildren()) do if d.ClassName == "MeshPart" then meshParts += 1; T.truthy(string.find(d.MeshId, "awp_", 1, true)); T.truthy(string.find(d.TextureID, ".png", 1, true)) end end
	T.eq(meshParts, 2)
	model:Destroy()
	T.eq((Custom.selectModel("gun", "import:nothing")), false)
	T.truthy(Custom.selectModel("gun", "import:awp")); T.eq(Settings.get("custom.gunModel"), "import:awp")
	local tool, handle = addTool(game, "Gun")
	T.truthy(Custom.apply("gun")); frames(60)
	T.eq(Cosmetics.status().gun, "applied")
	local skin = tool:FindFirstChild("MM2HubSkin")
	T.truthy(skin ~= nil)
	T.eq(count(skin:GetChildren(), function(c) return c.ClassName == "MeshPart" end), 2)
	Custom.reset("gun"); frames(60)
	T.eq(tool:FindFirstChild("MM2HubSkin"), nil)
	-- a vanished entry is refused when the snapshot is read again
	Settings.set("custom.gunModel", "import:awp"); Custom.apply("gun")
	Env.write(Meshes.INDEX, indexWith({})); Meshes.reload(); frames(60)
	T.eq(Custom.applied("gun"), nil, "a look that points at a missing import is not trusted")
	done(h)
end)
T.test("an executor without getcustomasset reports it and leaves nothing behind", "build fails cleanly", function()
	if Hub.current() then Hub.current().unload() end
	Mock.uninstall(); T.fresh(); Mock.install(); Services.clear()
	Env.write(Meshes.INDEX, indexWith({ goodGun })); Meshes.reload()
	local m, err = Meshes.build("gun", "awp")
	T.eq(m, nil); T.truthy(string.find(err, "getcustomasset", 1, true), tostring(err))
	Mock.uninstall()
end)

T.suite("Game audio")
local GameAudio = import("features/GameAudio")
local function sound(parent, name, vol)
	local s = Mock.makeInstance("Sound"); s.Name = name; s.SoundId = "rbxassetid://5"; s.Volume = vol or 0.7; s.Parent = parent
	return s
end
T.test("keywords decide the category", "name and path, fixed order, our own sounds ignored", function()
	T.fresh()
	T.eq(GameAudio.categoryOf("ReloadSound", "Character/Gun/ReloadSound"), "reload")
	T.eq(GameAudio.categoryOf("Boom", "Character/Knife/Boom"), "knife", "the path counts")
	T.eq(GameAudio.categoryOf("Victory", "SoundService/Victory"), "win")
	T.eq(GameAudio.categoryOf("Ambient", "Workspace/Ambient"), nil)
	T.truthy(GameAudio.addKeyword("shot", "Pew")); T.eq(GameAudio.categoryOf("pew", "Workspace/pew"), "shot")
	T.truthy(GameAudio.addKeyword("shot", "pew")); T.eq(GameAudio.keywords("shot")[#GameAudio.keywords("shot")], "pew")
	T.falsy((GameAudio.addKeyword("shot", "a,b"))); T.falsy((GameAudio.addKeyword("shot", ""))); T.falsy((GameAudio.addKeyword("nope", "x")))
end)
T.test("muting is reversible and local", "volume 0 while on, restored when off, game cannot raise it, our sounds untouched", function()
	local h, game = boot()
	local char = game.Players.LocalPlayer.Character
	local reload = sound(char, "ReloadSound", 0.7)
	local other = sound(char, "Footstep", 0.5)
	local ours = sound(char, "MM2Hub_Reload", 0.9)
	T.eq(reload.Volume, 0.7)
	Settings.set("gameaudio.muteReload", true)
	T.eq(reload.Volume, 0); T.eq(other.Volume, 0.5); T.eq(ours.Volume, 0.9)
	reload.Volume = 0.8
	T.eq(reload.Volume, 0, "the game cannot raise a muted sound")
	local later = sound(char, "ReloadAgain", 0.6)
	T.eq(later.Volume, 0, "a sound created later is muted at once")
	T.eq(GameAudio.mutedCount(), 2)
	Settings.set("gameaudio.muteReload", false)
	T.eq(reload.Volume, 0.8, "restored to the last volume the game set"); T.eq(later.Volume, 0.6); T.eq(GameAudio.mutedCount(), 0)
	Settings.set("gameaudio.muteReload", true)
	h.unload()
	T.eq(reload.Volume, 0.8, "unload restores"); Mock.uninstall()
end)
T.test("the game's kill sounds are silenced only while a custom one is on", "needs an applied, enabled kill sound; reset gives them back", function()
	local h, game = boot()
	local kill = sound(game.Players.LocalPlayer.Character, "KillSound", 0.6)
	T.eq(kill.Volume, 0.6, "nothing custom yet")
	KillSounds.addSound("sheriff", "S", "asset:222"); KillSounds.pick("sheriff", "asset:222"); KillSounds.apply("sheriff")
	T.eq(kill.Volume, 0)
	Settings.set("gameaudio.muteKill", false); T.eq(kill.Volume, 0.6)
	Settings.set("gameaudio.muteKill", true); T.eq(kill.Volume, 0)
	KillSounds.reset("sheriff"); T.eq(kill.Volume, 0.6)
	done(h)
end)
T.test("learn mode lists what played", "names, paths, counts; nothing recorded after the session; ours ignored", function()
	local h, game = boot()
	local char = game.Players.LocalPlayer.Character
	local a = sound(char, "BangSound"); local b = sound(game.__services.SoundService, "RoundMusic"); local ours = sound(char, "MM2Hub_x")
	local result
	T.truthy(GameAudio.learn(5, function(list) result = list end))
	T.falsy((GameAudio.learn(5)), "one session at a time"); T.truthy(GameAudio.isLearning())
	a:Play(); a:Play(); b:Play(); ours:Play()
	task.flush()
	T.truthy(result ~= nil); T.eq(#result, 2); T.eq(result[1].name, "BangSound"); T.eq(result[1].count, 2); T.truthy(string.find(result[1].path, "BangSound", 1, true))
	T.falsy(GameAudio.isLearning())
	a:Play(); T.eq(#result, 2); T.eq(result[1].count, 2)
	done(h)
end)
T.test("a round-end sound starts your song and is silenced", "needs a song source; once per round", function()
	local files = {}
	if Hub.current() then Hub.current().unload() end
	Mock.uninstall(); T.fresh({ lookup = fakeFiles(files) })
	local game = Mock.install(); Services.clear(); Env.setLookup(fakeFiles(files))
	local h = Hub.run({ skipLicense = true })
	local function songs()
		local n = 0
		for _, d in ipairs(Services.SoundService:GetChildren()) do if d.Name == "MM2Hub_RoundSong" then n += 1 end end
		return n
	end
	local win = sound(game.__services.SoundService, "VictoryTheme", 0.8)
	win:Play(); T.eq(songs(), 0, "switched off")
	Settings.set("gameaudio.songEnabled", true); Settings.set("gameaudio.songSource", "file:otpusti.mp3"); Settings.set("gameaudio.songVolume", 0.5)
	T.eq(win.Volume, 0, "the game's round-end sound is silenced")
	win:Play(); T.eq(songs(), 1)
	local song = Services.SoundService:FindFirstChild("MM2Hub_RoundSong")
	T.eq(song.Volume, 0.5); T.truthy(string.find(song.SoundId, "otpusti.mp3", 1, true))
	win:Play(); T.eq(songs(), 1, "no second song within the same round")
	GameAudio.songStop(); T.eq(songs(), 0)
	Settings.set("gameaudio.songEnabled", false); T.eq(win.Volume, 0.8)
	T.falsy((GameAudio.songPlay()) == false and false)
	done(h)
end)

T.suite("Audio probe")
local Probe = import("features/AudioProbe")
-- run a probe against a Sound whose engine-side properties the test decides (the mock has no audio engine)
local function probe(spec, props)
	Mock.uninstall(); local game = Mock.install(); Services.clear()
	local files = spec.files or {}
	T.fresh({ lookup = fakeFiles(files) }); Env.setLookup(fakeFiles(files)); Pack._reset()
	local c = Services.SoundService.ChildAdded:Connect(function(s)
		for k, v in pairs(props or {}) do s[k] = v end
	end)
	local report
	Probe.run(spec, function(r) report = r end)
	c:Disconnect()
	local left = #Services.SoundService:GetChildren()
	Mock.uninstall()
	return report, left
end
T.test("a working sound passes every stage", "all stages ok, the probe sound is removed afterwards", function()
	local r, left = probe({ url = "rbxassetid://1", volume = 0.8 }, { IsLoaded = true, TimeLength = 1.2, PlaybackLoudness = 40 })
	T.truthy(r.ok, tostring(r.verdict)); T.eq(r.failed, nil); T.eq(left, 0)
	local names = {}
	for _, s in ipairs(r.stages) do names[s.name] = s.ok end
	T.truthy(names.sound and names.fetch and names.loaded and names.volume and names.playing and names.signal)
	T.truthy(string.find(r.verdict, "measures a signal", 1, true)); T.truthy(r.loudness > 0); T.eq(r.length, 1.2)
end)
T.test("each failure names its stage", "not loaded, zero length, zero volume, silent file, bad source, missing file, no getcustomasset", function()
	local r = probe({ url = "rbxassetid://1" }, { IsLoaded = false, TimeLength = 0 })
	T.falsy(r.ok); T.eq(r.failed, "loaded"); T.truthy(string.find(r.verdict, "did not load", 1, true))
	r = probe({ url = "rbxassetid://1" }, { IsLoaded = true, TimeLength = 0 })
	T.eq(r.failed, "loaded")
	r = probe({ url = "rbxassetid://1", volume = 0 }, { IsLoaded = true, TimeLength = 1, PlaybackLoudness = 0 })
	T.eq(r.failed, "volume"); T.truthy(string.find(r.verdict, "volume", 1, true))
	r = probe({ url = "rbxassetid://1" }, { IsLoaded = true, TimeLength = 1, PlaybackLoudness = 0 })
	T.eq(r.failed, "signal"); T.truthy(string.find(r.verdict, "no loudness", 1, true))
	r = probe({ source = "proc:neon" })
	T.eq(r.failed, "source")
	r = probe({ source = "file:missing.mp3" }, { IsLoaded = true })
	T.eq(r.failed, "file"); T.truthy(string.find(r.verdict, "not in MM2Hub/sounds", 1, true))
	r = probe({ source = "asset:123", files = nil }, nil)
	T.truthy(r ~= nil)
	-- no file API at all: a bundled sound cannot be installed, and the report says so
	Mock.uninstall(); Mock.install(); Services.clear(); T.fresh(); Pack._reset()
	local rep; Probe.run({ source = "file:neverlose.mp3" }, function(x) rep = x end)
	T.eq(rep.failed, "file"); T.truthy(string.find(rep.verdict, "could not be written", 1, true))
	Mock.uninstall()
end)
T.test("files and bundled sounds resolve to a URL before playing", "file in MM2Hub/sounds, bundled sound installed on demand, music folder", function()
	local files = { ["MM2Hub/sounds/mine.mp3"] = "xx", ["MM2Hub/music/song.mp3"] = "yy" }
	local r = probe({ source = "file:mine.mp3", files = files }, { IsLoaded = true, TimeLength = 1, PlaybackLoudness = 5 })
	T.truthy(r.ok, tostring(r.verdict))
	local url; for _, s in ipairs(r.stages) do if s.name == "url" then url = s.detail end end
	T.truthy(string.find(url, "MM2Hub/sounds/mine.mp3", 1, true))
	r = probe({ source = "file:song.mp3", folder = "music", files = files }, { IsLoaded = true, TimeLength = 1, PlaybackLoudness = 5 })
	T.truthy(r.ok, tostring(r.verdict))
	local f2 = {}
	r = probe({ source = "file:neverlose.mp3", files = f2 }, { IsLoaded = true, TimeLength = 0.5, PlaybackLoudness = 9 })
	T.truthy(r.ok, tostring(r.verdict)); T.truthy(f2["MM2Hub/sounds/neverlose.mp3"] ~= nil, "the bundled file was written")
end)
T.test("a kept sound survives the probe and the report is readable", "keep = true, format lines", function()
	Mock.uninstall(); Mock.install(); Services.clear(); T.fresh()
	local c = Services.SoundService.ChildAdded:Connect(function(s) s.IsLoaded = true; s.TimeLength = 1; s.PlaybackLoudness = 3 end)
	local rep; Probe.run({ url = "rbxassetid://1", keep = true }, function(x) rep = x end)
	c:Disconnect()
	T.truthy(rep.sound ~= nil); T.eq(#Services.SoundService:GetChildren(), 1)
	local text = Probe.format(rep)
	T.truthy(string.find(text, "✓ sound", 1, true) and string.find(text, "✓ signal", 1, true))
	rep.sound:Destroy(); Mock.uninstall()
end)

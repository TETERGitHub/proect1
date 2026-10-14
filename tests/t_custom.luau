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
		if d:IsA("BasePart") and d.Name == "Slide" and r and (r >= 200 or (r <= 1 and r > 0.9)) then red = true end
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
	T.eq(#KillSounds.library("sheriff"), 0)
	T.falsy((KillSounds.addSound("murderer", "Boom", "asset:222")), "duplicate name")
	T.falsy((KillSounds.addSound("murderer", "", "asset:1"))); T.falsy((KillSounds.addSound("murderer", "x", "proc:neon")))
	T.falsy((KillSounds.addSound("murderer", "x", "file:../evil.mp3"))); T.falsy((KillSounds.addSound("murderer", "x", "garbage")))
	T.truthy(KillSounds.addSound("sheriff", "Boom", "file:ding.mp3"), "the same name may exist in the other list")
	T.falsy((KillSounds.pick("murderer", "file:ding.mp3")), "a sound from the other list cannot be picked")
	T.truthy(KillSounds.pick("murderer", "asset:111"))
	T.eq(Settings.get("ksound.sheriffPick"), "")
	for i = 1, KillSounds.MAX_ENTRIES do KillSounds.addSound("murderer", "S" .. i, "asset:" .. (1000 + i)) end
	T.eq(#KillSounds.library("murderer"), KillSounds.MAX_ENTRIES)
	T.truthy(KillSounds.removeSound("murderer", 1)); T.eq(Settings.get("ksound.murdererPick"), "")
	Settings.set("ksound.sheriffLibrary", "not json")
	T.eq(#KillSounds.library("sheriff"), 0)
end)
T.test("a confirmed kill plays only the matching role's sound", "own switch, own volume, once per episode; Reset touches one role", function()
	local h, game = boot()
	KillSounds.addSound("murderer", "M", "asset:111"); KillSounds.addSound("sheriff", "S", "asset:222")
	KillSounds.pick("murderer", "asset:111"); KillSounds.pick("sheriff", "asset:222")
	T.eq((KillSounds.apply("murderer")), true); T.eq((KillSounds.apply("sheriff")), true)
	Settings.set("ksound.murdererVolume", 0.3); Settings.set("ksound.sheriffVolume", 0.9)
	local v = {}
	T.truthy(KillEvents.report("sheriff", v, "world"))
	T.eq(#sounds("sheriff"), 1); T.eq(#sounds("murderer"), 0)
	T.eq(sounds("sheriff")[1].Volume, 0.9)
	KillEvents.report("sheriff", v, "world")
	T.eq(#sounds("sheriff"), 1, "the same death does not play twice")
	KillEvents.report("murderer", {}, "world")
	T.eq(#sounds("murderer"), 1); T.eq(sounds("murderer")[1].Volume, 0.3)
	-- switching one role off silences only that role
	Settings.set("ksound.murdererEnabled", false)
	KillEvents.report("murderer", {}, "world"); KillEvents.report("sheriff", {}, "world")
	T.eq(#sounds("murderer"), 1); T.eq(#sounds("sheriff"), 2)
	-- reset one role, the other keeps everything
	Settings.set("ksound.murdererEnabled", true)
	KillSounds.reset("murderer")
	T.eq(Settings.get("ksound.murdererSource"), ""); T.eq(Settings.get("ksound.murdererVolume"), 0.8)
	T.eq(Settings.get("ksound.sheriffSource"), "asset:222"); T.eq(Settings.get("ksound.sheriffVolume"), 0.9); T.eq(Settings.get("ksound.sheriffEnabled"), true)
	T.eq(#KillSounds.library("murderer"), 1, "Reset keeps the list")
	-- using a tool without a kill never plays anything
	local n = #sounds("sheriff")
	local tool = addTool(game, "Gun")
	tool.Activated:Fire(); frames(10)
	T.eq(#sounds("sheriff"), n, "shooting alone is not a kill")
	done(h)
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

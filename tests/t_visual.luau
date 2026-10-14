--!nonstrict
-- Visual-system tests: design-system rules (glass levels, reduced effects), button states, tween conflicts and
-- clean-up, shared key window and the loader's prompt handle. These check structure and state, not pixels: the mock
-- has no renderer, so how it looks is judged separately with tools/ui_render.py (a proxy, not Roblox).
local import = ...
local T = import("tests/Framework")
local Mock = import("tests/mock_roblox")
local Services = import("core/Services")
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Theme = import("ui/Theme")
local Motion = import("ui/Motion")
local F = import("ui/Framework")
local KeyCard = import("ui/KeyCard")
local Loader = import("loader/Loader")
local Json = import("core/Json")
local Codec = import("core/Codec")
local PayloadCipher = import("core/PayloadCipher")

local function boot()
	T.fresh(); Mock.uninstall()
	local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	for _ = 1, 6 do Perf.frame(1 / 30) end
	return game, h
end
local function done(h) h.unload(); Mock.uninstall() end

T.suite("Design system")
T.test("surfaces get more opaque when effects are reduced", "every level: reduceEffects >= glass transparency floor", function()
	local game, h = boot()
	for _, level in ipairs({ "window", "rail", "card", "control", "popover", "modal", "toast" }) do
		Settings.set("ui.reduceEffects", false)
		local _, glassT = Theme.surface(level)
		Settings.set("ui.reduceEffects", true)
		local _, solidT = Theme.surface(level)
		T.truthy(solidT <= glassT, level)
		T.eq(Theme.glassAmount(), 0)
		T.eq(Theme.sheen(), 1)
	end
	Settings.set("ui.reduceEffects", false)
	done(h)
end)
T.test("reduced effects removes springy easing", "spring/bounce become smooth", function()
	local game, h = boot()
	Settings.set("ui.reduceEffects", true)
	local scale = Instance.new("UIScale")
	Motion.tween(scale, { Scale = 2 }, 0.2, "spring")
	T.eq(scale.Scale, 2)
	done(h)
end)
T.test("the radius scale follows the setting", "rad() grows with ui.cornerRadius and pill stays round", function()
	local game, h = boot()
	Settings.set("ui.cornerRadius", 4)
	local small = Theme.rad("card")
	Settings.set("ui.cornerRadius", 12)
	T.truthy(Theme.rad("card") > small)
	T.eq(Theme.rad("pill"), 999)
	done(h)
end)

T.suite("Components")
T.test("button states track enabled and loading", "disabled ignores state writes twice, loading swaps the label", function()
	local game, h = boot()
	local root = Instance.new("Frame")
	local b = F.button(root, "Save", function() end, { style = "primary" })
	T.eq(F.buttonState(b).enabled, true)
	F.setButtonEnabled(b, false)
	T.eq(F.buttonState(b).enabled, false); T.eq(b.Active, false)
	F.setButtonEnabled(b, true)
	F.setButtonLoading(b, true, "Working")
	T.eq(F.buttonState(b).loading, true)
	F.setButtonLoading(b, false)
	T.eq(b.Text, "Save")
	F.setButtonStyle(b, "danger")
	T.eq(F.buttonState(b).style, "danger")
	done(h)
end)
T.test("a second tween on one property replaces the first", "no pile-up of running tweens", function()
	local game, h = boot()
	Settings.set("ui.animSpeed", 1)
	local f = Instance.new("Frame")
	local before = Motion.activeCount()
	Motion.tween(f, { BackgroundTransparency = 0.5 }, 1, "smooth")
	Motion.tween(f, { BackgroundTransparency = 0.2 }, 1, "smooth")
	T.truthy(Motion.activeCount() <= before + 1)
	Motion.cancel(f)
	T.eq(Motion.activeCount(), before)
	done(h)
end)
T.test("every page builds a header and survives a reduced-effects switch", "navigate all pages, toggle the mode both ways", function()
	local game, h = boot()
	for _, id in ipairs(Window.pageIds()) do
		Window.navigate(id)
		for _ = 1, 3 do Perf.frame(1 / 30) end
	end
	Settings.set("ui.reduceEffects", true); for _ = 1, 3 do Perf.frame(1 / 30) end
	Settings.set("ui.reduceEffects", false); for _ = 1, 3 do Perf.frame(1 / 30) end
	T.truthy(game.__services.CoreGui:FindFirstChild("MM2Hub"))
	done(h)
end)

T.suite("Key window")
T.test("KeyCard submit, busy and error states", "busy blocks a second submit; error shows and clears on typing", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local gui = Instance.new("ScreenGui"); gui.Parent = game.__services.CoreGui
	local got = {}
	local card = KeyCard.build(gui, { title = "T", prompt = "P", placeholder = "k", button = "Go", busy = "Wait", onSubmit = function(t) table.insert(got, t) end })
	card.box.Text = "abc"
	card.button.Activated:Fire()
	T.eq(#got, 1); T.eq(got[1], "abc")
	card.setBusy(true)
	T.eq(card.button.Text, "Wait"); T.truthy(card.isBusy())
	card.button.Activated:Fire()
	T.eq(#got, 1)
	card.setBusy(false)
	T.eq(card.button.Text, "Go")
	card.setStatus("bad key", "error")
	T.eq(card.status.Text, "bad key")
	card.box.Text = "abcd"
	T.eq(card.status.Text, "")
	card.destroy()
	T.falsy(gui:FindFirstChild("KeyCardBackdrop"))
	Mock.uninstall()
end)

local KEY = "MM2H-0406N-KMFQ9-NCZR9-T6QA2-QNQS4-A5MEY-7BZ39-07AR"
local NONCE = string.rep("\7", 12)
local function loaderDeps(withHandle)
	local d = { prompts = {}, handle = { calls = {} }, hubs = 0, clockValue = 0, waits = 0 }
	local cipher, tag = PayloadCipher.encrypt(KEY, NONCE, "return nil")
	local good = false
	d.good = function(v) good = v end
	d.request = function(req)
		local body
		if string.find(req.Url, "ping") then body = { ok = true }
		elseif not good then body = { ok = false, error = "key expired" }
		else body = { ok = true, expires = 10000, now = 100, nonce = Codec.b64encode(NONCE), tag = tag, payload = Codec.b64encode(cipher) } end
		return { Success = true, StatusCode = 200, Body = Json.encode(body) }
	end
	d.loadstring = function() return function() d.hubs += 1; return { unload = function() end } end end
	d.readKey = function() return nil end
	d.writeKey = function() end
	local calls = d.handle.calls
	d.prompt = function(cb, err)
		table.insert(d.prompts, { cb = cb, err = err })
		if withHandle then
			return {
				busy = function(b) table.insert(calls, "busy:" .. tostring(b)) end,
				fail = function(m) table.insert(calls, "fail:" .. tostring(m)) end,
				close = function() table.insert(calls, "close") end,
			}
		end
	end
	d.uid = 1
	d.notify = function() end
	d.clock = function() return d.clockValue end
	d.spawn = function(fn) pcall(fn) end
	d.wait = function(s) d.waits += 1; d.clockValue += s; if d.waits > 2 then error("stop") end end
	d.serverUrl = "https://x.example"
	d.heartbeat = 50
	return d
end
T.test("loader reuses one prompt window", "failure goes through handle.fail, success closes it", function()
	local d = loaderDeps(true)
	local h = Loader.run(d)
	T.eq(#d.prompts, 1)
	d.prompts[1].cb(KEY)
	T.eq(#d.prompts, 1, "no second window was opened")
	T.eq(d.handle.calls[1], "busy:true")
	T.truthy(string.find(d.handle.calls[2] or "", "^fail:"))
	d.good(true)
	d.prompts[1].cb(KEY)
	T.eq(d.handle.calls[#d.handle.calls], "close")
	T.eq(d.hubs, 1); T.truthy(h.running)
end)
T.test("a prompt without a handle still works", "failure reopens the prompt like before", function()
	local d = loaderDeps(false)
	Loader.run(d)
	d.prompts[1].cb(KEY)
	T.eq(#d.prompts, 2)
	T.eq(d.prompts[2].err, "key expired")
end)

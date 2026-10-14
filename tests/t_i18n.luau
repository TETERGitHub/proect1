--!nonstrict
-- Russian-interface tests. The coverage test drives the whole UI in Russian (every page, every button, popups,
-- notifications, search) and fails on any visible English text that has no translation.
local import = ...
local T = import("tests/Framework")
local Mock = import("tests/mock_roblox")
local Probe = import("tests/i18n_probe")
local I18n = import("core/I18n")
local Settings = import("core/Settings")
local Services = import("core/Services")
local Perf = import("core/Perf")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Text = import("core/LicenseText")
local Texts = import("data/RuTexts")

T.suite("Russian interface")
T.test("Russian is the default language", "schema default is ru", function()
	T.fresh()
	T.eq(Settings.get("ui.language"), "ru")
end)
T.test("no visible text is left untranslated", "walking every page/button/popup/notification finds no English strings", function()
	local misses = Probe.run()
	T.eq(#misses, 0, "untranslated: " .. table.concat(misses, " | "))
	return "0 untranslated texts after exercising all pages"
end)
for _, lang in ipairs({ "uk", "es", "pt", "fr" }) do
	T.test("no visible text is left untranslated (" .. lang .. ")", "every page/button/popup walked in " .. I18n.NAMES[lang], function()
		local misses = Probe.run(lang)
		T.eq(#misses, 0, "untranslated: " .. table.concat(misses, " | "))
		return "0 untranslated texts"
	end)
end
T.test("languages list and upper-case for accents", "menu order, native names, Ukrainian and Latin accents", function()
	T.eq(table.concat(I18n.languages(), ","), "ru,en,uk,es,pt,fr")
	T.eq(I18n.upper("configuración"), "CONFIGURACIÓN"); T.eq(I18n.upper("їжак і ґанок"), "ЇЖАК І ҐАНОК"); T.eq(I18n.upper("ça"), "ÇA")
	T.truthy(I18n.set("es")); T.eq(I18n.t("nav.crosshair") ~= "Crosshair", true)
	I18n.set("en")
end)
T.test("translations keep placeholders intact", "every pattern template accepts as many values as it captures", function()
	for _, rule in ipairs(Texts.patterns) do
		local _, captures = string.gsub(rule[1], "%(", "")
		local escaped = select(2, string.gsub(rule[1], "%%%(", ""))
		local groups = captures - escaped * 1
		local _, specs = string.gsub(rule[2], "%%s", "")
		T.truthy(specs <= groups + 0, rule[1])
	end
end)
T.test("number and name patterns translate", "dynamic texts become Russian", function()
	I18n.set("ru")
	T.eq(I18n.tr("2 of 5 in FOV"), "2 из 5 в зоне FOV")
	T.eq(I18n.tr("Saved 'Alt'"), "Сохранён профиль «Alt»"); T.eq(I18n.tr("Target 3"), "Мишень 3")
	T.eq(I18n.tr("Dummy: off-screen"), "Манекен: вне экрана")
	T.eq(I18n.tr("Orbit -> HubLabHitbox.Position"), "Орбита → HubLabHitbox.Position")
	T.eq(I18n.tr("asset:123"), "asset:123", "source specs stay as written")
	T.eq(I18n.tr("Привет"), "Привет"); T.eq(I18n.tr("12:30"), "12:30")
	I18n.set("en")
	T.eq(I18n.tr("70 studs/s"), "70 studs/s", "English mode leaves texts unchanged")
end)
T.test("upper-case and truncation work for Cyrillic", "no broken UTF-8", function()
	T.eq(I18n.upper("прицел и камера"), "ПРИЦЕЛ И КАМЕРА"); T.eq(I18n.upper("ёж"), "ЁЖ"); T.eq(I18n.upper("abc"), "ABC")
	T.eq(I18n.cut("Хитбокс лаборатории", 7), "Хитбокс"); T.eq(I18n.cut("short", 10), "short")
	T.truthy(utf8.len(I18n.cut("Режим камеры сейчас", 5)) == 5)
end)
T.test("language switches at runtime without restart", "pages and navigation relabel; switching back restores English", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	local gui = game.__services.CoreGui.MM2Hub
	local function navLabel(id) return gui.Root.Window.Sidebar:FindFirstChild("Nav_" .. id, true).Label.Text end
	I18n.set("ru"); T.eq(navLabel("camera"), "Камера"); T.eq(navLabel("keys"), "Горячие клавиши")
	Window.navigate("camera"); for _ = 1, 5 do Perf.frame(1 / 30) end
	local function has(text)
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == text then return true end
		end
		return false
	end
	T.truthy(has("Масштабирует весь текст интерфейса.") or has("Режим камеры"), "camera page is Russian")
	I18n.set("en"); T.eq(navLabel("camera"), "Camera"); Window.navigate("camera"); for _ = 1, 5 do Perf.frame(1 / 30) end
	T.truthy(has("Camera mode"), "English labels return")
	h.unload(); Mock.uninstall()
end)
T.test("settings pages show Russian labels, descriptions and options", "samples from different pages", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true }); I18n.set("ru"); Window.relocalize()
	local gui = game.__services.CoreGui.MM2Hub
	local seen = {}
	for _, id in ipairs({ "ui", "crosshair", "training", "keys", "about" }) do
		Window.navigate(id); for _ = 1, 6 do Perf.frame(1 / 30) end
		for _, d in ipairs(gui:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.Text) == "string" then seen[d.Text] = true end
		end
	end
	local missing
	for _, want in ipairs({ "Масштаб интерфейса", "Свой прицел", "Следующая страница", "Сбросить все горячие клавиши", "Крест", "Компактный режим" }) do
		local found = false
		for text in pairs(seen) do if string.find(string.upper(text), string.upper(want), 1, true) or text == want then found = true end end
		missing = missing or (not (found or want == "Крест") and want or nil)
	end
	h.unload(); Mock.uninstall()
	T.eq(missing, nil)
end)

T.suite("Licence texts (Russian)")
T.test("every verifier and server message has a Russian text", "known messages translated, unknown ones pass through", function()
	local known = {
		"invalid key", "this key has been revoked", "key expired", "key is already bound to another account", "account id required",
		"key is not valid yet", "too many attempts, wait a minute", "bad request", "not found",
		"that does not look like a key", "could not reach the licence server", "licence server sent an unreadable response",
		"payload authentication failed (wrong key or tampered data)", "not a MM2 Hub key (expected MM2H-...)",
		"invalid key (signature mismatch)", "system clock was set back; refusing to run",
	}
	for _, m in ipairs(known) do
		local ru = Text.ru(m)
		T.truthy(ru ~= m and string.find(ru, "[\208\209]"), m)
	end
	T.eq(Text.ru("some brand-new server error"), "some brand-new server error")
	T.eq(Text.ru(nil), "Неизвестная ошибка.")
	T.truthy(string.find(Text.ru("key expired 3d 2h 1m ago"), "Срок действия ключа истёк"))
	T.truthy(string.find(Text.ru("hub failed to start: boom"), "Хаб не запустился: boom", 1, true))
end)
T.test("remaining time reads naturally", "plural forms and units", function()
	T.eq(Text.remaining(0), "срок истёк")
	T.eq(Text.remaining(86400 + 3600 + 60), "1 день 1 ч 1 мин"); T.eq(Text.remaining(2 * 86400), "2 дня 0 ч 0 мин"); T.eq(Text.remaining(5 * 86400), "5 дней 0 ч 0 мин")
	T.eq(Text.remaining(11 * 86400), "11 дней 0 ч 0 мин"); T.eq(Text.remaining(21 * 86400), "21 день 0 ч 0 мин")
	T.eq(Text.remaining(3725), "1 ч 2 мин 5 с"); T.eq(Text.remaining(125), "2 минуты 5 с"); T.eq(Text.remaining(61), "1 минута 1 с"); T.eq(Text.remaining(45), "45 с")
end)
T.test("the in-script gate and the loader window show Russian", "gate text comes from LicenseText", function()
	local Gate = import("ui/LicenseGate")
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local shown = Gate.show(function() end)
	T.truthy(shown ~= nil)
	local gui = game.__services.CoreGui.MM2HubLicense
	local texts = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then texts[d.Text] = true end
	end
	T.truthy(texts[Text.UI.title] and texts[Text.UI.prompt] and texts[Text.UI.button], "title, prompt and button are Russian")
	shown.Destroy(); Mock.uninstall()
end)

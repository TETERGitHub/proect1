--!nonstrict
-- data/Features: the feature catalogue (single registry, no duplicates).
-- impl shorthand:  "s:<setting key>"  "a:<action id>"  "f:<module path>:<function>"  "u:<ui feature id>"
-- status: tested | implemented | env | partial   (see core/Registry.STATUS)

local categories = {
	A = "Interface & personalisation",
	B = "Window management",
	C = "Search & navigation",
	D = "Configurations",
	E = "Input",
	F = "Visual tools",
	G = "Graphics & environment",
	H = "Camera",
	I = "Performance",
	J = "Reliability",
	K = "Extra tools",
	L = "Local training range",
	M = "Defence",
	N = "Customisation",
}

local list = {}

local function parseImpl(s)
	local kind, rest = string.match(s, "^(%a):(.+)$")
	assert(kind, "bad impl: " .. s)
	if kind == "s" then
		return { kind = "setting", target = rest }
	elseif kind == "a" then
		return { kind = "action", target = rest }
	elseif kind == "u" then
		return { kind = "ui", target = rest }
	elseif kind == "f" then
		local module, fn = string.match(rest, "^(.+):(.+)$")
		assert(module, "bad fn impl: " .. s)
		return { kind = "fn", module = module, target = fn }
	end
	error("bad impl kind: " .. s)
end

local function F(id, cat, name, ru, status, impl, desc, note)
	table.insert(list, {
		id = id,
		cat = cat,
		name = name,
		ru = ru,
		status = status,
		impl = parseImpl(impl),
		desc = desc,
		note = note,
	})
end

-- A. Interface ------------------------------------------------------------------
F("ui.theme", "A", "Theme switcher", "Переключение темы", "tested", "s:ui.theme", "Eight themes: iOS glass (dark/light), Midnight, Obsidian, Ocean, Rose, Forest and a high-contrast one.")
F("ui.accent", "A", "Accent colour", "Акцентный цвет", "implemented", "s:ui.accent", "Custom accent colour picker (overrides theme accent).")
F("ui.opacity", "A", "Window opacity", "Прозрачность окна", "implemented", "s:ui.opacity", "Background opacity of the window.")
F("ui.scale", "A", "Interface scale", "Масштаб интерфейса", "implemented", "s:ui.scale", "UIScale, auto-clamped so the window fits the screen.")
F("ui.animations", "A", "Animation speed", "Регулировка анимаций", "implemented", "s:ui.animSpeed", "Tween speed; 0 means reduced motion.")
F("ui.corners", "A", "Corner radius", "Скругления", "implemented", "s:ui.cornerRadius", "Roundness of cards and controls.")
F("ui.density", "A", "Density", "Плотность элементов", "implemented", "s:ui.density", "Compact / Normal / Comfortable row height.")
F("ui.textsize", "A", "Text size", "Размер текста", "implemented", "s:ui.textScale", "Scales all text (accessibility).")
F("ui.sounds", "A", "Interface sounds", "Звуки интерфейса", "env", "s:sounds.uiClickEnabled", "Click sound on controls, from a file or asset ID you provide.", "No built-in Roblox sounds are used; nothing plays until you set a source on the Sounds page.")
F("ui.screenbuttons", "A", "On-screen buttons", "Экранные кнопки", "implemented", "s:ui.screenButtons", "Starred features become draggable round buttons with an on/off ring - made for phones.")
F("ui.platform", "A", "Phone layout preset", "Режим для телефона", "tested", "f:ui/Platform:detect", "Detects phone / tablet / desktop and applies a small compact layout on first run.")
F("ui.compact", "A", "Compact mode", "Компактный режим", "implemented", "s:ui.compact", "Hides descriptions to show more rows.")

-- B. Window ---------------------------------------------------------------------
F("win.drag", "B", "Move window", "Перемещение окна", "implemented", "u:Window.drag", "Drag the title bar.")
F("win.resize", "B", "Resize window", "Изменение размера", "implemented", "u:Window.resize", "Drag the bottom-right handle.")
F("win.minimize", "B", "Minimise", "Сворачивание окна", "implemented", "a:window.minimize", "Collapses to the compact quick bar.")
F("win.expand", "B", "Expand", "Разворачивание окна", "implemented", "a:window.expand", "Restores the full window from the quick bar.")
F("win.lock", "B", "Lock position", "Закрепление положения", "implemented", "s:ui.lockPosition", "Disables dragging and resizing.")
F("win.savepos", "B", "Save position", "Сохранение координат", "implemented", "u:Window.savePosition", "Geometry is stored in UI state and written by Config.")
F("win.restorepos", "B", "Restore position", "Восстановление положения", "implemented", "u:Window.restorePosition", "Geometry is re-applied and clamped to the viewport on start.")
F("win.tabkeys", "B", "Tab hotkeys", "Переключение вкладок клавишами", "implemented", "a:window.nextTab", "Next/previous page via configurable hotkeys.")
F("win.toggle", "B", "Toggle visibility", "Переключение видимости", "implemented", "a:window.toggle", "Show/hide the hub with a hotkey.")
F("win.quickbar", "B", "Quick action bar", "Компактная панель быстрых действий", "implemented", "u:Window.quickBar", "Minimised bar with FPS and favourite toggles.")

-- C. Search ---------------------------------------------------------------------
F("search.global", "C", "Global search", "Глобальный поиск", "tested", "f:core/Search:query", "Searches names, descriptions, keywords and categories.")
F("search.category", "C", "Category filter", "Поиск по категории", "tested", "u:Search.category", "Restrict results to one category.")
F("search.active", "C", "Active-only filter", "Фильтр активных функций", "tested", "u:Search.active", "Show only switched-on or customised features.")
F("search.favorites", "C", "Favourites filter", "Фильтр избранного", "tested", "u:Search.favorites", "Show only pinned features.")
F("search.recent", "C", "Recent features", "Недавно открытые функции", "tested", "f:core/Recents:touch", "Dashboard list of last used features.")
F("search.commands", "C", "Quick commands", "Быстрые команды", "tested", "f:core/Search:commands", "Type '>' in search to run any action.")
F("search.keynav", "C", "Keyboard navigation", "Навигация с клавиатуры", "implemented", "u:Window.keyNav", "Arrow keys and Enter in search results.")
F("search.hotkeys", "C", "Hotkey list", "Список горячих клавиш", "implemented", "u:Pages.hotkeys", "Page listing every binding with conflict marks.")
F("search.desc", "C", "Search by description", "Поиск по описанию", "tested", "f:core/Search:query", "Description text is part of the search index.")
F("search.help", "C", "Contextual help", "Контекстная справка", "implemented", "s:ui.showTooltips", "Tooltips with each control's description.")

-- D. Configurations -----------------------------------------------------------
F("cfg.create", "D", "Create profile", "Создание конфигурации", "tested", "f:core/Config:create", "New profile from defaults or current settings.")
F("cfg.rename", "D", "Rename profile", "Переименование конфигурации", "tested", "f:core/Config:rename", "Renames and keeps the active pointer.")
F("cfg.duplicate", "D", "Duplicate profile", "Дублирование конфигурации", "tested", "f:core/Config:duplicate", "Copies a profile under a new name.")
F("cfg.delete", "D", "Delete profile", "Удаление конфигурации с подтверждением", "tested", "f:core/Config:delete", "UI asks for confirmation; last profile is protected.")
F("cfg.export", "D", "Export settings", "Экспорт настроек", "tested", "f:core/Config:exportString", "Checksummed text string, copied to clipboard when available.")
F("cfg.import", "D", "Import settings", "Импорт настроек", "tested", "f:core/Config:importString", "Validated import creating a new profile.")
F("cfg.validate", "D", "Format validation", "Проверка формата конфигурации", "tested", "f:core/Json:decode", "Strict JSON, prefix, checksum and per-key validation.")
F("cfg.migrate", "D", "Schema migration", "Миграция старых настроек", "partial", "f:core/Version:migrate", "Migration framework is tested with synthetic formats.", "No legacy formats exist yet (schema 1 is the first release).")
F("cfg.resetCategory", "D", "Reset category", "Сброс отдельной категории", "tested", "f:core/Settings:resetCategory", "Restores defaults for one settings page.")
F("cfg.resetAll", "D", "Full reset", "Полный сброс с подтверждением", "tested", "f:core/Settings:resetAll", "UI asks for confirmation.")

-- E. Input --------------------------------------------------------------------
F("input.bind", "E", "Assign hotkeys", "Назначение горячих клавиш", "tested", "f:core/Input:bind", "Every action can have a key stored in the profile.")
F("input.rebind", "E", "Change hotkey", "Изменение назначенной клавиши", "tested", "f:core/Input:rebind", "Click a key box, press the new key.")
F("input.conflicts", "E", "Conflict check", "Проверка конфликтов клавиш", "tested", "f:core/Input:conflicts", "Duplicate keys are refused or flagged.")
F("input.clear", "E", "Unbind", "Отмена назначения", "tested", "f:core/Input:clear", "Sets a binding to None.")
F("input.enabled", "E", "Hotkeys master switch", "Включение и отключение обработки ввода", "tested", "s:input.enabled", "Disables all hub hotkeys.")
F("input.keyboard", "E", "Keyboard support", "Поддержка клавиатуры", "implemented", "f:core/Input:connect", "UserInputService keyboard events.")
F("input.mouse", "E", "Mouse support", "Поддержка мыши", "implemented", "f:core/Input:connect", "Mouse2/Mouse3 can be bound; UI is fully mouse-driven.")
F("input.focus", "E", "Typing guard", "Управление фокусом", "tested", "s:input.ignoreTyping", "Hotkeys ignored while a text box is focused.")
F("input.focuslost", "E", "Focus-loss handling", "Обработка потери фокуса", "tested", "f:core/Input:focusLost", "Clears held keys and cancels key capture.")
F("input.restore", "E", "Input restore on close", "Восстановление ввода после закрытия окна", "tested", "f:core/Input:cancelCapture", "Hiding the hub cancels pending capture.")

-- F. Visual tools -----------------------------------------------------------------
F("xh.enable", "F", "Custom crosshair", "Настраиваемый прицел", "implemented", "s:crosshair.enabled", "Own crosshair overlay at screen centre.")
F("xh.size", "F", "Crosshair size", "Регулировка размера прицела", "implemented", "s:crosshair.size", "Arm length / circle radius.")
F("xh.thickness", "F", "Line thickness", "Настройка толщины линий", "implemented", "s:crosshair.thickness", "Thickness in pixels.")
F("xh.color", "F", "Crosshair colour", "Выбор цвета прицела", "implemented", "s:crosshair.color", "RGB colour picker.")
F("xh.opacity", "F", "Crosshair opacity", "Настройка прозрачности прицела", "implemented", "s:crosshair.opacity", "Transparency of all elements.")
F("xh.dot", "F", "Centre dot", "Центральная точка", "implemented", "s:crosshair.centerDot", "Optional dot with its own size.")
F("xh.dynamic", "F", "Dynamic spread", "Настройка динамического прицела", "env", "s:crosshair.dynamic", "Gap widens with character speed.", "Needs a Humanoid on the local character.")
F("xh.owncharacter", "F", "Own character opacity", "Настройка отображения собственного персонажа", "env", "s:camera.ownOpacity", "Local-only transparency of your character.", "The game's camera scripts may also write LocalTransparencyModifier.")
F("ghost.visual", "F", "Local invisibility", "Локальная невидимость", "implemented", "s:ghost.enabled", "Fades your own character on your own screen (parts, accessories, face, tools, name tag).", nil)
F("xh.filters", "F", "Colour filter presets", "Доступные локальные визуальные эффекты", "implemented", "s:lighting.filter", "Warm / Cool / Mono / Sepia / Vivid.")
F("xh.bloom", "F", "Bloom effect", "Настройка визуальных эффектов камеры", "implemented", "s:lighting.bloomEnabled", "Local glow effect.")

-- G. Graphics ---------------------------------------------------------------------
F("gfx.brightness", "G", "Brightness", "Настройка яркости", "env", "s:lighting.brightness", "Overrides Lighting.Brightness locally.", "The game may rewrite Lighting; the hub re-applies at 2 Hz.")
F("gfx.color", "G", "Colour correction", "Контроль цветокоррекции", "implemented", "s:lighting.colorEnabled", "Hub-owned ColorCorrectionEffect.")
F("gfx.saturation", "G", "Saturation", "Настройка насыщенности", "implemented", "s:lighting.saturation", "ColorCorrection saturation.")
F("gfx.contrast", "G", "Contrast", "Настройка контраста", "implemented", "s:lighting.contrast", "ColorCorrection contrast.")
F("gfx.time", "G", "Time-of-day preset", "Выбор доступного оформления неба", "env", "s:lighting.timePreset", "Local ClockTime/ambient presets.", "Uses Lighting properties only; no custom sky assets are loaded.")
F("gfx.decor", "G", "Decorative effects", "Управление декоративными эффектами", "implemented", "s:ui.decor", "Animated accent line and gradient in the UI.")
F("gfx.particles", "G", "Hit particles", "Настройка частиц в собственном тестовом окружении", "implemented", "s:training.particles", "Particles in the local training range.")
F("gfx.blur", "G", "Blur", "Настройка размытия", "implemented", "s:lighting.blurEnabled", "Hub-owned BlurEffect.")
F("gfx.tint", "G", "Colour tint", "Настройка цветовых фильтров", "implemented", "s:lighting.tint", "Custom tint colour.")
F("gfx.reset", "G", "Reset graphics", "Сброс графических настроек", "implemented", "a:lighting.reset", "Restores all lighting settings and original Lighting values.")

-- H. Camera -----------------------------------------------------------------------
F("cam.sensitivity", "H", "Mouse sensitivity", "Настройка чувствительности камеры", "env", "s:camera.sensitivity", "UserInputService.MouseDeltaSensitivity multiplier.", "Writable from LocalScripts per Roblox docs; executors normally allow it, but some games re-set it.")
F("cam.zoomspeed", "H", "Zoom speed", "Настройка скорости прокрутки зума", "env", "s:camera.zoomSpeed", "Custom scroll-wheel zoom.", "Takes over zoom by driving Min/MaxZoomDistance; game camera scripts may interfere.")
F("cam.rememberzoom", "H", "Remember zoom", "Сохранение предпочтительного зума", "env", "s:camera.rememberZoom", "Restores preferred zoom after respawn.", "Relies on Player.CameraMinZoomDistance/MaxZoomDistance being writable on the local player.")
F("cam.mode", "H", "Camera mode", "Переключение доступных режимов камеры", "env", "s:camera.mode", "Default / first-person lock / third-person.", "Writes Player.CameraMode; the game can restrict it.")
F("cam.bob", "H", "Head bob intensity", "Настройка интенсивности тряски", "env", "s:camera.bobIntensity", "Optional walking bob via Humanoid.CameraOffset.", "Other scripts that write CameraOffset (some game cameras) can fight this.")
F("cam.noeffects", "H", "Disable camera effects", "Отключение необязательных эффектов камеры", "implemented", "s:camera.disableEffects", "Turns off head bob and blur.")
F("cam.smoothing", "H", "Smoothing", "Настройка сглаживания", "partial", "s:camera.smoothing", "Smooths zoom and FOV transitions.", "Does not smooth mouse look; Roblox does not expose that.")
F("cam.fov", "H", "Field of view", "Регулировка поля зрения там, где это разрешено", "env", "s:camera.fov", "FOV override enforced while enabled.", "The game may reset FOV; the hub re-applies it.")
F("cam.crosshairpos", "H", "Crosshair position", "Настройка положения прицела на экране", "implemented", "s:crosshair.offsetX", "X/Y offset of the crosshair.")
F("cam.reset", "H", "Reset camera", "Сброс параметров камеры", "implemented", "a:camera.reset", "Resets camera settings and restores original zoom limits.")

-- I. Performance ---------------------------------------------------------------
F("perf.fps", "I", "FPS indicator", "Индикатор FPS", "implemented", "s:ui.showFpsBadge", "Live FPS in the title bar and quick bar.")
F("perf.ping", "I", "Network ping", "Индикатор задержки сети", "env", "u:Perf.ping", "Player:GetNetworkPing() in milliseconds.", "Documented Roblox API; shows n/a if the call is unavailable.")
F("perf.timings", "I", "Module timings", "Мониторинг времени обновления модулей", "tested", "f:core/Perf:timings", "Per-task average/max milliseconds.")
F("perf.visualhz", "I", "Visual update rate", "Контроль частоты визуальных обновлений", "tested", "s:perf.visualHz", "Caps update rate of visual tasks.")
F("perf.maxdecor", "I", "Decorative object limit", "Ограничение количества декоративных элементов", "tested", "s:perf.maxDecor", "Caps targets and visible toasts.")
F("perf.pool", "I", "UI object reuse", "Переиспользование UI-объектов", "tested", "f:core/Pool:Acquire", "Pooled rows and toast cards.")
F("perf.cleanup", "I", "Temporary object cleanup", "Очистка временных объектов", "implemented", "a:training.clear", "Removes all spawned training objects.")
F("perf.connections", "I", "Connection monitor", "Контроль подключённых событий", "tested", "f:core/Maid:stats", "Counts live tasks across all Maids.")
F("perf.longops", "I", "Long operation detection", "Диагностика длительных операций", "tested", "s:perf.warnMs", "Warns when a task exceeds the threshold.")
F("perf.low", "I", "Low load profile", "Профиль низкой нагрузки", "tested", "s:perf.lowProfile", "Halves update rates and disables heavy effects.")

-- J. Reliability ------------------------------------------------------------------
F("rel.errorlog", "J", "Error log", "Журнал ошибок", "tested", "f:core/Logger:entries", "Structured ring buffer shown on the Diagnostics page.")
F("rel.report", "J", "Diagnostic report export", "Экспорт диагностического отчёта", "tested", "a:diagnostics.export", "File and clipboard export.")
F("rel.deps", "J", "Dependency check", "Проверка обязательных зависимостей", "tested", "f:core/Core:checkDependencies", "Missing/cyclic module dependencies and optional executor APIs.")
F("rel.reinit", "J", "Re-initialisation detection", "Обнаружение повторной инициализации", "tested", "f:core/Core:boot", "Previous instance is shut down before a new one starts.")
F("rel.shutdown", "J", "Safe shutdown", "Безопасное выключение модулей", "tested", "a:hub.unload", "Stops modules in reverse order with error isolation.")
F("rel.events", "J", "Event cleanup", "Очистка событий при закрытии", "tested", "f:core/Cleanup:run", "All connections are released on unload.")
F("rel.validation", "J", "Value validation", "Проверка значений настроек", "tested", "f:core/Settings:validateMap", "Type, range and enum checks on every write.")
F("rel.recovery", "J", "Module recovery", "Восстановление после ошибки отдельного модуля", "tested", "f:core/Core:restart", "Failed modules are isolated and can be restarted.")
F("rel.version", "J", "Version info", "Информация о версиях", "implemented", "u:Pages.about", "Version, schema and changelog.")
F("rel.help", "J", "Help & documentation", "Экран справки и документации", "implemented", "u:Pages.help", "In-app help page.")

-- K. Extra --------------------------------------------------------------------------
F("x.modules", "K", "Active modules list", "Список активных модулей", "tested", "f:core/Core:status", "State and errors of every module.")
F("x.favorites", "K", "Favourites panel", "Настраиваемая панель избранного", "tested", "f:core/Recents:toggleFavorite", "Pin features to the dashboard and quick bar.")
F("x.session", "K", "Session timer", "Счётчик времени сессии", "tested", "f:features/Tools:sessionSeconds", "Time since the hub started.")
F("x.notes", "K", "Local notes", "Локальные заметки пользователя", "tested", "f:features/Tools:setNotes", "Saved to MM2Hub/notes.txt (or session memory).")
F("x.timers", "K", "Timers & stopwatch", "Таймеры и секундомер", "tested", "f:features/Tools:addTimer", "Stopwatch with laps and countdown timers.")
F("x.history", "K", "Settings change history", "История изменений настроек", "tested", "f:core/Settings:history", "Last 100 changes with source.")
F("x.compare", "K", "Compare configurations", "Сравнение двух конфигураций", "tested", "f:core/Config:diff", "Key-by-key diff of two profiles or the live settings.")
F("x.conflicts", "K", "Setting conflict finder", "Поиск конфликтующих параметров", "tested", "f:core/Settings:conflicts", "Rules flag combinations that cancel each other.")
F("x.resetmodule", "K", "Reset module", "Сброс настроек конкретного модуля", "tested", "f:core/Settings:resetModule", "Restores defaults of one module's settings.")
F("x.integrity", "K", "Config integrity check", "Автоматическая проверка целостности конфигурации", "tested", "f:core/Config:checkIntegrity", "Verifies checksum and values of every saved profile.")

-- L. Local training range (own objects only) -------------------------------------
F("train.range", "L", "Training range", "Тренировочный полигон", "implemented", "s:training.enabled", "Local-only practice targets with hit statistics.")
F("train.modes", "L", "Target modes", "Режимы мишеней", "implemented", "s:training.mode", "Static, strafing and pop-up targets.")
F("train.guide", "L", "Demo guide", "Демонстрационное наведение", "implemented", "s:training.demoGuide", "Highlights the nearest practice target; never other players.")
F("train.stats", "L", "Accuracy stats", "Статистика точности", "implemented", "f:features/Training:getStats", "Hits, shots, accuracy and average reaction time.")
F("train.physics", "L", "Physics stand", "Физический стенд", "implemented", "a:training.launch", "Local dummy with impulse, speed limit and full reset.")
F("train.hitbox", "L", "Hitbox lab", "Лаборатория хитбокса", "implemented", "a:training.spawnLab", "Isolated test scene: a mannequin plus a separate hitbox (sphere or box) with size, offset, coordinates and intersection checks. Local scoring only.")
F("train.hbmodes", "L", "Hitbox motion modes", "Режимы движения хитбокса", "tested", "f:features/HitboxMath:offset", "Orbit / Jitter / Blink, each with its own settings; they change only the lab hitbox position.")
F("train.geometry", "L", "Geometry intersection checks", "Проверка пересечений", "tested", "f:features/Geometry:rayBox", "Ray/sphere, ray/box, sphere/sphere and sphere/box tests used by the lab readout.")
F("train.probe", "L", "Physical probe projectiles", "Пробные снаряды", "implemented", "a:training.fireProbe", "Real engine collisions between a thrown probe and the lab hitbox (Touched), in the isolated scene.")
F("aim.select", "L", "Select Aim (test targets)", "Выбор цели (тестовые мишени)", "implemented", "s:selectaim.enabled", "Selects one local test target by mode, FOV, visibility and lock, with highlight and info. No shooting, no camera control.")
F("aim.logic", "L", "Target selection rules", "Правила выбора цели", "tested", "f:features/SelectLogic:evaluate", "Eligibility (FOV, visibility, activity), modes, lock, loss reasons.")
F("aim.cycle", "L", "Target switching", "Переключение целей", "tested", "f:features/SelectLogic:cycle", "Next / previous eligible target with wrap-around.")
F("aim.predict", "L", "Movement prediction", "Прогноз положения мишени", "tested", "f:features/SelectLogic:intercept", "Intercept time and predicted position of a moving test target.")
F("aim.keys", "L", "Select / lock / reset / switch keys", "Клавиши выбора цели", "implemented", "a:selectaim.next", "Rebindable hotkeys wired to the real selection state.")
F("train.reset", "L", "Reset dummy", "Сброс стенда", "implemented", "a:training.resetDummy", "Restores dummy position and velocity.")

-- M. Defence (protects only the local player; never touches other players) -----------------
F("def.antifling", "M", "Anti-fling guard", "Анти-флинг", "implemented", "s:antifling.enabled", "Cancels abnormal speed and spin of your own character.", nil)
F("def.noCollide", "M", "Ghost collisions", "Коллизии-призраки", "env", "s:antifling.noCollide", "Other players' bodies stop colliding with you on your screen only.", "Relies on the client simulating your character; a game that re-enables collisions each frame can undo it.")
F("def.guardlogic", "M", "Fling detection logic", "Логика обнаружения флинга", "tested", "f:features/AntiFlingLogic:evaluate", "Pure speed/spin classifier (falling is never treated as a fling).")

-- N. Customisation (local only: gun, knife, character, kill sounds) ------------------------------
local NOTE_TOOL = "Needs your gun/knife to be a Tool with a Handle named as set on the page; a game that rebuilds its tools differently needs the tool name adjusted. Unverified in a real client."
F("cust.gun", "N", "Custom gun", "Свой пистолет", "env", "f:features/CustomLogic:apply", "Eight original gun models, style categories, colours, material, glow, preview and presets; applied to your own gun tool only.", NOTE_TOOL)
F("cust.knife", "N", "Custom knife", "Свой нож", "env", "f:features/CustomLogic:apply", "Eight original knife models with their own colours, effects, preview and presets, independent of the gun.", NOTE_TOOL)
F("cust.char", "N", "Custom character", "Свой персонаж", "env", "f:features/CustomLogic:apply", "Eight blocky costumes and twelve head/back/aura accessories drawn over your own avatar on your screen; safe mannequin preview.", "Costumes are static Part models welded to your root part: they do not animate with your limbs. Unverified in a real client.")
F("cust.preview", "N", "Model preview", "Предпросмотр модели", "implemented", "f:features/Cosmetics:buildPreview", "ViewportFrame preview with drag-rotate, zoom, reset and auto-rotate; it never touches your real items.")
F("cust.presets", "N", "Per-page presets", "Пресеты по страницам", "tested", "f:features/CustomLogic:savePreset", "Save, load, duplicate and delete named looks; each page keeps its own list and every entry is validated on load.")
F("cust.validate", "N", "Look validation", "Проверка параметров вида", "tested", "f:features/CustomLogic:normalize", "Unknown models, odd colours and materials are dropped or clamped; only plain data is stored, never code.")
F("kill.murderer", "N", "Murderer kill sound", "Звук убийства: Murderer", "env", "f:features/KillSounds:playEvent", "Own list, selection, volume, switch, preview, Apply and Reset for the murderer role.", "A kill is confirmed on your client (another player's death soon after your own knife use, nearby); a client cannot prove who killed whom. Sounds are only those you add.")
F("kill.sheriff", "N", "Sheriff kill sound", "Звук убийства: Sheriff", "env", "f:features/KillSounds:playEvent", "Own list, selection, volume, switch, preview, Apply and Reset for the sheriff role; never shares a setting with the murderer sound.", "A kill is confirmed on your client (another player's death soon after your own gun use); a client cannot prove who killed whom. Sounds are only those you add.")
F("kill.events", "N", "Confirmed-kill events", "Подтверждённые убийства", "tested", "f:features/KillEvents:report", "MurdererKillConfirmed / SheriffKillConfirmed with per-victim dedupe; shots and swings alone never fire them.")

return { categories = categories, list = list }

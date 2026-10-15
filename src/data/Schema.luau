--!nonstrict
-- data/Schema: every user-facing setting. `master = true` marks the on/off switch
-- of a feature (used by the "active features" filter and dashboard counter).
-- scope "state" values (window geometry, favourites...) are not part of profiles.

local THEMES = { "iOS", "iOS 27 Glass", "iOS 27 Chrome", "iOS 27 Prism", "iOS 27 Violet", "iOS Light", "Midnight", "Obsidian", "Ocean", "Rose", "Forest", "HighContrast" }

local function bool(key, default, label, desc, extra)
	local d = { key = key, type = "bool", default = default, label = label, desc = desc }
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return d
end

local function num(key, default, min, max, step, label, desc, extra)
	local d = { key = key, type = "number", default = default, min = min, max = max, step = step, label = label, desc = desc }
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return d
end

local function enum(key, default, options, label, desc, extra)
	local d = { key = key, type = "enum", default = default, options = options, label = label, desc = desc }
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return d
end

local function color(key, default, label, desc, extra)
	local d = { key = key, type = "color", default = default, label = label, desc = desc }
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return d
end

local function with(category, module, list)
	for _, d in ipairs(list) do
		d.category = category
		d.module = module
	end
	return list
end

local settings = {}
local function add(list)
	for _, d in ipairs(list) do
		table.insert(settings, d)
	end
end

add(with("ui", "Interface", {
	enum("ui.theme", "iOS 27 Glass", THEMES, "Theme", "Colour scheme. 'iOS' is a glass-style dark theme inspired by the latest iOS."),
	bool("ui.useThemeAccent", true, "Use theme accent", "When off, the custom accent colour below is used."),
	color("ui.accent", { r = 110, g = 120, b = 255 }, "Accent colour", "Custom accent used when 'Use theme accent' is off."),
	num("ui.opacity", 0.96, 0.5, 1, 0.01, "Window opacity", "Background opacity of the main window."),
	num("ui.glass", 0.7, 0, 1, 0.05, "Glass intensity", "How translucent surfaces are and how strong the light edge and sheen look. Low values give flatter, more solid panels."),
	bool("ui.reduceEffects", false, "Reduced effects", "Solid surfaces, no sheen, shadows, gradients or animated accents. Also applied automatically by the low load profile."),
	num("ui.scale", 1, 0.7, 1.5, 0.05, "Interface scale", "Scales the entire window. Clamped to fit the screen."),
	num("ui.animSpeed", 1, 0, 2, 0.1, "Animation speed", "0 disables animations (reduced motion)."),
	num("ui.cornerRadius", 8, 0, 16, 1, "Corner radius", "Roundness of cards and controls in pixels."),
	enum("ui.density", "Normal", { "Compact", "Normal", "Comfortable" }, "Density", "Row height and spacing."),
	num("ui.textScale", 1, 0.8, 1.4, 0.05, "Text size", "Scales all interface text."),
	bool("ui.compact", false, "Compact mode", "Hides descriptions to fit more rows on screen.", { master = true }),
	bool("ui.lockPosition", false, "Lock window", "Prevents moving and resizing the window."),
	bool("ui.showTooltips", true, "Tooltips", "Shows descriptions when hovering a control."),
	bool("ui.tint", false, "Own menu colour", "Tints the whole menu with the colour below. The glass, the glossy rim and every effect stay; only the colour changes."),
	color("ui.tintColor", { r = 120, g = 60, b = 255 }, "Menu colour", "Colour of the menu background and panels when 'Own menu colour' is on."),
	num("ui.tintStrength", 0.6, 0.1, 1, 0.05, "Colour strength", "How strongly the menu takes your colour."),
	bool("ui.titleFlow", true, "Flowing title", "The menu title flows with the colours, style and direction set on the Watermark page."),
	enum("ui.background", "Chrome", { "Off", "Chrome" }, "Menu background", "Picture behind the menu: liquid chrome waves (tinted to your theme or menu colour).", { labels = { Off = "Off", Chrome = "Chrome waves" } }),
	num("ui.backgroundStrength", 0.45, 0.05, 1, 0.05, "Background strength", "How visible the background picture is."),
	bool("ui.grain", true, "Glass grain", "A very fine frosted-glass grain and a soft highlight over the window."),
	bool("ui.decor", true, "Decorative effects", "Animated accent line and soft gradient. Disabled automatically in low profile."),
	bool("ui.splash", true, "Loading animation", "Shows the mascot and a progress bar inside the window when the hub starts."),
	bool("ui.cursor", true, "Custom cursor", "Replaces the mouse arrow with a glossy ring while the menu is open."),
	bool("ui.sticker", true, "Menu sticker", "The mascot sticker on the top-right corner of the window."),
	enum("ui.language", "ru", { "ru", "en", "uk", "es", "pt", "fr" }, "Language", "Interface language.", { labels = { ru = "Русский", en = "English", uk = "Українська", es = "Español", pt = "Português", fr = "Français" } }),
	enum("ui.font", "Auto", { "Auto", "Gotham", "Montserrat", "BuilderSans", "Arial", "SourceSans" }, "Font", "Auto: Montserrat for Russian and other non-English text (the default Gotham font has no Cyrillic letters in Roblox), the theme font for English. Pick another one if letters look uneven."),
	bool("ui.notifications", true, "Notifications", "Show toast notifications."),
	num("ui.notifyDuration", 4, 2, 12, 1, "Notification time", "Seconds before a toast disappears."),
	bool("ui.showLauncher", true, "Floating launcher button", "Round button that opens the hub (essential on mobile where there is no keyboard)."),
	bool("ui.screenButtons", false, "On-screen buttons", "Shows your starred features as floating round buttons you can tap and drag. Turned on automatically on phones.", { master = true }),
	num("ui.screenButtonSize", 46, 34, 70, 2, "Button size", "Diameter of the on-screen buttons."),
	num("ui.screenButtonOpacity", 0.85, 0.3, 1, 0.05, "Button opacity", "Transparency of the on-screen buttons."),
	bool("ui.showFpsBadge", true, "FPS in title bar", "Shows a live FPS badge next to the title."),
}))

add(with("state", "State", {
	num("state.posX", -1, -1, 8000, 1, "Window X", "Saved window position (-1 = centred).", { scope = "state", hidden = true }),
	num("state.posY", -1, -1, 8000, 1, "Window Y", "Saved window position (-1 = centred).", { scope = "state", hidden = true }),
	num("state.width", 820, 460, 1600, 1, "Window width", "Saved window width.", { scope = "state", hidden = true }),
	num("state.height", 560, 320, 1200, 1, "Window height", "Saved window height.", { scope = "state", hidden = true }),
	bool("state.minimized", false, "Minimised", "Saved minimised state.", { scope = "state", hidden = true }),
	{ key = "state.page", type = "string", default = "dashboard", maxLen = 32, label = "Page", desc = "Last opened page.", scope = "state", hidden = true },
	{ key = "state.favorites", type = "strlist", default = {}, maxItems = 24, label = "Favourites", desc = "Pinned feature ids.", scope = "state", hidden = true },
	{ key = "state.recent", type = "strlist", default = {}, maxItems = 8, label = "Recent", desc = "Recently used feature ids.", scope = "state", hidden = true },
	{ key = "state.platform", type = "string", default = "", maxLen = 12, label = "Platform", desc = "Device class the layout preset was applied for.", scope = "state", hidden = true },
	{ key = "state.buttonPos", type = "strlist", default = {}, maxItems = 24, itemMax = 60, label = "Button positions", desc = "Saved positions of on-screen buttons.", scope = "state", hidden = true },
	{ key = "state.activeProfile", type = "string", default = "Default", maxLen = 32, label = "Profile", desc = "Active configuration profile.", scope = "state", hidden = true },
}))

add(with("crosshair", "Crosshair", {
	bool("crosshair.enabled", false, "Custom crosshair", "Draws your own crosshair at the screen centre.", { master = true }),
	enum("crosshair.style", "Cross", { "Cross", "Dot", "Circle", "CrossCircle" }, "Style", "Shape of the line crosshair."),
	enum("crosshair.design", "Lines", { "Lines", "Sniper", "Tactical", "Diamond", "Chevron", "Hexagon", "Star", "Brackets", "Tri", "Segments", "Scope", "Heart", "X",
		"Radar", "Ripple", "Lock-on", "Orbit", "Breathe", "Menacing" },
		"Design", "Lines = the classic crosshair built from the settings below; the others are drawn designs (the hub's own textures)."),
	num("crosshair.imageSize", 48, 16, 200, 2, "Design size", "Size of a drawn design in pixels."),
	bool("crosshair.glow", false, "Glow", "Soft glow in the crosshair colour behind a drawn design."),
	num("crosshair.spin", 0, -360, 360, 10, "Rotation speed", "Turns a drawn design (degrees per second, 0 = still)."),
	bool("crosshair.pulse", false, "Pulse", "A drawn design gently breathes in size."),
	num("crosshair.animSpeed", 1, 0.2, 3, 0.1, "Animation speed", "How fast the animated designs (Radar, Ripple, Lock-on, Orbit, Breathe, Menacing) play."),
	bool("crosshair.rainbow", false, "Rainbow colour", "The crosshair (any design) slowly cycles through all colours instead of the chosen one."),
	num("crosshair.size", 10, 2, 60, 1, "Size", "Length of each arm / circle radius in pixels."),
	num("crosshair.thickness", 2, 1, 8, 1, "Thickness", "Line thickness in pixels."),
	num("crosshair.gap", 4, 0, 30, 1, "Centre gap", "Empty space around the centre."),
	color("crosshair.color", { r = 255, g = 255, b = 255 }, "Colour", "Crosshair colour."),
	num("crosshair.opacity", 1, 0, 1, 0.05, "Opacity", "Crosshair transparency (1 = solid)."),
	bool("crosshair.centerDot", false, "Centre dot", "Adds a dot in the middle."),
	num("crosshair.dotSize", 2, 1, 8, 1, "Dot size", "Diameter of the centre dot in pixels."),
	bool("crosshair.outline", true, "Outline", "Dark outline for readability on bright backgrounds."),
	bool("crosshair.dynamic", false, "Dynamic spread", "Widens the gap while your character moves."),
	num("crosshair.dynamicAmount", 8, 0, 30, 1, "Spread amount", "Maximum extra gap while moving at full speed."),
	num("crosshair.offsetX", 0, -200, 200, 1, "Offset X", "Horizontal offset from the screen centre."),
	num("crosshair.offsetY", 0, -200, 200, 1, "Offset Y", "Vertical offset from the screen centre."),
	bool("crosshair.hideCursor", true, "Hide the game's crosshair", "While your crosshair is on, the game's own crosshair / mouse icon is hidden (it comes back when you open the menu or turn yours off)."),
}))

add(with("camera", "Camera", {
	bool("camera.sensitivityEnabled", false, "Override sensitivity", "Applies the mouse sensitivity multiplier below.", { master = true }),
	num("camera.sensitivity", 1, 0.1, 3, 0.05, "Mouse sensitivity", "Multiplier applied to mouse movement (UserInputService.MouseDeltaSensitivity)."),
	bool("camera.zoomEnabled", false, "Custom zoom control", "Takes over scroll-wheel zoom with your speed and limits.", { master = true }),
	num("camera.zoomSpeed", 1, 0.25, 4, 0.05, "Zoom speed", "Scroll-wheel zoom speed multiplier."),
	num("camera.minZoom", 0.5, 0.5, 20, 0.5, "Minimum zoom", "Closest camera distance in studs."),
	num("camera.maxZoom", 128, 5, 500, 1, "Maximum zoom", "Farthest camera distance in studs."),
	bool("camera.rememberZoom", false, "Remember zoom", "Restores your preferred zoom after respawn."),
	num("camera.preferredZoom", 12, 0.5, 500, 0.5, "Preferred zoom", "Distance restored after respawn when 'Remember zoom' is on."),
	enum("camera.mode", "Default", { "Default", "FirstPerson", "ThirdPerson" }, "Camera mode", "Forces first-person lock or classic third-person; Default leaves the game in control."),
	bool("camera.fovEnabled", false, "Override field of view", "Keeps the field of view at the value below.", { master = true }),
	num("camera.fov", 70, 30, 120, 1, "Field of view", "Camera field of view in degrees."),
	num("camera.smoothing", 0.35, 0, 0.95, 0.05, "Smoothing", "Smooths zoom and FOV transitions (does not alter mouse look)."),
	num("camera.bobIntensity", 0, 0, 1, 0.05, "Head bob", "Optional walking head bob via Humanoid.CameraOffset. 0 = off."),
	num("camera.ownOpacity", 1, 0, 1, 0.05, "Own character opacity", "Local-only transparency of your own character."),
	bool("camera.disableEffects", false, "Disable optional camera effects", "Turns off head bob and the hub's blur effect."),
}))

add(with("lighting", "Lighting", {
	bool("lighting.brightnessEnabled", false, "Override brightness", "Applies the brightness value below to Lighting.", { master = true }),
	num("lighting.brightness", 2, 0, 5, 0.1, "Brightness", "Lighting.Brightness while override is on."),
	enum("lighting.timePreset", "Game", { "Game", "Dawn", "Noon", "Dusk", "Night" }, "Time of day", "Local sky/ambient preset. 'Game' leaves the game's lighting alone."),
	bool("lighting.colorEnabled", false, "Colour correction", "Enables the hub's ColorCorrection effect.", { master = true }),
	num("lighting.saturation", 0, -1, 2, 0.05, "Saturation", "Colour saturation (-1 greyscale, 2 vivid)."),
	num("lighting.contrast", 0, -1, 1, 0.05, "Contrast", "Image contrast."),
	num("lighting.exposure", 0, -0.5, 0.5, 0.05, "Exposure", "Brightness offset of the colour correction."),
	enum("lighting.filter", "None", { "None", "Warm", "Cool", "Mono", "Sepia", "Vivid" }, "Colour filter", "Preset applied on top of the sliders."),
	color("lighting.tint", { r = 255, g = 255, b = 255 }, "Tint", "Custom tint multiplied into the image."),
	bool("lighting.blurEnabled", false, "Blur", "Enables a screen blur effect.", { master = true }),
	num("lighting.blurSize", 6, 0, 24, 1, "Blur size", "Blur radius."),
	bool("lighting.bloomEnabled", false, "Bloom", "Enables a bloom glow effect.", { master = true }),
	num("lighting.bloomIntensity", 1, 0, 3, 0.1, "Bloom intensity", "Strength of the glow."),
	num("lighting.bloomSize", 24, 0, 56, 1, "Bloom size", "Spread of the glow."),
	num("lighting.bloomThreshold", 2, 0, 4, 0.1, "Bloom threshold", "Brightness above which glow begins."),
}))

add(with("training", "Training", {
	bool("training.enabled", false, "Training range", "Spawns local-only practice targets in front of you.", { master = true }),
	enum("training.mode", "Strafing", { "Static", "Strafing", "Popup" }, "Target mode", "How the targets behave."),
	num("training.count", 4, 1, 12, 1, "Target count", "Number of targets (capped by Performance > decorative limit)."),
	num("training.targetSize", 3, 1, 8, 0.5, "Target size", "Diameter in studs."),
	num("training.speed", 8, 0, 30, 1, "Target speed", "Movement speed in studs per second."),
	num("training.distance", 35, 15, 80, 1, "Distance", "Distance from you at spawn time."),
	color("training.targetColor", { r = 255, g = 90, b = 90 }, "Target colour", "Colour of the targets."),
	bool("training.particles", true, "Hit particles", "Particle burst when a target is hit."),
	bool("training.demoGuide", false, "Demo guide", "Highlights the nearest practice target. Never touches other players."),
	-- Hitbox lab: visual hitbox geometry
	enum("training.hbShape", "Sphere", { "Sphere", "Box" }, "Hitbox shape", "Geometry of the lab hitbox (a Box is an axis-aligned cube)."),
	num("training.hbSize", 3, 1, 8, 0.5, "Hitbox size", "Diameter of the sphere / edge of the box, in studs."),
	num("training.hbOffsetX", 0, -6, 6, 0.5, "Static offset X", "Fixed offset of the hitbox centre from the body centre (studs)."),
	num("training.hbOffsetY", 0, -6, 6, 0.5, "Static offset Y", "Fixed offset of the hitbox centre from the body centre (studs)."),
	num("training.hbOffsetZ", 0, -6, 6, 0.5, "Static offset Z", "Fixed offset of the hitbox centre from the body centre (studs)."),
	bool("training.hbShow", true, "Show hitbox", "Draws the hitbox as a translucent shape."),
	bool("training.hbCollide", false, "Physical collisions", "Makes the lab hitbox collide with the probe projectiles in the isolated scene (CanCollide)."),
	-- motion modes: each mode has its own settings and changes ONE property: HubLabHitbox.Position
	enum("training.hbMode", "Orbit", { "Off", "Orbit", "Jitter", "Blink" }, "Motion mode", "Moves the lab hitbox around the body. Changes only the hitbox position, never the body, your character or any real hitbox."),
	num("training.orbitRadius", 8, 2, 25, 1, "Orbit radius", "Orbit: distance of the circular path from the body."),
	num("training.orbitSpeed", 8, 1, 30, 1, "Orbit speed", "Orbit: travel speed along the path (studs/s)."),
	num("training.orbitTilt", 0.3, 0, 1, 0.05, "Orbit tilt", "Orbit: vertical wobble relative to the radius."),
	num("training.jitterAmplitude", 3, 0.5, 10, 0.5, "Jitter amplitude", "Jitter: maximum distance from the base position."),
	num("training.jitterSpeed", 8, 1, 30, 1, "Jitter speed", "Jitter: how fast the hitbox shakes."),
	num("training.blinkRange", 10, 2, 25, 1, "Blink range", "Blink: maximum jump distance from the base position."),
	num("training.blinkInterval", 0.8, 0.2, 3, 0.1, "Blink interval", "Blink: seconds the hitbox rests before jumping again."),
	num("training.physImpulse", 120, 0, 500, 5, "Impulse strength", "Impulse (per unit mass) used by the physics stand."),
	num("training.physMaxSpeed", 80, 10, 200, 5, "Speed limit", "Dummy velocity is clamped to this speed."),
	enum("training.physDirection", "Forward", { "Up", "Forward", "Back", "Left", "Right" }, "Impulse direction", "Direction relative to your camera."),
}))

add(with("selectaim", "SelectAim", {
	bool("selectaim.enabled", false, "Select Aim", "Selects one of your local TEST targets (training range, dummy, lab hitbox). It never fires, moves your camera or touches hit registration.", { master = true }),
	enum("selectaim.mode", "Crosshair", { "Crosshair", "Distance", "Manual" }, "Selection mode", "Crosshair: nearest to the search centre. Distance: nearest to you. Manual: the target you picked in the list or with the switch keys."),
	bool("selectaim.lock", false, "Target lock", "Keeps the selected target for as long as it exists and still passes visibility and the FOV."),
	num("selectaim.fov", 150, 20, 600, 5, "FOV radius", "Search radius in pixels around the crosshair centre (or the screen centre when the crosshair is off)."),
	bool("selectaim.showFov", true, "Show FOV circle", "Draws the search circle on screen."),
	bool("selectaim.highlight", true, "Target highlight", "Draws a ring and brackets on the selected target."),
	bool("selectaim.visibilityCheck", true, "Visibility check", "Ignores test targets hidden behind scene geometry (uses Workspace:Raycast)."),
	bool("selectaim.autoAcquire", true, "Auto acquire", "Select automatically by the mode. Off: only the Select key acquires a target."),
	bool("selectaim.prediction", false, "Prediction", "Calculates where a moving test target will be after the projectile travel time and marks it."),
	num("selectaim.projectileSpeed", 200, 50, 500, 10, "Projectile speed", "Studs per second used by the prediction calculation (the hub fires nothing)."),
	num("selectaim.leadMax", 0.6, 0.05, 1.5, 0.05, "Maximum lead time", "Cap on how far ahead the prediction looks (seconds)."),
	color("selectaim.highlightColor", { r = 255, g = 214, b = 10 }, "Highlight colour", "Colour of the target highlight."),
}))

add(with("ghost", "Ghost", {
	bool("ghost.enabled", false, "Local invisibility", "Makes YOUR character see-through on YOUR screen only. Other players still see you normally.", { master = true }),
	num("ghost.opacity", 0.15, 0, 1, 0.05, "Visibility to you", "0 = fully invisible to you, 1 = normal."),
	num("ghost.fadeTime", 0.35, 0, 2, 0.05, "Fade time", "Seconds to fade in or out."),
	bool("ghost.includeAccessories", true, "Include accessories", "Hats, hair and other accessories fade too."),
	bool("ghost.includeFace", true, "Include face", "Face decals fade too."),
	bool("ghost.includeTools", false, "Include held tools", "Tools in your hands fade too."),
	bool("ghost.hideName", true, "Hide own name tag", "Hides your name/health bar on your screen."),
	bool("ghost.restoreOnDeath", true, "Show body on death", "Becomes visible when you die so you can see what happens."),
}))

add(with("antifling", "AntiFling", {
	bool("antifling.enabled", false, "Anti-fling guard", "Cancels abnormal speed/spin of YOUR character and keeps you from being thrown around. Local to your client.", { master = true }),
	num("antifling.maxSpeed", 120, 60, 300, 10, "Speed limit", "Horizontal/upward speed (studs/s) above which your movement counts as a fling. Normal running is 16."),
	num("antifling.angularLimit", 60, 20, 200, 5, "Spin limit", "Angular speed (rad/s) above which your spin is cancelled."),
	bool("antifling.noCollide", true, "Ghost collisions with others", "On your screen other players' bodies stop colliding with you, so they cannot push or fling you. They are unaffected."),
	bool("antifling.notify", true, "Notify when blocked", "Shows a notification (rate-limited) when a fling is cancelled."),
}))

add(with("perf", "Performance", {
	bool("perf.lowProfile", false, "Low load profile", "Halves update rates, disables decorations and heavy effects.", { master = true }),
	bool("perf.autoLow", false, "Auto low profile", "Enables the low profile when FPS stays under the threshold for 5 seconds."),
	num("perf.autoLowFps", 25, 15, 60, 1, "Auto threshold", "FPS under which auto low profile triggers."),
	num("perf.visualHz", 30, 10, 60, 1, "Visual update rate", "Maximum update rate of crosshair/effects (Hz)."),
	num("perf.maxDecor", 12, 1, 24, 1, "Decorative object limit", "Upper bound for training targets and toast cards."),
	num("perf.warnMs", 8, 2, 50, 1, "Long operation warning", "Log a warning when one scheduled task exceeds this many milliseconds."),
}))

add(with("tools", "Tools", {
	bool("tools.notesAutosave", true, "Autosave notes", "Saves notes automatically after you stop typing."),
	bool("tools.timerSound", true, "Timer alert sound", "Plays a ping when a countdown ends (needs interface sounds on)."),
}))

add(with("input", "Input", {
	bool("input.enabled", true, "Hotkeys enabled", "Master switch for all hub hotkeys."),
	bool("input.ignoreTyping", true, "Ignore while typing", "Hotkeys do nothing while a text box is focused."),
}))

add(with("cosmetics", "Cosmetics", {
	bool("cosmetics.gunEnabled", false, "Gun skin", "Replaces the look of your gun tool. Visible only to you.", { master = true }),
	{ key = "cosmetics.gunSource", type = "string", default = "proc:neon", maxLen = 120, label = "Gun model source", desc = "proc:<name>, asset:<id> or file:<name.rbxm>." },
	{ key = "cosmetics.gunTool", type = "string", default = "Gun", maxLen = 32, label = "Gun tool name", desc = "Name of the Tool instance to skin." },
	num("cosmetics.gunScale", 1, 0.2, 4, 0.05, "Gun scale", "Size multiplier of the replacement model."),
	num("cosmetics.gunOffsetX", 0, -3, 3, 0.05, "Gun offset X", "Offset relative to the tool handle."),
	num("cosmetics.gunOffsetY", 0, -3, 3, 0.05, "Gun offset Y", "Offset relative to the tool handle."),
	num("cosmetics.gunOffsetZ", 0, -3, 3, 0.05, "Gun offset Z", "Offset relative to the tool handle."),
	num("cosmetics.gunRotY", 0, -180, 180, 5, "Gun rotation Y", "Yaw correction in degrees."),
	bool("cosmetics.knifeEnabled", false, "Knife skin", "Replaces the look of your knife tool. Visible only to you.", { master = true }),
	{ key = "cosmetics.knifeSource", type = "string", default = "proc:blade", maxLen = 120, label = "Knife model source", desc = "proc:<name>, asset:<id> or file:<name.rbxm>." },
	{ key = "cosmetics.knifeTool", type = "string", default = "Knife", maxLen = 32, label = "Knife tool name", desc = "Name of the Tool instance to skin." },
	num("cosmetics.knifeScale", 1, 0.2, 4, 0.05, "Knife scale", "Size multiplier of the replacement model."),
	num("cosmetics.knifeOffsetX", 0, -3, 3, 0.05, "Knife offset X", "Offset relative to the tool handle."),
	num("cosmetics.knifeOffsetY", 0, -3, 3, 0.05, "Knife offset Y", "Offset relative to the tool handle."),
	num("cosmetics.knifeOffsetZ", 0, -3, 3, 0.05, "Knife offset Z", "Offset relative to the tool handle."),
	num("cosmetics.knifeRotY", 0, -180, 180, 5, "Knife rotation Y", "Yaw correction in degrees."),
	bool("cosmetics.charEnabled", false, "Character model", "Attaches a model to your own character. Visible only to you.", { master = true }),
	{ key = "cosmetics.charSource", type = "string", default = "proc:halo", maxLen = 120, label = "Character model source", desc = "proc:<name>, asset:<id> or file:<name.rbxm>." },
	enum("cosmetics.charAttach", "Head", { "Head", "Torso", "RootPart" }, "Attach to", "Body part the model is welded to."),
	num("cosmetics.charScale", 1, 0.2, 4, 0.05, "Model scale", "Size multiplier."),
	num("cosmetics.charOffsetY", 1.2, -5, 5, 0.1, "Model height", "Vertical offset from the body part."),
	bool("cosmetics.bodyColorEnabled", false, "Body colour override", "Recolours your own character locally.", { master = true }),
	color("cosmetics.bodyColor", { r = 120, g = 90, b = 255 }, "Body colour", "Colour applied to your character's body parts."),
	bool("cosmetics.neon", false, "Neon material", "Local Neon material on your body parts."),
}))

add(with("music", "Music", {
	{ key = "music.playlist", type = "strlist", default = {}, maxItems = 40, itemMax = 140, label = "Playlist", desc = "Entries 'asset:<id>|Title' or 'file:<name>|Title'.", hidden = true },
	num("music.volume", 0.5, 0, 1, 0.05, "Volume", "Playback volume."),
	enum("music.loop", "All", { "Off", "One", "All" }, "Repeat", "Repeat mode."),
	bool("music.shuffle", false, "Shuffle", "Play tracks in random order."),
	num("music.speed", 1, 0.5, 2, 0.05, "Playback speed", "Sound.PlaybackSpeed."),
	bool("music.autoplay", false, "Autoplay on start", "Starts the playlist when the hub loads."),
	num("music.index", 1, 1, 40, 1, "Current track", "Index of the current track.", { hidden = true }),
}))

local SOUND_SLOTS = {
	{ "gunShot", "Gun shot", "Plays when you use your gun tool." },
	{ "knifeSwing", "Knife swing", "Plays when you use your knife tool." },
	{ "hit", "Hit", "Plays when you hit a training target." },
	{ "kill", "Kill", "Plays when you eliminate a training target or dummy." },
	{ "uiClick", "Interface click", "Plays when you press toggles and buttons in the hub." },
}
add(with("sounds", "Sounds", {
	num("sounds.master", 1, 0, 1, 0.05, "Master volume", "Scales all custom sounds."),
}))
for _, slot in ipairs(SOUND_SLOTS) do
	local id, label, desc = slot[1], slot[2], slot[3]
	add(with("sounds", "Sounds", {
		bool("sounds." .. id .. "Enabled", false, label, desc .. " Needs a source below.", { master = true }),
		{ key = "sounds." .. id .. "Source", type = "string", default = "", maxLen = 120, label = label .. " source", desc = "asset:<id> or file:<name> (from MM2Hub/sounds)." },
		num("sounds." .. id .. "Volume", 0.8, 0, 1, 0.05, label .. " volume", "Volume of this sound."),
		num("sounds." .. id .. "Pitch", 1, 0.5, 2, 0.05, label .. " pitch", "Playback speed / pitch."),
	}))
end

-- Customisation (gun / knife / character) ---------------------------------------------------------------------------------
-- One block per kind. The plain keys are the DRAFT the page edits and the preview shows; `applied` is the snapshot the
-- game-side builder reads (set by Apply, cleared by Reset). Nothing here changes damage, speed or any gameplay value.
local MATERIALS = { "SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "Foil", "Glass", "Marble", "Slate", "Wood" }
local LOOK_DEFAULT = {
	gun = { primary = { r = 150, g = 154, b = 162 }, secondary = { r = 112, g = 70, b = 40 }, grip = { r = 112, g = 70, b = 40 }, detail = { r = 196, g = 154, b = 72 }, glow = { r = 255, g = 214, b = 120 }, material = "Metal", glowAmount = 0.2 },
	knife = { primary = { r = 196, g = 202, b = 212 }, secondary = { r = 120, g = 126, b = 138 }, grip = { r = 98, g = 62, b = 36 }, detail = { r = 196, g = 154, b = 72 }, glow = { r = 255, g = 214, b = 120 }, material = "Metal", glowAmount = 0.2 },
	char = { primary = { r = 255, g = 255, b = 255 }, secondary = { r = 210, g = 214, b = 224 }, grip = { r = 40, g = 40, b = 46 }, detail = { r = 255, g = 224, b = 120 }, glow = { r = 255, g = 232, b = 140 }, material = "SmoothPlastic", glowAmount = 0.5 },
}
local CUSTOM_KINDS = {
	{ "gun", "CustomGun", "Custom gun", "revolver", "gun" },
	{ "knife", "CustomKnife", "Custom knife", "classic", "knife" },
	{ "char", "CustomChar", "Custom character", "", "character" },
}
for _, k in ipairs(CUSTOM_KINDS) do
	local kind, module, label, model, noun = k[1], k[2], k[3], k[4], k[5]
	local d = LOOK_DEFAULT[kind]
	local p = "custom." .. kind
	local list = {
		bool(p .. "Enabled", false, label .. " shown", "Shows the applied look on your own " .. noun .. ". Visible only to you.", { master = true }),
		{ key = p .. "Style", type = "string", default = "Custom", maxLen = 16, label = "Style category", desc = "Last chosen style category.", hidden = true },
		color(p .. "Primary", d.primary, "Main colour", "Main colour of the " .. noun .. "."),
		color(p .. "Secondary", d.secondary, "Secondary colour", "Second colour of the " .. noun .. "."),
		color(p .. "Grip", d.grip, "Grip colour", "Handle, grip or trim colour."),
		color(p .. "Detail", d.detail, "Detail colour", "Small decorative parts."),
		color(p .. "Glow", d.glow, "Glow colour", "Colour of the glowing accents."),
		enum(p .. "Material", d.material, MATERIALS, "Material", "Surface material of the main parts."),
		num(p .. "GlowAmount", d.glowAmount, 0, 1, 0.05, "Glow intensity", "0 turns glowing parts into plain plastic."),
		num(p .. "Decor", 0, 0, 0.6, 0.05, "Decor transparency", "Applies only to decorative glass parts, never to the main body."),
		bool(p .. "Effects", true, "Effects", "Soft light and a short trail or sparkle. Off = no lights, no particles."),
		{ key = p .. "Applied", type = "string", default = "", maxLen = 900, label = "Applied look", desc = "Snapshot of the applied look.", hidden = true },
		{ key = p .. "Presets", type = "string", default = "", maxLen = 9000, label = "Saved presets", desc = "Your saved presets.", hidden = true },
	}
	if kind == "char" then
		for _, slot in ipairs({ "costume", "head", "back", "aura" }) do
			table.insert(list, { key = p .. string.upper(string.sub(slot, 1, 1)) .. string.sub(slot, 2), type = "string", default = "", maxLen = 40, label = "Selected " .. slot, desc = "Chosen model for this slot (empty = none).", hidden = true })
		end
	else
		table.insert(list, { key = p .. "Model", type = "string", default = model, maxLen = 40, label = "Selected model", desc = "Chosen model id.", hidden = true })
	end
	add(with("custom", module, list))
end
add(with("killfx", "KillFX", {
	bool("killfx.enabled", true, "Kill effects", "A big finisher on the victim when you get a confirmed kill: lightning, explosion, vaporize, black hole or ice shatter. Only you see it.", { master = true }),
	enum("killfx.effect", "Lightning", { "Lightning", "Explosion", "Vaporize", "BlackHole", "Shatter", "Troll", "Random" }, "Effect", "Which finisher plays.", { labels = { Lightning = "Lightning", Explosion = "Explosion", Vaporize = "Vaporize", BlackHole = "Black hole", Shatter = "Ice shatter", Troll = "Troll", Random = "Random" } }),
	num("killfx.scale", 1, 0.5, 2, 0.05, "Size", "How big the effect is."),
	num("killfx.detail", 1, 0.3, 1.5, 0.05, "Detail", "Number of sparks, shards and dust. Lowered automatically in the low load profile."),
	bool("killfx.customColor", false, "Own colour", "Use your colour below instead of the effect's own colours."),
	color("killfx.color", { r = 178, g = 120, b = 255 }, "Effect colour", "Main colour of the bolts, rings, glow and dust."),
	bool("killfx.hideBody", true, "Hide the real body", "On your screen the victim's body is replaced by the animated copy (other players still see the normal body)."),
	bool("killfx.onMurderer", true, "As murderer", "Play on kills with your knife."),
	bool("killfx.onSheriff", true, "As sheriff", "Play on kills with your gun."),
}))

add(with("watermark", "Watermark", {
	bool("watermark.enabled", true, "Watermark", "A badge on your screen with your text, the mascot and optional FPS, ping and time. Only you see it.", { master = true }),
	{ key = "watermark.text", type = "string", default = "TrollHub", maxLen = 40, label = "Text", desc = "What the watermark says." },
	enum("watermark.position", "TopLeft", { "TopLeft", "TopCenter", "TopRight", "BottomLeft", "BottomRight" }, "Position", "Corner of the screen.", { labels = { TopLeft = "Top left", TopCenter = "Top centre", TopRight = "Top right", BottomLeft = "Bottom left", BottomRight = "Bottom right" } }),
	num("watermark.size", 1, 0.6, 2, 0.05, "Size", "Scale of the watermark."),
	bool("watermark.background", true, "Glass background", "Black glass with a glossy rim behind the text."),
	bool("watermark.sticker", true, "Mascot", "The Trollface sticker at the start of the watermark."),
	bool("watermark.showFps", true, "FPS", "Frames per second."),
	bool("watermark.showPing", true, "Ping", "Network delay in milliseconds."),
	bool("watermark.showTime", false, "Time", "Your local clock."),
	enum("watermark.style", "Wave", { "Off", "Wave", "Rainbow", "Pulse", "Chrome", "Neon" }, "Flow style", "How the colour moves: Wave - your colours flow across; Rainbow - the whole spectrum; Pulse - the text breathes between your colours; Chrome - silver bands; Neon - a bright glint runs along; Off - one plain colour.", { labels = { Off = "Off", Wave = "Wave", Rainbow = "Rainbow", Pulse = "Pulse", Chrome = "Chrome", Neon = "Neon" } }),
	enum("watermark.direction", "Right", { "Right", "Left", "Up", "Down", "Diagonal", "Spin" }, "Flow direction", "Which way the colour flows. Spin turns it round.", { labels = { Right = "Right", Left = "Left", Up = "Up", Down = "Down", Diagonal = "Diagonal", Spin = "Spin" } }),
	num("watermark.speed", 1, 0.1, 4, 0.1, "Flow speed", "How fast the colour moves."),
	bool("watermark.themeColors", false, "Theme colours", "Use the menu accent instead of your three colours."),
	color("watermark.color1", { r = 255, g = 255, b = 255 }, "Colour 1", "First flow colour."),
	color("watermark.color2", { r = 178, g = 120, b = 255 }, "Colour 2", "Second flow colour."),
	color("watermark.color3", { r = 90, g = 210, b = 255 }, "Colour 3", "Third flow colour."),
}))

add(with("aura", "Aura", {
	bool("aura.enabled", false, "Aura", "Wings, halo, a rotating rune circle, orbiting chains and sparkles on your own character. Only you see it.", { master = true }),
	enum("aura.style", "Classic", { "Classic", "Inferno Crown", "Storm God", "Galaxy", "Frost Monarch", "Void Wings", "Sakura", "Phoenix", "Dragon Spirit", "Holy Light", "Toxic Rift", "Shadow Reaper", "Neon Cyber", "Troll", "Burning" }, "Style", "Classic: wings, halo, rune circle and chains (the switches below). The others are big full auras with their own shapes and particles.", { labels = { Classic = "Classic", ["Inferno Crown"] = "Inferno Crown", ["Storm God"] = "Storm God", Galaxy = "Galaxy", ["Frost Monarch"] = "Frost Monarch", ["Void Wings"] = "Void Wings", Sakura = "Sakura", Phoenix = "Phoenix", ["Dragon Spirit"] = "Dragon Spirit", ["Holy Light"] = "Holy Light", ["Toxic Rift"] = "Toxic Rift", ["Shadow Reaper"] = "Shadow Reaper", ["Neon Cyber"] = "Neon Cyber", Troll = "Troll", Burning = "Burning" } }),
	bool("aura.highlight", true, "Glow outline", "A pulsing colour fill over your character with a thin outline, in the aura colours."),
	num("aura.pulse", 0.5, 0, 1, 0.05, "Pulse speed", "How fast the glow fill breathes."),
	bool("aura.spheres", true, "Orbiting spheres", "Glowing spheres circle you, each bobbing on its own wave, with light trails."),
	num("aura.sphereCount", 4, 2, 8, 1, "Sphere count", "How many spheres circle you."),
	bool("aura.feet", true, "Ring and foot trails", "A turning ring at your feet with rising stars, and a double light trail behind your feet while you walk."),
	enum("aura.preset", "Angel", { "Angel", "Inferno", "Frost", "Toxic", "Crimson", "Rainbow" }, "Preset", "Colour scheme of the aura."),
	bool("aura.wings", true, "Wings", "Angel wings behind your back; they flap faster while you run."),
	bool("aura.halo", true, "Halo", "A double ring above your head."),
	bool("aura.circle", true, "Rune circle", "Rotating rings, runes and a glowing disc under your feet."),
	bool("aura.chains", true, "Chains", "Four chains orbiting around you."),
	bool("aura.particles", true, "Sparkles and light", "Particles and a soft light. Switched off automatically in the low load profile and with reduced effects."),
	num("aura.intensity", 1, 0.2, 2, 0.05, "Intensity", "Brightness and particle amount."),
	num("aura.wingScale", 1, 0.5, 1.6, 0.05, "Aura size", "Size of the wings (classic style) or of the whole aura (the other styles)."),
	bool("aura.rainbow", false, "Rainbow", "Colours cycle through the rainbow."),
	bool("aura.customColors", false, "Own colours", "Use the two colours below instead of the preset."),
	color("aura.primary", { r = 176, g = 84, b = 255 }, "Main colour", "Rims, rings, chains and the light."),
	color("aura.secondary", { r = 90, g = 210, b = 255 }, "Second colour", "Halo, runes and the particle fade."),
}))

add(with("custom", "CustomMeshes", {
	bool("custom.useMeshes", true, "Smooth meshes", "Draws the built-in models as smooth meshes (written to MM2Hub/meshcache/ and loaded with getcustomasset). When the executor cannot, the page says why and the simple Part version is used instead."),
}))

-- Kill sounds (two independent settings) -----------------------------------------------------------------------------------
-- Murderer and Sheriff never share a key. `pick` is what the list has selected (and what Preview plays); `source` is
-- what is applied and played on a confirmed kill.
for _, role in ipairs({ { "murderer", "MurdererKillSound", "Murderer kill sound" }, { "sheriff", "SheriffKillSound", "Sheriff kill sound" } }) do
	local p = "ksound." .. role[1]
	add(with("ksound", role[2], {
		bool(p .. "Enabled", false, role[3], "Plays your applied sound when a " .. role[1] .. " kill is confirmed. Local only.", { master = true }),
		{ key = p .. "Pick", type = "string", default = "", maxLen = 120, label = role[3] .. " selection", desc = "Selected sound (source text).", hidden = true },
		{ key = p .. "Source", type = "string", default = "", maxLen = 120, label = role[3] .. " applied", desc = "Applied sound source.", hidden = true },
		num(p .. "Volume", 0.8, 0, 1, 0.05, role[3] .. " volume", "Volume of this sound only."),
		{ key = p .. "Library", type = "string", default = "", maxLen = 4000, label = role[3] .. " list", desc = "Sounds you added for this role.", hidden = true },
	}))
end

-- Game audio (local mute list, learn mode, round-end song) ---------------------------------------------------------------------
-- Silences chosen sounds of the game on YOUR client only (their Volume is set to 0 and restored on disable/unload) and can play your own
-- song when a round-end sound is detected. Which game sounds count is decided by keywords in the sound's name/path; the defaults are
-- guesses, "Learn" on the page finds the real names.
add(with("gameaudio", "GameAudio", {
	bool("gameaudio.muteKill", true, "Mute the game's kill sounds while mine is on", "While a custom Murderer or Sheriff kill sound is applied and switched on, the game's own kill sounds are silenced on your client.", { master = true }),
	bool("gameaudio.muteShot", false, "Mute the game's gun shot sound", "Silences the game's own gun shot sound on your client (pair it with your own gun-shot sound on the Sounds page)."),
	bool("gameaudio.muteReload", false, "Mute the game's reload sound", "Silences the game's own reload sound on your client."),
	bool("gameaudio.muteKnife", false, "Mute the game's knife sounds", "Silences the game's own knife swing and stab sounds on your client."),
	{ key = "gameaudio.kwKill", type = "string", default = "kill,killed,death,eliminated", maxLen = 120, label = "Kill sound keywords", desc = "Comma-separated whole words of the names of the game's kill sounds (\"GunShot\" has the words gun and shot). Defaults are guesses: use Learn." },
	{ key = "gameaudio.kwShot", type = "string", default = "shoot,shot,fire,gunshot,bang", maxLen = 120, label = "Gun shot keywords", desc = "Whole words of the names of the gun shot sounds." },
	{ key = "gameaudio.kwReload", type = "string", default = "reload,reloading", maxLen = 120, label = "Reload keywords", desc = "Whole words of the names of the reload sounds." },
	{ key = "gameaudio.kwKnife", type = "string", default = "knife,slash,swing,stab", maxLen = 120, label = "Knife keywords", desc = "Whole words of the names of the knife sounds." },
	{ key = "gameaudio.kwWin", type = "string", default = "victory,winner,roundend,gameover", maxLen = 120, label = "Round-end keywords", desc = "Whole words of the names of the round-end sounds that start your song." },
	bool("gameaudio.songEnabled", false, "Play my song at round end", "When a round-end sound of the game is detected, your song plays instead. Needs a song source below.", { master = true }),
	{ key = "gameaudio.songSource", type = "string", default = "", maxLen = 120, label = "Round-end song source", desc = "asset:<id> or file:<name.mp3> (in MM2Hub/sounds/). Only audio you may use; the hub does not fetch music from any site." },
	num("gameaudio.songVolume", 0.8, 0, 1, 0.05, "Round-end song volume", "Volume of your round-end song."),
	bool("gameaudio.muteWin", true, "Mute the game's round-end sound while my song is on", "Silences the game's own round-end sound on your client when your song is switched on."),
}))

local conflicts = {
	{
		id = "lowprofile-vs-effects",
		keys = { "perf.lowProfile", "lighting.blurEnabled", "lighting.bloomEnabled" },
		check = function(get)
			if get("perf.lowProfile") and (get("lighting.blurEnabled") or get("lighting.bloomEnabled")) then
				return "Low load profile disables blur/bloom, so those switches have no visible effect."
			end
		end,
	},
	{
		id = "compact-vs-text",
		keys = { "ui.compact", "ui.textScale" },
		check = function(get)
			if get("ui.compact") and get("ui.textScale") > 1.25 then
				return "Compact mode with large text may clip labels."
			end
		end,
	},
	{
		id = "crosshair-dynamic-off",
		keys = { "crosshair.enabled", "crosshair.dynamic" },
		check = function(get)
			if not get("crosshair.enabled") and get("crosshair.dynamic") then
				return "Dynamic spread is on but the crosshair itself is off."
			end
		end,
	},
	{
		id = "zoom-range",
		keys = { "camera.minZoom", "camera.maxZoom", "camera.preferredZoom" },
		check = function(get)
			if get("camera.zoomEnabled") then
				local p = get("camera.preferredZoom")
				if p < get("camera.minZoom") or p > get("camera.maxZoom") then
					return "Preferred zoom lies outside the min/max zoom range and will be clamped."
				end
			end
		end,
	},
	{
		id = "firstperson-zoom",
		keys = { "camera.mode", "camera.zoomEnabled" },
		check = function(get)
			if get("camera.mode") == "FirstPerson" and get("camera.zoomEnabled") then
				return "First-person lock ignores zoom; custom zoom has no effect in this mode."
			end
		end,
	},
	{
		id = "effects-disabled",
		keys = { "camera.disableEffects", "camera.bobIntensity", "lighting.blurEnabled" },
		check = function(get)
			if get("camera.disableEffects") and (get("camera.bobIntensity") > 0 or get("lighting.blurEnabled")) then
				return "'Disable optional camera effects' overrides head bob and blur."
			end
		end,
	},
	{
		id = "time-vs-brightness",
		keys = { "lighting.timePreset", "lighting.brightnessEnabled" },
		check = function(get)
			if get("lighting.timePreset") ~= "Game" and get("lighting.brightnessEnabled") then
				return "Time-of-day preset and brightness override both change Lighting; the brightness value wins."
			end
		end,
	},
	{
		id = "autolow-threshold",
		keys = { "perf.autoLow", "perf.lowProfile" },
		check = function(get)
			if get("perf.autoLow") and get("perf.lowProfile") then
				return "Auto low profile is on but the low profile is already forced on."
			end
		end,
	},
}

return { settings = settings, conflicts = conflicts, themes = THEMES, soundSlots = SOUND_SLOTS }

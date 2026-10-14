--!nonstrict
-- ui/Theme: theme engine. Resolves colour tokens (theme + accent override), keeps a weak
-- registry of bound instance properties and re-applies them when appearance settings change.
-- Roblox datatypes are only created inside functions (never at load time).
-- Depends on: Settings, Themes, Signal.

local import = ...
local Settings = import("core/Settings")
local Themes = import("data/Themes")
local Signal = import("core/Signal")
local Perf = import("core/Perf")

local Theme = {}

Theme.Changed = Signal.new("Theme.Changed")

-- inst -> list of {prop, source, kind}; weak keys so destroyed instances drop out
local bindings = setmetatable({}, { __mode = "k" })
local count = 0

local function themeData()
	return Themes[Settings.get("ui.theme")] or Themes.iOS
end

function Theme.data()
	return themeData()
end

function Theme.names()
	local out = {}
	for name in pairs(Themes) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

-- rgb(token) -> {r,g,b}
function Theme.rgb(token)
	if token == "accent" and not Settings.get("ui.useThemeAccent") then
		return Settings.get("ui.accent")
	end
	local t = themeData()
	return t[token] or t.text
end

function Theme.color(token)
	local c = Theme.rgb(token)
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- mix(tokenA, tokenB, t) -> Color3
function Theme.mix(a, b, t)
	local ca, cb = Theme.rgb(a), Theme.rgb(b)
	return Color3.fromRGB(
		math.floor(ca.r + (cb.r - ca.r) * t + 0.5),
		math.floor(ca.g + (cb.g - ca.g) * t + 0.5),
		math.floor(ca.b + (cb.b - ca.b) * t + 0.5)
	)
end

-- accent text colour must stay readable when a custom accent is used
function Theme.accentText()
	if Settings.get("ui.useThemeAccent") then
		return Theme.color("accentText")
	end
	local a = Settings.get("ui.accent")
	local lum = (0.299 * a.r + 0.587 * a.g + 0.114 * a.b) / 255
	return lum > 0.6 and Color3.fromRGB(10, 10, 10) or Color3.fromRGB(255, 255, 255)
end

function Theme.switchToken()
	return themeData().switchToken or "accent"
end

function Theme.isGlass()
	return themeData().glass >= 0.08
end

-- Fonts ----------------------------------------------------------------------------

-- Gotham has no Cyrillic glyphs in Roblox: the engine borrows them from a fallback font, so Russian text looks uneven ("shifted"
-- letters, mixed weights). "Auto" therefore uses Montserrat (which has Cyrillic) for every language but English. The choice is a
-- setting because the result can only be judged in the real client.
local FONT_FAMILIES = {
	Gotham = { "GothamMedium", "GothamBold" },
	Montserrat = { "MontserratMedium", "MontserratBold" },
	BuilderSans = { "BuilderSansMedium", "BuilderSansBold" },
	Arial = { "Arial", "ArialBold" },
	SourceSans = { "SourceSansSemibold", "SourceSansBold" },
}
Theme.FONT_FAMILIES = FONT_FAMILIES

function Theme.fontFamily()
	local choice = Settings.get("ui.font")
	if FONT_FAMILIES[choice] then
		return choice
	end
	return Settings.get("ui.language") == "en" and "Theme" or "Montserrat"
end

function Theme.font(bold)
	local fam = FONT_FAMILIES[Theme.fontFamily()]
	if fam then
		return Enum.Font[bold and fam[2] or fam[1]]
	end
	local t = themeData()
	return Enum.Font[bold and t.fontBold or t.font]
end

-- Metrics --------------------------------------------------------------------------

local ROW = { Compact = 34, Normal = 42, Comfortable = 52 }

function Theme.rowHeight()
	local h = ROW[Settings.get("ui.density")] or 42
	if Settings.get("ui.compact") then
		h -= 6
	end
	return h
end

function Theme.pad()
	local d = Settings.get("ui.density")
	return d == "Compact" and 6 or (d == "Comfortable" and 12 or 9)
end

function Theme.textSize(base)
	return math.floor(base * Settings.get("ui.textScale") + 0.5)
end

function Theme.radius(extra)
	return math.max(0, Settings.get("ui.cornerRadius") + (themeData().radiusBoost or 0) + (extra or 0))
end

-- Design system -----------------------------------------------------------------------------------------------------
-- One place for the numbers every component uses: glass intensity, surface levels, radii, type scale, spacing.
-- "Glass" here is translucency + a thin light edge + a faint sheen; Roblox has no real background blur, so nothing
-- here claims to refract or blur what is behind the window.

-- glassAmount() -> 0..1. 0 = solid surfaces and no sheen (reduced effects, low load profile, or a theme without glass).
function Theme.glassAmount()
	if Settings.get("ui.reduceEffects") or Perf.isLow() or themeData().glass <= 0 then
		return 0
	end
	return Settings.get("ui.glass")
end

function Theme.effectsOn()
	return Theme.glassAmount() > 0
end

local LEVELS = {
	window = { token = "bg0", solid = 0.02, glass = 0.14 },
	rail = { token = "bg1", solid = 0.10, glass = 0.5 },
	card = { token = "bg2", solid = 0.06, glass = 0.45 },
	control = { token = "bg3", solid = 0.0, glass = 0.32 },
	popover = { token = "bg1", solid = 0.0, glass = 0.07 },
	modal = { token = "bg1", solid = 0.0, glass = 0.015 },
	toast = { token = "bg1", solid = 0.02, glass = 0.12 },
}

-- surface(level) -> colour token, background transparency
function Theme.surface(level)
	local def = LEVELS[level] or LEVELS.card
	local g = Theme.glassAmount()
	local t = def.solid + (def.glass - def.solid) * g
	if level == "window" then
		t += (1 - Settings.get("ui.opacity")) * 0.85
	end
	return def.token, math.clamp(t, 0, 1)
end

-- edge(level) -> top transparency, bottom transparency of the thin light edge (a stroke with a vertical gradient).
-- Big floating surfaces carry a clearer edge than the cards and controls that sit on them.
local EDGE_STRENGTH = { window = 1, popover = 0.9, modal = 0.9, toast = 0.9, card = 0.3, control = 0.3, rail = 0.3 }

function Theme.edge(level)
local g = Theme.glassAmount()
local k = EDGE_STRENGTH[level] or 0.5
return 0.74 + (0.5 - 0.74) * g * k, 0.74 + (0.92 - 0.74) * g
end

-- sheen() -> transparency of the faint highlight laid over the top of large surfaces (1 = invisible)
function Theme.sheen()
	return 1 + (0.93 - 1) * Theme.glassAmount()
end

local RADII = { window = 20, card = 14, control = 10, small = 7, none = 0 }

-- rad(name) -> pixels. "pill" is always fully round. The corner-radius setting scales the whole scale.
function Theme.rad(name)
	if name == "pill" then
		return 999
	end
	local base = RADII[name] or RADII.card
	local scale = Settings.get("ui.cornerRadius") / 8 * (themeData().shape or 1)
	return math.floor(base * scale + 0.5)
end

-- Type scale: size (px at 100 %), bold, colour token
local TYPE = {
	app = { 15, true, "text" },
	page = { 20, true, "text" },
	section = { 11.5, true, "textDim" },
	card = { 14, true, "text" },
	body = { 13, false, "text" },
	caption = { 11.5, false, "textDim" },
	value = { 12.5, true, "textDim" },
	micro = { 10, true, "textDim" },
}

function Theme.type(name)
	local t = TYPE[name] or TYPE.body
	return t[1], t[2], t[3]
end

Theme.space = { xs = 4, s = 8, m = 12, l = 16, xl = 24 }

-- Binding --------------------------------------------------------------------------------

local function apply(inst, b)
	local value
	if b.kind == "token" then
		value = Theme.color(b.source)
	elseif b.kind == "fn" then
		value = b.source()
	end
	local ok = pcall(function()
		inst[b.prop] = value
	end)
	return ok
end

-- bind(inst, prop, tokenOrFn): tokenOrFn is a colour token name or a function returning the value
function Theme.bind(inst, prop, source)
	local list = bindings[inst]
	if not list then
		list = {}
		bindings[inst] = list
	end
	local b = { prop = prop, source = source, kind = type(source) == "function" and "fn" or "token" }
	-- replace an earlier binding of the same property
	for i, old in ipairs(list) do
		if old.prop == prop then
			list[i] = b
			apply(inst, b)
			return inst
		end
	end
	table.insert(list, b)
	count += 1
	apply(inst, b)
	return inst
end

function Theme.unbind(inst)
	local list = bindings[inst]
	if list then
		count -= #list
		bindings[inst] = nil
	end
end

function Theme.bindingCount()
	local n = 0
	for _, list in pairs(bindings) do
		n += #list
	end
	return n
end

function Theme.refresh()
	for inst, list in pairs(bindings) do
		for _, b in ipairs(list) do
			apply(inst, b)
		end
	end
	Theme.Changed:Fire()
end

local watched = {
	"ui.theme", "ui.accent", "ui.useThemeAccent", "ui.textScale", "ui.density", "ui.cornerRadius", "ui.compact",
	"ui.glass", "ui.reduceEffects", "ui.opacity", "ui.font", "ui.language",
}

-- start(maid): observe appearance settings so bound properties follow them.
function Theme.start(maid)
	for _, key in ipairs(watched) do
		maid:Give(Settings.observe(key, function()
			Theme.refresh()
		end))
	end
	maid:Give(Perf.LowChanged:Connect(function()
		Theme.refresh()
	end))
end

return Theme

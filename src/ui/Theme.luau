--!nonstrict
-- ui/Theme: theme engine. Resolves colour tokens (theme + accent override), keeps a weak
-- registry of bound instance properties and re-applies them when appearance settings change.
-- Roblox datatypes are only created inside functions (never at load time).
-- Depends on: Settings, Themes, Signal.

local import = ...
local Settings = import("core/Settings")
local Themes = import("data/Themes")
local Signal = import("core/Signal")

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

function Theme.font(bold)
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
}

-- start(maid): observe appearance settings so bound properties follow them.
function Theme.start(maid)
	for _, key in ipairs(watched) do
		maid:Give(Settings.observe(key, function()
			Theme.refresh()
		end))
	end
end

return Theme

--!nonstrict
-- core/I18n: localisation. t(key, ...) falls back to English, then to the key itself.
-- Depends on: Signal, data/Strings.

local import = ...
local Signal = import("core/Signal")
local Strings = import("data/Strings")
local Texts = import("data/RuTexts")

local I18n = {}

I18n.Changed = Signal.new("I18n.Changed") -- (language)

local current = "en"
local missing = {}

function I18n.languages()
	local out = {}
	for lang in pairs(Strings) do
		table.insert(out, lang)
	end
	table.sort(out)
	return out
end

-- tr() result cache; declared before set() so a language change clears this table, not a global
local cache = {}
local cacheSize = 0

function I18n.set(lang)
	if not Strings[lang] then
		return false, "unknown language: " .. tostring(lang)
	end
	if current ~= lang then
		current = lang
		cache, cacheSize = {}, 0
		I18n.Changed:Fire(lang)
	end
	return true
end

function I18n.get()
	return current
end

function I18n.t(key, ...)
	local text = Strings[current][key]
	if text == nil then
		text = Strings.en[key]
		if text == nil then
			missing[key] = true
			text = key
		end
	end
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, text, ...)
		if ok then
			return res
		end
	end
	return text
end

-- Free-text translation ---------------------------------------------------------------------------------------
-- tr(text) translates a hard-coded English UI string. Exact matches come from data/RuTexts.exact, strings with
-- numbers or names inside from data/RuTexts.patterns ({luaPattern, format}). Text without a real English word
-- (numbers, symbols, key names) is returned as is; anything else that has no translation is recorded in
-- I18n.misses() so a test can prove coverage instead of guessing.

local trMisses = {}

local function needsTranslation(text)
	if string.find(text, "[\208\209]") then
		return false -- already Russian
	end
	if string.match(text, "^%a+:%S*$") then
		return false -- source specs such as asset:123 or file:song.mp3
	end
	return string.find(text, "%a%a%a") ~= nil
end

local function translate(text)
	local exact = Texts.exact[text]
	if exact then
		return exact
	end
	for _, rule in ipairs(Texts.patterns) do
		local captures = { string.match(text, rule[1]) }
		if #captures > 0 then
			-- captures that are themselves English words are translated recursively (e.g. enum values)
			for i, c in ipairs(captures) do
				if type(c) == "string" and Texts.exact[c] then
					captures[i] = Texts.exact[c]
				end
			end
			local ok, out = pcall(string.format, rule[2], table.unpack(captures))
			if ok then
				return out
			end
		end
	end
	return nil
end

function I18n.tr(text)
	if current == "en" or type(text) ~= "string" or text == "" then
		return text
	end
	local hit = cache[text]
	if hit then
		return hit
	end
	if not needsTranslation(text) or Texts.keep[text] then
		return text
	end
	local out = translate(text)
	if not out then
		trMisses[text] = true
		return text
	end
	if cacheSize > 3000 then
		cache, cacheSize = {}, 0
	end
	cache[text] = out
	cacheSize += 1
	return out
end

function I18n.misses()
	local out = {}
	for k in pairs(trMisses) do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

function I18n.clearMisses()
	trMisses = {}
end

-- upper(text): upper-case for Latin and Cyrillic (string.upper only knows ASCII).
function I18n.upper(text)
	text = string.upper(text)
	if not string.find(text, "[\208\209]") then
		return text
	end
	local ok, out = pcall(function()
		local parts = {}
		for _, cp in utf8.codes(text) do
			if cp >= 0x430 and cp <= 0x44F then
				cp -= 32
			elseif cp == 0x451 then
				cp = 0x401
			end
			table.insert(parts, utf8.char(cp))
		end
		return table.concat(parts)
	end)
	return ok and out or text
end

-- cut(text, n): at most n characters, never splitting a multi-byte character.
function I18n.cut(text, n)
	if utf8.len(text) and utf8.len(text) > n then
		return string.sub(text, 1, utf8.offset(text, n + 1) - 1)
	end
	return text
end

-- featureName(feature): the catalogue name in the active language.
function I18n.featureName(feature)
	if current == "ru" and feature.ru and feature.ru ~= "" then
		return feature.ru
	end
	return feature.name
end

function I18n.missing()
	local out = {}
	for k in pairs(missing) do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- untranslated(lang) -> keys present in English but absent in `lang`.
function I18n.untranslated(lang)
	local out = {}
	for k in pairs(Strings.en) do
		if Strings[lang] and Strings[lang][k] == nil then
			table.insert(out, k)
		end
	end
	table.sort(out)
	return out
end

return I18n

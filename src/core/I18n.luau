--!nonstrict
-- core/I18n: localisation. t(key, ...) falls back to English, then to the key itself.
-- Depends on: Signal, data/Strings.

local import = ...
local Signal = import("core/Signal")
local Strings = import("data/Strings")
-- every language except English: texts for I18n.tr plus (for generated languages) the keyed strings
local LANGS = {
	ru = import("data/RuTexts"),
	uk = import("data/Texts_uk"),
	es = import("data/Texts_es"),
	pt = import("data/Texts_pt"),
	fr = import("data/Texts_fr"),
}
local Texts = LANGS.ru

local I18n = {}

I18n.Changed = Signal.new("I18n.Changed") -- (language)

local current = "en"
local missing = {}

-- language codes in menu order and their names in their own language
I18n.ORDER = { "ru", "en", "uk", "es", "pt", "fr" }
I18n.NAMES = { ru = "Русский", en = "English", uk = "Українська", es = "Español", pt = "Português", fr = "Français", de = "Deutsch" }

local function keyed(lang)
	return Strings[lang] or (LANGS[lang] and LANGS[lang].strings)
end

function I18n.languages()
	local out = {}
	for _, lang in ipairs(I18n.ORDER) do
		if lang == "en" or keyed(lang) then
			table.insert(out, lang)
		end
	end
	return out
end

-- tr() result cache; declared before set() so a language change clears this table, not a global
local cache = {}
local cacheSize = 0

function I18n.set(lang)
	if not keyed(lang) then
		return false, "unknown language: " .. tostring(lang)
	end
	if current ~= lang then
		current = lang
		Texts = LANGS[lang] or LANGS.ru
		cache, cacheSize = {}, 0
		I18n.Changed:Fire(lang)
	end
	return true
end

function I18n.get()
	return current
end

function I18n.t(key, ...)
	local text = keyed(current)[key]
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

-- texts that are already in the current language (a translated text passed through tr() again, e.g. an upper-cased section
-- title): returned as they are. Cyrillic is recognised by its letters; Latin languages need this set.
local known, knownLang = {}, nil
local function isKnown(text)
	if knownLang ~= current then
		known, knownLang = {}, current
		for _, v in pairs(Texts.exact) do
			known[v] = true
			known[I18n.upper(v)] = true
		end
		local keyedStrings = keyed(current)
		for _, v in pairs(keyedStrings or {}) do
			known[v] = true
			known[I18n.upper(v)] = true
		end
	end
	return known[text] == true
end

-- remember(text): marks a text composed from translated parts as already translated
function I18n.remember(text)
	isKnown("")
	known[text] = true
	return text
end

function I18n.tr(text)
	if current == "en" or type(text) ~= "string" or text == "" then
		return text
	end
	local hit = cache[text]
	if hit then
		return hit
	end
	if isKnown(text) then
		return text
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
	-- a pattern result passed through tr() again (labels are re-translated on refresh) is already in this language
	known[out] = true
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

-- upper(text): upper-case for Latin (with accents), Cyrillic and Ukrainian letters (string.upper only knows ASCII).
function I18n.upper(text)
	text = string.upper(text)
	if not string.find(text, "[\195\208\209\210]") then
		return text
	end
	local ok, out = pcall(function()
		local parts = {}
		for _, cp in utf8.codes(text) do
			if cp >= 0x430 and cp <= 0x44F then
				cp -= 32
			elseif cp >= 0x450 and cp <= 0x45F then
				cp -= 80 -- ё є і ї ...
			elseif cp == 0x491 then
				cp = 0x490 -- ґ
			elseif cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then
				cp -= 32 -- á é ñ ç ü ...
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
		local out = string.sub(text, 1, utf8.offset(text, n + 1) - 1)
		if current ~= "en" then
			I18n.remember(out) -- a shortened translation is still a translation
		end
		return out
	end
	return text
end

-- featureName(feature): the catalogue name in the active language.
function I18n.featureName(feature)
	if current == "ru" and feature.ru and feature.ru ~= "" then
		return feature.ru
	end
	return I18n.tr(feature.name)
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
		if keyed(lang) and keyed(lang)[k] == nil then
			table.insert(out, k)
		end
	end
	table.sort(out)
	return out
end

return I18n

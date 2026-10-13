--!nonstrict
-- core/I18n: localisation. t(key, ...) falls back to English, then to the key itself.
-- Depends on: Signal, data/Strings.

local import = ...
local Signal = import("core/Signal")
local Strings = import("data/Strings")

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

function I18n.set(lang)
	if not Strings[lang] then
		return false, "unknown language: " .. tostring(lang)
	end
	if current ~= lang then
		current = lang
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

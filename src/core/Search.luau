--!nonstrict
-- core/Search: ranked search over features, un-catalogued settings and actions.
-- All query terms must match somewhere (AND); names weigh more than descriptions.
-- Depends on: Registry, Settings, Actions, Recents.

local import = ...
local Registry = import("core/Registry")
local Settings = import("core/Settings")
local Actions = import("core/Actions")
local Recents = import("core/Recents")

local Search = {}

-- UTF-8 aware lowercase: ASCII plus Cyrillic (U+0410-042F, U+0401), which string.lower ignores.
local function lower(s)
	s = string.lower(s or "")
	if not string.find(s, "[\208\209]") then
		return s
	end
	local ok, out = pcall(function()
		local parts = {}
		for _, cp in utf8.codes(s) do
			if cp >= 0x410 and cp <= 0x42F then
				cp += 32
			elseif cp == 0x401 then
				cp = 0x451
			end
			table.insert(parts, utf8.char(cp))
		end
		return table.concat(parts)
	end)
	return ok and out or s
end

-- buildIndex() -> items. Items: {id, kind, title, ru, desc, category, keywords, settingKey?}
function Search.buildIndex()
	local items = {}
	local covered = {}
	for _, e in ipairs(Registry.all()) do
		local item = {
			id = e.id,
			kind = "feature",
			title = e.name,
			ru = e.ru,
			desc = e.desc,
			category = e.cat,
			categoryName = Registry.CATEGORIES[e.cat],
		}
		if e.impl.kind == "setting" then
			item.settingKey = e.impl.target
			covered[e.impl.target] = true
			local def = Settings.schema(e.impl.target)
			if def then
				item.page = def.category
			end
		end
		table.insert(items, item)
	end
	for _, key in ipairs(Settings.keys()) do
		if not covered[key] then
			local def = Settings.schema(key)
			table.insert(items, {
				id = "setting:" .. key,
				kind = "setting",
				title = def.label,
				ru = "",
				desc = def.desc,
				category = def.category,
				categoryName = def.category,
				settingKey = key,
				page = def.category,
			})
		end
	end
	return items
end

local function isActive(item)
	if not item.settingKey or not Settings.has(item.settingKey) then
		return false
	end
	local def = Settings.schema(item.settingKey)
	local v = Settings.get(item.settingKey)
	if def.type == "bool" then
		return v == true
	end
	return not Settings.isDefault(item.settingKey)
end

Search.isActive = isActive

local function score(item, query, tokens)
	local name, ru, desc = lower(item.title), lower(item.ru), lower(item.desc)
	local cat = lower(item.categoryName)
	local total = 0
	if name == query then
		total += 120
	elseif string.sub(name, 1, #query) == query then
		total += 80
	elseif string.find(name, query, 1, true) then
		total += 50
	end
	for _, tok in ipairs(tokens) do
		local hit = 0
		if string.find(" " .. name, " " .. tok, 1, true) then
			hit = 20
		elseif string.find(name, tok, 1, true) then
			hit = 12
		elseif string.find(ru, tok, 1, true) then
			hit = 12
		elseif string.find(cat, tok, 1, true) then
			hit = 5
		elseif string.find(desc, tok, 1, true) then
			hit = 6
		elseif item.settingKey and string.find(lower(item.settingKey), tok, 1, true) then
			hit = 4
		end
		if hit == 0 then
			return 0
		end
		total += hit
	end
	return total
end

local indexCache

function Search.invalidate()
	indexCache = nil
end

-- query(text, opts{category, onlyActive, onlyFavorites, limit}) -> results (sorted)
function Search.query(text, opts)
	opts = opts or {}
	if not indexCache then
		indexCache = Search.buildIndex()
	end
	local q = lower(string.match(text or "", "^%s*(.-)%s*$"))
	local tokens = {}
	for tok in string.gmatch(q, "%S+") do
		table.insert(tokens, tok)
	end
	local favs = opts.onlyFavorites and Recents.favorites() or nil
	local results = {}
	for _, item in ipairs(indexCache) do
		if
			(not opts.category or item.category == opts.category)
			and (not opts.onlyActive or isActive(item))
			and (not favs or table.find(favs, item.id))
		then
			local s = #tokens == 0 and 1 or score(item, q, tokens)
			if s > 0 then
				table.insert(results, { item = item, score = s })
			end
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.item.title < b.item.title
	end)
	local out = {}
	for i, r in ipairs(results) do
		if opts.limit and i > opts.limit then
			break
		end
		out[i] = r.item
	end
	return out
end

-- commands(text, limit?) -> actions whose id/name/keywords match all tokens (text without leading '>').
function Search.commands(text, limit)
	local q = lower(string.match(text or "", "^%s*(.-)%s*$"))
	local tokens = {}
	for tok in string.gmatch(q, "%S+") do
		table.insert(tokens, tok)
	end
	local out = {}
	for _, a in ipairs(Actions.list()) do
		local hay = lower(a.id .. " " .. a.name .. " " .. a.desc .. " " .. table.concat(a.keywords, " "))
		local ok = true
		for _, tok in ipairs(tokens) do
			if not string.find(hay, tok, 1, true) then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, a)
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	if limit and #out > limit then
		for i = #out, limit + 1, -1 do
			out[i] = nil
		end
	end
	return out
end

return Search

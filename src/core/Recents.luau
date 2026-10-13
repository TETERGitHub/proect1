--!nonstrict
-- core/Recents: favourites and recently used feature ids, persisted via Settings (state scope).
-- Depends on: Settings.

local import = ...
local Settings = import("core/Settings")

local Recents = {}

local RECENT_KEY = "state.recent"
local FAV_KEY = "state.favorites"

local function copy(list)
	return table.clone(list)
end

-- touch(id): move id to the front of the recent list.
function Recents.touch(id)
	if type(id) ~= "string" or id == "" then
		return false
	end
	local list = copy(Settings.get(RECENT_KEY))
	local i = table.find(list, id)
	if i then
		table.remove(list, i)
	end
	table.insert(list, 1, id)
	local max = Settings.schema(RECENT_KEY).maxItems
	while #list > max do
		table.remove(list)
	end
	return (Settings.set(RECENT_KEY, list, "recent"))
end

function Recents.recent()
	return copy(Settings.get(RECENT_KEY))
end

function Recents.isFavorite(id)
	return table.find(Settings.get(FAV_KEY), id) ~= nil
end

-- toggleFavorite(id) -> ok, isNowFavorite|err
function Recents.toggleFavorite(id)
	if type(id) ~= "string" or id == "" then
		return false, "bad id"
	end
	local list = copy(Settings.get(FAV_KEY))
	local i = table.find(list, id)
	if i then
		table.remove(list, i)
		Settings.set(FAV_KEY, list, "favorite")
		return true, false
	end
	if #list >= Settings.schema(FAV_KEY).maxItems then
		return false, "favourite limit reached"
	end
	table.insert(list, id)
	Settings.set(FAV_KEY, list, "favorite")
	return true, true
end

function Recents.favorites()
	return copy(Settings.get(FAV_KEY))
end

function Recents.clearRecent()
	return (Settings.set(RECENT_KEY, {}, "recent"))
end

return Recents

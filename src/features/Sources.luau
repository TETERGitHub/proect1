--!nonstrict
-- features/Sources: parsing and validation of user-supplied content references used by
-- Cosmetics, Music and Sounds:   proc:<name> | asset:<numeric id> | file:<name.ext>
-- The hub never downloads from third-party sites; assets come from IDs the user
-- supplies (which must be loadable by their client) or files in MM2Hub/.

local Sources = {}

local EXT = {
	model = { rbxm = true, rbxmx = true },
	audio = { mp3 = true, ogg = true, wav = true },
}

-- parse(text, kind) -> {type, ref}|nil, err. kind: "model" | "audio"
function Sources.parse(text, kind)
	if type(text) ~= "string" then
		return nil, "source must be text"
	end
	local t = string.match(text, "^%s*(.-)%s*$")
	if t == "" then
		return nil, "empty source"
	end
	local direct = string.match(t, "^rbxassetid://(%d+)$")
	if direct then
		if #direct > 20 then
			return nil, "asset id must be a number"
		end
		return { type = "asset", ref = direct }
	end
	local scheme, ref = string.match(t, "^(%a+):(.+)$")
	if not scheme then
		-- bare number = asset id
		if string.match(t, "^%d+$") then
			scheme, ref = "asset", t
		else
			return nil, "use proc:<name>, asset:<id> or file:<name>"
		end
	end
	scheme = string.lower(scheme)
	if scheme == "asset" then
		local id = string.match(ref, "^%s*(%d+)%s*$") or string.match(ref, "rbxassetid://(%d+)")
		if not id or #id > 20 then
			return nil, "asset id must be a number"
		end
		return { type = "asset", ref = id }
	elseif scheme == "file" then
		local name = string.match(ref, "^%s*(.-)%s*$")
		if string.find(name, "..", 1, true) or string.find(name, "[/\\]") or not string.match(name, "^[%w _%-%.%(%)]+$") then
			return nil, "file name may not contain paths or odd characters"
		end
		local ext = string.lower(string.match(name, "%.(%w+)$") or "")
		if kind and EXT[kind] and not EXT[kind][ext] then
			return nil, "unsupported file type '." .. ext .. "' for " .. kind
		end
		return { type = "file", ref = name }
	elseif scheme == "proc" then
		if not string.match(ref, "^[%w_]+$") then
			return nil, "bad procedural model name"
		end
		if kind == "audio" then
			return nil, "procedural sources are for models only"
		end
		return { type = "proc", ref = ref }
	end
	return nil, "unknown source type '" .. scheme .. "'"
end

-- Playlist entries: "<source>|<title>"
function Sources.parseEntry(entry)
	local src, title = string.match(entry, "^(.-)|(.*)$")
	if not src then
		src, title = entry, ""
	end
	local parsed, err = Sources.parse(src, "audio")
	if not parsed then
		return nil, err
	end
	if parsed.type == "proc" then
		return nil, "procedural source not allowed for audio"
	end
	if title == "" then
		title = parsed.type == "file" and parsed.ref or ("Track " .. parsed.ref)
	end
	return { source = parsed, title = string.sub(title, 1, 60), raw = entry }
end

function Sources.makeEntry(sourceText, title)
	local parsed, err = Sources.parse(sourceText, "audio")
	if not parsed or parsed.type == "proc" then
		return nil, err or "procedural source not allowed for audio"
	end
	local clean = string.gsub(title or "", "[|\n\r]", " ")
	return string.format("%s:%s|%s", parsed.type, parsed.ref, string.sub(clean, 1, 60))
end

return Sources

--!nonstrict
-- features/Music: local music player. Plays tracks YOU supply (asset ids you can use, or audio
-- files placed in MM2Hub/music/). Playback is local-only, so it also works in the lobby; other
-- players do not hear it. The hub does not search for or download songs from any site.
-- STATUS: env-dependent (file playback needs getcustomasset; private/unlicensed asset ids will not load).
-- Depends on: Settings, Sources, Playlist, Sounds(resolver), Services, Perf, Signal, Notify, Logger.

local import = ...
local Settings = import("core/Settings")
local Sources = import("features/Sources")
local Playlist = import("features/Playlist")
local Sounds = import("features/Sounds")
local Services = import("core/Services")
local Signal = import("core/Signal")
local Notify = import("core/Notify")
local Logger = import("core/Logger")

local Music = {}

Music.Changed = Signal.new("Music.Changed") -- (reason)

local MAX_TRACKS = 40
local LOAD_TIMEOUT = 8

local state = nil

local function entries()
	local out = {}
	for i, raw in ipairs(Settings.get("music.playlist")) do
		local e = Sources.parseEntry(raw)
		out[i] = e or { title = "(invalid entry)", raw = raw, invalid = true }
	end
	return out
end

function Music.tracks()
	return entries()
end

-- Playlist editing ---------------------------------------------------------------------------------------------------

function Music.add(sourceText, title)
	local list = table.clone(Settings.get("music.playlist"))
	if #list >= MAX_TRACKS then
		return false, "playlist is full (" .. MAX_TRACKS .. ")"
	end
	local entry, err = Sources.makeEntry(sourceText, title)
	if not entry then
		return false, err
	end
	local source = string.match(entry, "^(.-)|")
	for _, existing in ipairs(list) do
		if string.match(existing, "^(.-)|") == source then
			return false, "that track is already in the playlist"
		end
	end
	table.insert(list, entry)
	local ok, serr = Settings.set("music.playlist", list, "music")
	if not ok then
		return false, serr
	end
	if state then
		state.list:setSize(#list, true)
	end
	Music.Changed:Fire("playlist")
	return true
end

function Music.remove(index)
	local list = table.clone(Settings.get("music.playlist"))
	if index < 1 or index > #list then
		return false, "no such track"
	end
	table.remove(list, index)
	Settings.set("music.playlist", list, "music")
	if state then
		if state.current == index then
			Music.stop()
		elseif state.current and state.current > index then
			state.current -= 1
		end
		state.list:setSize(#list, true)
	end
	Music.Changed:Fire("playlist")
	return true
end

function Music.move(index, delta)
	local list = table.clone(Settings.get("music.playlist"))
	local target = index + delta
	if index < 1 or index > #list or target < 1 or target > #list then
		return false
	end
	list[index], list[target] = list[target], list[index]
	Settings.set("music.playlist", list, "music")
	if state and state.current == index then
		state.current = target
	elseif state and state.current == target then
		state.current = index
	end
	Music.Changed:Fire("playlist")
	return true
end

function Music.clearPlaylist()
	Music.stop()
	Settings.set("music.playlist", {}, "music")
	if state then
		state.list:setSize(0)
	end
	Music.Changed:Fire("playlist")
end

-- Playback ---------------------------------------------------------------------------------------------------------------

local function resolve(entry)
	if entry.invalid then
		return nil, "invalid playlist entry"
	end
	return Sounds.resolveParsed(entry.source, "music")
end

local function fail(index, reason)
	local e = entries()[index]
	local name = e and e.title or "track"
	Logger.warn("Music", "%s: %s", name, tostring(reason))
	Notify.push({ title = "Music", text = name .. ": " .. tostring(reason), level = "warn" })
end

-- playIndex(i): start track i (1-based). Returns ok, err.
function Music.playIndex(i)
	if not state then
		return false, "music module is not running"
	end
	local all = entries()
	local entry = all[i]
	if not entry then
		return false, "no such track"
	end
	local id, err = resolve(entry)
	if not id then
		fail(i, err)
		return false, err
	end
	state.token += 1
	local mine = state.token
	local snd = state.sound
	snd:Stop()
	snd.SoundId = id
	snd.TimePosition = 0
	snd.Volume = Settings.get("music.volume")
	snd.PlaybackSpeed = Settings.get("music.speed")
	snd.Looped = Settings.get("music.loop") == "One"
	state.current = i
	state.list:jump(i)
	Settings.set("music.index", i, "music")
	state.loading = true
	snd:Play()
	Music.Changed:Fire("track")
	-- watchdog: tracks that never load (bad id, no access) are skipped with a message
	task.delay(LOAD_TIMEOUT, function()
		if state and state.token == mine and state.loading and not snd.IsLoaded then
			state.loading = false
			snd:Stop()
			fail(i, "failed to load (id not accessible or file missing)")
			Music.Changed:Fire("error")
		end
	end)
	return true
end

function Music.play()
	if not state then
		return false
	end
	local snd = state.sound
	if state.current and not snd.IsPlaying and snd.SoundId ~= "" then
		snd:Resume()
		Music.Changed:Fire("state")
		return true
	end
	local start = state.list:current() or Settings.get("music.index")
	local total = #Settings.get("music.playlist")
	if total == 0 then
		return false, "playlist is empty"
	end
	return Music.playIndex(math.clamp(start, 1, total))
end

function Music.pause()
	if state and state.sound.IsPlaying then
		state.sound:Pause()
		Music.Changed:Fire("state")
	end
end

function Music.toggle()
	if state and state.sound.IsPlaying then
		Music.pause()
		return false
	end
	return Music.play()
end

function Music.stop()
	if state then
		state.token += 1
		state.sound:Stop()
		state.current = nil
		state.loading = false
		Music.Changed:Fire("state")
	end
end

function Music.next()
	if not state then
		return false
	end
	local n = state.list:advance("next")
	if n then
		return Music.playIndex(n)
	end
	return false
end

function Music.previous()
	if not state then
		return false
	end
	local n = state.list:previous()
	if n then
		return Music.playIndex(n)
	end
	return false
end

function Music.seek(fraction)
	if not state or not state.current then
		return false
	end
	local len = state.sound.TimeLength
	if len and len > 0 then
		state.sound.TimePosition = math.clamp(fraction, 0, 1) * len
		return true
	end
	return false
end

-- nowPlaying() -> table for the UI
function Music.nowPlaying()
	if not state then
		return nil
	end
	local snd = state.sound
	local entry = state.current and entries()[state.current]
	return {
		index = state.current,
		title = entry and entry.title or nil,
		playing = snd.IsPlaying == true,
		loading = state.loading and not snd.IsLoaded,
		position = snd.TimePosition or 0,
		length = snd.TimeLength or 0,
	}
end

local function onEnded()
	if not state or not state.current then
		return
	end
	local n = state.list:advance("ended")
	if n then
		Music.playIndex(n)
	else
		state.current = nil
		Music.Changed:Fire("state")
	end
end

function Music.start(ctx)
	assert(state == nil, "Music already started")
	local snd = Instance.new("Sound")
	snd.Name = "MM2HubMusic"
	snd.Volume = Settings.get("music.volume")
	snd.Parent = Services.SoundService
	ctx.maid:Give(snd)
	state = { sound = snd, list = Playlist.new(), current = nil, token = 0, loading = false }
	state.list.loop = Settings.get("music.loop")
	state.list.shuffle = Settings.get("music.shuffle")
	state.list:setSize(#Settings.get("music.playlist"))
	ctx.maid:Give(function()
		if state then
			state.sound:Stop()
		end
		state = nil
	end)
	ctx.maid:Give(snd.Ended:Connect(onEnded))
	ctx.maid:Give(snd.Loaded:Connect(function()
		if state then
			state.loading = false
			Music.Changed:Fire("loaded")
		end
	end))
	ctx.maid:Give(Settings.observe("music.volume", function(v)
		snd.Volume = v
	end))
	ctx.maid:Give(Settings.observe("music.speed", function(v)
		snd.PlaybackSpeed = v
	end))
	ctx.maid:Give(Settings.observe("music.loop", function(v)
		state.list.loop = v
		snd.Looped = v == "One"
	end))
	ctx.maid:Give(Settings.observe("music.shuffle", function(v)
		state.list:setShuffle(v)
	end))
	if Settings.get("music.autoplay") and #Settings.get("music.playlist") > 0 then
		task.defer(function()
			if state then
				Music.play()
			end
		end)
	end
end

function Music.isRunning()
	return state ~= nil
end

return Music

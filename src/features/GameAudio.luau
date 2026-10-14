--!nonstrict
-- features/GameAudio: local control of the game's OWN sounds on YOUR client.
--   mute lists   kill / gun shot / reload / knife sounds can be silenced (Volume = 0; the original volume is restored when the
--                option is switched off, the keywords change or the hub unloads). Nothing is sent to the server or other players.
--   kill sounds  while a custom Murderer/Sheriff kill sound is applied and switched on, the game's own kill sounds are silenced.
--   round song   when a round-end sound of the game starts, your own song plays (and the game's sound is silenced).
--   learn        listens for a few seconds and lists every sound that started playing (name, path, id) so the real names can be
--                added to the keyword lists, instead of trusting guesses.
-- Which sounds belong to which category is decided by KEYWORDS in the sound's name or path. The defaults are guesses about the
-- game; they are not verified. Our own sounds (names starting with "MM2Hub_") are never touched.
-- Depends on: Settings, Sources, Sounds, Services, Env, Logger, Signal.

local import = ...
local Settings = import("core/Settings")
local Sources = import("features/Sources")
local Sounds = import("features/Sounds")
local Services = import("core/Services")
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local GA = {}

GA.CATEGORIES = { "win", "kill", "reload", "shot", "knife" } -- checked in this order
GA.Learned = Signal.new("GameAudio.Learned")
local KW_KEY = { kill = "gameaudio.kwKill", shot = "gameaudio.kwShot", reload = "gameaudio.kwReload", knife = "gameaudio.kwKnife", win = "gameaudio.kwWin" }
local SONG_GAP_S = 15

local state = nil

-- keywords(cat) -> list of lowercase words
function GA.keywords(cat)
	local out = {}
	for w in string.gmatch(string.lower(Settings.get(KW_KEY[cat]) or ""), "[^,]+") do
		w = string.match(w, "^%s*(.-)%s*$")
		if w ~= "" then
			table.insert(out, w)
		end
	end
	return out
end

local function pathOf(inst)
	local parts, cur = {}, inst
	for _ = 1, 5 do
		if not cur then
			break
		end
		table.insert(parts, 1, tostring(cur.Name))
		cur = cur.Parent
	end
	return table.concat(parts, "/")
end

-- tokens(name) -> lowercase words of a sound name: "GunShotSound_2" -> { gun, shot, sound, 2 }
function GA.tokens(name)
	local spaced = string.gsub(tostring(name), "(%l)(%u)", "%1 %2")
	spaced = string.gsub(spaced, "(%u)(%u%l)", "%1 %2")
	spaced = string.gsub(spaced, "(%a)(%d)", "%1 %2")
	local out = {}
	for w in string.gmatch(string.lower(spaced), "[%w]+") do
		table.insert(out, w)
	end
	return out
end

-- categoryOf(name) -> the first category with a keyword that is a whole WORD of the sound's name, or the whole name itself
-- (what Learn adds). Only the sound's own name counts: parents are not looked at, so a player called "Firebird" or "Killua"
-- cannot drag their footsteps into a category, and "Swing" never matches "win". (`path` is accepted for older callers and ignored.)
function GA.categoryOf(name, path, keywordsFn)
	keywordsFn = keywordsFn or GA.keywords
	local whole = string.lower(tostring(name))
	local words = {}
	for _, w in ipairs(GA.tokens(name)) do
		words[w] = true
	end
	for _, cat in ipairs(GA.CATEGORIES) do
		for _, w in ipairs(keywordsFn(cat)) do
			if words[w] or w == whole then
				return cat
			end
		end
	end
	return nil
end

local function customKillActive()
	for _, role in ipairs({ "murderer", "sheriff" }) do
		if Settings.get("ksound." .. role .. "Enabled") and Settings.get("ksound." .. role .. "Source") ~= "" then
			return true
		end
	end
	return false
end

-- wanted(cat) -> true when sounds of this category should be silenced right now
function GA.wanted(cat)
	if cat == "kill" then
		return Settings.get("gameaudio.muteKill") and customKillActive()
	elseif cat == "shot" then
		return Settings.get("gameaudio.muteShot")
	elseif cat == "reload" then
		return Settings.get("gameaudio.muteReload")
	elseif cat == "knife" then
		return Settings.get("gameaudio.muteKnife")
	elseif cat == "win" then
		return Settings.get("gameaudio.muteWin") and Settings.get("gameaudio.songEnabled") and Settings.get("gameaudio.songSource") ~= ""
	end
	return false
end

-- Muting ---------------------------------------------------------------------------------------------------------------------

local function unmute(sound)
	local m = state.muted[sound]
	if m then
		state.muted[sound] = nil
		state.busy = true
		pcall(function()
			sound.Volume = m.vol
		end)
		state.busy = false
	end
end

local function mute(sound)
	if state.muted[sound] then
		return
	end
	state.muted[sound] = { vol = sound.Volume }
	state.busy = true
	pcall(function()
		sound.Volume = 0
	end)
	state.busy = false
	state.mutedCount += 1
end

local function forget(sound)
	local h = state.hooked[sound]
	if h then
		for _, c in ipairs(h.conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		state.hooked[sound] = nil
	end
	state.muted[sound] = nil
end

local function apply(sound, cat)
	if GA.wanted(cat) then
		mute(sound)
	else
		unmute(sound)
	end
end

local function triggerWin()
	if not Settings.get("gameaudio.songEnabled") then
		return
	end
	local now = os.clock()
	if state.lastSong and now - state.lastSong < SONG_GAP_S then
		return
	end
	if GA.songPlay() then
		state.lastSong = now -- a failed attempt (no source yet, unreadable file) must not use up the once-per-round gap
	end
end

local function hook(sound)
	if state.hooked[sound] or not sound:IsA("Sound") or string.sub(sound.Name, 1, 6) == "MM2Hub" then
		return
	end
	local cat = GA.categoryOf(sound.Name, pathOf(sound))
	if not cat then
		return
	end
	local entry = { cat = cat, conns = {} }
	state.hooked[sound] = entry
	local function onPlayed()
		if not state then
			return
		end
		apply(sound, cat)
		if cat == "win" then
			triggerWin()
		end
	end
	table.insert(entry.conns, sound.Played:Connect(onPlayed))
	table.insert(entry.conns, sound.Destroying:Connect(function()
		if state then
			forget(sound)
		end
	end))
	-- the game may set the volume again before playing: keep a muted sound muted
	table.insert(entry.conns, sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if state and not state.busy and state.muted[sound] and sound.Volume ~= 0 then
			state.muted[sound].vol = sound.Volume
			state.busy = true
			sound.Volume = 0
			state.busy = false
		end
	end))
	apply(sound, cat)
	if cat == "win" and sound.IsPlaying then
		triggerWin()
	end
end

local function scopeRoots(withWorld)
	local lp = Services.Players.LocalPlayer
	local roots = { Services.SoundService, lp, lp.Character }
	if withWorld then
		table.insert(roots, Services.Workspace)
	end
	return roots
end

-- rescan(): forget everything and re-apply the current settings to the sounds that exist now (the world included: sounds that
-- were there before the hub started, or before a keyword changed, must be found again)
function GA.rescan()
	if not state then
		return
	end
	for sound in pairs(table.clone(state.hooked)) do
		unmute(sound)
		forget(sound)
	end
	for _, root in ipairs(scopeRoots(true)) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				hook(d)
			end
		end
	end
end

function GA.mutedCount()
	local n = 0
	if state then
		for _ in pairs(state.muted) do
			n += 1
		end
	end
	return n
end

-- Round-end song -------------------------------------------------------------------------------------------------------------

function GA.songStop()
	if state and state.song then
		local s = state.song
		state.song = nil
		pcall(function()
			s:Stop()
			s:Destroy()
		end)
	end
end

-- songPlay() -> true | false, err. Plays the configured song (also used by the page's test button).
function GA.songPlay()
	local source = Settings.get("gameaudio.songSource")
	if source == "" then
		return false, "no song source set"
	end
	local parsed, err = Sources.parse(source, "audio")
	if not parsed or parsed.type == "proc" then
		return false, err or "use asset:<id> or file:<name>"
	end
	local id, rerr = Sounds.resolveParsed(parsed, "sounds")
	if not id then
		Logger.warn("GameAudio", "round song: %s", tostring(rerr))
		return false, rerr
	end
	GA.songStop()
	local ok, snd = pcall(function()
		local s = Instance.new("Sound")
		s.Name = "MM2Hub_RoundSong"
		s.SoundId = id
		s.Volume = Settings.get("gameaudio.songVolume")
		s.Parent = Services.SoundService
		s.Ended:Once(function()
			if state and state.song == s then
				state.song = nil
			end
			s:Destroy()
		end)
		s:Play()
		return s
	end)
	if not ok then
		return false, tostring(snd)
	end
	if state then
		state.song = snd
	end
	return true
end

function GA.songPlaying()
	return state ~= nil and state.song ~= nil
end

-- Learn mode -----------------------------------------------------------------------------------------------------------------

-- learn(seconds, cb): listens for sounds that start playing; cb(list) gets { name, path, soundId, count } sorted by count.
-- Only one session at a time. Listens to sounds that exist now and to every sound added to your character, GUI, the sound service and the world.
function GA.learn(seconds, cb)
	if not state then
		return false, "the module is not running"
	end
	if state.learning then
		return false, "already listening"
	end
	seconds = math.clamp(tonumber(seconds) or 8, 2, 30)
	local seen, conns = {}, {}
	local function note(sound)
		if string.sub(sound.Name, 1, 6) == "MM2Hub" then
			return
		end
		local key = sound.Name .. "|" .. tostring(sound.SoundId)
		local e = seen[key]
		if not e then
			e = { name = sound.Name, path = pathOf(sound), soundId = tostring(sound.SoundId), count = 0 }
			seen[key] = e
		end
		e.count += 1
	end
	local hooked = setmetatable({}, { __mode = "k" })
	local function listen(d)
		if d:IsA("Sound") and not hooked[d] then
			hooked[d] = true
			table.insert(conns, d.Played:Connect(function()
				note(d)
			end))
			-- a sound created already playing (PlayOnRemove or Playing = true) never fires Played
			if d.IsPlaying then
				note(d)
			end
		end
	end
	local roots = scopeRoots()
	table.insert(roots, Services.Workspace)
	for _, root in ipairs(roots) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				listen(d)
			end
			table.insert(conns, root.DescendantAdded:Connect(listen))
		end
	end
	state.learning = true
	task.delay(seconds, function()
		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		local list = {}
		for _, e in pairs(seen) do
			table.insert(list, e)
		end
		table.sort(list, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.name < b.name
		end)
		if state then
			state.learning = false
		end
		GA.Learned:Fire(list)
		if cb then
			cb(list)
		end
	end)
	return true
end

function GA.isLearning()
	return state ~= nil and state.learning == true
end

-- addKeyword(cat, word) -> true | false, err: appends a word to a category's keyword list (no duplicates, 120 characters in total)
function GA.addKeyword(cat, word)
	if not KW_KEY[cat] then
		return false, "unknown category"
	end
	word = string.lower(tostring(word or ""))
	word = string.match(word, "^%s*(.-)%s*$")
	if word == "" or string.find(word, "[,%c]") or #word > 40 then
		return false, "the keyword must be 1-40 characters without commas"
	end
	for _, w in ipairs(GA.keywords(cat)) do
		if w == word then
			return true
		end
	end
	local list = GA.keywords(cat)
	table.insert(list, word)
	return Settings.set(KW_KEY[cat], table.concat(list, ","), "gameaudio")
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------------

function GA.start(ctx)
	assert(state == nil, "GameAudio already started")
	state = { hooked = setmetatable({}, { __mode = "k" }), muted = setmetatable({}, { __mode = "k" }), mutedCount = 0, busy = false, learning = false }
	local lp = Services.Players.LocalPlayer
	ctx.maid:Give(function()
		if not state then
			return
		end
		GA.songStop()
		for sound in pairs(table.clone(state.muted)) do
			unmute(sound)
		end
		for sound in pairs(table.clone(state.hooked)) do
			forget(sound)
		end
		state = nil
	end)
	local function watch(root)
		if root then
			ctx.maid:Give(root.DescendantAdded:Connect(function(d)
				if state then
					hook(d)
				end
			end))
		end
	end
	watch(Services.SoundService)
	watch(lp)
	watch(Services.Workspace)
	ctx.maid:Give(lp.CharacterAdded:Connect(function(char)
		if state then
			for _, d in ipairs(char:GetDescendants()) do
				hook(d)
			end
		end
	end))
	-- any change of a setting that decides what is silenced re-applies at once
	local keys = { "gameaudio.muteKill", "gameaudio.muteShot", "gameaudio.muteReload", "gameaudio.muteKnife", "gameaudio.muteWin", "gameaudio.songEnabled", "gameaudio.songSource",
		"ksound.murdererEnabled", "ksound.murdererSource", "ksound.sheriffEnabled", "ksound.sheriffSource" }
	for _, cat in ipairs(GA.CATEGORIES) do
		table.insert(keys, KW_KEY[cat])
	end
	for _, k in ipairs(keys) do
		ctx.maid:Give(Settings.observe(k, function()
			GA.rescan()
		end))
	end
	ctx.maid:Give(Settings.observe("gameaudio.songVolume", function(v)
		if state and state.song then
			state.song.Volume = v
		end
	end))
	GA.rescan()
end

return GA

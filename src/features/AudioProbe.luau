--!nonstrict
-- features/AudioProbe: stage-by-stage check of the whole audio path, from the chosen source to an engine-measured signal.
-- A sound that "does nothing" has one of a handful of causes; this module tests each one and reports WHICH:
--   source    the text is a valid asset id / file name
--   file      the file exists in MM2Hub/ (bundled sounds are written first); size > 0
--   url       getcustomasset gave a URL (file sources) or the asset id was turned into rbxassetid://
--   sound     a Sound object could be created and parented to SoundService
--   fetch     ContentProvider:PreloadAsync reports Success (a private/removed asset or a blocked file reports Failure)
--   loaded    Sound.IsLoaded became true and TimeLength > 0 within the timeout
--   volume    the sound's volume, SoundGroup and the client's master volume are not zero
--   playing   after Play(), IsPlaying is true and TimePosition advances
--   signal    PlaybackLoudness (measured by the engine while playing) rose above 0
-- The last stage is the strongest evidence a script can get that audio is being produced; it still cannot prove that the
-- speakers are on. A CONTROL sound that ships with the Roblox client (rbxasset://sounds/electronicpingshort.wav) can be run the same way:
-- if the control passes and your sound fails, the fault is in your source; if both fail, it is the game or system volume.
-- Depends on: Sources, Sounds, SoundPack, Env, Services, Logger.

local import = ...
local Sources = import("features/Sources")
local Sounds = import("features/Sounds")
local Pack = import("features/SoundPack")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")

local Probe = {}

Probe.CONTROL_URL = "rbxasset://sounds/electronicpingshort.wav"
Probe.LOAD_TIMEOUT = 6
Probe.PLAY_WINDOW = 1.2

local function stage(report, name, ok, detail)
	table.insert(report.stages, { name = name, ok = ok, detail = detail or "" })
	if not ok and not report.failed then
		report.failed = name
	end
	return ok
end

local function waitUntil(fn, timeout, step)
	local t = 0
	while t < timeout do
		if fn() then
			return true
		end
		task.wait(step)
		t += step
	end
	return fn()
end

local function masterVolume()
	local ok, v = pcall(function()
		return UserSettings():GetService("UserGameSettings").MasterVolume
	end)
	return ok and tonumber(v) or nil
end

-- run(spec, cb)
--   spec = { source = "file:x.mp3" | "asset:123" | nil, url = direct url (control), volume = 0..1, keep = true to leave the sound playing,
--            folder = "sounds" (default) or "music" for file: sources, label = text shown in the report }
--   cb(report) is called once: report = { ok, failed (stage name), stages = { {name, ok, detail} }, verdict, loudness, length, sound (when keep) }
-- Returns true when the check was started.
function Probe.run(spec, cb)
	local report = { ok = false, stages = {}, label = spec.label or spec.source or spec.url or "sound", loudness = 0 }
	local function finish(verdict)
		report.verdict = verdict
		report.ok = report.failed == nil
		Logger.info("AudioProbe", "%s: %s", report.label, verdict)
		for _, s in ipairs(report.stages) do
			Logger.info("AudioProbe", "  [%s] %s %s", s.ok and "ok" or "FAIL", s.name, s.detail)
		end
		if cb then
			cb(report)
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local url = spec.url
			if not url then
				-- source -> file -> url
				local parsed, perr = Sources.parse(spec.source or "", "audio")
				if not stage(report, "source", parsed ~= nil and parsed.type ~= "proc", parsed and (parsed.type .. ":" .. parsed.ref) or tostring(perr or "not an audio source")) then
					return finish("the source text is not valid (use asset:<id> or file:<name.mp3>)")
				end
				if parsed.type == "file" then
					local bundled = (spec.folder or "sounds") == "sounds" and Pack.has(parsed.ref)
					if bundled then
						local iok, ierr = Pack.ensure(parsed.ref)
						if not stage(report, "file", iok, iok and "bundled sound installed in MM2Hub/sounds" or tostring(ierr)) then
							return finish("the bundled file could not be written: " .. tostring(ierr))
						end
					else
						local path = Env.ROOT .. "/" .. (spec.folder or "sounds") .. "/" .. parsed.ref
						local exists = Env.exists(path)
						if not stage(report, "file", exists, exists and path or (path .. " does not exist")) then
							return finish("the file is not in MM2Hub/sounds/ (name must match exactly)")
						end
					end
				end
				local u, uerr = Sounds.resolveParsed(parsed, spec.folder or "sounds")
				if not stage(report, "url", u ~= nil, u or tostring(uerr)) then
					return finish("no usable URL: " .. tostring(uerr))
				end
				url = u
			end
			local snd
			local cok, cerr = pcall(function()
				snd = Instance.new("Sound")
				snd.Name = "MM2Hub_Probe"
				snd.SoundId = url
				snd.Volume = spec.volume or 0.8
				snd.Parent = Services.SoundService
			end)
			if not stage(report, "sound", cok, cok and "Sound created in SoundService" or tostring(cerr)) then
				return finish("a Sound object could not be created: " .. tostring(cerr))
			end
			if spec.onSound then
				spec.onSound(snd) -- lets the caller stop it while the check is still running
			end
			local function destroy()
				pcall(function()
					snd:Stop()
					snd:Destroy()
				end)
			end
			-- The checks below are DIAGNOSTICS: whatever they say, Play() is still attempted, so a sound that the executor reports
			-- oddly but can actually play is never kept silent by the check itself. The verdict names the first stage that failed.
			local firstProblem
			local function problem(msg)
				firstProblem = firstProblem or msg
			end
			-- fetch
			local status = "no status"
			local pok, perr2 = pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ snd }, function(_, st)
					status = tostring(st)
				end)
			end)
			-- PreloadAsync missing or erroring in an executor is not a failure of the sound: IsLoaded below decides. A reported Failure is.
			local fetched = not pok or status == "no status" or string.find(status, "Success", 1, true) ~= nil
			local fdetail = pok and ("ContentProvider status: " .. status) or ("skipped, PreloadAsync unavailable: " .. tostring(perr2))
			if not stage(report, "fetch", fetched, fdetail) then
				problem("the asset could not be fetched (" .. status .. "): wrong id, private audio, or the file is unreadable")
			end
			-- loaded
			local loaded = waitUntil(function()
				return snd.IsLoaded ~= false and (snd.TimeLength == nil or snd.TimeLength > 0)
			end, fetched and Probe.LOAD_TIMEOUT or 1, 0.1)
			report.length = tonumber(snd.TimeLength)
			if not stage(report, "loaded", loaded, loaded and string.format("IsLoaded, length %.2f s", report.length or 0) or ("not loaded after the wait (IsLoaded=" .. tostring(snd.IsLoaded) .. ", TimeLength=" .. tostring(snd.TimeLength) .. ")")) then
				problem("the audio did not load: the game may not be allowed to play this asset")
			end
			-- volume
			local mv = masterVolume()
			local group = snd.SoundGroup
			local gv = group and group.Volume
			local vol = snd.Volume
			local vok = vol > 0 and (mv == nil or mv > 0.001) and (gv == nil or gv > 0)
			stage(report, "volume", vok, string.format("sound %.2f, group %s, client master %s", vol, gv and string.format("%.2f", gv) or "none", mv and string.format("%.2f", mv) or "unknown"))
			-- playing
			snd.TimePosition = 0
			snd:Play()
			local playing, advanced, maxLoud, ended = false, false, 0, false
			local t = 0
			while t < Probe.PLAY_WINDOW do
				task.wait(0.05)
				t += 0.05
				if not snd.Parent then
					break -- stopped by the caller
				end
				if snd.IsPlaying then
					playing = true
				end
				if (snd.TimePosition or 0) > 0.02 then
					advanced = true
				end
				local l = tonumber(snd.PlaybackLoudness) or 0
				if l > maxLoud then
					maxLoud = l
				end
				if snd.IsPlaying == false and playing then
					ended = true
					break -- short sound finished
				end
			end
			report.loudness = maxLoud
			local pl = playing or advanced
			if not stage(report, "playing", pl, pl and ("IsPlaying=" .. tostring(playing) .. ", position advanced=" .. tostring(advanced)) or "Play() was called but the sound never started (stopped by another script or blocked)") then
				problem("Play() did not start the sound")
			end
			local short = (report.length ~= nil and report.length > 0 and report.length < 0.5) or ended
			local sigok = maxLoud > 0 or (pl and short)
			stage(report, "signal", sigok, maxLoud > 0 and string.format("max PlaybackLoudness %.1f", maxLoud)
				or (pl and short and "not measured: the sound is too short for the 50 ms samples") or "max PlaybackLoudness 0")
			if not vok then
				problem("it plays, but a volume setting is zero (see the volume line)")
			end
			if not sigok then
				problem("the engine plays it but measures no loudness: the file may be silent")
			end
			-- keep a sound that is still playing (preview); everything else is removed here, also on failure
			if spec.keep and pl and snd.IsPlaying and snd.Parent then
				report.sound = snd
			else
				destroy()
			end
			if firstProblem then
				return finish(firstProblem)
			end
			finish(maxLoud > 0 and string.format("playing: the engine measures a signal (loudness %.0f). If you still hear nothing, check your system and in-game volume.", maxLoud)
				or "playing (too short to measure loudness). If you hear nothing, check your system and in-game volume.")
		end)
		if not ok then
			report.failed = report.failed or "error"
			stage(report, "error", false, tostring(err))
			finish("the check itself failed: " .. tostring(err))
		end
	end)
	return true
end

-- format(report) -> multi-line text for a label or the log
function Probe.format(report)
	local lines = { report.label .. ": " .. tostring(report.verdict) }
	for _, s in ipairs(report.stages) do
		table.insert(lines, string.format("%s %s  %s", s.ok and "✓" or "✗", s.name, s.detail))
	end
	return table.concat(lines, "\n")
end

-- control(cb): the same check on a sound that ships with the Roblox client
function Probe.control(cb)
	return Probe.run({ url = Probe.CONTROL_URL, volume = 0.7, label = "Roblox client control sound" }, cb)
end

return Probe

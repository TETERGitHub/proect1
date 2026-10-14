--!nonstrict
-- ui/PagesGame: pages for the gameplay-side features: training range, drone, cosmetics, music, sounds.
-- Depends on: PageKit, Framework, Theme, Settings, Perf, Actions and the feature modules.

local import = ...
local Kit = import("ui/PageKit")
local F = import("ui/Framework")
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Actions = import("core/Actions")
local Training = import("features/Training")
local TargetSelect = import("features/TargetSelect")
local Drone = import("features/Drone")
local Cosmetics = import("features/Cosmetics")
local Music = import("features/Music")
local Sounds = import("features/Sounds")
local Tools = import("features/Tools")

local notify, visible, auto, section, resetButton, dataList, infoLine = Kit.notify, Kit.visible, Kit.auto, Kit.section, Kit.resetButton, Kit.dataList, Kit.infoLine

local G = {}

local function buttonRow(page, buttons, height)
	local card = F.frame(page.content, { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, height or 40) })
	F.list(card, 8, true)
	for i, b in ipairs(buttons) do
		local btn = F.button(card, b.text, b.fn, b.style or "tinted", UDim2.fromOffset(b.width or 130, height and height - 6 or 34), page.maid)
		btn.LayoutOrder = i
	end
	return card
end

-- Training -----------------------------------------------------------------------------------------------------------

function G.training(page)
	local update = page:stats({
		{ title = "SHOTS", value = "0" }, { title = "HITS", value = "0" }, { title = "ACCURACY", value = "—" }, { title = "REACTION", value = "—" },
	})
	local handle = Perf.every("ui.training", 4, function()
		if not visible("training") then
			return
		end
		local s = Training.getStats()
		update(1, tostring(s.shots)); update(2, tostring(s.hits))
		update(3, s.shots > 0 and string.format("%d%%", s.accuracy * 100 + 0.5) or "—")
		update(4, s.reaction and string.format("%d ms", s.reaction * 1000 + 0.5) or "—")
	end)
	page.maid:Give(handle.Cancel)
	page:note("The range is a sandbox: targets and the dummy exist only on your screen and never interact with other players. Click targets to score; the drone page can fly into the dummy.", "textDim", 52)
	buttonRow(page, {
		{ text = "Reset stats", fn = Training.resetStats },
		{ text = "Clear everything", fn = function() Actions.run("training.clear") end, style = "danger" },
	})
	section(page, "Practice targets", { "training.enabled", "training.mode", "training.count", "training.targetSize", "training.speed", "training.distance", "training.targetColor", "training.particles", "training.demoGuide" })
	page:section("Physics stand")
	buttonRow(page, {
		{ text = "Spawn dummy", fn = function() Actions.run("training.spawnDummy") end, style = "filled" },
		{ text = "Launch", fn = function() Actions.run("training.launch") end, style = "filled" },
		{ text = "Reset dummy", fn = function() Actions.run("training.resetDummy") end },
	})
	section(page, "Stand settings", { "training.physImpulse", "training.physMaxSpeed", "training.physDirection" })

	-- Hitbox lab ------------------------------------------------------------------------------------------------
	page:section("Hitbox lab - isolated test scene")
	page:note("Builds a small local scene with a mannequin and a SEPARATE hitbox you can size, offset and move (Orbit / Jitter / Blink). Click to shoot: only the hitbox scores, the body alone is a miss. This does NOT change any real MM2 hitbox and says nothing about how the game registers hits on real players.", "textDim", 74)
	local layers = dataList(page, { rowHeight = 46, maxRows = 3 })
	local lines = {}
	local function line(label, fn)
		local update = infoLine(page, label, fn)
		table.insert(lines, update)
	end
	local function fmtV(v)
		return string.format("%.1f, %.1f, %.1f", v.x, v.y, v.z)
	end
	line("Body position", function()
		local r = Training.labReadout()
		return r and fmtV(r.body) or "no lab"
	end)
	line("Hitbox position", function()
		local r = Training.labReadout()
		return r and fmtV(r.hitbox) or "no lab"
	end)
	line("Hitbox offset from body", function()
		local r = Training.labReadout()
		return r and (fmtV(r.offset) .. string.format("  (|d| %.1f)", r.distanceFromBody)) or "no lab"
	end)
	line("Active mode changes", function()
		local r = Training.labReadout()
		return r and (r.mode .. " -> " .. r.modeChanges) or "no lab"
	end)
	line("Crosshair ray", function()
		local p = Training.labProbe()
		if not p then
			return "no lab"
		end
		if p.hitbox then
			return string.format("hitbox @ %.1f studs", p.hitbox)
		elseif p.body then
			return string.format("body only @ %.1f (hitbox missed by %.1f)", p.body, p.nearMiss)
		end
		return string.format("miss (nearest %.1f studs)", p.nearMiss)
	end)
	line("Overlapping scene parts", function()
		local o = Training.labOverlap()
		return #o > 0 and table.concat(o, ", ") or "none"
	end)
	line("Shots / hits / body-only", function()
		local r = Training.labReadout()
		return r and string.format("%d / %d / %d", r.shots, r.hits, r.bodyOnly) or "no lab"
	end)
	line("Probes / physical collisions", function()
		local r = Training.labReadout()
		return r and string.format("%d / %d", r.probes, r.collisions) or "no lab"
	end)
	local function renderLayers()
		local items = {}
		for _, l in ipairs(Training.labLayers()) do
			local ok = l.state ~= "not available" and l.state ~= "no lab"
			table.insert(items, { title = l.name, sub = l.detail, value = l.state, valueToken = ok and "good" or (l.state == "not available" and "warn" or "textDim") })
		end
		layers.set(items)
	end
	local labHandle = Perf.every("ui.lab", 5, function()
		if visible("training") then
			for _, update in ipairs(lines) do
				update()
			end
		end
	end)
	page.maid:Give(labHandle.Cancel)
	local layerHandle = Perf.every("ui.lab.layers", 1, function()
		if visible("training") then
			renderLayers()
		end
	end)
	page.maid:Give(layerHandle.Cancel)
	renderLayers()
	buttonRow(page, {
		{ text = "Spawn lab", fn = function() local ok, err = Training.spawnLab(); if not ok then notify("Hitbox lab", tostring(err), "error") end end, style = "filled" },
		{ text = "Fire probe", fn = function() local ok, err = Training.fireProbe(); if not ok then notify("Hitbox lab", tostring(err), "warn") end end },
		{ text = "Remove lab", fn = function() Training.clearLab() end },
		{ text = "Reset counters", fn = function() Training.resetLabCounters() end, width = 140 },
	})
	section(page, "Lab hitbox geometry", { "training.hbShape", "training.hbSize", "training.hbOffsetX", "training.hbOffsetY", "training.hbOffsetZ", "training.hbShow", "training.hbCollide" })
	section(page, "Lab motion mode", { "training.hbMode" })
	section(page, "Orbit settings", { "training.orbitRadius", "training.orbitSpeed", "training.orbitTilt" })
	section(page, "Jitter settings", { "training.jitterAmplitude", "training.jitterSpeed" })
	section(page, "Blink settings", { "training.blinkRange", "training.blinkInterval" })

	-- Select Aim (test targets only) -------------------------------------------------------------------------------
	page:section("Select Aim - test target selector")
	page:note("Selects ONE of your local test targets (training targets, dummy, lab hitbox) by mode, FOV, visibility and lock, highlights it and shows its info. It does not fire, aim your camera or touch MM2 hit registration, and it is not a silent aim. Next / Previous switch to Manual mode. Assign keys on the Hotkeys page.", "textDim", 74)
	section(page, "Select Aim", { "selectaim.enabled", "selectaim.mode", "selectaim.lock", "selectaim.fov", "selectaim.showFov", "selectaim.highlight", "selectaim.highlightColor" })
	section(page, "Checks & prediction", { "selectaim.visibilityCheck", "selectaim.autoAcquire", "selectaim.prediction", "selectaim.projectileSpeed", "selectaim.leadMax" })
	local infoLines = {}
	local function info(label, fn)
		table.insert(infoLines, (infoLine(page, label, fn)))
	end
	info("Target", function()
		local i = TargetSelect.info()
		return i.name or "none"
	end)
	info("Distance", function()
		local i = TargetSelect.info()
		return i.distance and string.format("%.1f studs%s", i.distance, i.screenDistance and string.format("  ·  %.0f px from centre", i.screenDistance) or "") or "—"
	end)
	info("Selection status", function()
		local i = TargetSelect.info()
		return i.status .. (i.locked and "  🔒" or "")
	end)
	info("Visibility", function()
		local i = TargetSelect.info()
		if not i.running or not i.name then
			return "—"
		end
		if i.visibilityAvailable == false then
			return "check unavailable (Workspace:Raycast failed)"
		end
		return i.visible == true and "visible" or (i.visible == false and "hidden" or "not checked")
	end)
	info("Eligible targets", function()
		local i = TargetSelect.info()
		return i.running and string.format("%d of %d in FOV", i.eligible, i.total) or "—"
	end)
	info("Predicted position", function()
		local i = TargetSelect.info()
		if not i.predicted then
			return Settings.get("selectaim.prediction") and "target is stationary / none" or "prediction off"
		end
		return string.format("%.1f, %.1f, %.1f  (lead %.2fs)", i.predicted.x, i.predicted.y, i.predicted.z, i.lead or 0)
	end)
	info("Last drop reason", function()
		local i = TargetSelect.info()
		return i.lost and (i.lost.id .. ": " .. i.lost.reason) or "—"
	end)
	local pickList = dataList(page, {
		rowHeight = 40, maxRows = 16,
		buttons = { { icon = "check", tip = "Select this target (Manual mode)", fn = function(item)
			local ok, err = TargetSelect.pick(item.id)
			if not ok then
				notify("Select Aim", tostring(err or "target is not eligible"), "warn")
			end
		end } },
	})
	local function renderPicks()
		local items = {}
		for _, t in ipairs(TargetSelect.list()) do
			table.insert(items, { id = t.id, title = t.name, sub = "", value = t.selected and "selected" or (t.eligible and "in FOV" or "outside / hidden"), valueToken = t.selected and "accent" or (t.eligible and "good" or "textDim") })
		end
		if #items == 0 then
			items[1] = { title = "No test targets yet - enable the training range or spawn the lab", titleToken = "textDim" }
		end
		pickList.set(items)
	end
	local selHandle = Perf.every("ui.selectaim", 4, function()
		if visible("training") then
			for _, update in ipairs(infoLines) do
				update()
			end
			renderPicks()
		end
	end)
	page.maid:Give(selHandle.Cancel)
	buttonRow(page, {
		{ text = "Select", style = "filled", width = 100, fn = function() local ok, err = TargetSelect.select(); if not ok then notify("Select Aim", tostring(err), "warn") end end },
		{ text = "Lock on/off", width = 110, fn = function() TargetSelect.toggleLock() end },
		{ text = "Reset", width = 90, fn = function() TargetSelect.reset() end },
		{ text = "Previous", width = 90, fn = function() TargetSelect.previous() end },
		{ text = "Next", width = 90, fn = function() TargetSelect.next() end },
	})
end

-- Defence ------------------------------------------------------------------------------------------------------------------

function G.defence(page)
	local AntiFling = import("features/AntiFling")
	local update = page:stats({ { title = "FLINGS BLOCKED", value = "0" }, { title = "GHOSTED PARTS", value = "0" } })
	local handle = Perf.every("ui.defence", 2, function()
		if visible("defence") then
			update(1, tostring(AntiFling.blocks()))
			update(2, tostring(AntiFling.ghostedParts()))
		end
	end)
	page.maid:Give(handle.Cancel)
	page:note("Defence only protects your own character on your own client. It cancels abnormal speed and spin and stops other bodies from colliding with you on your screen. It cannot change what other players or the server do, and it cannot redirect shots aimed at you: hits are decided by the shooter and the server.", "textDim", 74)
	resetButton(page, "AntiFling")
	section(page, "Anti-fling", { "antifling.enabled", "antifling.maxSpeed", "antifling.angularLimit", "antifling.noCollide", "antifling.notify" })
	buttonRow(page, { { text = "Reset counter", fn = AntiFling.resetCounter } })
end

-- Drone -------------------------------------------------------------------------------------------------------------------

function G.drone(page)
	local card = page:card(132)
	F.padding(card, 18, 14, 18, 14)
	local title = F.label(card, "FPV loitering drone", { size = 17, bold = true })
	local desc = F.label(card, "Third-person flight, dot reticle. Impacts work on the local training dummy and targets only: Fling pushes them, Eliminate removes them (Murderer role in the sandbox).", { size = 12, token = "textDim", wrap = true, dim = UDim2.new(1, -170, 0, 48), valign = Enum.TextYAlignment.Top })
	desc.Position = UDim2.fromOffset(0, 26)
	local controls = F.label(card, "W/S pitch · A/D turn · Space/Shift throttle · X exit   (touch: on-screen stick)", { size = 11, token = "textDim", dim = UDim2.new(1, -170, 0, 16) })
	controls.Position = UDim2.new(0, 0, 1, -34)
	local launch
	launch = F.button(card, "Launch", function()
		if Drone.isFlying() then
			Drone.land()
		else
			local ok, err = Drone.launch()
			if not ok then
				notify("Drone", tostring(err), "error")
			end
		end
	end, "filled", UDim2.fromOffset(130, 44), page.maid)
	launch.AnchorPoint = Vector2.new(1, 0.5)
	launch.Position = UDim2.new(1, 0, 0.5, 0)
	page.maid:Give(Drone.Changed:Connect(function(flying)
		launch.Text = flying and "Land" or "Launch"
	end))
	buttonRow(page, {
		{ text = "Spawn training dummy", fn = function() Actions.run("training.spawnDummy") end, width = 200 },
		{ text = "Enable practice targets", fn = function() Settings.set("training.enabled", true, "ui") end, width = 200 },
	})
	section(page, "Impact", { "drone.mode", "drone.simRole", "drone.flingForce" })
	section(page, "Flight", { "drone.speed", "drone.turnRate", "drone.invertPitch", "drone.worldCollision" })
	section(page, "Camera & HUD", { "drone.camDistance", "drone.camHeight", "drone.showHud", "drone.trail", "drone.engineSound" })
	page:note("Simulated role is a setting of the sandbox only; it does not read or change your real MM2 role. Map geometry crashes the drone and respawns it at launch height.", "textDim", 52)
end

-- Cosmetics ----------------------------------------------------------------------------------------------------------------------

local function quickPicks(page, kind, key)
	local names = Cosmetics.procNames(kind)
	local card = F.frame(page.content, { LayoutOrder = page:nextOrder(), Size = UDim2.new(1, 0, 0, 36) })
	F.list(card, 6, true)
	local label = F.label(card, "Built-in:", { size = 12, token = "textDim", dim = UDim2.fromOffset(60, 30) })
	label.LayoutOrder = 0
	for i, name in ipairs(names) do
		local b = F.button(card, name, function()
			Settings.set(key, "proc:" .. name, "ui")
		end, "tinted", UDim2.fromOffset(math.max(64, #name * 8 + 24), 28), page.maid)
		b.LayoutOrder = i
	end
end

function G.cosmetics(page)
	page:note("Skins are LOCAL: only you see them. Supply your own models by asset id or as a file in MM2Hub/models/ (.rbxm); scripts inside loaded models are removed. The hub does not fetch models from any site.", "textDim", 56)
	local statusUpdate = {}
	for _, slot in ipairs({ { "gun", "Gun" }, { "knife", "Knife" }, { "char", "Character" } }) do
		local fn = Kit.infoLine(page, slot[2] .. " status", function()
			return Cosmetics.status()[slot[1]] or "off"
		end)
		table.insert(statusUpdate, fn)
	end
	local handle = Perf.every("ui.cosmetics", 2, function()
		if visible("cosmetics") then
			for _, fn in ipairs(statusUpdate) do
				fn()
			end
		end
	end)
	page.maid:Give(handle.Cancel)
	buttonRow(page, {
		{ text = "Re-apply skins", fn = function() Cosmetics.reapply(); notify("Cosmetics", "Skins re-applied.", "success") end, style = "filled" },
		{ text = "Reset page", fn = function() Settings.resetModule("Cosmetics") end, style = "danger" },
	})
	section(page, "Gun", { "cosmetics.gunEnabled", "cosmetics.gunSource" })
	quickPicks(page, "gun", "cosmetics.gunSource")
	section(page, "Gun fit", { "cosmetics.gunTool", "cosmetics.gunScale", "cosmetics.gunOffsetX", "cosmetics.gunOffsetY", "cosmetics.gunOffsetZ", "cosmetics.gunRotY" })
	section(page, "Knife", { "cosmetics.knifeEnabled", "cosmetics.knifeSource" })
	quickPicks(page, "knife", "cosmetics.knifeSource")
	section(page, "Knife fit", { "cosmetics.knifeTool", "cosmetics.knifeScale", "cosmetics.knifeOffsetX", "cosmetics.knifeOffsetY", "cosmetics.knifeOffsetZ", "cosmetics.knifeRotY" })
	section(page, "Character model", { "cosmetics.charEnabled", "cosmetics.charSource" })
	quickPicks(page, "char", "cosmetics.charSource")
	section(page, "Character fit", { "cosmetics.charAttach", "cosmetics.charScale", "cosmetics.charOffsetY" })
	section(page, "Body", { "cosmetics.bodyColorEnabled", "cosmetics.bodyColor", "cosmetics.neon" })
end

-- Music ----------------------------------------------------------------------------------------------------------------------------

function G.music(page)
	local card = page:card(112)
	F.padding(card, 18, 12, 18, 12)
	local titleLabel = F.label(card, "Nothing playing", { size = 16, bold = true })
	local stateLabel = F.label(card, "", { size = 12, token = "textDim", dim = UDim2.new(1, 0, 0, 16) })
	stateLabel.Position = UDim2.fromOffset(0, 22)
	local bar = F.frame(card, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 6) }, { BackgroundColor3 = "bg3" })
	bar.BackgroundTransparency = 0
	local barHit = Instance.new("TextButton")
	barHit.Text = ""
	barHit.BackgroundTransparency = 1
	barHit.Position = UDim2.fromOffset(0, 40)
	barHit.Size = UDim2.new(1, 0, 0, 22)
	barHit.Parent = card
	F.pillCorner(bar)
	local fill = F.frame(bar, { Size = UDim2.fromScale(0, 1) }, { BackgroundColor3 = "accent" })
	fill.BackgroundTransparency = 0
	F.pillCorner(fill)
	page.maid:Give(barHit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local function upd(pos)
				local w = bar.AbsoluteSize.X
				if w > 0 then
					Music.seek((pos.X - bar.AbsolutePosition.X) / w)
				end
			end
			upd(input.Position)
			F.beginDrag(upd)
		end
	end))
	local controls = F.frame(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(220, 34) })
	F.list(controls, 14, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local playBtn
	local prev = F.iconButton(controls, "skip", Music.previous, 32, page.maid); prev.LayoutOrder = 1
	local prevIcon = prev:FindFirstChildOfClass("Frame"); if prevIcon then prevIcon.Rotation = 180 end
	playBtn = F.iconButton(controls, "play", Music.toggle, 36, page.maid, "accent"); playBtn.LayoutOrder = 2
	local nextBtn = F.iconButton(controls, "skip", Music.next, 32, page.maid); nextBtn.LayoutOrder = 3
	local function fmt(s) return Tools.formatTime(s) end
	local handle = Perf.every("ui.music", 4, function()
		if not visible("music") then
			return
		end
		local n = Music.nowPlaying()
		if not n or not n.index then
			titleLabel.Text = "Nothing playing"
			stateLabel.Text = #Settings.get("music.playlist") == 0 and "Add a track below" or "Press play"
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		titleLabel.Text = n.title or "Track"
		stateLabel.Text = n.loading and "loading…" or (fmt(n.position) .. " / " .. fmt(n.length) .. (n.playing and "" or "  ·  paused"))
		fill.Size = UDim2.fromScale(n.length > 0 and math.clamp(n.position / n.length, 0, 1) or 0, 1)
	end)
	page.maid:Give(handle.Cancel)

	page:section("Add a track")
	local srcBox, titleBox
	local row1, h1 = page:row({ label = "Source", desc = "asset:<id> (an audio you may use) or file:<name.mp3> from MM2Hub/music/", width = 260 })
	srcBox = F.textBox(h1, { placeholder = "asset:123456  or  file:song.mp3", dim = UDim2.fromOffset(260, 30) }, page.maid)
	srcBox.AnchorPoint = Vector2.new(1, 0.5); srcBox.Position = UDim2.fromScale(1, 0.5)
	local row2, h2 = page:row({ label = "Title", width = 260 })
	titleBox = F.textBox(h2, { placeholder = "optional", dim = UDim2.fromOffset(260, 30) }, page.maid)
	titleBox.AnchorPoint = Vector2.new(1, 0.5); titleBox.Position = UDim2.fromScale(1, 0.5)
	buttonRow(page, {
		{ text = "Add to playlist", style = "filled", width = 160, fn = function()
			local ok, err = Music.add(srcBox.Text, titleBox.Text)
			if ok then
				srcBox.Text, titleBox.Text = "", ""
			else
				notify("Music", tostring(err), "warn")
			end
		end },
		{ text = "Clear playlist", style = "danger", width = 140, fn = function()
			F.confirm({ title = "Clear playlist", text = "Remove every track from the playlist?", danger = true, onConfirm = Music.clearPlaylist })
		end },
	})
	page:note("Only tracks you supply are played. Roblox may refuse audio you do not own; unreadable tracks are skipped with a message. Playback is local, so it also works in the lobby, but nobody else hears it.", "textDim", 56)

	page:section("Playlist")
	local list = dataList(page, {
		rowHeight = 44, maxRows = 40,
		buttons = {
			{ icon = "play", tip = "Play", fn = function(item) Music.playIndex(item.index) end },
			{ icon = "chevron", tip = "Move down", fn = function(item) Music.move(item.index, 1) end },
			{ icon = "close", tip = "Remove", token = "bad", fn = function(item) Music.remove(item.index) end },
		},
	})
	local function render()
		local items = {}
		local np = Music.nowPlaying()
		for i, t in ipairs(Music.tracks()) do
			table.insert(items, {
				index = i, title = t.title, sub = t.invalid and "invalid entry" or (t.source.type .. ":" .. t.source.ref),
				value = (np and np.index == i) and "▶ playing" or "", valueToken = "accent",
			})
		end
		list.set(items)
	end
	page.maid:Give(Music.Changed:Connect(function(reason)
		if reason == "playlist" or reason == "track" or reason == "state" then
			render()
		end
	end))
	render()
	section(page, "Playback", { "music.volume", "music.loop", "music.shuffle", "music.speed", "music.autoplay" })
end

-- Sounds ---------------------------------------------------------------------------------------------------------------------------------

function G.sounds(page)
	page:note("Assign your own sounds to events. Each slot stays silent until it has a source (asset:<id> or file:<name> in MM2Hub/sounds/). No sounds are bundled and no Roblox default sounds are used. Gun and knife slots play when you use your own tools; Hit/Kill play in the training range.", "textDim", 70)
	auto(page, "sounds.master")
	for _, slot in ipairs(Sounds.slots()) do
		page:section(slot.label)
		auto(page, "sounds." .. slot.id .. "Enabled")
		auto(page, "sounds." .. slot.id .. "Source")
		auto(page, "sounds." .. slot.id .. "Volume")
		auto(page, "sounds." .. slot.id .. "Pitch")
		page:action({ label = "Test " .. string.lower(slot.label), desc = "Plays this slot once.", text = "Test", onClick = function()
			local ok, err = Sounds.test(slot.id)
			if not ok then
				notify(slot.label, tostring(err or "could not play"), "warn")
			end
		end })
	end
	resetButton(page, "Sounds")
end

return G

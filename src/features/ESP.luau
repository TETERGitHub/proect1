--!nonstrict
-- features/ESP: boxes, names, distance, health, tracers, highlights and a held-weapon tag drawn over characters.
--   Players (the real round): ONLY while the player is in your direct line of sight - a ray from your camera to their head
--     or body must reach them without hitting a wall. Behind a wall nothing is drawn at all, and it comes back when they
--     come into view again. No roles are shown: the weapon tag appears only when a Knife / Gun tool is actually equipped
--     (held in their hand, which everyone can see) - it is what is visible, not a guess about their role. No off-screen
--     arrows for players. Highlights use DepthMode Occluded, so only the parts you can see light up.
--   Test mannequins (features/MurderTrainer): everything, with their TEST role and off-screen arrows - practice only.
-- One visual task (rate from the settings, low profile halves it), one set of pooled GUI objects per target, destroyed
-- when the target leaves, dies or the module stops. Nothing is sent anywhere; only your screen changes.
-- STATUS: implemented; verified against the mock layer only. In MM2: line-of-sight rule and weapon tag rely on standard
-- Roblox characters and the Knife / Gun tool names (settings); not checked in a live MM2 server.
--   Dropped gun: a marker on the object named in the settings (MM2 is commonly reported to call it "GunDrop"; not confirmed
--     here) - also only while it is in your line of sight.
-- Depends on: Settings, Perf, Env, Services, Logger, MurderTrainer, I18n.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Env = import("core/Env")
local Services = import("core/Services")
local Logger = import("core/Logger")
local MurderTrainer = import("features/MurderTrainer")
local I18n = import("core/I18n")

local ESP = {}

local ROLE_COLOR = { Innocent = Color3.fromRGB(90, 200, 120), Sheriff = Color3.fromRGB(70, 140, 255) }
local KNIFE_COLOR, GUN_COLOR = Color3.fromRGB(255, 70, 70), Color3.fromRGB(80, 160, 255)
local state = nil
local sourceOverride = nil

local function s(k)
	return Settings.get("esp." .. k)
end

local function rgb(k)
	local c = s(k)
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- targets ------------------------------------------------------------------------------------------------------------------

-- setSource(fn): tests can provide the player targets (fn() -> list of { key, name, character, player = true })
function ESP.setSource(fn)
	sourceOverride = fn
end

local function playerTargets()
	if sourceOverride then
		local ok, list = pcall(sourceOverride)
		return ok and list or {}
	end
	local out = {}
	local lp = Services.Players.LocalPlayer
	for _, p in ipairs(Services.Players:GetPlayers()) do
		if p ~= lp and p.Character then
			table.insert(out, { key = "P:" .. p.UserId, name = p.DisplayName ~= p.Name and (p.DisplayName .. " (@" .. p.Name .. ")") or p.Name,
				character = p.Character, player = true })
		end
	end
	return out
end

-- heldWeapon(character) -> "Knife" | "Gun" | nil : a Tool equipped (parented to the character = in hand, visible to all)
function ESP.heldWeapon(char)
	if not char then
		return nil
	end
	local knife, gun = Settings.get("cosmetics.knifeTool"), Settings.get("cosmetics.gunTool")
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			if c.Name == knife then
				return "Knife"
			elseif c.Name == gun then
				return "Gun"
			end
		end
	end
	return nil
end

-- line of sight from the camera to the character: a ray to the head and one to the body; the first thing hit must be
-- part of that character (or nothing). Your own character and the hub's objects are ignored.
function ESP.inSight(char, from)
	local cam = Services.Workspace.CurrentCamera
	from = from or cam.CFrame.Position
	local lp = Services.Players.LocalPlayer
	local ignore = { cam }
	if lp and lp.Character then
		table.insert(ignore, lp.Character)
	end
	for _, name in ipairs({ "MM2Hub_Training", "MM2Hub_MurderTrainer" }) do
		local f = Services.Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, partName in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "Torso" }) do
		local part = char:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			local ok, hit = pcall(function()
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = ignore
				return Services.Workspace:Raycast(from, part.Position - from, params)
			end)
			if not ok then
				return false -- cannot check: treat as not visible (never draw what could be behind a wall)
			end
			if hit == nil or (hit.Instance and hit.Instance:IsDescendantOf(char)) then
				return true
			end
		end
	end
	return false
end

-- visuals ------------------------------------------------------------------------------------------------------------------

local function frame(parent, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = parent
	return f
end

local function line(parent, name)
	local f = frame(parent, name)
	f.BackgroundTransparency = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	return f
end

local function text(parent, name)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Font = Enum.Font.GothamBold
	t.TextStrokeTransparency = 0.4
	t.Size = UDim2.fromOffset(240, 16)
	t.Visible = false
	t.Parent = parent
	return t
end

local function newSet(key)
	local root = frame(state.gui, key)
	root.Visible = true
	local set = { root = root, key = key, lines = {}, corners = {} }
	set.box = frame(root, "Box")
	local stroke = Instance.new("UIStroke")
	stroke.Parent = set.box
	set.stroke = stroke
	for i = 1, 8 do
		set.corners[i] = line(root, "Corner" .. i)
	end
	set.name = text(root, "Name")
	set.info = text(root, "Info")
	set.info.AnchorPoint = Vector2.new(0.5, 0)
	set.tag = text(root, "Weapon")
	set.hpBack = line(root, "HealthBack")
	set.hpBack.AnchorPoint = Vector2.new(0, 0)
	set.hpFill = line(root, "HealthFill")
	set.hpFill.AnchorPoint = Vector2.new(0, 1)
	set.tracer = line(root, "Tracer")
	set.arrow = text(root, "Arrow")
	set.arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	set.arrow.Text = "▲"
	return set
end

local function hideSet(set)
	for _, o in ipairs({ set.box, set.name, set.info, set.tag, set.hpBack, set.hpFill, set.tracer, set.arrow }) do
		o.Visible = false
	end
	for _, c in ipairs(set.corners) do
		c.Visible = false
	end
	if set.highlight then
		set.highlight.Enabled = false
	end
end

local function destroySet(set)
	pcall(function()
		set.root:Destroy()
	end)
	if set.highlight then
		pcall(function()
			set.highlight:Destroy()
		end)
	end
end

local function setLine(f, x1, y1, x2, y2, thick, color, tr)
	local dx, dy = x2 - x1, y2 - y1
	f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thick)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BackgroundColor3, f.BackgroundTransparency = color, tr
	f.Visible = true
end

local function project(cam, p)
	local ok, v, on = pcall(function()
		return cam:WorldToViewportPoint(p)
	end)
	if not ok then
		return nil
	end
	return v, on
end

-- draw(set, t): one target. t: { char, name, color, role, weapon, dist, test }
local function draw(set, t, cam, vp)
	local char = t.char
	local head = char:FindFirstChild("Head")
	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or head
	if not root then
		hideSet(set)
		return false
	end
	local top = (head and head.Position or root.Position + Vector3.new(0, 2, 0)) + Vector3.new(0, 1, 0)
	local bottom = root.Position - Vector3.new(0, 3, 0)
	local a, onA = project(cam, top)
	local b, onB = project(cam, bottom)
	local fade = s("fade") and math.clamp(1 - (t.dist / s("maxDistance")) * 0.6, 0.35, 1) or 1
	local tr = 1 - s("opacity") * fade
	local color = t.color
	if not a or not b or a.Z <= 0 or b.Z <= 0 or not (onA or onB) then
		hideSet(set)
		-- off-screen arrow: test mannequins only (never for real players)
		if t.test and s("offscreen") and a and b then
			local cx, cy = vp.X / 2, vp.Y / 2
			local px, py = (a.X + b.X) / 2 - cx, (a.Y + b.Y) / 2 - cy
			if a.Z <= 0 then
				px, py = -px, -py
			end
			local ang = math.atan2(py, px)
			local r = math.min(vp.X, vp.Y) / 2 - 40
			set.arrow.Position = UDim2.fromOffset(cx + math.cos(ang) * r, cy + math.sin(ang) * r)
			set.arrow.Rotation = math.deg(ang) + 90
			set.arrow.TextColor3, set.arrow.TextTransparency, set.arrow.TextSize = color, tr, 22
			set.arrow.Visible = true
		end
		return false
	end
	set.arrow.Visible = false
	local h = math.max(math.abs(b.Y - a.Y), 6)
	local w = h * 0.55
	local x, y = (a.X + b.X) / 2 - w / 2, math.min(a.Y, b.Y)
	local thick = s("thickness")
	-- box
	local style = s("boxStyle")
	set.box.Visible = s("box") and style == "Full"
	if set.box.Visible then
		set.box.Position, set.box.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
		set.stroke.Color, set.stroke.Thickness, set.stroke.Transparency = color, thick, tr
	end
	local cornerOn = s("box") and style == "Corner"
	if cornerOn then
		local cl = math.max(4, math.min(w, h) * 0.25)
		local pts = {
			{ x, y, x + cl, y }, { x, y, x, y + cl }, { x + w, y, x + w - cl, y }, { x + w, y, x + w, y + cl },
			{ x, y + h, x + cl, y + h }, { x, y + h, x, y + h - cl }, { x + w, y + h, x + w - cl, y + h }, { x + w, y + h, x + w, y + h - cl },
		}
		for i, p in ipairs(pts) do
			setLine(set.corners[i], p[1], p[2], p[3], p[4], thick, color, tr)
		end
	else
		for _, c in ipairs(set.corners) do
			c.Visible = false
		end
	end
	local size = s("textSize")
	-- name (and the test role of a mannequin)
	set.name.Visible = s("names")
	if set.name.Visible then
		set.name.Text = t.role and (t.name .. " [" .. I18n.tr(t.role) .. "]") or t.name
		set.name.Position, set.name.TextSize = UDim2.fromOffset(x + w / 2, y - 2), size
		set.name.TextColor3, set.name.TextTransparency = color, tr
	end
	-- held weapon (visible tool in hand)
	set.tag.Visible = s("weaponTag") and t.weapon ~= nil
	if set.tag.Visible then
		set.tag.Text = I18n.tr(t.weapon == "Knife" and "Knife in hand" or t.weapon == "Gun" and "Gun in hand" or "Dropped gun")
		set.tag.Position, set.tag.TextSize = UDim2.fromOffset(x + w / 2, y - 2 - (set.name.Visible and size + 2 or 0)), size
		set.tag.TextColor3, set.tag.TextTransparency = t.weapon == "Knife" and KNIFE_COLOR or GUN_COLOR, tr
	end
	-- distance under the box
	set.info.Visible = s("distance")
	if set.info.Visible then
		set.info.Text = math.floor(t.dist + 0.5) .. " " .. I18n.tr("studs")
		set.info.Position, set.info.TextSize = UDim2.fromOffset(x + w / 2, y + h + 2), math.max(10, size - 2)
		set.info.TextColor3, set.info.TextTransparency = Color3.fromRGB(230, 230, 235), tr
	end
	-- health bar (left of the box); no bar when the health cannot be read
	local hum = char:FindFirstChildOfClass("Humanoid")
	local frac = nil
	if hum and tonumber(hum.MaxHealth) and hum.MaxHealth > 0 and tonumber(hum.Health) then
		frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
	end
	set.hpBack.Visible = s("health") and frac ~= nil
	set.hpFill.Visible = set.hpBack.Visible
	if set.hpBack.Visible then
		set.hpBack.Position, set.hpBack.Size = UDim2.fromOffset(x - 5, y), UDim2.fromOffset(3, h)
		set.hpBack.BackgroundColor3, set.hpBack.BackgroundTransparency = Color3.fromRGB(0, 0, 0), math.min(1, tr + 0.3)
		set.hpFill.Position, set.hpFill.Size = UDim2.fromOffset(x - 5, y + h), UDim2.fromOffset(3, h * frac)
		set.hpFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(80, 230, 110), frac)
		set.hpFill.BackgroundTransparency = tr
	end
	-- tracer from the chosen screen point to the feet
	if s("tracers") then
		local ox = vp.X / 2
		local oy = ({ Bottom = vp.Y, Center = vp.Y / 2, Top = 0 })[s("tracerOrigin")] or vp.Y
		setLine(set.tracer, ox, oy, x + w / 2, y + h, math.max(1, thick - 0.5), color, math.min(1, tr + 0.15))
	else
		set.tracer.Visible = false
	end
	-- highlight: only the visible parts light up (Occluded), one per target, reused
	if s("highlight") then
		if not set.highlight then
			pcall(function()
				local hl = Instance.new("Highlight")
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.Parent = state.hlFolder
				set.highlight = hl
			end)
		end
		if set.highlight then
			set.highlight.Adornee = char
			set.highlight.FillColor, set.highlight.OutlineColor = color, color
			set.highlight.FillTransparency = math.clamp(1 - (1 - tr) * 0.45, 0, 1)
			set.highlight.OutlineTransparency = tr
			set.highlight.Enabled = true
		end
	elseif set.highlight then
		set.highlight.Enabled = false
	end
	return true
end

-- update ---------------------------------------------------------------------------------------------------------------------

local function gather(cam)
	local camPos = cam.CFrame.Position
	local out = {}
	local maxD = s("maxDistance")
	if s("players") then
		for _, p in ipairs(playerTargets()) do
			local char = p.character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
			if root and (not hum or (tonumber(hum.Health) or 1) > 0) then
				local d = (root.Position - camPos).Magnitude
				if d <= maxD then
					table.insert(out, { key = p.key, char = char, name = p.name, dist = d, test = false })
				end
			end
		end
	end
	if s("mannequins") then
		for _, m in ipairs(MurderTrainer.list()) do
			if m.alive and m.model then
				local d = (m.position - camPos).Magnitude
				if d <= maxD then
					table.insert(out, { key = "M:" .. m.id, char = m.model, name = m.id, role = m.role, dist = d, test = true })
				end
			end
		end
	end
	if s("gunDrop") then
		local gun = state.gunDrop
		if gun and gun.Parent then
			local part = gun:IsA("BasePart") and gun or gun:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local d = (part.Position - camPos).Magnitude
				if d <= maxD then
					table.insert(out, { key = "G:drop", char = gun, part = part, name = I18n.tr("Dropped gun"), dist = d, test = false, item = true })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	return out
end

-- the dropped gun is looked up once a second (a search of the whole map every frame would be wasteful)
local function findGunDrop()
	if not state or not s("gunDrop") then
		return
	end
	local name = s("gunDropName")
	local ok, found = pcall(function()
		return Services.Workspace:FindFirstChild(name, true)
	end)
	state.gunDrop = ok and found or nil
end

-- item marker: a label and distance at the item, only while it is in sight
local function drawItem(set, t, cam)
	local v, on = project(cam, t.part.Position)
	if not v or v.Z <= 0 or not on then
		hideSet(set)
		return false
	end
	hideSet(set)
	local size = s("textSize")
	set.tag.Text = t.name
	set.tag.Position, set.tag.TextSize = UDim2.fromOffset(v.X, v.Y - 6), size
	set.tag.TextColor3, set.tag.TextTransparency, set.tag.Visible = GUN_COLOR, 1 - s("opacity"), true
	if s("distance") then
		set.info.Text = math.floor(t.dist + 0.5) .. " " .. I18n.tr("studs")
		set.info.Position, set.info.TextSize = UDim2.fromOffset(v.X, v.Y), math.max(10, size - 2)
		set.info.TextColor3, set.info.TextTransparency, set.info.Visible = Color3.fromRGB(230, 230, 235), 1 - s("opacity"), true
	end
	return true
end

-- itemInSight(part): nothing solid between the camera and the item
local function itemInSight(item, part)
	local cam = Services.Workspace.CurrentCamera
	local from = cam.CFrame.Position
	local lp = Services.Players.LocalPlayer
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { cam, lp and lp.Character }
		return Services.Workspace:Raycast(from, part.Position - from, params)
	end)
	return ok and (hit == nil or (hit.Instance and (hit.Instance == item or hit.Instance:IsDescendantOf(item))))
end

function ESP.update()
	if not state then
		return
	end
	local cam = Services.Workspace.CurrentCamera
	if not s("enabled") or not cam then
		for key, set in pairs(state.sets) do
			destroySet(set)
			state.sets[key] = nil
		end
		state.drawn, state.hidden = 0, 0
		return
	end
	local vp = cam.ViewportSize
	local seen = {}
	local drawn, hidden = 0, 0
	local limit = s("maxTargets")
	for _, t in ipairs(gather(cam)) do
		if drawn >= limit then
			break
		end
		local visibleNow = t.test or (t.item and itemInSight(t.char, t.part)) or (not t.item and ESP.inSight(t.char))
		if visibleNow then
			if t.item then
				t.color = GUN_COLOR
			elseif t.test then
				t.color = s("roleColors") and ROLE_COLOR[t.role] or rgb("color")
			else
				t.weapon = ESP.heldWeapon(t.char)
				t.color = (s("weaponColors") and t.weapon == "Knife" and KNIFE_COLOR) or (s("weaponColors") and t.weapon == "Gun" and GUN_COLOR) or rgb("color")
			end
			local set = state.sets[t.key] or newSet(t.key)
			state.sets[t.key] = set
			seen[t.key] = true
			if (t.item and drawItem(set, t, cam)) or (not t.item and draw(set, t, cam, vp)) then
				drawn += 1
			end
		else
			hidden += 1 -- out of sight: nothing drawn (its set is removed below)
		end
	end
	for key, set in pairs(state.sets) do
		if not seen[key] then
			destroySet(set)
			state.sets[key] = nil
		end
	end
	state.drawn, state.hidden = drawn, hidden
end

function ESP.status()
	if not state then
		return { running = false }
	end
	local sets = 0
	for _ in pairs(state.sets) do
		sets += 1
	end
	return { running = true, enabled = s("enabled"), drawn = state.drawn or 0, hiddenBySight = state.hidden or 0, sets = sets }
end

-- clear(): removes every ESP object now (they are rebuilt on the next update when ESP is on)
function ESP.clear()
	if not state then
		return
	end
	for key, set in pairs(state.sets) do
		destroySet(set)
		state.sets[key] = nil
	end
end

function ESP.start(ctx)
	assert(state == nil, "ESP already started")
	local parent = Env.guiParent()
	if not parent then
		error("no GUI container available for ESP")
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubESP"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = parent
	ctx.maid:Give(gui)
	local hlFolder = Instance.new("Folder")
	hlFolder.Name = "MM2HubESPHighlights"
	hlFolder.Parent = parent
	ctx.maid:Give(hlFolder)
	state = { gui = gui, hlFolder = hlFolder, sets = {}, drawn = 0, hidden = 0 }
	ctx.maid:Give(function()
		ESP.clear()
		sourceOverride = nil
		state = nil
	end)
	local handle = nil
	local function schedule()
		if handle then
			handle.Cancel()
		end
		handle = Perf.every("esp", s("hz"), function()
			local ok, err = pcall(ESP.update)
			if not ok then
				Logger.error("ESP", "update failed: %s", tostring(err))
			end
		end, { visual = true })
	end
	schedule()
	ctx.maid:Give(Settings.observe("esp.hz", schedule))
	local finder = Perf.every("esp.items", 1, findGunDrop)
	ctx.maid:Give(finder.Cancel)
	ctx.maid:Give(function()
		if handle then
			handle.Cancel()
		end
	end)
end

return ESP

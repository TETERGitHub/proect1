--!nonstrict
-- ui/ScreenButtons: starred features as floating round buttons (made for phones, usable anywhere).
-- Tap runs the feature (toggles a switch / runs an action) and the ring shows the on/off state;
-- drag to move, positions are remembered. Icons are drawn from Frames. Buttons are rebuilt only
-- when the favourites list, size or visibility change; state rings update through Settings observers.
-- Depends on: Framework, Theme, Icons, Motion, Settings, Recents, Registry, Actions, Env, Maid, Services.

local import = ...
local F = import("ui/Framework")
local Theme = import("ui/Theme")
local Icons = import("ui/Icons")
local Motion = import("ui/Motion")
local Settings = import("core/Settings")
local Recents = import("core/Recents")
local Registry = import("core/Registry")
local Actions = import("core/Actions")
local Env = import("core/Env")
local Maid = import("core/Maid")
local Services = import("core/Services")
local Logger = import("core/Logger")

local Buttons = {}

local state = nil

local CATEGORY_ICON = { crosshair = "target", camera = "camera", lighting = "sun", training = "bolt", perf = "gauge", ui = "sliders", cosmetics = "shirt", music = "music", sounds = "speaker", tools = "timer" }
local MAX_BUTTONS = 8

-- iconFor(feature) -> icon name
function Buttons.iconFor(feat)
	if feat.impl.kind == "setting" and Settings.has(feat.impl.target) then
		return CATEGORY_ICON[Settings.schema(feat.impl.target).category] or "star"
	end
	if feat.impl.kind == "action" then
		local id = feat.impl.target
		if string.find(id, "window", 1, true) then
			return "home"
		elseif string.find(id, "music", 1, true) then
			return "music"
		end
	end
	return CATEGORY_ICON[string.lower(feat.cat)] or "bolt"
end

-- isOn(feature) -> boolean|nil  (nil = not a switch)
function Buttons.isOn(feat)
	if feat.impl.kind == "setting" and Settings.has(feat.impl.target) and Settings.schema(feat.impl.target).type == "bool" then
		return Settings.get(feat.impl.target)
	end
	return nil
end

-- press(feature): toggle a switch or run an action; other settings open the hub on their page.
function Buttons.press(feat)
	if feat.impl.kind == "setting" and Settings.schema(feat.impl.target).type == "bool" then
		Settings.toggle(feat.impl.target, "screen-button")
	elseif feat.impl.kind == "action" then
		Actions.run(feat.impl.target)
	else
		local Window = import("ui/Window")
		Window.show()
		local pageId, key = Window.pageForItem({ settingKey = feat.impl.kind == "setting" and feat.impl.target or nil, category = feat.cat })
		Window.navigate(pageId, key)
	end
	Recents.touch(feat.id)
end

local function savedPositions()
	local map = {}
	for _, entry in ipairs(Settings.get("state.buttonPos")) do
		local id, x, y = string.match(entry, "^(.-)|(%-?%d+)|(%-?%d+)$")
		if id then
			map[id] = { tonumber(x), tonumber(y) }
		end
	end
	return map
end

local function savePosition(id, x, y)
	local list = {}
	for _, entry in ipairs(Settings.get("state.buttonPos")) do
		if string.match(entry, "^(.-)|") ~= id then
			table.insert(list, entry)
		end
	end
	table.insert(list, string.format("%s|%d|%d", id, x, y))
	Settings.set("state.buttonPos", list, "screen-button")
end

local function viewport()
	local cam = Services.Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function rebuild()
	local st = state
	if not st then
		return
	end
	st.buttons:Clean()
	table.clear(st.rings)
	if not Settings.get("ui.screenButtons") then
		st.holder.Visible = false
		return
	end
	st.holder.Visible = true
	local size = Settings.get("ui.screenButtonSize")
	local vp = viewport()
	local saved = savedPositions()
	local shown = 0
	for _, id in ipairs(Recents.favorites()) do
		local feat = Registry.get(id)
		if feat and shown < MAX_BUTTONS then
			shown += 1
			local pos = saved[id] or { vp.X - size - 14, 80 + (shown - 1) * (size + 10) }
			pos = { math.clamp(pos[1], 0, math.max(0, vp.X - size)), math.clamp(pos[2], 0, math.max(0, vp.Y - size - 36)) }
			local b = Instance.new("TextButton")
			b.Name = "Pin_" .. id
			b.Text = ""
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Size = UDim2.fromOffset(size, size)
			b.Position = UDim2.fromOffset(pos[1], pos[2])
			b.BackgroundTransparency = 1 - Settings.get("ui.screenButtonOpacity")
			Theme.bind(b, "BackgroundColor3", "bg1")
			F.pillCorner(b)
			local ring = F.stroke(b, "stroke", 2, 0.3)
			local icon = Icons.draw(b, Buttons.iconFor(feat), math.floor(size * 0.5), "text")
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			b.Parent = st.holder
			st.buttons:Give(b)
			Motion.pressable(b, st.buttons, 0.08)
			st.rings[id] = { ring = ring, feat = feat, icon = icon }

			local moved = false
			st.buttons:Give(b.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local start = input.Position
					local x0, y0 = b.AbsolutePosition.X, b.AbsolutePosition.Y
					moved = false
					F.beginDrag(function(p)
						local dx, dy = p.X - start.X, p.Y - start.Y
						if moved or math.abs(dx) + math.abs(dy) > 9 then
							moved = true
							local v = viewport()
							b.Position = UDim2.fromOffset(math.clamp(x0 + dx, 0, v.X - size), math.clamp(y0 + dy, 0, v.Y - size - 36))
						end
					end, function()
						if moved then
							savePosition(id, b.Position.X.Offset, b.Position.Y.Offset)
						end
					end)
				end
			end))
			st.buttons:Give(b.Activated:Connect(function()
				if moved then
					moved = false
					return
				end
				F.click()
				Buttons.press(feat)
			end))
		end
	end
	Buttons.refreshRings()
end

-- refreshRings(): accent ring on enabled switches, dim ring otherwise
function Buttons.refreshRings()
	if not state then
		return
	end
	for _, r in pairs(state.rings) do
		local on = Buttons.isOn(r.feat)
		Theme.bind(r.ring, "Color", on and "accent" or "stroke")
		r.ring.Transparency = on and 0 or 0.3
		r.ring.Thickness = on and 3 or 2
		Icons.recolor(r.icon, on and "accent" or "text")
	end
end

function Buttons.count()
	if not state or not state.holder.Visible then
		return 0
	end
	return #state.holder:GetChildren()
end

function Buttons.button(id)
	return state and state.holder:FindFirstChild("Pin_" .. id) or nil
end

function Buttons.start(ctx)
	assert(state == nil, "ScreenButtons already started")
	local parent = Env.guiParent()
	if not parent then
		error("no GUI container for the on-screen buttons")
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 9
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	ctx.maid:Give(gui)
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	state = { gui = gui, holder = holder, buttons = Maid.new("screen-buttons"), rings = {} }
	ctx.maid:Give(function()
		if state then
			state.buttons:Clean()
		end
		state = nil
	end)
	for _, key in ipairs({ "ui.screenButtons", "ui.screenButtonSize", "ui.screenButtonOpacity", "state.favorites" }) do
		ctx.maid:Give(Settings.observe(key, rebuild))
	end
	ctx.maid:Give(Settings.Changed:Connect(function(key)
		if state and string.sub(key, 1, 3) ~= "ui." and string.sub(key, 1, 6) ~= "state." then
			Buttons.refreshRings()
		elseif state and key == "ui.theme" then
			Buttons.refreshRings()
		end
	end))
	rebuild()
	Logger.info("ScreenButtons", "ready (%d pinned)", Buttons.count())
end

function Buttons.isRunning()
	return state ~= nil
end

return Buttons

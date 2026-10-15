--!nonstrict
-- ui/Watermark: an always-on-top badge on your own screen: the mascot, your text (default "TrollHub") with animated "flowing"
-- colour (ui/Shimmer), and optional FPS, ping and clock. Everything is a setting on the Watermark page: text, position, size,
-- the glass background, which stats are shown, flow style / direction / speed and your own colours. Local to this client.
-- STATUS: implemented; verified against the mock layer only (the look has not been checked in Roblox).
-- Depends on: Settings, Env, Perf, Logger, Theme, Shimmer, Flair.

local import = ...
local Settings = import("core/Settings")
local Env = import("core/Env")
local Perf = import("core/Perf")
local Logger = import("core/Logger")
local Theme = import("ui/Theme")
local Shimmer = import("ui/Shimmer")
local Flair = import("ui/Flair")

local Watermark = {}

Watermark.POSITIONS = { "TopLeft", "TopCenter", "TopRight", "BottomLeft", "BottomRight" }
local ANCHOR = {
	TopLeft = { 0, 0, 0, 0, 14, 14 },
	TopCenter = { 0.5, 0, 0.5, 0, 0, 14 },
	TopRight = { 1, 0, 1, 0, -14, 14 },
	BottomLeft = { 0, 1, 0, 1, 14, -14 },
	BottomRight = { 1, 1, 1, 1, -14, -14 },
}

local state = nil

local function s(name)
	return Settings.get("watermark." .. name)
end

-- shimmerConfig() -> the flow settings shared by the watermark and (optionally) the menu title
function Watermark.shimmerConfig()
	local colors
	if s("themeColors") then
		local a = Theme.rgb("accent")
		colors = { a, { r = 255, g = 255, b = 255 }, a }
	else
		colors = { s("color1"), s("color2"), s("color3") }
	end
	return { style = s("style"), direction = s("direction"), speed = s("speed"), colors = colors }
end

-- text() -> the line shown, e.g. "TrollHub | 60 FPS | 45 ms | 21:04"
function Watermark.text()
	local parts = { (s("text") ~= "" and s("text")) or "TrollHub" }
	if s("showFps") then
		table.insert(parts, string.format("%d FPS", Perf.fps() + 0.5))
	end
	if s("showPing") then
		local p = Perf.ping()
		table.insert(parts, p and string.format("%d ms", p + 0.5) or "— ms")
	end
	if s("showTime") then
		table.insert(parts, os.date("%H:%M"))
	end
	return table.concat(parts, "  |  ")
end

local function layout()
	if not state then
		return
	end
	local a = ANCHOR[s("position")] or ANCHOR.TopLeft
	state.frame.AnchorPoint = Vector2.new(a[1], a[2])
	state.frame.Position = UDim2.new(a[3], a[5], a[4], a[6])
	state.scale.Scale = s("size")
	state.frame.Visible = s("enabled")
	state.frame.BackgroundTransparency = s("background") and 0.25 or 1
	state.rim.Enabled = s("background")
	state.mascot.Visible = s("sticker")
	state.label.Position = UDim2.fromOffset(s("sticker") and 40 or 12, 0)
	state.label.Font = Theme.font(true)
end

local function refreshText()
	if not state or not s("enabled") then
		return
	end
	local text = Watermark.text()
	if state.label.Text ~= text then
		state.label.Text = text
		local w = state.label.TextBounds.X
		if w <= 0 then
			w = #text * 7.5 -- TextBounds is 0 before the first render
		end
		state.frame.Size = UDim2.fromOffset(math.floor(w + (s("sticker") and 54 or 26)), 34)
	end
end

function Watermark.isVisible()
	return state ~= nil and state.frame.Visible
end

function Watermark.label()
	return state and state.label
end

function Watermark.start(ctx)
	assert(state == nil, "Watermark already started")
	local parent = Env.guiParent()
	if not parent then
		error("no GUI container for the watermark")
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubWatermark"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	ctx.maid:Give(gui)

	local frame = Instance.new("Frame")
	frame.Name = "Watermark"
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Size = UDim2.fromOffset(180, 34)
	frame.Parent = gui
	Theme.bind(frame, "BackgroundColor3", "bg0")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 17)
	corner.Parent = frame
	local rim = Instance.new("UIStroke")
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Color3.fromRGB(255, 255, 255)
	local rg = Instance.new("UIGradient")
	rg.Rotation = 90
	rg.Transparency = NumberSequence.new(0.1, 0.55)
	Theme.bind(rg, "Color", function()
		return Theme.edgeColors()
	end)
	rg.Parent = rim
	rim.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local mascot = Flair.mascot(frame, 28)
	mascot.AnchorPoint = Vector2.new(0, 0.5)
	mascot.Position = UDim2.new(0, 7, 0.5, 0)
	mascot.Rotation = -8

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, 0)
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 255, 255) -- the flow gradient colours it
	label.Text = ""
	label.Parent = frame
	local shadow = Instance.new("UIStroke")
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Transparency = 0.6
	shadow.Parent = label
	Shimmer.attach(label, ctx.maid, Watermark.shimmerConfig)

	state = { gui = gui, frame = frame, label = label, rim = rim, scale = scale, mascot = mascot }
	ctx.maid:Give(function()
		state = nil
	end)
	for _, key in ipairs(Settings.keys({ module = "Watermark", includeHidden = true })) do
		ctx.maid:Give(Settings.observe(key, function()
			layout()
			if state then
				state.label.Text = "" -- force a re-measure
			end
			refreshText()
		end))
	end
	ctx.maid:Give(Theme.Changed:Connect(layout))
	local handle = Perf.every("ui.watermark", 2, refreshText, { visual = true })
	ctx.maid:Give(handle.Cancel)
	layout()
	refreshText()
	Logger.info("Watermark", "ready")
end

return Watermark

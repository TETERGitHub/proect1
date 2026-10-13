--!nonstrict
-- ui/LicenseGate: small activation window shown before the hub starts when the build requires a key.
-- Drawn from Frames only. Calls onActivated() after a valid key was accepted.
-- Depends on: License, Env, Services, Logger, Theme-free (own fixed dark palette: no settings exist yet).

local import = ...
local License = import("core/License")
local Env = import("core/Env")
local Logger = import("core/Logger")
local Maid = import("core/Maid")

local Gate = {}

local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

-- show(onActivated) -> handle with Destroy()
function Gate.show(onActivated)
	local parent = Env.guiParent()
	if not parent then
		return nil, "no GUI container"
	end
	local maid = Maid.new("license-gate")
	local gui = make("ScreenGui", { Name = "MM2HubLicense", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, parent)
	maid:Give(gui)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, gui)
	local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 250), BackgroundColor3 = Color3.fromRGB(28, 28, 30), BorderSizePixel = 0 }, back)
	corner(card, 22)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.84, Thickness = 1.2 }, card)
	local scale = make("UIScale", { Scale = 0.9 }, card)
	pcall(function()
		game:GetService("TweenService"):Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 20), Size = UDim2.new(1, -48, 0, 26), Text = "MM2 Hub", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Left }, card)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 50), Size = UDim2.new(1, -48, 0, 34), Text = "Enter your licence key to continue.", Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(174, 174, 178), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, card)
	local box = make("TextBox", { Position = UDim2.fromOffset(24, 96), Size = UDim2.new(1, -48, 0, 42), BackgroundColor3 = Color3.fromRGB(58, 58, 60), BorderSizePixel = 0, Text = "", PlaceholderText = "MM2H-XXXXX-XXXXX-...", PlaceholderColor3 = Color3.fromRGB(140, 140, 145), TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamMedium, TextSize = 14, ClearTextOnFocus = false }, card)
	corner(box, 12)
	local status = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 146), Size = UDim2.new(1, -48, 0, 20), Text = "", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(255, 69, 58), TextXAlignment = Enum.TextXAlignment.Left }, card)
	local button = make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.new(1, -48, 0, 44), BackgroundColor3 = Color3.fromRGB(10, 132, 255), BorderSizePixel = 0, Text = "Activate", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255), AutoButtonColor = false }, card)
	corner(button, 14)

	local busy = false
	local function submit()
		if busy then
			return
		end
		busy = true
		local ok, res = License.activate(box.Text)
		if ok and not (type(res) == "table" and res.needsActivation) then
			status.TextColor3 = Color3.fromRGB(48, 209, 88)
			status.Text = "Valid. Time left: " .. License.formatRemaining(res.remaining)
			task.delay(0.6, function()
				maid:Clean()
				onActivated(res)
			end)
			return
		end
		status.TextColor3 = Color3.fromRGB(255, 69, 58)
		status.Text = tostring(ok and "activation failed" or res)
		Logger.warn("License", "activation rejected: %s", tostring(ok and "activation failed" or res))
		busy = false
	end
	maid:Give(button.Activated:Connect(submit))
	maid:Give(box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end))
	return { Destroy = function() maid:Clean() end }
end

return Gate

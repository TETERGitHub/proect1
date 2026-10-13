--!nonstrict
-- loader/main: entry of dist/Loader.lua. Wires the real executor APIs into Loader.run.
-- STATUS: environment-dependent (needs an HTTP request function and loadstring in the executor).
local import = ...
local Loader = import("loader/Loader")
local Ru = import("core/LicenseText")

local SERVER_URL = "@@SERVER_URL@@"
local KEY_PATH = "MM2Hub/license.key"

local function firstFunction(...)
	for _, getter in ipairs({ ... }) do
		local ok, f = pcall(getter)
		if ok and type(f) == "function" then
			return f
		end
	end
	return nil
end

local request = firstFunction(
	function() return request end,
	function() return http_request end,
	function() return syn and syn.request end,
	function() return http and http.request end,
	function() return fluxus and fluxus.request end
)
local compile = firstFunction(function() return loadstring end, function() return load end)
local write = firstFunction(function() return writefile end)
local read = firstFunction(function() return readfile end)
local exists = firstFunction(function() return isfile end)
local mkdir = firstFunction(function() return makefolder end)
local hui = firstFunction(function() return gethui end)

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
	end)
end

if not request or not compile then
	notify("MM2 Hub", "В этом исполнителе нет HTTP-запросов или loadstring: загрузчик с лицензией не сможет работать.")
	return nil
end

local function prompt(onSubmit, lastError)
	local parent = (hui and hui()) or game:GetService("CoreGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubKey"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = parent
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(400, 200)
	card.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
	card.BorderSizePixel = 0
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 20)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(20, 14)
	label.Size = UDim2.new(1, -40, 0, 50)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = lastError and Color3.fromRGB(255, 69, 58) or Color3.fromRGB(235, 235, 245)
	label.Text = lastError and Ru.ru(lastError) or (Ru.UI.title .. " — " .. Ru.UI.pasteHint)
	label.Parent = card
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(20, 76)
	box.Size = UDim2.new(1, -40, 0, 40)
	box.BackgroundColor3 = Color3.fromRGB(58, 58, 60)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(255, 255, 255)
	box.PlaceholderText = Ru.UI.placeholder
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = card
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -18)
	button.Size = UDim2.new(1, -40, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(10, 132, 255)
	button.BorderSizePixel = 0
	button.Text = Ru.UI.button
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = false
	button.Parent = card
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)
	local done = false
	local function submit()
		if done then
			return
		end
		done = true
		gui:Destroy()
		onSubmit(box.Text)
	end
	button.Activated:Connect(submit)
	box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
end

return Loader.run({
	request = request,
	loadstring = compile,
	readKey = function()
		if read and exists then
			local ok, present = pcall(exists, KEY_PATH)
			if ok and present then
				local okr, text = pcall(read, KEY_PATH)
				return okr and text or nil
			end
		end
		return nil
	end,
	writeKey = function(text)
		if write then
			if mkdir then
				pcall(mkdir, "MM2Hub")
			end
			pcall(write, KEY_PATH, text)
		end
	end,
	prompt = prompt,
	uid = game:GetService("Players").LocalPlayer.UserId,
	notify = notify,
	clock = os.clock,
	spawn = task.spawn,
	wait = task.wait,
	log = function(text)
		print("[MM2Hub] " .. text)
	end,
	serverUrl = SERVER_URL,
	heartbeat = 300,
})

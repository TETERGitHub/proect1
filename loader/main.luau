--!nonstrict
-- loader/main: entry of dist/Loader.lua. Wires the real executor APIs into Loader.run.
-- STATUS: environment-dependent (needs an HTTP request function and loadstring in the executor).
local import = ...
local Loader = import("loader/Loader")
local Ru = import("core/LicenseText")
local KeyCard = import("ui/KeyCard")

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

-- prompt(onSubmit, lastError) -> handle { busy(bool), fail(message), close() }
-- One window for the whole session: a refused key shows its message in the same card instead of opening a new one.
local function prompt(onSubmit, lastError)
	local parent = (hui and hui()) or game:GetService("CoreGui")
	local stale = parent:FindFirstChild("MM2HubKey")
	if stale then
		stale:Destroy() -- a second run of the loader must not stack key windows
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubKey"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = parent
	local card
	card = KeyCard.build(gui, {
		title = Ru.UI.title,
		prompt = Ru.UI.pasteHint,
		placeholder = Ru.UI.placeholder,
		button = Ru.UI.button,
		busy = Ru.UI.checking,
		onSubmit = function(text)
			card.setBusy(true)
			onSubmit(text)
		end,
	})
	if lastError then
		card.setStatus(Ru.ru(lastError), "error")
	end
	card.focus()
	return {
		busy = function(on)
			card.setBusy(on)
		end,
		fail = function(message)
			card.setBusy(false)
			card.setStatus(Ru.ru(message), "error")
			card.focus()
		end,
		close = function()
			card.destroy()
			gui:Destroy()
		end,
	}
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
	uid = (function()
		-- LocalPlayer can still be nil when the script is injected very early
		local players = game:GetService("Players")
		local me = players.LocalPlayer
		for _ = 1, 100 do
			if me then
				break
			end
			task.wait(0.1)
			me = players.LocalPlayer
		end
		-- no player -> no uid: the server answers "account id required" instead of binding the key to a fake account
		return me and me.UserId or nil
	end)(),
	notify = notify,
	clock = os.time, -- wall clock: os.clock is process CPU time and would let a term run longer than it should
	spawn = task.spawn,
	wait = task.wait,
	log = function(text)
		print("[MM2Hub] " .. text)
	end,
	serverUrl = SERVER_URL,
	heartbeat = 300,
})

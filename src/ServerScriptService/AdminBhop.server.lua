--[[
	AdminBhop (сервер)

	Выдаёт клиентский скрипт бхопа ТОЛЬКО админам и сохраняет их настройки в DataStore.
	Обычные игроки не получают ничего: ни скрипта, ни remote, ни атрибутов —
	снаружи админ выглядит как обычный игрок.

	Куда класть:
	  - этот Script            -> ServerScriptService
	  - LocalScript AdminBhopClient -> ServerStorage
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- ================== КОНФИГ ==================

-- Впиши сюда свой UserId (и друзей, если надо)
local ADMINS = {
	-- [123456789] = true,
}

-- Если игра принадлежит группе: все с рангом >= MinRank считаются админами
local ADMIN_GROUP = {
	Id = 0, -- 0 = выключено
	MinRank = 255,
}

-- Владелец места (если игра на личном аккаунте) — всегда админ
local OWNER_IS_ADMIN = true

-- В Studio все игроки — админы (удобно для тестов)
local ADMIN_IN_STUDIO = true

local DATASTORE_NAME = "AdminBhop_v1"

-- ============================================

local clientTemplate = ServerStorage:WaitForChild("AdminBhopClient")

-- Серверный список активных админов. Нигде не реплицируется — клиенты о нём не знают.
local activeAdmins = {}

-- Проверка для твоего античита (ServerStorage клиентам не виден):
--   local check = game.ServerStorage:WaitForChild("AdminBhopCheck")
--   if check:Invoke(player) then return end -- не кикать за скорость
local check = Instance.new("BindableFunction")
check.Name = "AdminBhopCheck"
check.OnInvoke = function(player)
	return activeAdmins[player] == true
end
check.Parent = ServerStorage

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[AdminBhop] DataStore недоступен (включи API Services в Studio):", result)
	end
end

local function isAdmin(player)
	if ADMINS[player.UserId] then
		return true
	end
	if OWNER_IS_ADMIN and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if ADMIN_GROUP.Id ~= 0 then
		local ok, rank = pcall(player.GetRankInGroup, player, ADMIN_GROUP.Id)
		if ok and rank >= ADMIN_GROUP.MinRank then
			return true
		end
	end
	if ADMIN_IN_STUDIO and RunService:IsStudio() then
		return true
	end
	return false
end

-- Чистим то, что прислал клиент: только простые ключи и значения
local function sanitize(data)
	if typeof(data) ~= "table" then
		return nil
	end
	local out, count = {}, 0
	for k, v in pairs(data) do
		if typeof(k) == "string" and #k <= 32 and k:match("^%a+$") then
			local t = typeof(v)
			if t == "boolean" then
				out[k] = v
			elseif t == "number" and v == v and math.abs(v) < 1e5 then
				out[k] = v
			elseif t == "string" and #v <= 32 and v:match("^%w+$") then
				out[k] = v
			else
				continue
			end
			count += 1
			if count >= 64 then
				break
			end
		end
	end
	return out
end

local lastSave = {}

local function handleRequest(player, action, data)
	if not activeAdmins[player] then
		return false, "нет доступа"
	end
	if not store then
		return false, "DataStore недоступен"
	end
	local key = "u" .. player.UserId

	if action == "load" then
		local ok, result = pcall(store.GetAsync, store, key)
		if ok and typeof(result) == "table" then
			return true, result
		end
		return false, ok and "нет сохранения" or tostring(result)
	elseif action == "save" then
		local now = os.clock()
		if lastSave[player] and now - lastSave[player] < 6 then
			return false, "подожди пару секунд"
		end
		lastSave[player] = now
		local clean = sanitize(data)
		if not clean then
			return false, "битые данные"
		end
		local ok, err = pcall(store.SetAsync, store, key, clean)
		return ok, ok and "сохранено" or tostring(err)
	end
	return false, "неизвестное действие"
end

local function onPlayerAdded(player)
	if not isAdmin(player) then
		return
	end
	activeAdmins[player] = true

	-- Всё кладём в PlayerGui админа: он реплицируется только ему самому,
	-- другие игроки не видят ни скрипт, ни remote.
	local playerGui = player:WaitForChild("PlayerGui")
	local client = clientTemplate:Clone()
	client.Name = "ClientModule"

	local remote = Instance.new("RemoteFunction")
	remote.Name = "R"
	remote.OnServerInvoke = function(invoker, action, data)
		if invoker ~= player then
			return false, "нет доступа"
		end
		return handleRequest(invoker, action, data)
	end
	remote.Parent = client

	client.Parent = playerGui -- LocalScript прямо в PlayerGui не сбрасывается при респавне
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(p)
	lastSave[p] = nil
	activeAdmins[p] = nil
end)

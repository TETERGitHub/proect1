--!nonstrict
-- core/Services: lazy, cached access to Roblox services. Nothing is touched at load
-- time, so modules that depend on it can be imported (and unit-tested) without a
-- running game. Each service is fetched with pcall(GetService).

local Services = {}

local cache = {}

setmetatable(Services, {
	__index = function(_, name)
		local cached = cache[name]
		if cached ~= nil then
			return cached
		end
		local ok, svc = pcall(function()
			return game:GetService(name)
		end)
		if ok and svc ~= nil then
			cache[name] = svc
			return svc
		end
		return nil
	end,
})

-- Services.clear(): used by tests and on unload.
function Services.clear()
	table.clear(cache)
end

return Services

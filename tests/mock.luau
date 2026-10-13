-- tests/mock: minimal environment for running core logic under the standalone Luau CLI.
-- It only provides what the logic modules touch (task scheduler stub, no Roblox services).
-- The Roblox-dependent modules are exercised by tests/mock_roblox (loaded on demand).

if task == nil then
	local pending = {}
	task = {
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			coroutine.resume(co, ...)
			return co
		end,
		defer = function(fn, ...)
			table.insert(pending, { fn, ... })
		end,
		delay = function(_, fn, ...)
			table.insert(pending, { fn, ... })
		end,
		wait = function(t)
			return t or 0
		end,
		cancel = function() end,
		flush = function()
			local list = pending
			pending = {}
			for _, p in ipairs(list) do
				p[1](table.unpack(p, 2))
			end
		end,
	}
end

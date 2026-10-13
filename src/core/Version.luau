--!nonstrict
-- core/Version: version metadata, changelog, and settings-schema migrations.
-- Depends on: nothing.

local Version = {}

Version.VERSION = "1.0.0"
Version.SCHEMA = 1 -- bump when the exported config layout changes, then add a migration
Version.NAME = "MM2 Hub"

Version.changelog = {
	{
		version = "1.0.0",
		date = "2026-10-13",
		notesRu = {
			"Первый выпуск: модульное ядро (события, очистка, журнал, настройки, профили, ввод, планировщик, диагностика).",
			"Интерфейс: 8 тем (по умолчанию стеклянная iOS), перетаскиваемое и масштабируемое окно, поиск, избранное, недавнее.",
			"Визуал: свой прицел, управление камерой, локальное освещение и цветовые фильтры, локальная невидимость.",
			"Локальный полигон: мишени, физический манекен, лаборатория хитбокса, выбор цели (только на ваших объектах).",
			"Дрон-песочница, косметика, музыка, свои звуки, анти-флинг, инструменты (таймеры, секундомер, заметки).",
			"Телефон: компактный пресет, экранные кнопки, плавающая кнопка запуска.",
			"Ключи лицензии на срок, сервер проверки и загрузчик.",
		},
		notes = {
			"Initial release: modular core (Signal, Maid, Logger, Settings, Config, Input, Perf, Diagnostics).",
			"UI framework with 6 themes, draggable/resizable window, search, favorites, recents.",
			"Visuals: custom crosshair, camera controls, local lighting/colour filters.",
			"Local training range: target practice and physics stand (own objects only).",
			"Tools: session timer, stopwatch, countdown timers, notes.",
		},
	},
}

local migrations = {}

-- registerMigration(fromSchema, fn): fn(data) mutates/returns data at schema fromSchema+1.
function Version.registerMigration(from, fn)
	assert(type(from) == "number" and from % 1 == 0 and from >= 0, "from must be a non-negative integer")
	assert(type(fn) == "function", "migration must be a function")
	migrations[from] = fn
end

function Version.clearMigrations()
	table.clear(migrations)
end

-- migrate(data) -> data, notes, err. data.schema selects the starting point.
function Version.migrate(data)
	if type(data) ~= "table" then
		return nil, nil, "config is not a table"
	end
	local schema = data.schema
	if type(schema) ~= "number" or schema % 1 ~= 0 or schema < 0 then
		return nil, nil, "missing or invalid schema number"
	end
	if schema > Version.SCHEMA then
		return nil, nil, string.format("config schema %d is newer than supported %d", schema, Version.SCHEMA)
	end
	local notes = {}
	while schema < Version.SCHEMA do
		local fn = migrations[schema]
		if not fn then
			return nil, notes, string.format("no migration from schema %d", schema)
		end
		local ok, result = pcall(fn, data)
		if not ok then
			return nil, notes, string.format("migration %d failed: %s", schema, tostring(result))
		end
		if type(result) == "table" then
			data = result
		end
		schema += 1
		data.schema = schema
		table.insert(notes, string.format("migrated schema %d -> %d", schema - 1, schema))
	end
	return data, notes, nil
end

-- compare("1.2.0", "1.10.0") -> -1|0|1
function Version.compare(a, b)
	local function parts(v)
		local out = {}
		for n in string.gmatch(v, "%d+") do
			table.insert(out, tonumber(n))
		end
		return out
	end
	local pa, pb = parts(a), parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x < y and -1 or 1
		end
	end
	return 0
end

function Version.info()
	return string.format("%s v%s (config schema %d)", Version.NAME, Version.VERSION, Version.SCHEMA)
end

return Version

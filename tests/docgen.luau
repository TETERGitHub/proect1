--!nonstrict
-- tests/docgen: prints docs/FEATURES.md from the live registry (run through tools/gen_docs.py).
local import = ...
local Registry = import("core/Registry")
local Schema = import("data/Schema")
local Settings = import("core/Settings")
local T = import("tests/Framework")
T.fresh()

local out = {}
local function p(s) table.insert(out, s) end
local c = Registry.statusCounts()
p("# Feature catalogue")
p("")
p(string.format("Generated from `src/data/Features.luau` by `python3 tools/gen_docs.py` - **%d features**: %d `tested`, %d `implemented`, %d `env`, %d `partial`.", Registry.count(), c.tested, c.implemented, c.env, c.partial))
p("")
p("Status meaning:")
p("")
for _, k in ipairs({ "tested", "implemented", "env", "partial" }) do
	p(string.format("- **%s** - %s", k, Registry.STATUS[k]))
end
p("")
p("`tested` means an automated test in `tests/` exercises the logic and passed in the run recorded in [TESTING.md](TESTING.md). Nothing here has been run inside a real Roblox client or a specific executor.")
p("")
local letters = {}
for l in pairs(Registry.CATEGORIES) do table.insert(letters, l) end
table.sort(letters)
for _, l in ipairs(letters) do
	p(string.format("## %s. %s", l, Registry.CATEGORIES[l]))
	p("")
	p("| # | Feature | RU | Status | Implementation | Notes |")
	p("|---|---|---|---|---|---|")
	for i, e in ipairs(Registry.byCategory(l)) do
		local impl = e.impl.kind == "fn" and (e.impl.module .. ":" .. e.impl.target) or (e.impl.kind .. ": " .. e.impl.target)
		p(string.format("| %d | %s | %s | %s | `%s` | %s |", i, e.name, e.ru, e.status, impl, e.note or ""))
	end
	p("")
end
p(string.format("## Settings schema (%d keys)", #Settings.keys({ includeHidden = true })))
p("")
p("| Key | Type | Default | Range / options | Module |")
p("|---|---|---|---|---|")
for _, key in ipairs(Settings.keys({ includeHidden = true })) do
	local d = Settings.schema(key)
	local range = ""
	if d.type == "number" then range = string.format("%s..%s step %s", d.min, d.max, d.step or "-") elseif d.type == "enum" then range = table.concat(d.options, ", ") end
	local default = d.default
	if type(default) == "table" then
		default = d.type == "color" and string.format("rgb(%d,%d,%d)", default.r, default.g, default.b) or "{}"
	end
	p(string.format("| `%s` | %s | %s | %s | %s |", key, d.type, tostring(default), range, d.module))
end
print("BEGIN_DOC")
print(table.concat(out, "\n"))
print("END_DOC")
return true

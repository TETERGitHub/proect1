--!nonstrict
-- tests/runner: loads every test module, runs all cases and prints the markdown table.

local import = ...
local T = import("tests/Framework")

local suites = {
	"tests/t_basics",
	"tests/t_settings",
	"tests/t_config",
	"tests/t_input",
	"tests/t_services",
	"tests/t_registry",
	"tests/t_features",
	"tests/t_license",
	"tests/t_i18n",
	"tests/t_audit",
	"tests/t_visual",
	"tests/t_roblox",
}
for _, name in ipairs(suites) do
	local ok, err = pcall(import, name)
	if not ok then
		print("SUITE LOAD FAILURE " .. name .. ": " .. tostring(err))
		error("suite failed to load: " .. name)
	end
end

local rows, passed, failed = T.runAll()

local function cell(s)
	return (string.gsub(tostring(s), "|", "\\|"))
end

print("BEGIN_TABLE")
print("| Модуль | Тест | Ожидаемый результат | Фактический результат | Статус |")
print("|---|---|---|---|---|")
for _, r in ipairs(rows) do
	print(string.format("| %s | %s | %s | %s | %s |", cell(r.module), cell(r.name), cell(r.expected), cell(r.actual), r.status))
end
print("END_TABLE")
print(string.format("TOTAL %d PASSED %d FAILED %d", #rows, passed, failed))
return failed == 0

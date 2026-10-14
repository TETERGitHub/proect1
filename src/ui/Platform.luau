--!nonstrict
-- ui/Platform: device-class detection and the layout presets applied on first run.
-- detect() is a pure function of its inputs so it can be tested; apply() writes settings.
-- Depends on: Settings, Logger.

local import = ...
local Settings = import("core/Settings")
local Logger = import("core/Logger")

local Platform = {}

-- Presets only touch appearance/behaviour defaults; every value stays user-editable afterwards.
Platform.presets = {
	phone = {
		["state.width"] = 520, ["state.height"] = 320,
		["ui.scale"] = 0.9, ["ui.compact"] = true, ["ui.showTooltips"] = false, ["ui.decor"] = false,
		["ui.notifyDuration"] = 3, ["ui.screenButtons"] = true, ["ui.screenButtonSize"] = 50,
		["perf.maxDecor"] = 8,
	},
	tablet = {
		["state.width"] = 640, ["state.height"] = 400,
		["ui.showTooltips"] = false, ["ui.screenButtons"] = true, ["ui.screenButtonSize"] = 52,
	},
	desktop = {},
}

-- Features pinned to the screen by default on touch devices (feature ids from the catalogue).
Platform.defaultPins = { "xh.enable", "train.range", "perf.low", "win.toggle" }

-- detect(touch, keyboard, viewportX, viewportY) -> "phone" | "tablet" | "desktop"
function Platform.detect(touch, keyboard, vx, vy)
	if not touch or keyboard then
		return "desktop"
	end
	local short = math.min(vx or 0, vy or 0)
	if short > 0 and short < 600 then
		return "phone"
	end
	return "tablet"
end

function Platform.isTouch(kind)
	return kind == "phone" or kind == "tablet"
end

-- apply(kind) -> number of settings changed. Idempotent per device class.
function Platform.apply(kind)
	local preset = Platform.presets[kind]
	if not preset then
		return 0
	end
	local n = 0
	for key, value in pairs(preset) do
		if Settings.has(key) then
			local ok = Settings.set(key, value, "platform")
			if ok then
				n += 1
			end
		end
	end
	if Platform.isTouch(kind) and #Settings.get("state.favorites") == 0 then
		Settings.set("state.favorites", table.clone(Platform.defaultPins), "platform")
	end
	Settings.set("state.platform", kind, "platform")
	Logger.info("Platform", "applied '%s' preset (%d settings)", kind, n)
	return n
end

-- ensure(touch, keyboard, vx, vy) -> kind. Applies the preset the first time only.
function Platform.ensure(touch, keyboard, vx, vy)
	local kind = Platform.detect(touch, keyboard, vx, vy)
	if Settings.get("state.platform") == "" then
		Platform.apply(kind)
	end
	return kind
end

return Platform

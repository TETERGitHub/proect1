--!nonstrict
-- features/Presets: ready-made sets of existing settings, applied together and still editable one by one afterwards.
--   camera  Default / Wide / Cinematic / Competitive / Minimal: field of view, smoothing, head bob, camera effects.
--   look    Minimal / Clean / High Contrast / Neon / Performance / Compact: the menu's look and the crosshair / ESP look.
-- A preset only touches the keys it lists (never other modules), and reports how many settings it changed.
-- Depends on: Settings, Logger.

local import = ...
local Settings = import("core/Settings")
local Logger = import("core/Logger")

local Presets = {}

Presets.CAMERA = {
	{ name = "Default", desc = "Roblox's own camera: no field-of-view override, no smoothing changes, no head bob.",
		values = { ["camera.fovEnabled"] = false, ["camera.fov"] = 70, ["camera.smoothing"] = 0.35, ["camera.bobIntensity"] = 0, ["camera.disableEffects"] = false } },
	{ name = "Wide", desc = "A wider view (field of view 95).",
		values = { ["camera.fovEnabled"] = true, ["camera.fov"] = 95, ["camera.smoothing"] = 0.35, ["camera.bobIntensity"] = 0 } },
	{ name = "Cinematic", desc = "Narrower view, soft smoothing and a light head bob.",
		values = { ["camera.fovEnabled"] = true, ["camera.fov"] = 60, ["camera.smoothing"] = 0.7, ["camera.bobIntensity"] = 0.3, ["camera.disableEffects"] = false } },
	{ name = "Competitive", desc = "Field of view 85, quick response, no head bob or optional camera effects.",
		values = { ["camera.fovEnabled"] = true, ["camera.fov"] = 85, ["camera.smoothing"] = 0.1, ["camera.bobIntensity"] = 0, ["camera.disableEffects"] = true } },
	{ name = "Minimal", desc = "No camera changes at all and the optional camera effects off.",
		values = { ["camera.fovEnabled"] = false, ["camera.bobIntensity"] = 0, ["camera.disableEffects"] = true, ["camera.sensitivityEnabled"] = false } },
}

Presets.LOOK = {
	{ name = "Minimal", desc = "Plain menu without decorations; a small dot crosshair; ESP names only.",
		values = { ["ui.decor"] = false, ["ui.grain"] = false, ["ui.background"] = "Off", ["crosshair.design"] = "Lines", ["crosshair.style"] = "Dot",
			["esp.box"] = false, ["esp.tracers"] = false, ["esp.highlight"] = false, ["esp.names"] = true } },
	{ name = "Clean", desc = "The glass menu with soft decorations; thin corner boxes.",
		values = { ["ui.decor"] = true, ["ui.grain"] = true, ["ui.background"] = "Chrome", ["esp.boxStyle"] = "Corner", ["esp.thickness"] = 1, ["esp.tracers"] = false } },
	{ name = "High Contrast", desc = "Solid surfaces, larger text, bold white crosshair with outline, thick ESP lines.",
		values = { ["ui.reduceEffects"] = true, ["ui.textScale"] = 1.15, ["crosshair.color"] = { r = 255, g = 255, b = 255 }, ["crosshair.outline"] = true,
			["crosshair.thickness"] = 3, ["esp.thickness"] = 2.5, ["esp.opacity"] = 1, ["esp.fade"] = false } },
	{ name = "Neon", desc = "Rainbow glowing crosshair, flowing title, highlights on.",
		values = { ["ui.titleFlow"] = true, ["crosshair.glow"] = true, ["crosshair.rainbow"] = true, ["esp.highlight"] = true } },
	{ name = "Performance", desc = "Everything decorative off and lighter ESP updates.",
		values = { ["ui.decor"] = false, ["ui.grain"] = false, ["ui.background"] = "Off", ["ui.reduceEffects"] = true, ["crosshair.glow"] = false,
			["crosshair.rainbow"] = false, ["esp.highlight"] = false, ["esp.hz"] = 10, ["esp.maxTargets"] = 8 } },
	{ name = "Compact", desc = "Compact rows, smaller window scale and text.",
		values = { ["ui.compact"] = true, ["ui.density"] = "Compact", ["ui.scale"] = 0.9, ["ui.textScale"] = 0.95 } },
}

local function find(list, name)
	for _, p in ipairs(list) do
		if p.name == name then
			return p
		end
	end
	return nil
end

-- apply(kind, name) -> changed count | nil, reason   (kind: "camera" | "look")
function Presets.apply(kind, name)
	local p = find(kind == "camera" and Presets.CAMERA or Presets.LOOK, name)
	if not p then
		return nil, "unknown preset"
	end
	local n = 0
	for k, v in pairs(p.values) do
		if Settings.has(k) then
			local cur = Settings.get(k)
			local same = cur == v or (type(v) == "table" and type(cur) == "table" and cur.r == v.r and cur.g == v.g and cur.b == v.b)
			if not same then
				local ok, err = Settings.set(k, v, "preset")
				if ok then
					n += 1
				else
					Logger.warn("Presets", "%s: %s", k, tostring(err))
				end
			end
		end
	end
	return n
end

return Presets

--!nonstrict
-- data/ModelsGun: detailed procedural sheriff-gun models (original designs, Part primitives only). Barrel points to -Z,
-- grip hangs below the rear (+Z). Each model lists its parts with roles, see data/ModelKit.
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local G = {}

-- shared pieces ------------------------------------------------------------------------------------------------------
local function triggerGuard(b, z, len, y)
	b:box("GuardBottom", "steel", 0.1, 0.07, len, 0, y - 0.28, z)
	b:box("GuardFront", "steel", 0.1, 0.3, 0.07, 0, y - 0.14, z - len / 2)
	b:box("GuardBack", "steel", 0.1, 0.3, 0.07, 0, y - 0.14, z + len / 2)
	b:box("Trigger", "black", 0.07, 0.24, 0.07, 0, y - 0.12, z + 0.02, 14, 0, 0)
end

local function gripPanels(b, y, z, h, w, rx)
	b:mirror(function(s)
		b:box("GripPlate" .. s, "detail", 0.045, h * 0.78, w * 0.8, s * 0.2, y, z, rx, 0, 0)
		for i = 0, 3 do
			b:box("GripRib" .. s .. i, "black", 0.05, 0.035, w * 0.7, s * 0.2, y - h * 0.3 + i * h * 0.2, z, rx, 0, 0)
		end
	end)
end

-- 1. Revolver (Default) -----------------------------------------------------------------------------------------------------
G.revolver = { id = "revolver", name = "Revolver", category = "Default", build = function(b)
	b:box("Frame", "primary", 0.34, 0.52, 1.0, 0, 0, 0.1).m = "mat"
	b:box("TopStrap", "primary", 0.3, 0.1, 1.5, 0, 0.3, -0.1).m = "mat"
	b:cylZ("Barrel", "steel", 1.3, 0.22, 0, 0.12, -1.05).m = "Metal"
	b:box("Rib", "secondary", 0.1, 0.08, 1.35, 0, 0.3, -1.0).m = "mat"
	b:cylZ("Muzzle", "black", 0.08, 0.16, 0, 0.12, -1.72)
	b:box("FrontSight", "detail", 0.06, 0.14, 0.1, 0, 0.4, -1.66)
	b:box("Ejector", "steel", 0.1, 0.1, 0.9, 0, -0.1, -0.9)
	-- cylinder with chambers
	b:cylZ("Drum", "steel", 0.62, 0.7, 0, 0.1, -0.12).m = "Metal"
	b:ring(6, 0.25, function(i, a, x, z)
		b:cylZ("Chamber" .. i, "black", 0.05, 0.13, x, 0.1 + z, -0.45)
	end)
	b:cylZ("DrumCap", "secondary", 0.04, 0.2, 0, 0.1, -0.44).m = "mat"
	b:box("Hammer", "steel", 0.1, 0.26, 0.14, 0, 0.42, 0.62, 28, 0, 0)
	b:box("HammerSpur", "black", 0.12, 0.06, 0.12, 0, 0.55, 0.72, 28, 0, 0)
	triggerGuard(b, 0.18, 0.62, -0.05)
	b:box("Grip", "grip", 0.36, 1.0, 0.52, 0, -0.68, 0.66, -20, 0, 0).m = "mat"
	gripPanels(b, -0.68, 0.66, 1.0, 0.52, -20)
	b:box("GripCap", "steel", 0.4, 0.1, 0.56, 0, -1.2, 0.8, -20, 0, 0)
	b:mirror(function(s) b:box("Engrave" .. s, "glow", 0.02, 0.05, 0.9, s * 0.18, 0.05, 0.1) end)
	b:ball("Pommel", "glow", 0.12, 0, -1.2, 0.88)
end }

-- 2. Compact pistol (Modern) -------------------------------------------------------------------------------------------------
G.pistol = { id = "pistol", name = "Compact", category = "Modern", build = function(b)
	b:box("Slide", "primary", 0.3, 0.34, 1.9, 0, 0.3, -0.25).m = "mat"
	b:box("SlideTop", "secondary", 0.2, 0.06, 1.7, 0, 0.5, -0.25).m = "mat"
	for i = 0, 4 do b:box("Serration" .. i, "black", 0.32, 0.26, 0.04, 0, 0.3, 0.45 + i * 0.09) end
	b:box("EjectPort", "black", 0.31, 0.12, 0.35, 0, 0.36, 0.0)
	b:box("Frame", "gunmetal", 0.3, 0.3, 1.5, 0, 0.02, -0.05).m = "Metal"
	b:cylZ("Barrel", "steel", 0.16, 0.18, 0, 0.3, -1.25).m = "Metal"
	b:box("FrontSight", "glow", 0.06, 0.1, 0.1, 0, 0.58, -1.05)
	b:box("RearSight", "glow", 0.14, 0.08, 0.1, 0, 0.56, 0.6)
	b:box("Rail", "black", 0.26, 0.06, 0.55, 0, -0.16, -0.7)
	triggerGuard(b, 0.15, 0.55, -0.12)
	b:box("Grip", "grip", 0.32, 0.95, 0.5, 0, -0.62, 0.55, -12, 0, 0).m = "mat"
	b:box("MagBase", "secondary", 0.34, 0.08, 0.52, 0, -1.12, 0.62, -12, 0, 0).m = "mat"
	gripPanels(b, -0.62, 0.55, 0.95, 0.5, -12)
	b:box("Lanyard", "detail", 0.12, 0.08, 0.1, 0, -1.08, 0.82)
	b:mirror(function(s) b:box("SlideGlow" .. s, "glow", 0.02, 0.05, 1.3, s * 0.16, 0.3, -0.35) end)
end }

-- 3. Tactical ----------------------------------------------------------------------------------------------------------------
G.tactical = { id = "tactical", name = "Tactical", category = "Tactical", build = function(b)
	b:box("Slide", "primary", 0.32, 0.36, 1.8, 0, 0.3, -0.2).m = "mat"
	b:box("Frame", "gunmetal", 0.3, 0.32, 1.7, 0, 0.0, -0.1).m = "Metal"
	b:box("PicRail", "black", 0.2, 0.06, 1.5, 0, 0.52, -0.25)
	for i = 0, 7 do b:box("RailSlot" .. i, "gunmetal", 0.22, 0.07, 0.05, 0, 0.53, -0.9 + i * 0.18) end
	-- red-dot optic
	b:box("OpticBase", "black", 0.28, 0.08, 0.5, 0, 0.58, 0.05)
	b:box("OpticBody", "black", 0.3, 0.3, 0.46, 0, 0.78, 0.05)
	b:box("OpticLens", "glass", 0.24, 0.22, 0.04, 0, 0.78, -0.2).m = "Glass"
	b:ball("Dot", "glow", 0.06, 0, 0.78, -0.22)
	-- suppressor
	b:cylZ("Suppressor", "gunmetal", 1.1, 0.3, 0, 0.3, -1.65).m = "Metal"
	for i = 0, 4 do b:cylZ("SuppRing" .. i, "black", 0.05, 0.33, 0, 0.3, -1.2 - i * 0.22) end
	b:cylZ("Barrel", "steel", 0.5, 0.14, 0, 0.3, -1.05)
	-- under-barrel flashlight
	b:box("Light", "black", 0.2, 0.2, 0.5, 0, -0.26, -0.8)
	b:box("LightLens", "glow", 0.16, 0.16, 0.04, 0, -0.26, -1.06)
	triggerGuard(b, 0.2, 0.6, -0.12)
	b:box("Grip", "grip", 0.34, 1.0, 0.5, 0, -0.65, 0.6, -10, 0, 0).m = "mat"
	for i = 0, 4 do b:box("Stipple" .. i, "black", 0.36, 0.04, 0.46, 0, -0.35 - i * 0.16, 0.57, -10, 0, 0) end
	b:box("Mag", "gunmetal", 0.3, 0.2, 0.46, 0, -1.2, 0.68, -10, 0, 0)
	b:box("MagWell", "black", 0.36, 0.12, 0.56, 0, -1.1, 0.67, -10, 0, 0)
	b:box("SafetyLever", "secondary", 0.06, 0.07, 0.16, 0.18, 0.18, 0.42).m = "mat"
	b:box("Charging", "secondary", 0.34, 0.1, 0.12, 0, 0.36, 0.78).m = "mat"
end }

-- 4. Plasma pistol (Futuristic) -------------------------------------------------------------------------------------------------
G.plasma = { id = "plasma", name = "Plasma", category = "Futuristic", build = function(b)
	b:box("Core", "primary", 0.36, 0.5, 1.5, 0, 0, 0.1).m = "mat"
	b:wedge("NoseTop", "primary", 0.32, 0.34, 0.7, 0, 0.1, -0.95, 0, 0, 0).m = "mat"
	b:box("Nose", "secondary", 0.34, 0.3, 0.5, 0, -0.04, -0.85).m = "mat"
	b:cylZ("Emitter", "black", 0.45, 0.3, 0, 0.0, -1.35)
	b:cylZ("EmitterGlow", "glow", 0.06, 0.24, 0, 0.0, -1.6)
	-- coils round the barrel
	for i = 0, 3 do
		b:cylZ("Coil" .. i, "glow", 0.07, 0.42, 0, 0.0, -0.65 - i * 0.2)
	end
	b:cylZ("CoreTube", "glass", 1.0, 0.18, 0, 0.32, -0.3).m = "Glass"
	b:cylZ("CoreTubeGlow", "glow", 0.9, 0.1, 0, 0.32, -0.3)
	b:mirror(function(s)
		b:box("Fin" .. s, "secondary", 0.05, 0.3, 0.7, s * 0.2, 0.12, 0.45, 0, 0, s * 18).m = "mat"
		b:box("Vent" .. s, "glow", 0.02, 0.05, 0.5, s * 0.19, -0.05, 0.1)
		b:box("Vent2" .. s, "glow", 0.02, 0.05, 0.35, s * 0.19, -0.14, 0.1)
	end)
	triggerGuard(b, 0.25, 0.5, -0.1)
	b:box("Grip", "grip", 0.34, 0.95, 0.46, 0, -0.62, 0.7, -18, 0, 0).m = "mat"
	b:box("EnergyCell", "glass", 0.3, 0.5, 0.3, 0, -0.5, 0.7, -18, 0, 0).m = "Glass"
	b:box("EnergyFill", "glow", 0.22, 0.4, 0.2, 0, -0.5, 0.7, -18, 0, 0)
	b:box("Heel", "black", 0.38, 0.1, 0.5, 0, -1.15, 0.85, -18, 0, 0)
	b:ball("Sight", "glow", 0.1, 0, 0.36, -0.6)
end }

-- 5. Raygun (Neon) ---------------------------------------------------------------------------------------------------------------
G.raygun = { id = "raygun", name = "Raygun", category = "Neon", build = function(b)
	b:box("Body", "primary", 0.34, 0.5, 1.3, 0, 0, 0.2).m = "mat"
	b:ball("Dome", "primary", 0.78, 0, 0.1, -0.5).m = "mat"
	b:cylZ("Barrel", "secondary", 0.9, 0.24, 0, 0.1, -1.1).m = "mat"
	for i = 0, 2 do b:cylZ("Fin" .. i, "glow", 0.06, 0.4 - i * 0.04, 0, 0.1, -0.85 - i * 0.28) end
	b:cylZ("TipGlow", "glow", 0.08, 0.2, 0, 0.1, -1.58)
	b:ball("DomeGlow", "glow", 0.4, 0, 0.1, -0.5)
	b:box("Dorsal", "secondary", 0.1, 0.34, 1.0, 0, 0.42, 0.35, 8, 0, 0).m = "mat"
	b:mirror(function(s)
		b:box("Stripe" .. s, "glow", 0.02, 0.06, 1.1, s * 0.18, 0.05, 0.25)
		b:wedge("Wing" .. s, "secondary", 0.06, 0.3, 0.5, s * 0.2, 0.28, 0.62, 0, 0, 0).m = "mat"
	end)
	triggerGuard(b, 0.3, 0.5, -0.1)
	b:box("Grip", "grip", 0.34, 0.95, 0.46, 0, -0.62, 0.78, -16, 0, 0).m = "mat"
	b:ball("GripGem", "glow", 0.16, 0, -0.5, 1.0)
	b:ball("Pommel", "detail", 0.3, 0, -1.15, 0.9).m = "mat"
end }

-- 6. Slim (Minimal) --------------------------------------------------------------------------------------------------------------
G.slim = { id = "slim", name = "Slim", category = "Minimal", build = function(b)
	b:box("Body", "primary", 0.22, 0.4, 1.9, 0, 0.15, -0.1).m = "mat"
	b:box("Cap", "secondary", 0.2, 0.08, 1.9, 0, 0.38, -0.1).m = "mat"
	b:box("Lower", "secondary", 0.2, 0.18, 1.2, 0, -0.12, 0.2).m = "mat"
	b:cylZ("Barrel", "steel", 0.3, 0.14, 0, 0.18, -1.2)
	b:box("Line", "glow", 0.24, 0.03, 1.5, 0, 0.18, -0.1)
	b:box("Sight", "detail", 0.05, 0.08, 0.08, 0, 0.46, -0.95).m = "mat"
	triggerGuard(b, 0.2, 0.5, -0.06)
	b:box("Grip", "grip", 0.24, 0.9, 0.44, 0, -0.55, 0.58, -10, 0, 0).m = "mat"
	b:box("Heel", "detail", 0.26, 0.06, 0.46, 0, -1.02, 0.66, -10, 0, 0).m = "mat"
end }

-- 7. Pump shotgun ------------------------------------------------------------------------------------------------------------------
G.pump = { id = "pump", name = "Pump", category = "Tactical", build = function(b)
	b:box("Receiver", "primary", 0.34, 0.46, 1.2, 0, 0, 0.25).m = "mat"
	b:cylZ("Barrel", "steel", 2.2, 0.2, 0, 0.12, -1.55).m = "Metal"
	b:cylZ("Tube", "gunmetal", 1.7, 0.2, 0, -0.14, -1.2).m = "Metal"
	b:cylZ("TubeCap", "black", 0.1, 0.24, 0, -0.14, -2.08)
	b:box("Rib", "secondary", 0.07, 0.05, 2.1, 0, 0.26, -1.55).m = "mat"
	b:box("FrontSight", "glow", 0.06, 0.12, 0.08, 0, 0.34, -2.55)
	b:cylZ("Muzzle", "black", 0.08, 0.17, 0, 0.12, -2.65)
	-- pump forend with grooves
	b:box("Forend", "grip", 0.4, 0.3, 0.9, 0, -0.14, -0.85).m = "mat"
	for i = 0, 5 do b:box("Groove" .. i, "black", 0.42, 0.22, 0.03, 0, -0.14, -1.1 + i * 0.12) end
	b:box("EjectPort", "black", 0.36, 0.14, 0.4, 0, 0.1, 0.1)
	b:box("Stock", "grip", 0.32, 0.55, 1.4, 0, -0.12, 1.55, -6, 0, 0).m = "Wood"
	b:box("ButtPad", "rubber", 0.34, 0.6, 0.1, 0, -0.14, 2.28, -6, 0, 0)
	b:box("Wrist", "grip", 0.3, 0.3, 0.5, 0, -0.02, 0.85).m = "Wood"
	triggerGuard(b, 0.45, 0.6, -0.12)
	b:mirror(function(s) b:box("RecvGlow" .. s, "glow", 0.02, 0.05, 0.8, s * 0.18, 0.12, 0.3) end)
end }

-- 8. Hand cannon (Dark/Metallic) -------------------------------------------------------------------------------------------------
G.cannon = { id = "cannon", name = "Cannon", category = "Dark", build = function(b)
	b:box("Slide", "primary", 0.42, 0.5, 2.1, 0, 0.3, -0.35).m = "mat"
	b:box("Frame", "gunmetal", 0.4, 0.4, 1.7, 0, -0.02, -0.15).m = "Metal"
	b:cylZ("Barrel", "steel", 0.5, 0.3, 0, 0.3, -1.6).m = "Metal"
	b:cylZ("Bore", "black", 0.08, 0.2, 0, 0.3, -1.85)
	b:box("Brake", "black", 0.44, 0.12, 0.55, 0, 0.58, -1.1)
	for i = 0, 3 do b:box("BrakeSlot" .. i, "glow", 0.46, 0.04, 0.05, 0, 0.58, -1.3 + i * 0.14) end
	b:mirror(function(s)
		for i = 0, 5 do b:box("Cut" .. s .. i, "black", 0.02, 0.4, 0.05, s * 0.22, 0.3, 0.3 + i * 0.09) end
		b:box("Skull" .. s, "detail", 0.02, 0.2, 0.2, s * 0.22, 0.32, -0.5).m = "mat"
	end)
	b:box("RearSight", "black", 0.2, 0.12, 0.1, 0, 0.62, 0.66)
	b:box("FrontSight", "glow", 0.06, 0.1, 0.1, 0, 0.6, -1.0)
	triggerGuard(b, 0.28, 0.7, -0.14)
	b:box("Grip", "grip", 0.42, 1.05, 0.6, 0, -0.72, 0.65, -14, 0, 0).m = "mat"
	gripPanels(b, -0.72, 0.65, 1.05, 0.6, -14)
	b:box("Heel", "steel", 0.46, 0.1, 0.64, 0, -1.28, 0.78, -14, 0, 0)
	b:ball("Gem", "glow", 0.14, 0, 0.3, 0.68)
end }

G.order = { "revolver", "pistol", "tactical", "plasma", "raygun", "slim", "pump", "cannon" }

-- style presets (the category cards): a palette and material per category, applied over any model ----------------------------
G.styles = {
	{ id = "Default", look = { primary = { 150, 154, 162 }, secondary = { 112, 70, 40 }, grip = { 112, 70, 40 }, detail = { 196, 154, 72 }, glow = { 255, 214, 120 }, material = "Metal", glowAmount = 0.2 } },
	{ id = "Modern", look = { primary = { 70, 74, 84 }, secondary = { 40, 42, 50 }, grip = { 30, 30, 34 }, detail = { 120, 126, 140 }, glow = { 90, 160, 255 }, material = "Metal", glowAmount = 0.4 } },
	{ id = "Tactical", look = { primary = { 84, 92, 66 }, secondary = { 50, 54, 42 }, grip = { 36, 38, 32 }, detail = { 120, 128, 100 }, glow = { 255, 170, 60 }, material = "SmoothPlastic", glowAmount = 0.3 } },
	{ id = "Futuristic", look = { primary = { 232, 236, 244 }, secondary = { 120, 130, 150 }, grip = { 60, 66, 80 }, detail = { 170, 180, 200 }, glow = { 80, 210, 255 }, material = "SmoothPlastic", glowAmount = 0.9 } },
	{ id = "Neon", look = { primary = { 28, 20, 48 }, secondary = { 60, 30, 110 }, grip = { 20, 16, 34 }, detail = { 255, 80, 200 }, glow = { 255, 60, 220 }, material = "SmoothPlastic", glowAmount = 1 } },
	{ id = "Dark", look = { primary = { 30, 30, 34 }, secondary = { 18, 18, 22 }, grip = { 14, 14, 16 }, detail = { 90, 90, 98 }, glow = { 220, 40, 50 }, material = "Metal", glowAmount = 0.5 } },
	{ id = "Metallic", look = { primary = { 205, 210, 220 }, secondary = { 150, 156, 168 }, grip = { 90, 94, 104 }, detail = { 240, 200, 120 }, glow = { 255, 240, 200 }, material = "Foil", glowAmount = 0.15 } },
	{ id = "Minimal", look = { primary = { 238, 238, 242 }, secondary = { 214, 214, 220 }, grip = { 190, 190, 198 }, detail = { 120, 120, 128 }, glow = { 10, 132, 255 }, material = "SmoothPlastic", glowAmount = 0.35 } },
}

return G

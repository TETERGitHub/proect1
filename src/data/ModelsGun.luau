--!nonstrict
-- data/ModelsGun: sheriff-gun models (original designs, Part primitives only). Barrel points to -Z, the grip hangs below the
-- rear (+Z). The side profile is drawn as polygons (see ModelKit:poly), then barrel, cylinder, sights, serrations and other
-- small parts are added on top. `hold` is the point the hand grips (model coordinates); features/Cosmetics puts that point on
-- the tool's Handle.
-- Depends on: ModelKit.

local import = ...
local Kit = import("data/ModelKit")

local G = {}

-- trigger guard (polyline) and trigger; z/y are the guard's top-front and top-rear junctions with the frame
local function guard(b, zf, zr, y, depth, thick)
	b:stroke("Guard", "steel", thick or 0.1, 0, { { zr, y }, { zr - 0.04, y - depth * 0.8 }, { zr - 0.2, y - depth }, { zf + 0.2, y - depth }, { zf + 0.04, y - depth * 0.7 }, { zf, y } }, 0.06, "Metal")
	b:poly("Trigger", "black", 0.07, 0, { { zr - 0.28, y - 0.02 }, { zr - 0.2, y - 0.02 }, { zr - 0.1, y - depth * 0.78 }, { zr - 0.2, y - depth * 0.78 } })
end

local function serrations(b, z0, count, step, y0, y1, thick)
	for i = 0, count - 1 do
		b:box("Serration" .. i, "black", thick, y1 - y0, 0.035, 0, (y0 + y1) / 2, z0 + i * step)
	end
end

-- panel texture on the grip (dark ribs), following a tilted grip given by its centre and tilt (degrees about X)
local function gripRibs(b, cz, cy, height, width, tilt, thick, count)
	for i = 0, count - 1 do
		local t = (i + 0.5) / count - 0.5
		b:box("GripRib" .. i, "black", thick, 0.03, width * 0.8, 0, cy + t * height * 0.9, cz + t * height * 0.9 * math.sin(math.rad(-tilt)), tilt, 0, 0)
	end
end

-- 1. Revolver (Default) ---------------------------------------------------------------------------------------------------------
G.revolver = { id = "revolver", name = "Revolver", category = "Default", hold = { 0, -0.55, 0.85 }, build = function(b)
	-- frame: top strap, body and the grip frame in one outline
	b:poly("Frame", "primary", 0.32, 0, {
		{ -0.62, 0.46 }, { 0.58, 0.46 }, { 0.78, 0.40 }, { 0.84, 0.22 }, { 0.98, 0.06 }, { 1.06, -0.30 }, { 1.18, -1.02 },
		{ 0.46, -1.06 }, { 0.42, -0.36 }, { 0.30, -0.14 }, { -0.62, -0.14 },
	}, "mat")
	-- wooden grip panels over the frame
	b:poly("GripPanel", "grip", 0.42, 0, { { 0.48, -0.30 }, { 0.86, 0.10 }, { 1.04, -0.40 }, { 1.17, -1.0 }, { 0.47, -1.04 } }, "Wood")
	gripRibs(b, 0.82, -0.62, 0.8, 0.5, -6, 0.43, 5)
	b:poly("GripCap", "steel", 0.46, 0, { { 0.46, -1.04 }, { 1.19, -1.0 }, { 1.2, -1.12 }, { 0.44, -1.14 } }, "Metal")
	b:ball("Lanyard", "detail", 0.14, 0, -1.1, 0.82).m = "Metal"
	-- cylinder with flutes and chamber mouths
	b:cylZ("Drum", "steel", 0.66, 0.8, 0, 0.14, -0.1).m = "Metal"
	b:cylZ("DrumRear", "secondary", 0.08, 0.86, 0, 0.14, 0.26).m = "mat"
	b:cylZ("DrumFront", "secondary", 0.08, 0.86, 0, 0.14, -0.46).m = "mat"
	b:mirror(function(s)
		for i = -1, 1 do
			b:box("Flute" .. s .. i, "black", 0.035, 0.13, 0.34, s * 0.405, 0.14 + i * 0.27, -0.1)
		end
	end)
	b:ring(6, 0.27, function(i, a, x, z) b:cylZ("Chamber" .. i, "black", 0.03, 0.14, x, 0.14 + z, -0.51) end)
	-- barrel, rib, ejector rod, front sight
	b:cylZ("Barrel", "steel", 1.5, 0.26, 0, 0.3, -1.4).m = "Metal"
	b:box("Shroud", "primary", 0.2, 0.2, 1.3, 0, 0.04, -1.3).m = "mat"
	b:cylZ("Ejector", "steel", 1.0, 0.1, 0, 0.04, -1.2).m = "Metal"
	b:cylZ("EjectorHead", "black", 0.12, 0.16, 0, 0.04, -1.78)
	b:box("Rib", "secondary", 0.1, 0.07, 1.5, 0, 0.46, -1.4).m = "mat"
	b:poly("FrontSight", "detail", 0.07, 0, { { -2.08, 0.43 }, { -2.0, 0.43 }, { -2.02, 0.6 }, { -2.1, 0.6 } }, "Metal")
	b:cylZ("Crown", "black", 0.05, 0.3, 0, 0.3, -2.14)
	-- hammer, rear sight, trigger
	b:poly("Hammer", "steel", 0.1, 0, { { 0.72, 0.4 }, { 0.8, 0.62 }, { 0.98, 0.7 }, { 1.04, 0.62 }, { 0.92, 0.42 } }, "Metal")
	b:box("RearSight", "black", 0.2, 0.07, 0.3, 0, 0.5, 0.45)
	guard(b, -0.3, 0.42, -0.14, 0.42)
	b:mirror(function(s) b:box("Engrave" .. s, "glow", 0.02, 0.05, 0.75, s * 0.166, 0.22, 0.12) end)
	b:ball("Medallion", "glow", 0.12, 0.22, -0.55, 0.82)
end }

-- 2. Compact pistol (Modern) ----------------------------------------------------------------------------------------------------
G.pistol = { id = "pistol", name = "Compact", category = "Modern", hold = { 0, -0.5, 0.7 }, build = function(b)
	-- slide: chamfered front and rear
	b:poly("Slide", "primary", 0.3, 0, { { -1.32, 0.52 }, { -1.22, 0.64 }, { 0.82, 0.64 }, { 1.0, 0.5 }, { 1.0, 0.2 }, { -1.32, 0.2 } }, "mat")
	b:poly("SlideTop", "secondary", 0.2, 0, { { -1.2, 0.64 }, { 0.8, 0.64 }, { 0.8, 0.7 }, { -1.2, 0.7 } }, "mat")
	serrations(b, 0.42, 6, 0.09, 0.26, 0.58, 0.32)
	b:box("EjectPort", "black", 0.02, 0.16, 0.45, 0.151, 0.46, -0.1)
	-- frame with dust cover, grip and beaver tail
	b:poly("Frame", "secondary", 0.26, 0, {
		{ -1.08, 0.2 }, { 0.98, 0.2 }, { 1.06, 0.12 }, { 1.2, -0.98 }, { 0.2, -1.0 }, { 0.04, -0.34 }, { -0.04, -0.14 },
		{ -0.34, -0.14 }, { -0.4, 0.0 }, { -1.08, 0.0 },
	}, "mat")
	b:poly("GripPanel", "grip", 0.34, 0, { { 0.18, -0.2 }, { 0.98, -0.02 }, { 1.16, -0.94 }, { 0.22, -0.96 } }, "mat")
	gripRibs(b, 0.7, -0.55, 0.7, 0.55, -14, 0.35, 7)
	b:poly("MagBase", "detail", 0.32, 0, { { 0.2, -0.96 }, { 1.18, -0.94 }, { 1.2, -1.06 }, { 0.18, -1.08 } }, "Metal")
	b:cylZ("Muzzle", "steel", 0.14, 0.17, 0, 0.42, -1.38).m = "Metal"
	b:box("FrontSight", "glow", 0.05, 0.12, 0.12, 0, 0.76, -1.12)
	b:box("RearSightL", "black", 0.06, 0.1, 0.14, 0.07, 0.75, 0.78)
	b:box("RearSightR", "black", 0.06, 0.1, 0.14, -0.07, 0.75, 0.78)
	b:box("RearDot", "glow", 0.03, 0.05, 0.02, 0.07, 0.75, 0.7)
	b:box("Rail", "black", 0.2, 0.07, 0.5, 0, -0.04, -0.7)
	b:box("SlideStop", "steel", 0.34, 0.06, 0.24, 0, 0.12, 0.16).m = "Metal"
	guard(b, -0.34, 0.2, -0.14, 0.4)
	b:mirror(function(s) b:box("SlideGlow" .. s, "glow", 0.02, 0.045, 1.0, s * 0.151, 0.56, -0.65) end)
end }

-- 3. Tactical -------------------------------------------------------------------------------------------------------------------
G.tactical = { id = "tactical", name = "Tactical", category = "Tactical", hold = { 0, -0.5, 0.72 }, build = function(b)
	b:poly("Slide", "primary", 0.32, 0, { { -1.18, 0.56 }, { -1.1, 0.66 }, { 0.84, 0.66 }, { 1.02, 0.5 }, { 1.02, 0.2 }, { -1.18, 0.2 } }, "mat")
	serrations(b, 0.46, 5, 0.09, 0.26, 0.6, 0.34)
	b:box("EjectPort", "black", 0.02, 0.18, 0.45, 0.161, 0.46, -0.05)
	b:poly("Frame", "gunmetal", 0.28, 0, {
		{ -1.14, 0.2 }, { 1.0, 0.2 }, { 1.08, 0.12 }, { 1.22, -0.98 }, { 0.22, -1.0 }, { 0.06, -0.34 }, { -0.02, -0.14 }, { -0.32, -0.14 }, { -0.38, 0.0 }, { -1.14, 0.0 },
	}, "Metal")
	-- accessory rail with slots, under-barrel light, red-dot sight
	b:box("Rail", "black", 0.22, 0.08, 0.95, 0, -0.04, -0.72)
	for i = 0, 5 do b:box("RailSlot" .. i, "gunmetal", 0.24, 0.09, 0.04, 0, -0.04, -1.08 + i * 0.16) end
	b:poly("Light", "black", 0.2, 0, { { -1.12, -0.08 }, { -0.62, -0.08 }, { -0.62, -0.3 }, { -1.08, -0.3 }, { -1.16, -0.2 } })
	b:cylZ("LightLens", "glow", 0.05, 0.16, 0, -0.2, -1.16)
	b:poly("OpticBase", "black", 0.26, 0, { { -0.5, 0.66 }, { 0.5, 0.66 }, { 0.5, 0.74 }, { -0.5, 0.74 } })
	b:poly("OpticBody", "black", 0.3, 0, { { -0.44, 0.74 }, { 0.44, 0.74 }, { 0.5, 1.12 }, { -0.5, 1.12 } })
	b:box("OpticHood", "gunmetal", 0.32, 0.06, 0.62, 0, 1.14, 0).m = "Metal"
	b:box("OpticLens", "glass", 0.24, 0.26, 0.03, 0, 0.94, -0.5).m = "Glass"
	b:ball("Dot", "glow", 0.05, 0, 0.96, -0.52)
	-- suppressor on a threaded barrel
	b:cylZ("Thread", "steel", 0.3, 0.17, 0, 0.42, -1.3).m = "Metal"
	b:cylZ("Suppressor", "black", 1.15, 0.34, 0, 0.42, -1.95).m = "Metal"
	for i = 0, 3 do b:cylZ("SuppBand" .. i, "gunmetal", 0.05, 0.37, 0, 0.42, -1.5 - i * 0.3).m = "Metal" end
	b:cylZ("SuppTip", "gunmetal", 0.06, 0.28, 0, 0.42, -2.55)
	guard(b, -0.32, 0.2, -0.14, 0.42)
	b:poly("GripPanel", "grip", 0.34, 0, { { 0.2, -0.2 }, { 1.0, -0.02 }, { 1.18, -0.94 }, { 0.24, -0.96 } }, "mat")
	for i = 0, 5 do b:box("Stipple" .. i, "black", 0.36, 0.035, 0.7, 0, -0.1 - i * 0.14, 0.62 + i * 0.075, -14, 0, 0) end
	-- extended magazine
	b:poly("Mag", "gunmetal", 0.3, 0, { { 0.24, -0.96 }, { 1.2, -0.94 }, { 1.3, -1.55 }, { 0.3, -1.57 } }, "Metal")
	b:poly("MagPad", "detail", 0.34, 0, { { 0.3, -1.56 }, { 1.3, -1.54 }, { 1.32, -1.66 }, { 0.28, -1.68 } }, "mat")
	b:box("Safety", "secondary", 0.08, 0.1, 0.16, 0.19, 0.3, 0.56).m = "mat"
	b:box("FrontSight", "glow", 0.05, 0.1, 0.1, 0, 0.72, -1.0)
end }

-- 4. Plasma pistol (Futuristic) ------------------------------------------------------------------------------------------------
G.plasma = { id = "plasma", name = "Plasma", category = "Futuristic", hold = { 0, -0.5, 0.78 }, build = function(b)
	-- smooth swept body
	b:poly("Body", "primary", 0.34, 0, {
		{ -1.55, 0.18 }, { -1.1, 0.5 }, { -0.2, 0.62 }, { 0.7, 0.58 }, { 1.05, 0.38 }, { 1.12, 0.1 }, { 0.9, -0.1 }, { -0.1, -0.16 }, { -0.9, -0.12 }, { -1.5, 0.0 },
	}, "mat")
	b:poly("Spine", "secondary", 0.2, 0, { { -1.2, 0.5 }, { -0.2, 0.62 }, { 0.7, 0.58 }, { 0.7, 0.72 }, { -0.2, 0.78 }, { -1.1, 0.64 } }, "mat")
	-- barrel with emitter and coils
	b:cylZ("Emitter", "black", 0.5, 0.3, 0, 0.26, -1.78)
	b:cylZ("EmitterGlow", "glow", 0.05, 0.22, 0, 0.26, -2.05)
	for i = 0, 3 do b:cylZ("Coil" .. i, "glow", 0.07, 0.46 - i * 0.02, 0, 0.26, -1.0 - i * 0.18) end
	b:cylZ("CoilCore", "black", 0.8, 0.28, 0, 0.26, -1.34).m = "Metal"
	-- energy cell window and vents
	b:poly("CellFrame", "black", 0.36, 0, { { -0.3, 0.46 }, { 0.5, 0.46 }, { 0.58, 0.2 }, { -0.26, 0.2 } })
	b:poly("CellGlass", "glass", 0.37, 0, { { -0.22, 0.4 }, { 0.44, 0.4 }, { 0.5, 0.26 }, { -0.2, 0.26 } }, "Glass")
	b:poly("CellFill", "glow", 0.3, 0, { { -0.18, 0.37 }, { 0.2, 0.37 }, { 0.22, 0.29 }, { -0.16, 0.29 } })
	for i = 0, 3 do b:box("Vent" .. i, "glow", 0.37, 0.03, 0.16, 0, 0.05 + i * 0.0, 0.5 + i * 0.12) end
	b:mirror(function(s)
		b:poly("Fin" .. s, "secondary", 0.06, s * 0.2, { { 0.5, 0.6 }, { 0.95, 0.78 }, { 1.12, 0.6 }, { 1.0, 0.4 } }, "mat")
	end)
	guard(b, -0.15, 0.55, -0.12, 0.38)
	-- angular grip with a glowing cell
	b:poly("Grip", "grip", 0.34, 0, { { 0.3, -0.1 }, { 1.0, -0.06 }, { 1.2, -0.95 }, { 0.38, -1.0 } }, "mat")
	b:poly("GripGlass", "glass", 0.37, 0, { { 0.52, -0.3 }, { 0.84, -0.28 }, { 0.94, -0.8 }, { 0.58, -0.82 } }, "Glass")
	b:poly("GripFill", "glow", 0.3, 0, { { 0.56, -0.38 }, { 0.8, -0.36 }, { 0.86, -0.72 }, { 0.6, -0.74 } })
	b:poly("Heel", "black", 0.38, 0, { { 0.38, -1.0 }, { 1.2, -0.95 }, { 1.22, -1.08 }, { 0.36, -1.12 } })
	b:ball("Sight", "glow", 0.1, 0, 0.7, -1.0)
end }

-- 5. Raygun (Neon) ------------------------------------------------------------------------------------------------------------------
G.raygun = { id = "raygun", name = "Raygun", category = "Neon", hold = { 0, -0.5, 0.85 }, build = function(b)
	b:poly("Body", "primary", 0.34, 0, { { -0.8, 0.45 }, { 0.4, 0.5 }, { 0.95, 0.38 }, { 1.05, 0.1 }, { 0.8, -0.14 }, { -0.1, -0.18 }, { -0.8, -0.2 } }, "mat")
	b:ball("Dome", "primary", 0.95, 0, 0.14, -0.55).m = "mat"
	b:ball("DomeCore", "glow", 0.5, 0, 0.14, -0.55)
	b:cylZ("DomeRing", "detail", 0.06, 0.98, 0, 0.14, -0.2).m = "Metal"
	-- barrel with fins
	b:cylZ("Barrel", "secondary", 0.8, 0.26, 0, 0.14, -1.45).m = "mat"
	for i = 0, 3 do b:cylZ("Fin" .. i, "glow", 0.06, 0.46 - i * 0.05, 0, 0.14, -1.18 - i * 0.22) end
	b:cylZ("Tip", "glow", 0.1, 0.2, 0, 0.14, -1.9)
	-- tail fin and side stripes
	b:poly("Dorsal", "secondary", 0.1, 0, { { 0.0, 0.5 }, { 0.9, 0.38 }, { 1.2, 0.95 }, { 0.5, 0.8 } }, "mat")
	b:mirror(function(s)
		b:poly("Wing" .. s, "secondary", 0.05, s * 0.2, { { 0.5, 0.4 }, { 1.0, 0.36 }, { 1.4, 0.7 }, { 0.8, 0.7 } }, "mat")
		b:box("Stripe" .. s, "glow", 0.02, 0.05, 1.0, s * 0.171, 0.22, 0.3)
	end)
	guard(b, -0.1, 0.6, -0.16, 0.38)
	b:poly("Grip", "grip", 0.34, 0, { { 0.45, -0.14 }, { 1.0, -0.08 }, { 1.25, -0.98 }, { 0.5, -1.0 } }, "mat")
	for i = 0, 3 do b:box("GripBand" .. i, "glow", 0.36, 0.04, 0.55, 0, -0.3 - i * 0.18, 0.78 + i * 0.1, -14, 0, 0) end
	b:ball("Pommel", "detail", 0.36, 0, -1.08, 0.95).m = "Metal"
	b:ball("PommelGem", "glow", 0.18, 0, -1.08, 1.08)
end }

-- 6. Slim (Minimal) -----------------------------------------------------------------------------------------------------------------
G.slim = { id = "slim", name = "Slim", category = "Minimal", hold = { 0, -0.45, 0.65 }, build = function(b)
	b:poly("Body", "primary", 0.24, 0, { { -1.4, 0.3 }, { -1.3, 0.46 }, { 0.8, 0.46 }, { 1.0, 0.36 }, { 1.0, 0.04 }, { -1.4, 0.04 } }, "mat")
	b:poly("Under", "secondary", 0.2, 0, { { -0.7, 0.04 }, { 0.98, 0.04 }, { 1.02, -0.1 }, { -0.7, -0.1 } }, "mat")
	b:cylZ("Muzzle", "steel", 0.1, 0.13, 0, 0.24, -1.45)
	b:box("Line", "glow", 0.26, 0.03, 1.55, 0, 0.26, -0.3)
	b:box("Sight", "detail", 0.05, 0.1, 0.09, 0, 0.53, -1.15).m = "mat"
	b:box("RearSight", "detail", 0.07, 0.08, 0.12, 0, 0.51, 0.8).m = "mat"
	guard(b, -0.1, 0.45, -0.1, 0.34, 0.08)
	b:poly("Grip", "grip", 0.26, 0, { { 0.4, -0.08 }, { 1.0, 0.02 }, { 1.2, -0.9 }, { 0.46, -0.94 } }, "mat")
	b:poly("Heel", "detail", 0.28, 0, { { 0.46, -0.94 }, { 1.2, -0.9 }, { 1.22, -1.0 }, { 0.44, -1.04 } }, "mat")
end }

-- 7. Pump shotgun --------------------------------------------------------------------------------------------------------------
G.pump = { id = "pump", name = "Pump", category = "Tactical", hold = { 0, -0.1, 0.9 }, build = function(b)
	-- receiver
	b:poly("Receiver", "primary", 0.34, 0, { { -0.3, 0.3 }, { 1.2, 0.3 }, { 1.3, 0.2 }, { 1.3, -0.3 }, { -0.1, -0.34 }, { -0.3, -0.2 } }, "mat")
	b:box("EjectPort", "black", 0.02, 0.2, 0.55, 0.171, 0.1, 0.45)
	-- barrel and magazine tube with rib, bead sight and muzzle
	b:cylZ("Barrel", "steel", 2.6, 0.22, 0, 0.2, -1.65).m = "Metal"
	b:cylZ("Tube", "gunmetal", 2.1, 0.2, 0, -0.14, -1.35).m = "Metal"
	b:cylZ("TubeCap", "steel", 0.12, 0.26, 0, -0.14, -2.42).m = "Metal"
	b:box("Rib", "secondary", 0.07, 0.05, 2.5, 0, 0.34, -1.65).m = "mat"
	b:ball("Bead", "glow", 0.1, 0, 0.4, -2.85)
	b:cylZ("Muzzle", "black", 0.1, 0.2, 0, 0.2, -2.98)
	-- forend with grooves
	b:poly("Forend", "grip", 0.4, 0, { { -1.35, 0.0 }, { -0.4, 0.04 }, { -0.4, -0.34 }, { -0.5, -0.4 }, { -1.3, -0.4 }, { -1.4, -0.3 } }, "Wood")
	for i = 0, 6 do b:box("Groove" .. i, "black", 0.42, 0.3, 0.03, 0, -0.17, -1.3 + i * 0.12) end
	-- stock with a drop and a recoil pad
	b:poly("Stock", "grip", 0.32, 0, { { 1.2, 0.24 }, { 2.5, 0.1 }, { 2.7, -0.7 }, { 2.4, -0.82 }, { 1.7, -0.32 }, { 1.3, -0.3 } }, "Wood")
	b:poly("Pad", "rubber", 0.34, 0, { { 2.4, -0.82 }, { 2.7, -0.7 }, { 2.74, -0.78 }, { 2.42, -0.9 } })
	b:poly("Wrist", "grip", 0.3, 0, { { 1.2, 0.24 }, { 1.7, 0.2 }, { 1.7, -0.34 }, { 1.3, -0.3 } }, "Wood")
	guard(b, 0.25, 0.9, -0.3, 0.32)
	b:mirror(function(s) b:box("RecvGlow" .. s, "glow", 0.02, 0.04, 0.8, s * 0.171, 0.2, 0.2) end)
	b:box("Latch", "steel", 0.1, 0.1, 0.12, 0, 0.0, 1.3).m = "Metal"
end }

-- 8. Hand cannon (Dark) ----------------------------------------------------------------------------------------------------------
G.cannon = { id = "cannon", name = "Cannon", category = "Dark", hold = { 0, -0.55, 0.8 }, build = function(b)
	b:poly("Slide", "primary", 0.44, 0, { { -1.6, 0.56 }, { -1.48, 0.76 }, { 0.9, 0.76 }, { 1.1, 0.56 }, { 1.1, 0.16 }, { -1.6, 0.16 } }, "mat")
	b:poly("Frame", "gunmetal", 0.4, 0, {
		{ -1.5, 0.16 }, { 1.06, 0.16 }, { 1.14, 0.06 }, { 1.3, -1.08 }, { 0.26, -1.1 }, { 0.1, -0.4 }, { 0.0, -0.18 }, { -0.4, -0.18 }, { -0.46, -0.04 }, { -1.5, -0.04 },
	}, "Metal")
	-- muzzle brake with slots
	b:box("Brake", "black", 0.46, 0.2, 0.7, 0, 0.7, -1.2)
	for i = 0, 3 do b:box("BrakeSlot" .. i, "glow", 0.48, 0.05, 0.06, 0, 0.7, -1.4 + i * 0.16) end
	b:cylZ("Bore", "black", 0.1, 0.22, 0, 0.36, -1.66)
	-- top rail with slots, sights
	b:box("Rail", "black", 0.24, 0.07, 1.5, 0, 0.8, 0.1)
	for i = 0, 9 do b:box("RailSlot" .. i, "gunmetal", 0.26, 0.08, 0.05, 0, 0.8, -0.55 + i * 0.15) end
	b:box("FrontSight", "glow", 0.06, 0.12, 0.12, 0, 0.9, -1.35)
	b:box("RearSight", "black", 0.22, 0.12, 0.12, 0, 0.9, 0.95)
	b:mirror(function(s)
		for i = 0, 6 do b:box("Cut" .. s .. i, "black", 0.02, 0.4, 0.05, s * 0.221, 0.36, 0.45 + i * 0.09) end
		b:poly("Plate" .. s, "detail", 0.02, s * 0.221, { { -1.0, 0.7 }, { -0.2, 0.7 }, { -0.1, 0.55 }, { -1.0, 0.55 } }, "mat")
	end)
	guard(b, -0.46, 0.2, -0.18, 0.46, 0.12)
	b:poly("Grip", "grip", 0.42, 0, { { 0.22, -0.2 }, { 1.12, -0.04 }, { 1.3, -1.02 }, { 0.28, -1.04 } }, "mat")
	gripRibs(b, 0.76, -0.6, 0.8, 0.6, -14, 0.44, 7)
	b:poly("Heel", "steel", 0.46, 0, { { 0.28, -1.04 }, { 1.3, -1.02 }, { 1.34, -1.16 }, { 0.26, -1.18 } }, "Metal")
	b:ball("Gem", "glow", 0.14, 0.23, 0.36, 0.86)
	b:ball("GemB", "glow", 0.14, -0.23, 0.36, 0.86)
end }

-- 9. Bolt-action sniper rifle (arctic AWP-style layout: long barrel, scope, bolt handle, thumb-hole stock, bipod) ---------------------
G.awp = { id = "awp", name = "Sniper", category = "Arctic", hold = { 0, -0.5, 1.2 }, build = function(b)
	-- thumb-hole stock with cheek riser, and the pistol grip
	b:poly("Stock", "primary", 0.3, 0, { { 1.3, 0.34 }, { 2.7, 0.46 }, { 3.1, 0.3 }, { 3.15, -0.5 }, { 2.6, -0.62 }, { 2.0, -0.4 }, { 1.3, -0.3 } }, "mat")
	b:poly("StockHole", "black", 0.31, 0, { { 1.9, 0.08 }, { 2.3, 0.1 }, { 2.4, -0.18 }, { 2.0, -0.22 } })
	b:poly("Cheek", "secondary", 0.3, 0, { { 2.0, 0.42 }, { 2.75, 0.48 }, { 2.75, 0.64 }, { 2.1, 0.6 } }, "mat")
	b:poly("Pad", "rubber", 0.32, 0, { { 3.1, 0.3 }, { 3.15, -0.5 }, { 3.24, -0.5 }, { 3.2, 0.3 } })
	b:poly("PistolGrip", "grip", 0.3, 0, { { 1.0, -0.22 }, { 1.55, -0.26 }, { 1.7, -1.0 }, { 1.2, -1.06 } }, "mat")
	for i = 0, 4 do b:box("GripRib" .. i, "black", 0.32, 0.03, 0.36, 0, -0.42 - i * 0.12, 1.3 + i * 0.07, -12, 0, 0) end
	-- receiver, magazine, trigger guard
	b:poly("Receiver", "secondary", 0.34, 0, { { -0.9, 0.44 }, { 1.4, 0.44 }, { 1.4, -0.3 }, { -0.9, -0.3 } }, "mat")
	b:box("EjectPort", "black", 0.02, 0.22, 0.6, 0.171, 0.2, 0.2)
	b:poly("Magazine", "gunmetal", 0.24, 0, { { 0.0, -0.3 }, { 0.62, -0.3 }, { 0.62, -0.82 }, { 0.0, -0.82 } }, "Metal")
	guard(b, 0.62, 1.08, -0.3, 0.38)
	-- barrel, fore-end, muzzle brake with ports, bipod folded forward
	b:cylZ("Barrel", "steel", 3.6, 0.2, 0, 0.14, -2.6).m = "Metal"
	b:cylZ("Sleeve", "gunmetal", 0.9, 0.3, 0, 0.14, -1.35).m = "Metal"
	b:poly("Forend", "primary", 0.3, 0, { { -0.9, 0.12 }, { -2.3, 0.14 }, { -2.3, -0.22 }, { -0.9, -0.3 } }, "mat")
	b:cylZ("Brake", "black", 0.55, 0.32, 0, 0.14, -4.6).m = "Metal"
	for i = 0, 3 do b:box("BrakePort" .. i, "glow", 0.34, 0.04, 0.05, 0, 0.14, -4.45 - i * 0.1) end
	b:stroke("BipodL", "gunmetal", 0.05, 0.12, { { -2.0, -0.25 }, { -2.9, -0.5 } }, 0.05, "Metal")
	b:stroke("BipodR", "gunmetal", 0.05, -0.12, { { -2.0, -0.25 }, { -2.9, -0.5 } }, 0.05, "Metal")
	-- scope: tube, bell, eyepiece, turrets, lenses, rings
	b:cylZ("ScopeTube", "black", 1.7, 0.28, 0, 0.86, -0.1).m = "Metal"
	b:cylZ("ScopeBell", "black", 0.55, 0.42, 0, 0.86, -1.15).m = "Metal"
	b:cylZ("ScopeEye", "black", 0.4, 0.36, 0, 0.86, 0.95).m = "Metal"
	b:cylZ("LensFront", "glass", 0.04, 0.38, 0, 0.86, -1.44).m = "Glass"
	b:cylZ("LensRear", "glow", 0.03, 0.26, 0, 0.86, 1.17)
	b:cylY("TurretTop", "gunmetal", 0.18, 0.2, 0, 1.08, -0.2).m = "Metal"
	b:cylY("TurretSide", "gunmetal", 0.18, 0.2, 0.21, 0.86, -0.2, 0, 0, 90).m = "Metal"
	b:box("MountA", "gunmetal", 0.2, 0.26, 0.2, 0, 0.58, -0.6).m = "Metal"
	b:box("MountB", "gunmetal", 0.2, 0.26, 0.2, 0, 0.58, 0.5).m = "Metal"
	-- bolt handle and knob (right side)
	b:stroke("BoltArm", "steel", 0.06, 0.2, { { 0.9, 0.24 }, { 0.95, 0.12 } }, 0.06, "Metal")
	b:cylX("BoltRod", "steel", 0.5, 0.07, 0.36, 0.24, 0.9).m = "Metal"
	b:ball("BoltKnob", "detail", 0.2, 0.62, 0.24, 0.92).m = "Metal"
	b:mirror(function(s) b:box("Accent" .. s, "glow", 0.02, 0.04, 1.4, s * 0.171, 0.3, 0.05) end)
end }

G.order = { "revolver", "pistol", "tactical", "plasma", "raygun", "slim", "pump", "cannon", "awp" }

-- style presets (the category cards): a palette and material per category, applied over any model ----------------------------
G.styles = {
	{ id = "Arctic", look = { primary = { 236, 241, 247 }, secondary = { 148, 184, 214 }, grip = { 38, 48, 66 }, detail = { 176, 186, 198 }, glow = { 90, 200, 255 }, material = "SmoothPlastic", glowAmount = 0.5 } },
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

--!nonstrict
-- data/Themes: colour tokens per theme (RGB 0-255). Pure data, validated for contrast in tests.
-- glass: window background transparency baseline (iOS themes mimic translucent "liquid glass").
-- shape: multiplier for the corner-radius scale (Theme.rad). edge: colour of the thin light edge on glass surfaces.

local function c(r, g, b)
	return { r = r, g = g, b = b }
end

return {
	["iOS"] = {
		shape = 1.0, edge = c(255, 255, 255),
		glass = 0.10, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 6,
		bg0 = c(28, 28, 30), bg1 = c(36, 36, 38), bg2 = c(44, 44, 46), bg3 = c(58, 58, 60),
		stroke = c(84, 84, 88), text = c(255, 255, 255), textDim = c(174, 174, 178),
		accent = c(10, 132, 255), accentText = c(255, 255, 255),
		good = c(48, 209, 88), warn = c(255, 159, 10), bad = c(255, 69, 58), highlight = c(255, 255, 255),
	},
	["iOS Light"] = {
		shape = 1.0, edge = c(255, 255, 255),
		glass = 0.08, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 6,
		bg0 = c(242, 242, 247), bg1 = c(229, 229, 234), bg2 = c(255, 255, 255), bg3 = c(235, 235, 240),
		stroke = c(198, 198, 200), text = c(0, 0, 0), textDim = c(86, 86, 90),
		accent = c(0, 98, 214), accentText = c(255, 255, 255),
		good = c(36, 138, 61), warn = c(178, 80, 0), bad = c(215, 0, 21), highlight = c(255, 255, 255),
	},
	Midnight = {
		shape = 0.7, edge = c(255, 255, 255),
		glass = 0.04, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(15, 17, 26), bg1 = c(20, 23, 35), bg2 = c(27, 31, 46), bg3 = c(38, 43, 63),
		stroke = c(50, 56, 80), text = c(232, 235, 245), textDim = c(150, 158, 182),
		accent = c(110, 120, 255), accentText = c(10, 10, 20),
		good = c(80, 220, 140), warn = c(255, 190, 80), bad = c(255, 100, 110), highlight = c(255, 255, 255),
	},
	Obsidian = {
		shape = 0.55, edge = c(255, 255, 255),
		glass = 0.03, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(10, 10, 10), bg1 = c(16, 16, 16), bg2 = c(24, 24, 24), bg3 = c(36, 36, 36),
		stroke = c(52, 52, 52), text = c(240, 240, 240), textDim = c(160, 160, 160),
		accent = c(235, 235, 235), accentText = c(10, 10, 10),
		good = c(90, 220, 130), warn = c(255, 190, 80), bad = c(255, 100, 100), highlight = c(255, 255, 255),
	},
	Ocean = {
		shape = 0.8, edge = c(255, 255, 255),
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(8, 20, 28), bg1 = c(11, 28, 40), bg2 = c(15, 38, 54), bg3 = c(22, 54, 76),
		stroke = c(34, 76, 104), text = c(225, 244, 250), textDim = c(140, 180, 196),
		accent = c(0, 200, 220), accentText = c(4, 16, 22),
		good = c(80, 230, 150), warn = c(255, 200, 90), bad = c(255, 110, 120), highlight = c(255, 255, 255),
	},
	Rose = {
		shape = 0.8, edge = c(255, 255, 255),
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(24, 13, 18), bg1 = c(32, 17, 24), bg2 = c(43, 23, 32), bg3 = c(62, 33, 46),
		stroke = c(90, 48, 66), text = c(250, 232, 238), textDim = c(190, 146, 162),
		accent = c(255, 95, 150), accentText = c(30, 8, 16),
		good = c(100, 225, 150), warn = c(255, 195, 90), bad = c(255, 110, 120), highlight = c(255, 255, 255),
	},
	Forest = {
		shape = 0.8, edge = c(255, 255, 255),
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(11, 19, 14), bg1 = c(15, 27, 19), bg2 = c(21, 38, 27), bg3 = c(31, 54, 39),
		stroke = c(44, 78, 56), text = c(230, 245, 235), textDim = c(146, 182, 156),
		accent = c(80, 220, 120), accentText = c(6, 20, 10),
		good = c(110, 235, 150), warn = c(255, 200, 90), bad = c(255, 110, 110), highlight = c(255, 255, 255),
	},
	HighContrast = {
		shape = 0.25, edge = c(255, 255, 255),
		glass = 0, font = "GothamBold", fontBold = "GothamBlack", radiusBoost = 0,
		bg0 = c(0, 0, 0), bg1 = c(0, 0, 0), bg2 = c(22, 22, 22), bg3 = c(48, 48, 48),
		stroke = c(255, 255, 255), text = c(255, 255, 255), textDim = c(235, 235, 235),
		accent = c(255, 230, 0), accentText = c(0, 0, 0),
		good = c(0, 255, 120), warn = c(255, 200, 0), bad = c(255, 90, 90), highlight = c(255, 255, 255),
	},
	-- iOS 27 family: crystal glass on pure black with a thick glossy edge. edgeWidth = stroke thickness of big surfaces,
	-- edgeStyle = how the edge is coloured: "white" (wet white gloss), "chrome" (silver bands), "prism" (rainbow refraction),
	-- "violet" (white to violet). Roblox has no real blur, so the "glass" is translucency + edge + sheen, nothing more.
	["iOS 27 Glass"] = {
		shape = 1.15, edge = c(255, 255, 255), edgeWidth = 2.5, edgeStyle = "white",
		glass = 0.16, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 8,
		bg0 = c(0, 0, 0), bg1 = c(14, 14, 18), bg2 = c(26, 26, 32), bg3 = c(44, 44, 52),
		stroke = c(120, 120, 132), text = c(255, 255, 255), textDim = c(190, 190, 200),
		accent = c(235, 240, 255), accentText = c(8, 8, 12),
		good = c(60, 220, 110), warn = c(255, 176, 40), bad = c(255, 82, 72), highlight = c(255, 255, 255),
	},
	["iOS 27 Chrome"] = {
		shape = 1.15, edge = c(255, 255, 255), edgeWidth = 2.5, edgeStyle = "chrome",
		glass = 0.16, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 8,
		bg0 = c(4, 4, 6), bg1 = c(18, 18, 22), bg2 = c(30, 31, 36), bg3 = c(52, 54, 60),
		stroke = c(150, 152, 160), text = c(250, 250, 252), textDim = c(192, 194, 202),
		accent = c(200, 206, 216), accentText = c(10, 10, 14),
		good = c(70, 220, 120), warn = c(255, 180, 50), bad = c(255, 90, 80), highlight = c(255, 255, 255),
	},
	["iOS 27 Prism"] = {
		shape = 1.15, edge = c(255, 255, 255), edgeWidth = 2.5, edgeStyle = "prism",
		glass = 0.16, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 8,
		bg0 = c(0, 0, 2), bg1 = c(14, 13, 20), bg2 = c(26, 24, 36), bg3 = c(44, 41, 60),
		stroke = c(126, 120, 150), text = c(255, 255, 255), textDim = c(196, 190, 214),
		accent = c(120, 200, 255), accentText = c(4, 10, 20),
		good = c(70, 225, 130), warn = c(255, 185, 60), bad = c(255, 92, 100), highlight = c(255, 255, 255),
	},
	["iOS 27 Violet"] = {
		shape = 1.15, edge = c(255, 255, 255), edgeWidth = 2.5, edgeStyle = "violet",
		glass = 0.16, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 8,
		bg0 = c(3, 0, 8), bg1 = c(18, 10, 30), bg2 = c(32, 18, 52), bg3 = c(54, 32, 84),
		stroke = c(140, 104, 196), text = c(255, 255, 255), textDim = c(206, 186, 236),
		accent = c(178, 120, 255), accentText = c(12, 4, 24),
		good = c(80, 225, 140), warn = c(255, 190, 70), bad = c(255, 96, 110), highlight = c(255, 255, 255),
	},
}

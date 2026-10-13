--!nonstrict
-- data/Themes: colour tokens per theme (RGB 0-255). Pure data, validated for contrast in tests.
-- glass: window background transparency baseline (iOS themes mimic translucent "liquid glass").

local function c(r, g, b)
	return { r = r, g = g, b = b }
end

return {
	["iOS"] = {
		glass = 0.10, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 6,
		bg0 = c(28, 28, 30), bg1 = c(36, 36, 38), bg2 = c(44, 44, 46), bg3 = c(58, 58, 60),
		stroke = c(84, 84, 88), text = c(255, 255, 255), textDim = c(174, 174, 178),
		accent = c(10, 132, 255), accentText = c(255, 255, 255),
		good = c(48, 209, 88), warn = c(255, 159, 10), bad = c(255, 69, 58), highlight = c(255, 255, 255),
	},
	["iOS Light"] = {
		glass = 0.08, switchToken = "good", font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 6,
		bg0 = c(242, 242, 247), bg1 = c(229, 229, 234), bg2 = c(255, 255, 255), bg3 = c(235, 235, 240),
		stroke = c(198, 198, 200), text = c(0, 0, 0), textDim = c(86, 86, 90),
		accent = c(0, 98, 214), accentText = c(255, 255, 255),
		good = c(36, 138, 61), warn = c(178, 80, 0), bad = c(215, 0, 21), highlight = c(255, 255, 255),
	},
	Midnight = {
		glass = 0.04, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(15, 17, 26), bg1 = c(20, 23, 35), bg2 = c(27, 31, 46), bg3 = c(38, 43, 63),
		stroke = c(50, 56, 80), text = c(232, 235, 245), textDim = c(150, 158, 182),
		accent = c(110, 120, 255), accentText = c(10, 10, 20),
		good = c(80, 220, 140), warn = c(255, 190, 80), bad = c(255, 100, 110), highlight = c(255, 255, 255),
	},
	Obsidian = {
		glass = 0.03, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(10, 10, 10), bg1 = c(16, 16, 16), bg2 = c(24, 24, 24), bg3 = c(36, 36, 36),
		stroke = c(52, 52, 52), text = c(240, 240, 240), textDim = c(160, 160, 160),
		accent = c(235, 235, 235), accentText = c(10, 10, 10),
		good = c(90, 220, 130), warn = c(255, 190, 80), bad = c(255, 100, 100), highlight = c(255, 255, 255),
	},
	Ocean = {
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(8, 20, 28), bg1 = c(11, 28, 40), bg2 = c(15, 38, 54), bg3 = c(22, 54, 76),
		stroke = c(34, 76, 104), text = c(225, 244, 250), textDim = c(140, 180, 196),
		accent = c(0, 200, 220), accentText = c(4, 16, 22),
		good = c(80, 230, 150), warn = c(255, 200, 90), bad = c(255, 110, 120), highlight = c(255, 255, 255),
	},
	Rose = {
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(24, 13, 18), bg1 = c(32, 17, 24), bg2 = c(43, 23, 32), bg3 = c(62, 33, 46),
		stroke = c(90, 48, 66), text = c(250, 232, 238), textDim = c(190, 146, 162),
		accent = c(255, 95, 150), accentText = c(30, 8, 16),
		good = c(100, 225, 150), warn = c(255, 195, 90), bad = c(255, 110, 120), highlight = c(255, 255, 255),
	},
	Forest = {
		glass = 0.05, font = "GothamMedium", fontBold = "GothamBold", radiusBoost = 0,
		bg0 = c(11, 19, 14), bg1 = c(15, 27, 19), bg2 = c(21, 38, 27), bg3 = c(31, 54, 39),
		stroke = c(44, 78, 56), text = c(230, 245, 235), textDim = c(146, 182, 156),
		accent = c(80, 220, 120), accentText = c(6, 20, 10),
		good = c(110, 235, 150), warn = c(255, 200, 90), bad = c(255, 110, 110), highlight = c(255, 255, 255),
	},
	HighContrast = {
		glass = 0, font = "GothamBold", fontBold = "GothamBlack", radiusBoost = 0,
		bg0 = c(0, 0, 0), bg1 = c(0, 0, 0), bg2 = c(22, 22, 22), bg3 = c(48, 48, 48),
		stroke = c(255, 255, 255), text = c(255, 255, 255), textDim = c(235, 235, 235),
		accent = c(255, 230, 0), accentText = c(0, 0, 0),
		good = c(0, 255, 120), warn = c(255, 200, 0), bad = c(255, 90, 90), highlight = c(255, 255, 255),
	},
}

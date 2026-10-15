--!nonstrict
-- ui/LicenseGate: activation window shown before the hub starts when the build requires a key. The window itself is
-- ui/KeyCard (shared with the loader); this module only connects it to License. Calls onActivated(res) after a valid
-- key was accepted.
-- Depends on: License, Env, Logger, Maid, LicenseText, KeyCard, Flair (sticker image).

local import = ...
local License = import("core/License")
local Env = import("core/Env")
local Logger = import("core/Logger")
local Maid = import("core/Maid")
local Ru = import("core/LicenseText")
local KeyCard = import("ui/KeyCard")
local Flair = import("ui/Flair")

local Gate = {}

-- show(onActivated) -> handle with Destroy()
function Gate.show(onActivated)
	local parent = Env.guiParent()
	if not parent then
		return nil, "no GUI container"
	end
	local maid = Maid.new("license-gate")
	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2HubLicense"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = parent
	maid:Give(gui)

	local card
	card = KeyCard.build(gui, {
		title = Ru.UI.title,
		prompt = Ru.UI.prompt,
		placeholder = Ru.UI.placeholder,
		button = Ru.UI.button,
		busy = Ru.UI.checking,
		sticker = { image = Flair.image("sticker_mouth.png"), frames = 10, cols = 5, cell = 128, period = 4.8 },
		onSubmit = function(text)
			card.setBusy(true)
			local ok, res = License.activate(text)
			if ok and not (type(res) == "table" and res.needsActivation) then
				card.setStatus(Ru.UI.valid .. Ru.remaining(res.remaining), "ok")
				task.delay(0.6, function()
					maid:Clean()
					onActivated(res)
				end)
				return -- stays busy: the card closes itself, a second press must not activate twice
			end
			card.setBusy(false)
			card.setStatus(Ru.ru(ok and Ru.UI.failed or res), "error")
			Logger.warn("License", "activation rejected: %s", tostring(ok and "activation failed" or res))
		end,
	})
	maid:Give(card.destroy)
	card.focus()
	return { Destroy = function() maid:Clean() end }
end

return Gate

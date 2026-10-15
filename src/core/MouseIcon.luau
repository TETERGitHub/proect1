--!nonstrict
-- core/MouseIcon: one owner of UserInputService.MouseIconEnabled. Several parts of the hub want the game's own mouse icon /
-- crosshair hidden (the custom crosshair, the menu's own cursor); each asks under its own name and the icon comes back, as it
-- was before the hub touched it, only when nobody wants it hidden any more. enforce() re-hides it when the game turns it back on
-- (MM2 and the shift-lock camera set the icon again when you equip a gun or switch the camera). Local to your client only.
-- Depends on: Services.

local import = ...
local Services = import("core/Services")

local MouseIcon = {}

local wants = {} -- owner -> true
local original = nil -- MouseIconEnabled before the first hide

local function uis()
	return Services.UserInputService
end

local function anyone()
	return next(wants) ~= nil
end

local function set(v)
	local u = uis()
	if u then
		pcall(function()
			if u.MouseIconEnabled ~= v then
				u.MouseIconEnabled = v
			end
		end)
	end
end

-- hide(owner, on): owner wants the icon hidden (on = true) or no longer cares (on = false)
function MouseIcon.hide(owner, on)
	local u = uis()
	if on then
		if not anyone() and u then
			local ok, v = pcall(function()
				return u.MouseIconEnabled
			end)
			original = (ok and v ~= false) and true or false
		end
		wants[owner] = true
		set(false)
	elseif wants[owner] then
		wants[owner] = nil
		if not anyone() then
			set(original ~= false)
			original = nil
		end
	end
end

-- enforce(): called every frame by an owner; keeps the icon off while someone wants it off
function MouseIcon.enforce()
	if anyone() then
		set(false)
	end
end

function MouseIcon.hidden()
	return anyone()
end

-- reset(): forget every request and put the icon back (hub shutdown)
function MouseIcon.reset()
	if anyone() then
		wants = {}
		set(original ~= false)
		original = nil
	end
end

return MouseIcon

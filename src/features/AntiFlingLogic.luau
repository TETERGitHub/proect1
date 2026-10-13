--!nonstrict
-- features/AntiFlingLogic: pure classification of "is this velocity a fling?" (no Roblox APIs).

local Logic = {}

-- evaluate(v{x,y,z}, w{x,y,z}, params{maxSpeed, angularLimit}) -> abnormal, reason
-- Falling (negative vertical speed) is never abnormal: gravity and jumps off ledges are legitimate.
function Logic.evaluate(v, w, params)
	local horizontal = math.sqrt(v.x * v.x + v.z * v.z)
	if horizontal > params.maxSpeed then
		return true, "horizontal"
	end
	if v.y > params.maxSpeed * 0.9 then
		return true, "vertical"
	end
	local spin = math.sqrt(w.x * w.x + w.y * w.y + w.z * w.z)
	if spin > params.angularLimit then
		return true, "spin"
	end
	return false, nil
end

-- cleaned(v) -> x, y, z : horizontal motion removed, falling kept, upward speed removed.
function Logic.cleaned(v)
	return 0, math.min(v.y, 0), 0
end

return Logic

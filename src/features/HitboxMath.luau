--!nonstrict
-- features/HitboxMath: pure motion patterns of the hitbox lab. Each mode has its OWN parameters and
-- affects exactly one thing: the lab hitbox position (HubLabHitbox.Position). Nothing else - not the lab
-- body, not your character, not any real game hitbox - is read or written by these functions.

local HitboxMath = {}

HitboxMath.MODES = {
	Off = { affects = "nothing", params = {} },
	Orbit = { affects = "HubLabHitbox.Position", params = { "orbitRadius", "orbitSpeed", "orbitTilt" } },
	Jitter = { affects = "HubLabHitbox.Position", params = { "jitterAmplitude", "jitterSpeed" } },
	Blink = { affects = "HubLabHitbox.Position", params = { "blinkRange", "blinkInterval" } },
}

-- Deterministic pseudo-random in [0,1) (math.random would make tests unrepeatable).
local function hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end
HitboxMath.hash = hash

-- offset(mode, t, p) -> x, y, z      p = { orbitRadius, orbitSpeed, orbitTilt, jitterAmplitude, jitterSpeed, blinkRange, blinkInterval }
-- Bounds: Orbit <= orbitRadius, Jitter <= jitterAmplitude, Blink <= blinkRange (all from the base position).
function HitboxMath.offset(mode, t, p)
	if mode == "Orbit" then
		local r = p.orbitRadius
		local a = t * p.orbitSpeed / math.max(r, 1) -- angular rate so orbitSpeed is a linear speed
		local x, y, z = math.cos(a), math.sin(a * 0.5) * p.orbitTilt, math.sin(a)
		local k = r / math.sqrt(1 + p.orbitTilt * p.orbitTilt)
		return x * k, y * k, z * k
	elseif mode == "Jitter" then
		local f = p.jitterSpeed * 0.7
		local x = math.sin(t * f * 1.3 + 1.0) * math.cos(t * f * 0.7)
		local y = math.sin(t * f * 0.9 + 2.0) * 0.4
		local z = math.cos(t * f * 1.1 + 0.5) * math.sin(t * f * 0.5 + 3.0)
		local m = math.sqrt(x * x + y * y + z * z)
		local k = m > 1 and (p.jitterAmplitude / m) or p.jitterAmplitude
		return x * k, y * k, z * k
	elseif mode == "Blink" then
		local step = math.floor(t / p.blinkInterval)
		local a = hash(step) * math.pi * 2
		local d = p.blinkRange * (0.4 + 0.6 * hash(step + 1000))
		local y = (hash(step + 2000) - 0.5) * p.blinkRange * 0.4
		-- keep the whole jump inside the stated range
		local m = math.sqrt(d * d + y * y)
		local k = m > p.blinkRange and p.blinkRange / m or 1
		return math.cos(a) * d * k, y * k, math.sin(a) * d * k
	end
	return 0, 0, 0
end

return HitboxMath

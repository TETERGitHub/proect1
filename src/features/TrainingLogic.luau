--!nonstrict
-- features/TrainingLogic: pure logic of the local training range: target layout,
-- motion patterns, ray/sphere hit tests and accuracy statistics.
-- Vectors are plain {x,y,z} tables.

local TL = {}

-- layout(count, distance, rng) -> list of {x,y,z} offsets in a forward arc (yaw 0 faces -Z)
function TL.layout(count, distance, rng)
	rng = rng or math.random
	local out = {}
	for i = 1, count do
		local frac = count == 1 and 0.5 or (i - 1) / (count - 1)
		local angle = math.rad(-40 + 80 * frac)
		local height = 4 + rng() * 8
		table.insert(out, {
			x = -math.sin(angle) * distance,
			y = height,
			z = -math.cos(angle) * distance,
		})
	end
	return out
end

-- motion(mode, t, speed, index) -> dx, dy, dz, visible
-- Strafing: sideways sine; Popup: targets appear for 1.2 s of every 2 s; Static: none.
function TL.motion(mode, t, speed, index)
	if mode == "Strafing" then
		local amplitude = 10
		local freq = speed > 0 and speed / amplitude or 0
		return math.sin(t * freq + index * 1.3) * amplitude, math.sin(t * freq * 0.5 + index) * 1.5, 0, true
	elseif mode == "Popup" then
		local phase = (t * 0.5 + index * 0.37) % 2
		local visible = phase < 1.2
		return 0, visible and 0 or -6, 0, visible
	end
	return 0, 0, 0, true
end

-- raySphere(origin, dir, centre, radius) -> distance|nil (dir must be unit length)
function TL.raySphere(o, d, c, r)
	local lx, ly, lz = c.x - o.x, c.y - o.y, c.z - o.z
	local tca = lx * d.x + ly * d.y + lz * d.z
	if tca < 0 then
		return nil
	end
	local d2 = lx * lx + ly * ly + lz * lz - tca * tca
	local r2 = r * r
	if d2 > r2 then
		return nil
	end
	return tca - math.sqrt(r2 - d2)
end

-- Stats ----------------------------------------------------------------------------

local Stats = {}
Stats.__index = Stats

function TL.newStats()
	return setmetatable({ shots = 0, hits = 0, kills = 0, reactionSum = 0, reactionCount = 0, best = nil }, Stats)
end

function Stats:shot(hit, reaction)
	self.shots += 1
	if hit then
		self.hits += 1
		if type(reaction) == "number" and reaction >= 0 then
			self.reactionSum += reaction
			self.reactionCount += 1
			if not self.best or reaction < self.best then
				self.best = reaction
			end
		end
	end
end

function Stats:kill()
	self.kills += 1
end

function Stats:accuracy()
	if self.shots == 0 then
		return 0
	end
	return self.hits / self.shots
end

function Stats:averageReaction()
	if self.reactionCount == 0 then
		return nil
	end
	return self.reactionSum / self.reactionCount
end

function Stats:summary()
	return {
		shots = self.shots,
		hits = self.hits,
		kills = self.kills,
		accuracy = self:accuracy(),
		reaction = self:averageReaction(),
		best = self.best,
	}
end

function Stats:reset()
	self.shots, self.hits, self.kills, self.reactionSum, self.reactionCount, self.best = 0, 0, 0, 0, 0, nil
end

-- Velocity limits ---------------------------------------------------------------------

-- clampVelocity(vx,vy,vz,maxSpeed) -> vx,vy,vz
function TL.clampVelocity(vx, vy, vz, maxSpeed)
	local m = math.sqrt(vx * vx + vy * vy + vz * vz)
	if m > maxSpeed and m > 0 then
		local k = maxSpeed / m
		return vx * k, vy * k, vz * k
	end
	return vx, vy, vz
end

return TL

--!nonstrict
-- features/DroneMath: pure fixed-wing flight model for the FPV/loitering drone visual.
-- Convention matches Roblox: heading yaw=0 faces -Z, positive yaw turns left,
-- positive pitch climbs. No Roblox APIs are used here.

local DroneMath = {}

DroneMath.MAX_PITCH = math.rad(70)

function DroneMath.newState(x, y, z, yaw)
	return { x = x, y = y, z = z, yaw = yaw or 0, pitch = 0, roll = 0, speed = 0 }
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- direction(state) -> dx, dy, dz (unit)
function DroneMath.direction(state)
	local cp = math.cos(state.pitch)
	return -math.sin(state.yaw) * cp, math.sin(state.pitch), -math.cos(state.yaw) * cp
end

-- step(state, input, dt, params)
-- input = {turn=-1..1 (left positive), pitch=-1..1 (up positive), throttle=-1..1}
-- params = {cruise, minFactor, maxFactor, accel, turnRate, pitchRate, bankMax, minY}
function DroneMath.step(state, input, dt, params)
	dt = clamp(dt, 0, 0.1) -- guard against frame hitches
	local cruise = params.cruise
	local minSpeed = cruise * (params.minFactor or 0.4)
	local maxSpeed = cruise * (params.maxFactor or 1.5)

	-- speed: eases toward the throttle-selected target
	local target = cruise
	if input.throttle > 0 then
		target = cruise + (maxSpeed - cruise) * input.throttle
	elseif input.throttle < 0 then
		target = cruise + (cruise - minSpeed) * input.throttle
	end
	local accel = params.accel or 40
	if state.speed < target then
		state.speed = math.min(target, state.speed + accel * dt)
	else
		state.speed = math.max(target, state.speed - accel * dt)
	end

	-- heading
	state.yaw = (state.yaw + clamp(input.turn, -1, 1) * params.turnRate * dt) % (2 * math.pi)
	local wantPitch = clamp(input.pitch, -1, 1) * DroneMath.MAX_PITCH
	local pitchRate = params.pitchRate or 1.8
	local dp = wantPitch - state.pitch
	local maxDp = pitchRate * dt
	state.pitch = clamp(state.pitch + clamp(dp, -maxDp, maxDp), -DroneMath.MAX_PITCH, DroneMath.MAX_PITCH)

	-- bank into the turn (visual only)
	local wantRoll = clamp(input.turn, -1, 1) * (params.bankMax or math.rad(55))
	state.roll = state.roll + (wantRoll - state.roll) * clamp(dt * 5, 0, 1)

	local dx, dy, dz = DroneMath.direction(state)
	local ox, oy, oz = state.x, state.y, state.z
	state.x += dx * state.speed * dt
	state.y += dy * state.speed * dt
	state.z += dz * state.speed * dt
	if params.minY and state.y < params.minY then
		state.y = params.minY
		if state.pitch < 0 then
			state.pitch = 0
		end
	end
	return ox, oy, oz -- previous position for swept collision tests
end

-- sweepHit: does the segment (a->b) pass within `radius` of centre c?
function DroneMath.sweepHit(ax, ay, az, bx, by, bz, cx, cy, cz, radius)
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local len2 = abx * abx + aby * aby + abz * abz
	local t = 0
	if len2 > 1e-9 then
		t = clamp(((cx - ax) * abx + (cy - ay) * aby + (cz - az) * abz) / len2, 0, 1)
	end
	local px, py, pz = ax + abx * t, ay + aby * t, az + abz * t
	local dx, dy, dz = cx - px, cy - py, cz - pz
	return dx * dx + dy * dy + dz * dz <= radius * radius
end

-- chaseCamera(state, distance, height) -> camera position x,y,z and look-at x,y,z (slightly ahead)
function DroneMath.chaseCamera(state, distance, height)
	local dx, dy, dz = DroneMath.direction(state)
	-- level the offset (ignore pitch for the horizontal pull-back so the camera does not dive into the floor)
	local hx, hz = -math.sin(state.yaw), -math.cos(state.yaw)
	local cx = state.x - hx * distance
	local cy = state.y + height - dy * distance * 0.3
	local cz = state.z - hz * distance
	return cx, cy, cz, state.x + dx * 30, state.y + dy * 30, state.z + dz * 30
end

-- Knock-back direction for an impact: from drone heading, with upward bias.
function DroneMath.impactVector(state, force, upBias)
	local dx, dy, dz = DroneMath.direction(state)
	return dx * force, dy * force + (upBias or 0.4) * force, dz * force
end

-- axes(keys, invertPitch) -> turn, pitch, throttle from a table of held keys.
-- keys: {W,S,A,D,Space,Shift,Up,Down,Left,Right}. W/Up pitch the nose down (FPV style) unless inverted.
function DroneMath.axes(keys, invertPitch)
	local function v(a, b)
		return ((keys[a] or keys[b]) and 1 or 0)
	end
	local pitch = v("S", "Down") - v("W", "Up")
	if invertPitch then
		pitch = -pitch
	end
	local turn = v("A", "Left") - v("D", "Right")
	local throttle = (keys.Space and 1 or 0) - (keys.Shift and 1 or 0)
	return turn, pitch, throttle
end

return DroneMath

--!nonstrict
-- ui/Motion: animation helpers. Every duration is scaled by ui.animSpeed and animations
-- are skipped entirely (instant property writes) when speed is 0 or the low profile is on.
-- Easing choices: Quint/Exponential Out for smooth deceleration, Back Out for the springy
-- overshoot used by iOS-style switches and sheets.
-- Depends on: Settings, Perf, Services.

local import = ...
local Settings = import("core/Settings")
local Perf = import("core/Perf")
local Services = import("core/Services")

local Motion = {}

-- Duration classes (seconds at animation speed 1): fast = direct feedback to input, std = a state change,
-- slow = a large layer appearing. Components pick a class instead of inventing a number.
Motion.D = { fast = 0.12, std = 0.22, slow = 0.4 }

-- weak: instance -> list of { tween, props }. Starting a tween on a property cancels the running tween of the
-- same property, so two animations never fight over one value and old tweens do not pile up.
local active = setmetatable({}, { __mode = "k" })

function Motion.enabled()
	return Settings.get("ui.animSpeed") > 0 and not Perf.isLow()
end

function Motion.duration(base)
	local speed = Settings.get("ui.animSpeed")
	if speed <= 0 then
		return 0
	end
	return base / speed
end

local STYLES = {
	smooth = { "Quint", "Out" },
	snap = { "Exponential", "Out" },
	spring = { "Back", "Out" },
	bounce = { "Elastic", "Out" },
	ease = { "Sine", "InOut" },
	enter = { "Quart", "Out" },
	exit = { "Quart", "In" },
}

-- reduced effects trade the springy styles for plain easing
local function curve(style)
	if Settings.get("ui.reduceEffects") and (style == "spring" or style == "bounce") then
		return "smooth"
	end
	return style or "smooth"
end

local function forget(inst, entry)
	local list = active[inst]
	if list then
		local i = table.find(list, entry)
		if i then
			table.remove(list, i)
		end
		if #list == 0 then
			active[inst] = nil
		end
	end
end

-- cancel(inst): stop every running tween on inst (used before destroying or re-parenting)
function Motion.cancel(inst)
	local list = active[inst]
	if list then
		active[inst] = nil
		for _, entry in ipairs(list) do
			pcall(function()
				entry.tween:Cancel()
			end)
		end
	end
end

local function cancelOverlapping(inst, goal)
	local list = active[inst]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		local entry = list[i]
		for k in pairs(goal) do
			if entry.props[k] then
				table.remove(list, i)
				pcall(function()
					entry.tween:Cancel()
				end)
				break
			end
		end
	end
	if #list == 0 then
		active[inst] = nil
	end
end

function Motion.activeCount()
	local n = 0
	for _, list in pairs(active) do
		n += #list
	end
	return n
end

-- tween(inst, goal, base, style) -> tween|nil
function Motion.tween(inst, goal, base, style)
	if not inst then
		return nil
	end
	if not Motion.enabled() then
		for k, v in pairs(goal) do
			pcall(function()
				inst[k] = v
			end)
		end
		return nil
	end
	local s = STYLES[curve(style)] or STYLES.smooth
	local info = TweenInfo.new(Motion.duration(base or 0.25), Enum.EasingStyle[s[1]], Enum.EasingDirection[s[2]])
	cancelOverlapping(inst, goal)
	local ok, tw = pcall(function()
		return Services.TweenService:Create(inst, info, goal)
	end)
	if ok and tw then
		local props = {}
		for k in pairs(goal) do
			props[k] = true
		end
		local entry = { tween = tw, props = props }
		local list = active[inst]
		if not list then
			list = {}
			active[inst] = list
		end
		table.insert(list, entry)
		if tw.Completed then
			tw.Completed:Once(function()
				forget(inst, entry)
			end)
		end
		tw:Play()
		return tw
	end
	for k, v in pairs(goal) do
		pcall(function()
			inst[k] = v
		end)
	end
	return nil
end

-- pressable(button, maid, strength): iOS-style press feedback (shrink on press, springy release).
function Motion.pressable(button, maid, strength)
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button
	local down = 1 - (strength or 0.04)
	maid:Give(button.MouseButton1Down:Connect(function()
		Motion.tween(scale, { Scale = down }, 0.12, "snap")
	end))
	local function release()
		Motion.tween(scale, { Scale = 1 }, 0.35, "spring")
	end
	maid:Give(button.MouseButton1Up:Connect(release))
	maid:Give(button.MouseLeave:Connect(release))
	return scale
end

-- countTo(label, from, to, formatFn, base): animated number change without a per-frame loop
-- (steps are driven by a short tween on a NumberValue).
function Motion.countTo(label, from, to, fmt, base)
	if not Motion.enabled() or from == to then
		label.Text = fmt(to)
		return nil
	end
	local value = Instance.new("NumberValue")
	value.Value = from
	local conn = value.Changed:Connect(function(v)
		label.Text = fmt(v)
	end)
	local tw = Motion.tween(value, { Value = to }, base or 0.4, "smooth")
	if tw then
		tw.Completed:Once(function()
			conn:Disconnect()
			value:Destroy()
			label.Text = fmt(to)
		end)
	else
		conn:Disconnect()
		value:Destroy()
		label.Text = fmt(to)
	end
	return tw
end

-- pulse(inst, prop, from, to): one-shot attention flash (used when search jumps to a control)
function Motion.flash(inst, prop, flashValue, restValue)
	inst[prop] = flashValue
	Motion.tween(inst, { [prop] = restValue }, 0.9, "smooth")
end

return Motion

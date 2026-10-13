--!nonstrict
-- core/Input: hotkey bindings stored in Settings (keys.<action>), conflict
-- detection, rebinding capture, typing/focus guards.
-- Logic is event-source agnostic (Input.handle) so it is unit-testable;
-- Input.connect() hooks the real UserInputService.
-- Depends on: Settings, Actions, Logger, Signal, Maid.

local import = ...
local Settings = import("core/Settings")
local Actions = import("core/Actions")
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local Input = {}

Input.Rebound = Signal.new("Input.Rebound") -- (actionId, newKey, oldKey)
Input.CaptureChanged = Signal.new("Input.CaptureChanged") -- (isCapturing)

local bindings = {} -- actionId -> {id, settingKey, name, default, hubOnly}
local order = {}
local capture = nil
local pressed = {}

local EXTRA_KEYS = { None = true, Mouse2 = true, Mouse3 = true }

local function settingKeyFor(actionId)
	return "keys." .. string.gsub(actionId, "[^%w_]", "_")
end

-- Input.isValidKey(name): "None", mouse buttons, or a member of Enum.KeyCode when present.
function Input.isValidKey(name)
	if type(name) ~= "string" then
		return false
	end
	if EXTRA_KEYS[name] then
		return true
	end
	if typeof(Enum) == "Enums" or type(Enum) == "table" then
		local ok, found = pcall(function()
			return Enum.KeyCode[name] ~= nil
		end)
		if ok then
			return found
		end
	end
	return string.match(name, "^%w+$") ~= nil
end

-- bind(actionId, defaultKey, {name=, hubOnly=})
function Input.bind(actionId, defaultKey, opts)
	assert(Actions.has(actionId), "bind: unknown action " .. tostring(actionId))
	assert(not bindings[actionId], "bind: already bound " .. actionId)
	assert(Input.isValidKey(defaultKey), "bind: invalid default key " .. tostring(defaultKey))
	opts = opts or {}
	local settingKey = settingKeyFor(actionId)
	local action = Actions.get(actionId)
	Settings.define({
		key = settingKey,
		type = "key",
		default = defaultKey,
		category = "keys",
		module = "Input",
		label = opts.name or action.name,
		desc = "Hotkey for: " .. action.name,
	})
	bindings[actionId] = {
		id = actionId,
		settingKey = settingKey,
		name = opts.name or action.name,
		default = defaultKey,
		hubOnly = opts.hubOnly == true,
	}
	table.insert(order, actionId)
end

function Input.keyOf(actionId)
	local b = bindings[actionId]
	return b and Settings.get(b.settingKey) or nil
end

function Input.list()
	local out = {}
	for _, id in ipairs(order) do
		local b = bindings[id]
		table.insert(out, {
			id = id,
			name = b.name,
			key = Settings.get(b.settingKey),
			default = b.default,
			hubOnly = b.hubOnly,
			settingKey = b.settingKey,
		})
	end
	return out
end

-- conflicts() -> list of {key, actions = {ids}}
function Input.conflicts()
	local byKey = {}
	for _, id in ipairs(order) do
		local key = Settings.get(bindings[id].settingKey)
		if key ~= "None" then
			byKey[key] = byKey[key] or {}
			table.insert(byKey[key], id)
		end
	end
	local out = {}
	for key, ids in pairs(byKey) do
		if #ids > 1 then
			table.insert(out, { key = key, actions = ids })
		end
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- rebind(actionId, key, force?) -> ok, errOrNil, conflictingActionId
function Input.rebind(actionId, key, force)
	local b = bindings[actionId]
	if not b then
		return false, "unknown binding"
	end
	if not Input.isValidKey(key) then
		return false, "invalid key: " .. tostring(key)
	end
	if key ~= "None" then
		for _, id in ipairs(order) do
			if id ~= actionId and Settings.get(bindings[id].settingKey) == key then
				if not force then
					return false, string.format("%s is already used by '%s'", key, bindings[id].name), id
				end
				Settings.set(bindings[id].settingKey, "None", "rebind-steal")
			end
		end
	end
	local old = Settings.get(b.settingKey)
	local ok, err = Settings.set(b.settingKey, key, "rebind")
	if not ok then
		return false, err
	end
	if old ~= key then
		Input.Rebound:Fire(actionId, key, old)
	end
	return true
end

function Input.clear(actionId)
	return Input.rebind(actionId, "None")
end

function Input.resetBinding(actionId)
	local b = bindings[actionId]
	if not b then
		return false, "unknown binding"
	end
	return Input.rebind(actionId, b.default, true)
end

-- Capture ----------------------------------------------------------------------

function Input.isCapturing()
	return capture ~= nil
end

-- startCapture(callback): next key press is delivered as callback(keyName); Escape cancels (nil).
function Input.startCapture(callback)
	assert(type(callback) == "function", "callback required")
	if capture then
		local old = capture
		capture = nil
		pcall(old, nil)
	end
	capture = callback
	Input.CaptureChanged:Fire(true)
end

function Input.cancelCapture()
	if capture then
		local cb = capture
		capture = nil
		Input.CaptureChanged:Fire(false)
		pcall(cb, nil)
	end
end

-- Event handling ---------------------------------------------------------------

-- handle(keyName, typing, hubVisible) -> list of action ids that fired
function Input.handle(keyName, typing, hubVisible)
	pressed[keyName] = true
	if capture then
		local cb = capture
		capture = nil
		Input.CaptureChanged:Fire(false)
		if keyName == "Escape" then
			pcall(cb, nil)
		else
			pcall(cb, keyName)
		end
		return {}
	end
	if not Settings.get("input.enabled") then
		return {}
	end
	if typing and Settings.get("input.ignoreTyping") then
		return {}
	end
	local fired = {}
	for _, id in ipairs(order) do
		local b = bindings[id]
		if (not b.hubOnly or hubVisible) and Settings.get(b.settingKey) == keyName then
			table.insert(fired, id)
			Actions.run(id)
		end
	end
	return fired
end

function Input.release(keyName)
	pressed[keyName] = nil
end

function Input.isDown(keyName)
	return pressed[keyName] == true
end

-- Window lost focus: held keys would never report release, so drop state and cancel capture.
function Input.focusLost()
	table.clear(pressed)
	Input.cancelCapture()
end

local function keyNameOf(inputObject)
	local t = inputObject.UserInputType
	if t == Enum.UserInputType.Keyboard then
		return inputObject.KeyCode.Name
	elseif t == Enum.UserInputType.MouseButton3 then
		return "Mouse3"
	elseif t == Enum.UserInputType.MouseButton2 then
		return "Mouse2"
	end
	return nil
end

-- connect(uis, maid, hubVisibleFn) hooks UserInputService events into handle().
function Input.connect(uis, maid, hubVisibleFn)
	maid:Give(uis.InputBegan:Connect(function(inputObject)
		local name = keyNameOf(inputObject)
		if not name then
			return
		end
		local typing = uis:GetFocusedTextBox() ~= nil
		local ok, err = pcall(Input.handle, name, typing, hubVisibleFn())
		if not ok then
			Logger.error("Input", "handler error: %s", tostring(err))
		end
	end))
	maid:Give(uis.InputEnded:Connect(function(inputObject)
		local name = keyNameOf(inputObject)
		if name then
			Input.release(name)
		end
	end))
	maid:Give(uis.WindowFocusReleased:Connect(Input.focusLost))
end

function Input._reset()
	table.clear(bindings)
	table.clear(order)
	table.clear(pressed)
	capture = nil
	Input.Rebound:DisconnectAll()
	Input.CaptureChanged:DisconnectAll()
end

return Input

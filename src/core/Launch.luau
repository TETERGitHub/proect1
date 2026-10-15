--!nonstrict
-- core/Launch: what the licensed loader passed to the hub when it started it (loader/Loader: serverUrl, key, uid, request).
-- Empty when the hub bundle is run directly. Read-only; used by features/ModelSync to fetch the models pack from the same server.
-- Depends on: nothing (the bundle header keeps the value in __LAUNCH).

local launch = type(__LAUNCH) == "table" and __LAUNCH or {}

return {
	serverUrl = type(launch.serverUrl) == "string" and launch.serverUrl or nil,
	key = type(launch.key) == "string" and launch.key or nil,
	uid = launch.uid,
	request = type(launch.request) == "function" and launch.request or nil,
}

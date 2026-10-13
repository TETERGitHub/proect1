--!nonstrict
-- main: bundle entry point. Everything is started by app/Hub.
local import = ...
local Hub = import("app/Hub")
return Hub.run({})

-- Main modifier key + shared helpers for keybinding files.
-- Returns the main modifier string used by all keybinding files.
--
-- Usage:
--   local mainMod = require("config.keybindings.modkey")
--   hl.bind(mainMod .. " + Q", ...)

return "SUPER"

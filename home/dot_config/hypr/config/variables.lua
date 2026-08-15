-- Programs/apps aliases used elsewhere in this config.
-- Require this file first so vars are available to keybindings and autostart.
--
-- Usage:
--   local vars = require("config.variables")
--   hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(vars.terminal))

local vars = {
    terminal    = "kitty",
    fileManager = "nautilus --new-window",
    browser     = "brave",
}

return vars

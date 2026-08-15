local mainMod = require("config.keybindings.modkey")

local screenshot = hl.dsp.exec_cmd("hyprshot -m region --freeze")

-- Nút Print Screen
hl.bind("Print", screenshot)

-- Super + Shift + S
hl.bind(mainMod .. " + SHIFT + S", screenshot)

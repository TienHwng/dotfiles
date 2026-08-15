-- Misc settings (wallpaper, hyprland logo toggle).
-- Splash + background colors sourced from Catppuccin Frappe
-- (config/look/colors.lua) to match starship + fastfetch.

local c = require("config.look.colors")

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
        col = {
            splash = c.lavender,  -- Splash text color
        },
        background_color = c.base, -- Default background if wallpaper not loaded
    },
})

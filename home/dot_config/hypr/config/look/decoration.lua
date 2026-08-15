-- Window decoration: rounding, opacity, shadow, blur.
-- Shadow color sourced from Catppuccin Frappe crust palette
-- (config/look/colors.lua) to match starship + fastfetch.

local c = require("config.look.colors")

hl.config({
    decoration = {
        rounding         = 10,
        rounding_power   = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow           = {
            enabled        = true,
            range          = 4,
            render_power   = 3,
            color          = c.crust_dim_hex,    -- Catppuccin crust shadow (AARRGGBB int)
            color_inactive = c.surface1_dim_hex, -- Lighter shadow on inactive windows
        },

        blur             = {
            enabled           = true,
            size              = 12,
            passes            = 2,
            ignore_opacity    = true,

            noise             = 0.05,
            contrast          = 1.5,
            brightness        = 1,

            xray              = true,
            new_optimizations = true,
            vibrancy          = 0.1696,
        },
    },
})

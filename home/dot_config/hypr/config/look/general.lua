-- General look-and-feel: gaps, borders, layout, resize_on_border, tearing.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/
-- Colors below are sourced from Catppuccin Frappe (config/look/colors.lua)
-- to stay in sync with starship + fastfetch.

local c = require("config.look.colors")

hl.config({
    general = {
        gaps_in          = 5,
        gaps_out         = 10,

        border_size      = 2,

        col              = {
            -- Catppuccin Frappe: lavender -> mauve -> blue gradient border.
            active_border         = { colors = { c.lavender, c.mauve, c.blue }, angle = 135 },
            inactive_border       = c.overlay1_dim,
            nogroup_border        = c.yellow_dim,
            nogroup_border_active = c.peach,
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing    = false,

        -- layout = "dwindle",
    },
    xwayland = {
        force_zero_scaling = true,
    },
})

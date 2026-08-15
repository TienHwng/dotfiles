-- =========================================================
-- Catppuccin Frappe palette (synced with starship/fastfetch).
-- Provide both rgba(RRGGBBAA) strings and 0xAARRGGBB hex literals so
-- any Hyprland field can pick whichever format it accepts.
-- Usage:
--   local c = require("config.look.colors")
--   hl.config({ general = { col = { active_border = { colors = { c.lavender, c.mauve }, angle = 135 } } } })
-- =========================================================

-- Helper: build an rgba() string from #RRGGBB and an alpha byte.
local function rgba(hex, alpha)
    return "rgba(" .. hex .. alpha .. ")"
end

local C = {
    -- Catppuccin Frappe accents
    rosewater = rgba("f2d5cf", "ee"),
    flamingo  = rgba("eebebe", "ee"),
    pink      = rgba("f4b8e4", "ee"),
    mauve     = rgba("ca9ee6", "ee"),
    red       = rgba("e78284", "ee"),
    maroon    = rgba("ea999c", "ee"),
    peach     = rgba("ef9f76", "ee"),
    yellow    = rgba("e5c890", "ee"),
    green     = rgba("a6d189", "ee"),
    teal      = rgba("81c8be", "ee"),
    sky       = rgba("99d1db", "ee"),
    sapphire  = rgba("85c1dc", "ee"),
    blue      = rgba("8caaee", "ee"),
    lavender  = rgba("babbf1", "ee"),

    -- Neutrals
    text      = rgba("c6d0f5", "ee"),
    subtext1  = rgba("b5bfe2", "ee"),
    subtext0  = rgba("a5adce", "ee"),
    overlay2  = rgba("949cbb", "ee"),
    overlay1  = rgba("838ba7", "ee"),
    overlay0  = rgba("737994", "ee"),
    surface2  = rgba("626880", "ee"),
    surface1  = rgba("51576d", "ee"),
    surface0  = rgba("414559", "ee"),
    base      = rgba("303446", "ee"),
    mantle    = rgba("292c3c", "ee"),
    crust     = rgba("232634", "ee"),

    -- Translucent overlays for inactive borders / dim backgrounds
    rosewater_dim = rgba("f2d5cf", "aa"),
    mauve_dim     = rgba("ca9ee6", "aa"),
    blue_dim      = rgba("8caaee", "aa"),
    overlay0_dim  = rgba("737994", "aa"),
    overlay1_dim  = rgba("838ba7", "aa"),
    surface1_dim  = rgba("51576d", "aa"),
    yellow_dim    = rgba("e5c890", "aa"),
    crust_dim     = rgba("232634", "cc"),

    -- 0xAARRGGBB hex literals for Hyprland fields that need a number
    rosewater_hex = 0xeef2d5cf,
    flamingo_hex  = 0xeeeebebe,
    pink_hex      = 0xeef4b8e4,
    mauve_hex     = 0xeeca9ee6,
    red_hex       = 0xeee78284,
    maroon_hex    = 0xeeea999c,
    peach_hex     = 0xeeef9f76,
    yellow_hex    = 0xeee5c890,
    green_hex     = 0xeea6d189,
    teal_hex      = 0xee81c8be,
    sky_hex       = 0xee99d1db,
    sapphire_hex  = 0xee85c1dc,
    blue_hex      = 0xee8caaee,
    lavender_hex  = 0xeebabbf1,

    surface0_hex  = 0xee414559,
    surface1_hex  = 0xee51576d,
    overlay0_hex  = 0xee737994,
    overlay1_hex  = 0xee838ba7,
    base_hex      = 0xee303446,
    mantle_hex    = 0xee292c3c,
    crust_hex     = 0xee232634,

    -- Lower-alpha hex for inactive borders / shadows (AARRGGBB)
    rosewater_dim_hex = 0xaaf2d5cf,
    mauve_dim_hex     = 0xaaca9ee6,
    blue_dim_hex      = 0xaa8caaee,
    overlay1_dim_hex  = 0xaa838ba7,
    surface1_dim_hex  = 0xaa51576d,
    yellow_dim_hex    = 0xaae5c890,
    crust_dim_hex     = 0xcc232634,
}

return C
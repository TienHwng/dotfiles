-- Window-related keybindings (close, float toggle, pseudo, togglesplit)

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
-- App-launcher binds (SUPER+Q/B/E/R/M) moved to config/keybindings/apps.lua
-- closeWindowBind:set_enabled(false)
local mainMod = require("config.keybindings.modkey")

-- local closeWindowBind = 
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({
    mode = "maximized",
    action = "toggle",
}))

hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({
    mode = "fullscreen",
    action = "toggle",
}))

hl.bind(mainMod .. " + Tab", function()
    local win = hl.get_active_window()
    if not win then return end

    local mode = win.fullscreen

    hl.dispatch(
	hl.dsp.window.cycle_next({
	    tiled = true
	})
    )

    -- If previous mode is maximized
    if mode == 1 then
	hl.dispatch(
	    hl.dsp.window.fullscreen({
		mode = "maximized",
		action = "set"
	    })
	)

    -- If previous mode is fullscreen
    elseif mode == 2 then
	hl.dispatch(
	    hl.dsp.window.fullscreen({
		mode = "fullscreen",
		action = "set"
	    })
	)
    end
end)

hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only


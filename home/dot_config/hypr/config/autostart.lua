-- Autostart applications launched once Hyprland starts.
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("kbuildsycoca6 --noincremental")

    -- Chezmoi Autostart
    hl.exec_cmd("sleep 5 && chezmoi update")
end)

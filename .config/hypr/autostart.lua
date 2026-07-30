-- Extra autostart processes

hl.on("hyprland.start", function ()
    -- Sets the cursor to Moga
    hl.exec_cmd("hyprctl setcursor Moga-Cursor 24")

    -- Opens PC Panel, StreamDeck UI, then closes both windows.
    hl.exec_cmd("uwsm app -- pcpanel")
    -- hl.exec_cmd("uwsm app -- opendeck")
    -- hl.exec_cmd("sh -c 'sleep 3 && ~/.config/hypr/close-autostarts.sh'")

    -- Launches Sunshine on boot
    -- hl.exec_cmd("uwsm app -- sunshine")

    -- Launches Music Presence on boot + Launch fix
    -- hl.exec_cmd("sleep 5 && uwsm app -- musicpresence")

    -- Audient Fix
    hl.exec_cmd([[bash -c 'card=$(aplay -l | grep "iD14" | sed "s/:.*$//g" | sed "s/card //"); amixer -c $card sset "Speaker" 100%']])
end)

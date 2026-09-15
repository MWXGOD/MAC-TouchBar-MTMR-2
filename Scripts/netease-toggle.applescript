tell application "System Events"
    tell process "NeteaseMusic"
        tell menu bar 1
            tell menu bar item "控制"
                tell menu 1
                    if exists menu item "暂停" then
                        click menu item "暂停"
                    else if exists menu item "播放" then
                        click menu item "播放"
                    else
                        error number 3
                    end if
                end tell
            end tell
        end tell
    end tell
end tell

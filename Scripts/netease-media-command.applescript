on run argv
    if (count of argv) is not 1 then error number 2
    set commandName to item 1 of argv

    tell application "System Events"
        tell process "NeteaseMusic"
            tell menu bar 1
                tell menu bar item "控制"
                    tell menu 1
                        if commandName is "previous" then
                            click menu item "上一个"
                        else if commandName is "next" then
                            click menu item "下一个"
                        else if commandName is "toggle" then
                            if exists menu item "暂停" then
                                click menu item "暂停"
                            else if exists menu item "播放" then
                                click menu item "播放"
                            else
                                error number 3
                            end if
                        else
                            error number 2
                        end if
                    end tell
                end tell
            end tell
        end tell
    end tell
end run

#!/bin/bash
# 停止并移除企微读取器。已读到的聊天记录保留，要删请自己删下面显示的文件夹。
root="$HOME/Library/Application Support/wecom-reader"
label=local.wecom-reader
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
pkill -f "$root/bin/wecom-reader daemon" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
# 启动器留着：系统权限绑在这个文件上，删了再装，开关看着是开的其实不起作用。
rm -f "$root/bin/wecom-reader"
echo "已卸载。以后再装不用重新开权限。"
echo "要彻底删掉：先在系统设置「辅助功能」里移除 wecom-reader-launcher，再删下面的文件夹。"
echo "聊天记录还在：$root"

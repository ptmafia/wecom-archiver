#!/bin/bash
# 把企微读取器装到这台 Mac。聊天只存在这台电脑上，不上传。
set -e
here="$(cd "$(dirname "$0")" && pwd)"
root="$HOME/Library/Application Support/wecom-reader"
label=local.wecom-reader
agent="$HOME/Library/LaunchAgents/$label.plist"

if [ -z "$(mdfind "kMDItemCFBundleIdentifier == 'com.tencent.WeWorkMac'" 2>/dev/null | head -1)" ] && [ ! -d /Applications/企业微信.app ]; then
  echo "没有找到企业微信（Mac 版），请先安装。"
  exit 1
fi

mkdir -p "$root/bin" "$root/logs"
chmod 700 "$root"
if [ -z "${WECOM_READER_DRY_RUN:-}" ]; then
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  pkill -f "$root/bin/wecom-reader daemon" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$root/bin/wecom-reader daemon" >/dev/null || break; sleep 0.3; done
fi

cp "$here/wecom-reader" "$root/bin/wecom-reader"
# 系统权限绑在启动器这个文件上，升级时不替换，就不用重新开权限。
[ -f "$root/bin/wecom-reader-launcher" ] || cp "$here/wecom-reader-launcher" "$root/bin/wecom-reader-launcher"
xattr -dr com.apple.quarantine "$root/bin" 2>/dev/null || true

if [ ! -f "$root/self.txt" ] && [ -z "${WECOM_READER_DRY_RUN:-}" ]; then
  echo "你在企微里显示的名字，用来认出别人 @ 你的消息、哪些是你自己发的。"
  read -r -p "名字（可以直接回车跳过）：" name || true
  [ -z "$name" ] || { printf '%s' "$name" > "$root/self.txt"; chmod 600 "$root/self.txt"; }
fi

mkdir -p "$HOME/Library/LaunchAgents"
# 路径写进 XML 前转义，用户名里有 & 之类也不会写坏。
xroot="$(printf '%s' "$root" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$xroot/bin/wecom-reader-launcher</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>$xroot/logs/stderr.log</string>
</dict>
</plist>
PLIST
plutil -lint -s "$agent"

if [ -n "${WECOM_READER_DRY_RUN:-}" ]; then
  echo "dry run ok"
  exit 0
fi

launchctl enable "gui/$(id -u)/$label"
launchctl bootstrap "gui/$(id -u)" "$agent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo
echo "装好了。还差一步：在刚打开的「辅助功能」里，打开 wecom-reader-launcher 的开关。"
echo "规则：你的未读单聊、@ 你的群不会被打开，你自己读完后才读；企微在最前面时不动它。"
if ! fdesetup status 2>/dev/null | grep -q "On"; then
  echo "注意：这台电脑没开 FileVault。聊天存的是明文，建议在系统设置里打开。"
fi

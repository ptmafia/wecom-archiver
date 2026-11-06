#!/bin/zsh
# Builds the hand-out folder for colleagues: two programs and two scripts, nothing else.
# Fails if anything in it mentions the owner or the company.
set -euo pipefail
# Short string literals are stored inside the code where `strings` cannot see them, so the sources are scanned too.
# Your login, your full name and home paths; add more words, one per line, to deploy/private-words.txt (not in git).
pattern="$(whoami)|$(id -F)|/Users/"
extra="${0:A:h}/private-words.txt"
[[ -f "$extra" ]] && pattern="$pattern|$(grep -v '^$' "$extra" | paste -sd'|' -)"
if grep -rniE "$pattern" Sources deploy/handout >&2; then echo "personal string in the sources" >&2; exit 1; fi
out="${1:-$HOME/Desktop/企微读取器}"
args=(-c release --arch arm64 --arch x86_64 -Xswiftc -gnone)
swift build "${args[@]}" --product wecom-reader
swift build "${args[@]}" --product wecom-reader-launcher
bin="$(swift build "${args[@]}" --show-bin-path)"
rm -rf "$out" "$out.zip"
mkdir -p "$out"
for p in wecom-reader wecom-reader-launcher; do
  cp "$bin/$p" "$out/$p"
  strip -x "$out/$p" 2>/dev/null || true
  codesign -f -s - --identifier "local.$p" "$out/$p"
done
cp deploy/handout/安装.command deploy/handout/卸载.command deploy/handout/使用说明.txt "$out/"
hits=0
for f in "$out"/*; do
  if strings -a "$f" | grep -iE "$pattern" >&2; then hits=1; echo "personal string in $f" >&2; fi
done
[ "$hits" = 0 ] || exit 1
ditto -c -k --sequesterRsrc --keepParent "$out" "$out.zip"
ls -la "$out" | tail -n +4 | awk '{print $5, $NF}'
lipo -archs "$out/wecom-reader"

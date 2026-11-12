#!/bin/zsh
# make-icon.sh — render starsync-icon.svg into the app's asset catalog.
#
# Writes StarSync/Assets.xcassets/AppIcon.appiconset, which is committed, so
# this only needs running when the artwork changes.
#
# The artwork is full-bleed and deliberately carries no corner rounding, inset
# or shadow: macOS applies the squircle mask, the platform inset and the drop
# shadow itself. Rounding it here would round it twice.
#
# The sources live outside StarSync/ on purpose. That folder is a synchronised
# group, so anything inside it is compiled into the app bundle — an SVG and a
# shell script would ship inside the .app.
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/icon/starsync-icon.svg"
SET="$ROOT/StarSync/Assets.xcassets/AppIcon.appiconset"

[[ -f "$SOURCE" ]] || { echo "!!  Missing artwork: $SOURCE"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Rasterizing $(basename "$SOURCE")"
# Quick Look renders SVG; sips cannot read it at all.
qlmanage -t -s 1024 -o "$TMP" "$SOURCE" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SOURCE").png"
[[ -f "$MASTER" ]] || { echo "!!  Quick Look produced no thumbnail for $SOURCE"; exit 1; }

WIDTH="$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/{print $2}')"
[[ "$WIDTH" == "1024" ]] || { echo "!!  Expected a 1024px render, got ${WIDTH}px"; exit 1; }

echo "==> Writing $SET"
rm -rf "$SET"
mkdir -p "$SET"
while read -r size name; do
    [[ -z "$size" ]] && continue
    sips -s format png -z "$size" "$size" "$MASTER" --out "$SET/icon_${name}.png" >/dev/null
done <<'SIZES'
16 16x16
32 16x16@2x
32 32x32
64 32x32@2x
128 128x128
256 128x128@2x
256 256x256
512 256x256@2x
512 512x512
1024 512x512@2x
SIZES

{
    echo '{'
    echo '  "images" : ['
    first=1
    for name in 16x16 32x32 128x128 256x256 512x512; do
        for scale in 1x 2x; do
            suffix=""
            [[ $scale == 2x ]] && suffix="@2x"
            [[ $first -eq 1 ]] || echo '    },'
            first=0
            echo '    {'
            echo "      \"filename\" : \"icon_${name}${suffix}.png\","
            echo '      "idiom" : "mac",'
            echo "      \"scale\" : \"$scale\","
            echo "      \"size\" : \"$name\""
        done
    done
    echo '    }'
    echo '  ],'
    echo '  "info" : { "author" : "xcode", "version" : 1 }'
    echo '}'
} > "$SET/Contents.json"

cat > "$ROOT/StarSync/Assets.xcassets/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "==> Done: $(ls "$SET"/*.png | wc -l | tr -d ' ') PNGs"

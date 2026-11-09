#!/bin/sh
# Renders the RAK1921 screens to PNGs (4x, with the OLED's look) in $1.
# Needs a C++ compiler, python3 and Adafruit GFX (PlatformIO fetches it: pio run -e rak3401_1w).
set -e
here=$(cd "$(dirname "$0")" && pwd)
mcu=$(cd "$here/../.." && pwd)
out=${1:-$here/out}
gfx=$(ls -d "$mcu"/.pio/libdeps/rak3401_1w/"Adafruit GFX Library" 2>/dev/null)
[ -n "$gfx" ] || { echo "Adafruit GFX not found: run pio run -e rak3401_1w first" >&2; exit 1; }
mkdir -p "$out"
c++ -std=c++17 -DGW_HOST_PREVIEW -DARDUINO=100 -I"$here/shim" -I"$gfx" -I"$mcu/src" -w \
  "$here/preview.cpp" "$mcu/src/oled_view.cpp" "$gfx/Adafruit_GFX.cpp" -o "$out/preview"
"$out/preview" "$out"
python3 "$here/to_png.py" "$out"/*.pbm

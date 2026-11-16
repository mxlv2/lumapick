#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/cache"
bin="$(swift build -c release -debug-info-format none --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")"
app="$PWD/dist/留影.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/XuanPian" "$app/Contents/MacOS/XuanPian"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
codesign --force --sign - "$app"
print "$app"

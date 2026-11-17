#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./scripts/build-app.sh
app="$PWD/dist/留影.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
arch=$(uname -m)
output="$PWD/dist/release-$version"
mkdir -p "$output"
staging=$(mktemp -d "$PWD/dist/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/留影.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/LICENSE.txt"
cat > "$staging/安装说明.txt" <<TEXT
留影 · LumaPick $version
适用：macOS 14 或更新版本，$arch 架构。
将“留影.app”拖到 Applications 文件夹，随后从应用程序中打开。
本版本采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名和公证。
首次打开可能被系统拦截。确认来自本项目后，按照 Apple 官方说明，
在“系统设置 → 隐私与安全性”中选择“仍要打开”。
https://support.apple.com/102445
源码与反馈：https://github.com/mxlv2/lumapick
RAW 预览取决于 macOS 对相机与压缩格式的支持。
TEXT
base="LumaPick-$version-macOS-$arch"
hdiutil create -volname '留影 LumaPick' -srcfolder "$staging" -ov -format UDZO "$output/$base.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$base.zip"
(cd "$output" && shasum -a 256 "$base.dmg" "$base.zip" > SHA256SUMS.txt)
codesign --verify --deep --strict "$app"
print "$output"

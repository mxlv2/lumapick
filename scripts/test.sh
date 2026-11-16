#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
compiler="$(xcrun --find swift)"
plugin="${compiler:h}/../lib/swift/host/plugins/testing"
swift test --disable-sandbox --cache-path "$PWD/.build/cache" -Xswiftc -plugin-path -Xswiftc "$plugin"

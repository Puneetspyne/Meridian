#!/usr/bin/env bash
# Runs the test suites with only the Xcode Command Line Tools installed (no Xcode).
# The Command Line Tools ship Swift Testing as a framework outside the default search path and without
# the _Testing_Foundation cross-import overlay, so we point the compiler and linker at it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
fw=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ -d "$fw/Testing.framework" ]] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app; then
  exec swift test -Xswiftc -F -Xswiftc "$fw" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$fw" -Xlinker -rpath -Xlinker "$fw" "$@"
else
  exec swift test "$@"
fi

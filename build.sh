#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DOTNET="${DOTNET:-dotnet}"
if ! command -v "$DOTNET" >/dev/null 2>&1 && [[ -x "$HOME/.dotnet/dotnet" ]]; then
  DOTNET="$HOME/.dotnet/dotnet"
fi
"$DOTNET" build DisconnectOnly.csproj -c Release
app="build/拔线.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ -f "Assets/Disconnect.icns" ]]; then
  cp Assets/Disconnect.icns "$app/Contents/Resources/"
fi
cp Info.plist "$app/Contents/Info.plist"
clang -O2 -Wall -Wextra DisconnectLauncher.c -o "$app/Contents/Resources/DisconnectLauncher"
swiftc -O RuntimeCore.swift StatusApp.swift -o "$app/Contents/MacOS/Disconnect"
codesign --force --sign - "$app"
echo "Built: $app and bin/Release/netstandard2.0/DisconnectOnly.dll"

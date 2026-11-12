#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/hearthstone-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc RuntimeCore.swift Tests/RuntimeCoreTests.swift -o "$test_dir/runtime"
"$test_dir/runtime"
swiftc GameLauncher.swift Tests/GameLauncherTests.swift -o "$test_dir/game-launch"
"$test_dir/game-launch"
clang -Wall -Wextra -Werror Tests/DisconnectLauncherTests.c -o "$test_dir/launcher"
"$test_dir/launcher"
DOTNET="${DOTNET:-dotnet}"
if ! command -v "$DOTNET" >/dev/null 2>&1 && [[ -x "$HOME/.dotnet/dotnet" ]]; then
    DOTNET="$HOME/.dotnet/dotnet"
fi
"$DOTNET" run --project Tests/PluginTests.csproj
swiftc -typecheck RuntimeCore.swift GameLauncher.swift StatusApp.swift
plutil -lint Info.plist

#!/usr/bin/env bash
# Issue #3: checks that scripts/test-release-package.ps1 rejects broken release archives.
# Usage: experiments/release-package-negative.sh [path-to-pwsh]
set -u
PWSH=${1:-pwsh}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
cp "$ROOT/installer_acad/PackageContents.xml" "$ROOT/installer_manual/install.cmd" "$WORK/"
restore() { cp "$WORK/PackageContents.xml" "$ROOT/installer_acad/"; cp "$WORK/install.cmd" "$ROOT/installer_manual/"; }
trap 'restore; rm -rf "$WORK"' EXIT
fail=0

expect_failure() { # name, expected text
  if "$PWSH" -NoProfile -File "$ROOT/scripts/test-release-package.ps1" -ReleaseRoot "$WORK/$1/v0.0.0" -Version "$VERSION" > "$WORK/$1.log" 2>&1; then
    echo "NOT DETECTED: $1"; fail=1
  elif grep -q "$2" "$WORK/$1.log"; then
    echo "detected: $1 -> $(grep -m1 "$2" "$WORK/$1.log")"
  else
    echo "WRONG MESSAGE: $1"; cat "$WORK/$1.log"; fail=1
  fi
}
package() { # name, extra build args
  "$PWSH" -NoProfile -File "$ROOT/scripts/package-release.ps1" -ReleaseBase "$WORK/$1" -Version "$VERSION" -NoBuild > "$WORK/$1.package.log" 2>&1 \
    && mv "$WORK/$1/v$VERSION" "$WORK/$1/v0.0.0"
}
VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ROOT/Directory.Build.props")
cd "$ROOT"
dotnet build src/VelecCableRouter.AutoCAD -c Release > "$WORK/build.log" 2>&1 || { cat "$WORK/build.log"; exit 1; }

sed -i "s/AppVersion=\"$VERSION\"/AppVersion=\"9.9.9\"/" installer_acad/PackageContents.xml
package app-version; expect_failure app-version "AppVersion '9.9.9'"
restore

sed -i 's/SeriesMax="R24.3"/SeriesMax="R24.0"/' installer_acad/PackageContents.xml
package series; expect_failure series "SeriesMax=R24.3"
restore

sed -i 's/\r$//' installer_manual/install.cmd
package line-endings; expect_failure line-endings "CRLF"
restore

# An AutoCAD 2024 API build would not load in AutoCAD 2020.
dotnet build src/VelecCableRouter.AutoCAD -c Release -f net48 -p:AutoCadNet48ApiVersion=24.3.0 > "$WORK/build24.log" 2>&1 || { cat "$WORK/build24.log"; exit 1; }
package api; expect_failure api "newer than 23.1"
dotnet build src/VelecCableRouter.AutoCAD -c Release -f net48 > /dev/null 2>&1

exit $fail

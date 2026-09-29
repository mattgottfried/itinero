#!/bin/sh
# Xcode Cloud runs this right after cloning. The .xcodeproj is generated (not committed), so build it first.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
brew install xcodegen
xcodegen generate

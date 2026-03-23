#!/bin/bash
set -e

echo "Building aTerm..."
swift build -c release

echo "Creating app bundle..."
rm -rf aTerm.app
mkdir -p aTerm.app/Contents/MacOS
mkdir -p aTerm.app/Contents/Resources

cp .build/release/aTerm aTerm.app/Contents/MacOS/
cp Info.plist aTerm.app/Contents/Info.plist

# Copy resources
if [ -d Sources/aTerm/Resources ]; then
  cp -R Sources/aTerm/Resources/* aTerm.app/Contents/Resources/ 2>/dev/null || true
fi

# Copy Swift package resource bundle
BUNDLE=$(find .build/release -name 'aTerm_aTerm.bundle' -maxdepth 1 2>/dev/null | head -1)
if [ -n "$BUNDLE" ]; then
  cp -R "$BUNDLE" aTerm.app/Contents/Resources/
fi

echo "Signing app..."
codesign --force --options runtime --entitlements aTerm.entitlements --sign - aTerm.app

echo "Installing to /Applications..."
rm -rf /Applications/aTerm.app
cp -R aTerm.app /Applications/

echo "✅ aTerm installed to /Applications"

#!/bin/bash

# Install Flutter
echo "Installing Flutter..."
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz | tar -xJ

# Add Flutter to PATH
export PATH="$PWD/flutter/bin:$PATH"

# Verify Flutter installation
echo "Flutter version:"
flutter --version

# Enable web support
flutter config --enable-web

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build web app
echo "Building web app..."
flutter build web --release

echo "Build complete!"

# List output files for verification
echo "Build output contents:"
ls -la build/web/

echo "Build complete and ready for deployment!" 
#!/bin/bash

# Script to update app icons from the CCC logo
# Requirements: ImageMagick (install with: winget install ImageMagick.ImageMagick)

LOGO_PATH="assets/ccc_logo.png"

if [ ! -f "$LOGO_PATH" ]; then
    echo "❌ Logo file not found at $LOGO_PATH"
    echo "Please save the CCC logo to assets/ccc_logo.png first"
    exit 1
fi

echo "🎨 Updating Android app icons..."

# Android icon sizes
mkdir -p android/app/src/main/res/mipmap-mdpi
mkdir -p android/app/src/main/res/mipmap-hdpi
mkdir -p android/app/src/main/res/mipmap-xhdpi
mkdir -p android/app/src/main/res/mipmap-xxhdpi
mkdir -p android/app/src/main/res/mipmap-xxxhdpi

# Resize logo for different Android densities
magick "$LOGO_PATH" -resize 48x48 android/app/src/main/res/mipmap-mdpi/ic_launcher.png
magick "$LOGO_PATH" -resize 72x72 android/app/src/main/res/mipmap-hdpi/ic_launcher.png
magick "$LOGO_PATH" -resize 96x96 android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
magick "$LOGO_PATH" -resize 144x144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
magick "$LOGO_PATH" -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png

echo "✅ Android icons updated!"

# Check if iOS directory exists
if [ -d "ios" ]; then
    echo "🍎 Updating iOS app icons..."
    
    # iOS icon sizes (you may need to adjust these paths based on your Xcode project)
    IOS_ICONS_PATH="ios/Runner/Assets.xcassets/AppIcon.appiconset"
    
    if [ -d "$IOS_ICONS_PATH" ]; then
        magick "$LOGO_PATH" -resize 20x20 "$IOS_ICONS_PATH/Icon-App-20x20@1x.png"
        magick "$LOGO_PATH" -resize 40x40 "$IOS_ICONS_PATH/Icon-App-20x20@2x.png"
        magick "$LOGO_PATH" -resize 60x60 "$IOS_ICONS_PATH/Icon-App-20x20@3x.png"
        magick "$LOGO_PATH" -resize 29x29 "$IOS_ICONS_PATH/Icon-App-29x29@1x.png"
        magick "$LOGO_PATH" -resize 58x58 "$IOS_ICONS_PATH/Icon-App-29x29@2x.png"
        magick "$LOGO_PATH" -resize 87x87 "$IOS_ICONS_PATH/Icon-App-29x29@3x.png"
        magick "$LOGO_PATH" -resize 40x40 "$IOS_ICONS_PATH/Icon-App-40x40@1x.png"
        magick "$LOGO_PATH" -resize 80x80 "$IOS_ICONS_PATH/Icon-App-40x40@2x.png"
        magick "$LOGO_PATH" -resize 120x120 "$IOS_ICONS_PATH/Icon-App-40x40@3x.png"
        magick "$LOGO_PATH" -resize 120x120 "$IOS_ICONS_PATH/Icon-App-60x60@2x.png"
        magick "$LOGO_PATH" -resize 180x180 "$IOS_ICONS_PATH/Icon-App-60x60@3x.png"
        magick "$LOGO_PATH" -resize 76x76 "$IOS_ICONS_PATH/Icon-App-76x76@1x.png"
        magick "$LOGO_PATH" -resize 152x152 "$IOS_ICONS_PATH/Icon-App-76x76@2x.png"
        magick "$LOGO_PATH" -resize 167x167 "$IOS_ICONS_PATH/Icon-App-83.5x83.5@2x.png"
        magick "$LOGO_PATH" -resize 1024x1024 "$IOS_ICONS_PATH/Icon-App-1024x1024@1x.png"
        
        echo "✅ iOS icons updated!"
    else
        echo "⚠️  iOS icon directory not found, skipping iOS icons"
    fi
fi

echo "🎉 App icon update complete!"
echo ""
echo "📱 To apply changes:"
echo "   • Run: flutter clean && flutter build apk"
echo "   • Or: flutter run" 
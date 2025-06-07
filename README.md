# Closed-Caption Companion (CCC)

Ultra-low-latency captions for live, in-person speech through a simple push-to-talk mobile interface, powered by advanced speech recognition technology.

## 🎯 Vision

Give hard-of-hearing people ultra-low-latency captions of live, in-person speech through a simple push-to-talk mobile interface. The app is designed to be:

- **Accessible** → Very large, high-contrast text; voice-over compatible; top-aligned text display
- **Affordable** → No ongoing subscription required; works out of the box
- **Private** → No audio recordings stored; data processed securely
- **Resilient** → Multiple speech recognition options with automatic reliability recovery
- **Simple** → One-button operation with instant text editing capabilities

## 🚀 Features

### Core Features
- **Push-to-Talk Caption** - Large accessible button: hold to capture live speech
- **Multiple Speech Engines** - Google Cloud STT (default), Azure Speech, or Device recognition
- **Editable Transcripts** - Tap text after recording to edit names and fix errors
- **Large Text Display** - Adjustable 16-120pt text, optimized for accessibility
- **Dark Mode Support** - High contrast white-on-black or black-on-white themes
- **Transcript History** - Save and review captions (24-hour local storage)
- **Multi-Language Support** - Australian, US, British, and Canadian English variants
- **No Account Required** - Works immediately after installation
- **Enhanced Reliability** - Automatic error recovery with exponential backoff

### New Features
- **Instant Text Editing** - Click to edit transcripts with automatic name capitalization
- **Smart Text Flow** - Carriage returns replaced with " / " for continuous reading
- **Continuous Recording** - Text accumulates during long recordings without interruption
- **Status Indicators** - Clear visual feedback (READY, LIVE, CONNECTING, ERROR)
- **Australian English Default** - Optimized for Australian accents out of the box

## 🛠️ Technical Architecture

### Stack
- **Frontend**: Flutter 3.32+ (Android & iOS)
- **Primary STT**: Google Cloud Speech-to-Text (default)
- **Alternative STT**: Azure Speech Service, Device recognition
- **Audio Processing**: Flutter speech_to_text with enhanced reliability
- **State Management**: Provider pattern with reactive UI
- **Storage**: SharedPreferences for settings, in-memory for transcripts

### Key Components
1. **AudioStreamingService** - Multi-service speech recognition with automatic recovery
2. **CaptionService** - Real-time caption management and editing
3. **SettingsService** - User preferences and speech service configuration
4. **Enhanced UI** - Large accessible buttons with haptic feedback

### Speech Recognition Services
- **Google Cloud STT** (Default) - Best accuracy, requires internet
- **Azure Speech Service** - Alternative cloud option with comparable accuracy  
- **Device Recognition** - Offline fallback using platform-native STT

## 📱 Download & Installation

### 🔽 Get the App

**📱 Android: Available Now**
- Download the latest APK from [GitHub Releases](https://github.com/economicalstories/CCC/releases)
- Ready to install on any Android device (Android 5.0+)

**🍎 iPhone: Potentially Available**
- iPhone version is technically possible if there's sufficient demand
- Would require annual iOS App Store costs ($99/year) to distribute
- [Contact us](mailto:contact@economicalstories.com) if you'd like to see an iPhone version

**💻 Build from Source**
- Clone this repository and build yourself
- See instructions below

---

## 📱 Installation & Setup

### Method 1: Install Android APK (Recommended)
1. **Download** the APK from [GitHub Releases](https://github.com/economicalstories/CCC/releases)
2. **Transfer** to your Android device (via USB, email, or cloud)
3. **Enable** "Install from unknown sources" in Settings > Security
4. **Install** and grant microphone permissions when prompted

### Method 2: Build Your Own APK
1. **Build the APK** using the source code instructions below
2. **Transfer** `build/app/outputs/flutter-apk/app-release.apk` to your Android device
3. **Follow installation steps** as above

### Method 3: Development Install (Direct)
```bash
# Clone repository
git clone https://github.com/economicalstories/CCC.git
cd CCC

# Install dependencies
flutter pub get

# Build for Android
flutter build apk --release

# Find your APK at: build/app/outputs/flutter-apk/app-release.apk
```

### Method 3: Direct Development (For Developers)
```bash
# Prerequisites: Flutter SDK, Android device with USB debugging
# Connect your Android device via USB

# Clone and run directly
git clone https://github.com/economicalstories/CCC.git
cd CCC
flutter pub get
flutter run

# Or install directly to connected device
flutter install
```

## 🔧 Configuration

### Speech Service Selection
1. Open Settings in the app
2. Choose from:
   - **Google Speech-to-Text** (Recommended) - Best accuracy
   - **Azure Speech Service** - Alternative cloud option
   - **Device Speech Recognition** - Offline capability

### Language Options
- **Australian English** (en_AU) - Default, optimized for Australian accents
- **US English** (en_US) - American English variant
- **British English** (en_GB) - UK English variant
- **Canadian English** (en_CA) - Canadian English variant

### Accessibility Settings
- **Font Size**: 16-120pt adjustable text
- **Theme**: Light, Dark, or System preference
- **Transcript Saving**: Enable/disable 24-hour local storage

## 📊 Performance Characteristics

- **Caption Latency**: ~800ms typical with cloud services
- **Accuracy**: Optimized for clear indoor speech
- **Reliability**: Automatic error recovery with exponential backoff
- **Offline Capability**: Device recognition works without internet
- **Text Continuity**: Maintains text across service restarts

## 🔒 Privacy & Security

- **No Cloud Storage**: Audio is processed in real-time, never stored
- **Local Transcripts**: 24-hour local storage only, automatically cleared
- **Secure Processing**: TLS encryption for cloud speech services
- **No Account Required**: Works immediately without registration
- **Minimal Permissions**: Only requires microphone access

## 🎨 User Experience

### Simple Operation
1. **Hold** the large button and speak
2. **Release** when finished speaking
3. **Tap** the text to edit names or corrections
4. **Long press** for transcript history and options

### Accessibility Features
- **Voice-over compatible** with semantic labels
- **High contrast themes** for visual accessibility
- **Large touch targets** for easy interaction
- **Haptic feedback** for button presses
- **Top-aligned text** for consistent reading position

## 🤝 Contributing

Contributions welcome! Please read contributing guidelines before submitting PRs.

### Development Setup
```bash
# Ensure Flutter 3.0+ is installed
flutter doctor

# Run in development mode
flutter run

# Run tests
flutter test
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built for all hard-of-hearing individuals who need reliable captions
- Powered by Google Cloud Speech-to-Text, Azure Speech Service, and device recognition
- Flutter community for excellent accessibility framework
- Speech recognition technology providers for enabling real-time processing

---

**Want an iPhone version?** [Let us know!](mailto:contact@economicalstories.com) If there's enough interest, we'll consider the annual App Store costs to bring CCC to iOS. 
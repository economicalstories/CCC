# Closed-Caption Companion (CCC)

**Making stories accessible to everyone.** Real-time captions help those who are hard of hearing participate in conversations, presentations, and the stories happening around them.

## 🚀 **Get CCC Now - Multiple Ways to Access**

### 🌐 **Progressive Web App (Easiest, but inconsistent handling of speech to text)**
y**✨ Install instantly on any device:**
- **Visit**: [ccc.economicalstories.com](https://ccc.economicalstories.com)
- **Android**: Chrome → Menu → "Add to Home screen"
- **iPhone**: Safari → Share → "Add to Home Screen"
- **Desktop**: Chrome → Install icon in address bar

*No download required - works offline after first visit!*

### 📱 **Native Android App (More consistent handling of speech to tet)**
**Download the APK for full native experience:**
- **Get it**: [GitHub Releases](https://github.com/economicalstories/CCC/releases)
- **Requirements**: Android 5.0+ (21 API level)
- **Install**: Enable "Unknown sources" → Install APK
- **Benefits**: Better performance, deeper system integration

### 🍎 **iPhone App Store Version**
**Interested in an iOS App Store version?**
- **Contact us**: [contact@economicalstories.com](mailto:contact@economicalstories.com)
- We're considering iOS development based on user demand
- App Store publishing requires annual fees - your interest helps justify the cost!

---

## 🎯 What is CCC?

Ultra-low-latency captions for live, in-person speech through a simple push-to-talk mobile interface, powered by advanced speech recognition technology.

### Key Benefits
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

### 🎯 Coming Soon: Real-Time Room Sharing
- **Join Caption Rooms** - Multiple people can view captions in the same room
- **Live Caption Sync** - See captions from any speaker in your room in real-time
- **Speaker Lock** - One person speaks at a time for clear conversations
- **Participant List** - See who's in your room
- **Connection Status** - Know when you're connected to others

[See implementation details →](PARTYKIT_IMPLEMENTATION.md)

## 🔧 Quick Setup

### Using the PWA (ccc.economicalstories.com)
1. **Visit** [ccc.economicalstories.com](https://ccc.economicalstories.com)
2. **Grant** microphone permission when prompted
3. **Install** by adding to home screen (optional but recommended)
4. **Start** using immediately - hold the big button and speak!

### Using Android APK
1. **Download** latest APK from [Releases](https://github.com/economicalstories/CCC/releases)
2. **Enable** "Install from unknown sources" in Android Settings
3. **Install** the APK and grant microphone permissions
4. **Open** CCC and start captioning!

### Speech Service Configuration
The app works immediately with device recognition, but for better accuracy:
1. **Open Settings** in the app
2. **Choose** from:
   - **Google Speech-to-Text** (Recommended) - Best accuracy, requires internet
   - **Azure Speech Service** - Alternative cloud option
   - **Device Speech Recognition** - Offline capability

## 🔒 Privacy Policy & Data Management

**Your privacy is paramount. Here's exactly how we handle your data:**

### Audio Processing
- **Real-time processing only**: Audio is processed in real-time for speech recognition
- **No storage**: Audio data is never stored on your device or transmitted to our servers
- **Immediate disposal**: Audio is discarded immediately after processing

### Speech Recognition Services
- **Cloud services**: When using Google or Azure speech recognition, audio is sent securely to their servers for processing
- **Secure transmission**: All data is encrypted in transit using TLS/SSL
- **No retention**: We do not store, log, or retain any audio data sent to cloud services
- **Third-party policies**: Cloud providers have their own data policies - we recommend reviewing them

### Local Data Storage
- **Captions only**: Only text captions are stored locally on your device when you enable transcript saving
- **24-hour limit**: Transcripts are automatically cleared after 24 hours
- **User control**: You can clear transcript data anytime in the app settings
- **No cloud sync**: Transcript data never leaves your device

### Analytics and Tracking
- **No analytics**: We do not collect usage analytics, crash reports, or behavioral data
- **No tracking**: No user tracking, cookies, or persistent identifiers
- **No personal data**: We do not collect names, emails, or any personal information
- **No account required**: The app works without registration or accounts

### Open Source Transparency
- **Public code**: This app is fully open source - you can review all code
- **Verifiable privacy**: Our privacy practices can be verified by examining the source code
- **Community oversight**: Open source allows community review of privacy practices
- **No hidden features**: What you see in the code is what the app does

### Data Sharing
- **No data sharing**: We do not share, sell, or distribute any user data
- **No third-party integration**: Except for speech recognition services, no data goes to third parties
- **No advertising**: No ads, no ad networks, no advertising data collection

### User Rights
- **Full control**: You have complete control over transcript data storage
- **Immediate deletion**: Clear all data instantly through app settings
- **No cloud dependency**: Core functionality works offline with device speech recognition
- **Transparent operation**: All data handling is visible and controllable by you

### Contact for Privacy Questions
If you have questions about our privacy practices:
- **Email**: [contact@economicalstories.com](mailto:contact@economicalstories.com)
- **Source Code**: [github.com/economicalstories/CCC](https://github.com/economicalstories/CCC)

## 🛠️ Technical Architecture

### Stack
- **Frontend**: Flutter 3.32+ (Web, Android & iOS)
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

## ⚙️ Configuration Options

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

## 🔧 Building from Source

### Prerequisites
- Flutter 3.0+ installed
- Android Studio (for Android builds)
- Xcode (for iOS builds, macOS only)

### Development Setup
```bash
# Clone repository
git clone https://github.com/economicalstories/CCC.git
cd CCC

# Install dependencies
flutter pub get

# Run in development mode
flutter run

# Build for production
flutter build web --release          # PWA
flutter build apk --release          # Android
flutter build ios --release          # iOS (macOS only)
```

### Build Outputs
- **PWA**: `build/web/` (ready for web hosting)
- **Android APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **iOS**: `build/ios/iphoneos/Runner.app` (requires code signing)

## 🤝 Contributing

Contributions welcome! Please read contributing guidelines before submitting PRs.

### Development Commands
```bash
# Ensure Flutter 3.0+ is installed
flutter doctor

# Run tests
flutter test

# Analyze code
flutter analyze
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built for all hard-of-hearing individuals who need reliable captions
- Powered by Google Cloud Speech-to-Text, Azure Speech Service, and device recognition
- Flutter community for excellent accessibility framework
- Speech recognition technology providers for enabling real-time processing

---

**Questions? Feedback? Want iOS version?** 
📧 [contact@economicalstories.com](mailto:contact@economicalstories.com) 

# Stoa

A lightweight, cross-platform collaborative application for file sharing, messaging, and real-time collaboration.

## Features

- 🔍 **Local Network Discovery** - Automatically find peers on your network
- 📁 **P2P File Sharing** - Share files directly, no server needed
- 📂 **Shared Folders** - Real-time synchronized directories with CRDT
- 💬 **Group Messaging** - WhatsApp-like group chats
- 📝 **Built-in Editor** - Collaborative plain text editing

## Development Setup (NixOS)

This project uses Nix flakes for reproducible development environments.

### Prerequisites

- NixOS or Nix with flakes enabled
- Git

### Getting Started

1. **Enter the development shell:**
   ```bash
   nix develop
   ```

2. **Initialize Flutter (first time only):**
   ```bash
   flutter doctor
   flutter pub get
   ```

3. **Run on Linux:**
   ```bash
   flutter run -d linux
   ```

4. **Run on Android (with device connected):**
   ```bash
   flutter run -d android
   ```

### Building

```bash
# Linux binary
flutter build linux

# Android APK
flutter build apk

# Android App Bundle
flutter build appbundle
```

## Development Setup (Windows)

To develop on Windows, you'll need to set up the Flutter environment manually as Nix is not natively supported.

### Prerequisites

1.  **Git for Windows**: [Download & Install](https://git-scm.com/download/win)
2.  **Flutter SDK**: [Download & Install](https://docs.flutter.dev/get-started/install/windows)
3.  **Visual Studio 2022** (for Windows Desktop):
    *   Download Community Edition.
    *   Select "Desktop development with C++" workload during installation.
4.  **Android Studio** (for Android):
    *   Install Android SDK and Command-line Tools.
    *   Set up an Android Emulator or connect a physical device.

### Getting Started

1.  **Clone the repository:**
    ```powershell
    git clone https://github.com/your-username/stoa.git
    cd stoa
    ```

2.  **Initialize Flutter:**
    ```powershell
    flutter doctor
    flutter pub get
    ```

3.  **Run on Windows:**
    ```powershell
    flutter run -d windows
    ```

4.  **Recieve on Network (Important):**
    *   When running for the first time, Windows Firewall may pop up.
    *   **Allow access** for both Private and Public networks to ensure local discovery works.

5.  **Run on Android:**
    ```powershell
    flutter run -d android
    ```

### Building on Windows

```powershell
# Windows EXE
flutter build windows

# Android APK
flutter build apk
```

## Project Structure

```
lib/
├── main.dart              # App entry point
├── app/                   # App configuration, routing, theme
├── features/              # Feature modules (onboarding, peers, chat, etc.)
├── core/                  # Core services, models, database
└── shared/                # Shared widgets
```

## Tech Stack

- **Framework:** Flutter 3.x
- **Language:** Dart 3.x
- **State Management:** Riverpod
- **Database:** Drift (SQLite)
- **Network Discovery:** Bonsoir (mDNS)
- **CRDT:** crdt package

## License

MIT License - see [LICENSE](LICENSE)

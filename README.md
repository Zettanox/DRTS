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

# Stoa — Local-First Decentralized Collaboration

Stoa is a privacy-first, decentralized communication platform built for the modern age. It combines the power of **libp2p** for peer-to-peer networking, **Tauri** for a lightweight desktop experience, and **CRDTs (Conflict-free Replicated Data Types)** for real-time collaborative document editing.

No clouds. No accounts. No tracking. Just peers.

---

## 🌟 Key Features

- **Decentralized Networking**: Powered by `rust-libp2p`, Stoa operates without a central server. You own your identity (Ed25519 keypair).
- **Double Encryption**: Every message is protected by two layers of security: libp2p's **Noise** protocol (transport) and Stoa's native **X25519 + AES-256-GCM** (content).
- **LAN & Internet Discovery**: Seamlessly find peers on your local Wi-Fi via **mDNS** or connect globally using the **Stoa Relay Oracle**.
- **Collaborative Spaces**: Real-time multi-user document editing in a "Shared Space" backed by `Yjs` CRDTs.
- **AutoNAT & DCUtR**: Robust NAT traversal using hole-punching to ensure high-speed direct connections whenever possible.

---

## 🚀 Getting Started (Walkthrough)

### 1. Initialize your Identity
When you first launch Stoa, you generate a unique cryptographic identity. Unlike email or usernames, your **PeerID** is derived from a private key stored only on your device. You can set a "Petname" for your contacts to recognize you.

### 2. Discovering Peers
- **On LAN**: If you and a friend are on the same Wi-Fi, Stoa will automatically detect them via mDNS. They’ll appear in your "Nearby Peers" list.
- **Over the Internet**: To connect globally, you use a **Relay Address**. Share your connection string (found in Settings) with a peer to establish a secure link through the Stoa Relay Oracle.

### 3. Messaging & Trust
Once a connection is established, you can send a **Contact Request**. Adding a contact triggers a keys-to-keys handshake (ECDH) that establishes a persistent shared secret for end-to-end encryption. Once "Trusted," your messages are double-encrypted.

### 4. Collaborative Shared Spaces
Within any group chat, switch to the **Space** tab.
- Create or import Markdown, Rust, Python, or JS files.
- The **Shared Space** is a real-time collaborative editor. Every keystroke is synced across the group using a gossip protocol.
- Changes are merged automatically even if you go offline and reconnect later.

---

## 🛠️ Technology Stack

- **Frontend**: SolidJS + TypeScript + Tailwind CSS
- **Framework**: Tauri 2.0 (Rust)
- **Networking**: `rust-libp2p` (Noise, Yamux, mDNS, Relay, DCUtR, AutoNAT)
- **Collaboration**: Y-Rust (Yjs implementation)
- **Editor**: CodeMirror 6

---

## 📥 Installation

### ⚡ Using Pre-built Binaries (Recommended)
You don't need to build Stoa from source to get started. We provide optimized binaries for **Windows, Linux, macOS, and Android**.

1. Go to the [Releases](https://github.com/Zettanox/Stoa/releases) page.
2. Download the version for your platform:
   - **Windows**: `.msi` or `.exe` installer.
   - **Linux**: `.AppImage` or `.deb`.
   - **Android**: `.apk`.
   - **macOS**: `.dmg`.

---

## 🛰️ Self-Hosting a Relay Server

If you want to contribute to the network or host a private relay for your team, you can run the standalone `stoa-relay` binary on any Linux VPS with a public IP.

### 1. Build or Download the Relay
- **Download**: Grab the `stoa-relay-linux-x86_64` binary from the latest Release.
- **Build from Source (Linux/macOS)**: 
  ```bash
  cd src-tauri
  cargo build --release --bin stoa-relay
  ```
- **Build from Source (Windows cross-compiling for Linux)**:
  ```powershell
  rustup target add x86_64-unknown-linux-gnu
  cargo build --release --bin stoa-relay --target x86_64-unknown-linux-gnu
  ```

### 2. Network Preparation
Before running the relay, ensure your server is allowed to receive traffic.
1. **Cloud Dashboard**: Open TCP port `38291` in your VPS provider's security lists/firewall (e.g., AWS Security Groups, Oracle VCN).
2. **Internal Firewall**: Open the port on the machine itself:
   ```bash
   # For Ubuntu/Debian (UFW)
   sudo ufw allow 38291/tcp

   # For Oracle/RHEL/CentOS (firewalld)
   sudo firewall-cmd --zone=public --add-port=38291/tcp --permanent
   sudo firewall-cmd --reload
   ```

### 3. Production Deployment (systemd)
Do **not** run the binary directly in your terminal, or it will shut down when you disconnect. Instead, install it as a background system service.

1. **Move the binary to a system path:**
   ```bash
   sudo mv stoa-relay /usr/bin/stoa-relay
   sudo chmod +x /usr/bin/stoa-relay
   ```
   *(Note: If you are using Oracle Linux, RHEL, or Fedora, run `sudo restorecon -Rv /usr/bin/stoa-relay` to prevent SELinux from blocking the execution).*

2. **Create the configuration directory:**
   ```bash
   sudo mkdir -p /etc/stoa-relay
   sudo chown -R $USER:$USER /etc/stoa-relay
   ```

3. **Create the systemd service file:**
   ```bash
   sudo nano /etc/systemd/system/stoa-relay.service
   ```
   Paste the following configuration, replacing `YOUR_PUBLIC_IP` with your server's actual public IP address:

   ```ini
   [Unit]
   Description=Stoa P2P Relay Server
   After=network.target

   [Service]
   Type=simple
   User=root
   # Hardened limits: 1024 max connections to prevent Out-Of-Memory crashes
   ExecStart=/usr/bin/stoa-relay --port 38291 --external-ip YOUR_PUBLIC_IP --key-file /etc/stoa-relay/relay.key --max-connections 1024 --max-reservations 1024
   Restart=on-failure
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```

4. **Start the relay:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now stoa-relay
   sudo systemctl status stoa-relay
   ```
   If it says `active (running)`, your relay is live, hardened against spam, and will automatically restart if the server reboots!

---

## 🏗️ Building from Source

### Prerequisites
- [Rust](https://www.rust-lang.org/) (latest stable)
- [Node.js](https://nodejs.org/) (v20+)
- System Dependencies (Linux): `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `libappindicator3-dev`, `librsvg2-dev`

### Compilation
1. Clone the repository.
2. Install frontend dependencies:
   ```bash
   npm install
   ```
3. Run in development mode:
   ```bash
   npm run tauri dev
   ```
4. Build the production binary:
   ```bash
   npm run tauri build
   ```

---

## ❄️ NixOS / Nix
A `flake.nix` is provided for a reproducible development environment. Run:
```bash
nix develop
```

---

## ⚖️ License
Stoa is open-source and released under the MIT License.


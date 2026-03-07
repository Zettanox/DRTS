# Stoa: Presentation Content

## Slide 1: Title Slide
**Stoa**
*Serverless, Offline-First Collaboration for Local Networks*
[Your Name / Team Name]
[Date]

---

## Slide 2: Problem Statement
**The Dependency Dilemma**
- **Always Online:** Modern collaboration tools (Slack, Google Docs, Teams) completely break down without an active internet connection.
- **Privacy & Security Risks:** Sensitive data must transit through third-party cloud servers, posing risks in highly secure or confidential environments.
- **Tool Fragmentation:** Teams typically juggle multiple isolated apps for messaging, file sharing, and real-time document editing, leading to workflow friction.
- **Cost Barriers:** Enterprise-grade self-hosted collaboration suites are expensive to license, deploy, and maintain.

---

## Slide 3: Abstract
**What is Stoa?**
In an era dominated by cloud-dependency, collaborative software often fails in environments lacking stable internet access, while simultaneously introducing profound privacy and financial hurdles. 

Stoa is an open-source, decentralized collaboration application engineered specifically to operate entirely offline on Local Area Networks (LAN or Wi-Fi). By eliminating the need for centralized cloud servers, Stoa empowers its users with absolute data sovereignty. It seamlessly fuses zero-configuration peer discovery (mDNS) with advanced Conflict-free Replicated Data Types (CRDTs) to deliver a zero-friction suite of tools. This suite enables high-throughput direct file transfers, private peer-to-peer messaging, and real-time collaborative document editing (Shared Spaces)—all functioning instantly from the moment devices join the same network. Stoa is the definitive solution for hackathons, secure air-gapped facilities, dynamic startup environments, and localized classrooms seeking a unified, privacy-first collaboration platform.

---

## Slide 4: Introduction
**The Vision Behind Stoa**
- **Target Audience:** Hackathons, startup teams, air-gapped secure facilities, classrooms, and disaster relief zones.
- **Core Philosophy:** True ownership of your data. If you are in the same room, you shouldn't need a server in another country to send a message to the person next to you.
- **Key Capabilities:**
  - Automated local peer discovery.
  - P2P messaging and groups.
  - High-throughput direct file sharing.
  - **Shared Spaces:** Real-time multi-user document editing without a host server.

---

## Slide 5: Our Solution
**How Stoa Works**
- **Serverless peer-to-peer network:** Devices discover each other automatically using mDNS. There is no central point of failure.
- **Real-Time Engine (CRDTs):** We implemented mathematical data structures (CRDTs) that allow multiple users to edit the same text document simultaneously. The algorithms mathematically guarantee that everyone's document mathematically merges to the exact same state, flawlessly handling network drops and offline edits.
- **Unified Local Storage:** Powered by Flutter and a local SQLite database, interactions are fast, responsive, and completely disconnected from the cloud.

---

## Slide 6: Difference from Existing Solutions
**Stoa vs. The Status Quo**

| Feature | Stoa | Cloud Suites (e.g., Google Workspace) | Local Sharing (e.g., AirDrop) |
| :--- | :--- | :--- | :--- |
| **Internet Required** | **No** (Local Network Only) | Yes | No |
| **Real-Time Co-Editing** | **Yes** (Offline CRDT sync) | Yes (Requires Cloud) | No |
| **Cross-Platform** | **Yes** (Windows, Linux, Android) | Yes | No (Apple Ecosystem Only) |
| **Data Privacy** | **100% Local** / Self-Contained | Data stored on external servers | File transfers only |
| **Cost** | **Free & Open Source** | Subscription-based | Included in OS |

---

## Slide 7: Limitations & Future Work
**Current Constraints**
- **Network Boundaries:** Users must be on the same physical Local Area Network (LAN) or VPN subnet for mDNS discovery to function.
- **Mobile Background Restrictions:** Devices like Android may aggressively pause background socket connections to save battery, requiring the app to be active for real-time synchronization.
- **Rich Text Complexity:** Currently, Shared Spaces supports plain text collaborative editing; building a conflict-free engine for complex rich text (images, advanced formatting) remains a future milestone.
- **Initial Authentication:** Lacks centralized identity verification (since there is no server), meaning "identity" is currently tied to the local device profile.

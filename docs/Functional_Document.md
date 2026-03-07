# Functional Document: Stoa

## 1. Introduction
The Stoa project aims to provide a lightweight, cross-platform collaborative application that emphasizes decentralization and offline-first capabilities. Sprint 1 focused on validating the core peer-to-peer (P2P) networking protocols and implementing the foundation for real-time collaborative document editing using CRDTs (Conflict-free Replicated Data Types).

## 2. Product Goal
The primary goal of this project is to create a seamless, serverless collaborative environment where users can share files, communicate via messaging, and co-author plain text documents across devices on the same local network, without relying on external cloud infrastructure.

## 3. Demography (Users, Location)
**Users**
- **Target Users:** Students, remote work teams, developers, and privacy-conscious individuals.
- **User Characteristics:** Varies from casual users needing quick file transfers to technical professionals collaborating in air-gapped or low-bandwidth environments.

**Location**
- **Target Location:** Global usage, specifically tailored for localized networks (offices, classrooms, home networks) where internet connectivity may be restricted or unavailable.

## 4. Business Processes
The key business processes include:
- **Peer Discovery and Connection:**
  Process for the application to automatically locate and establish direct TCP connections with other users on the local network via mDNS.
- **Collaborative Editing (Shared Spaces):**
  Process for multiple users to simultaneously edit a shared plain-text document, resolving concurrent edits in real-time.
- **P2P Data Exchange:**
  Process for initiating and completing direct file transfers and chat messages between individual peers or within shared groups.

## 5. Features
The current release focuses on implementing the following key features:

**Feature #1: Real-Time Document Editing (Shared Spaces)**
- **Description:** A collaborative editor allowing multiple users within a group to edit the same document simultaneously. It leverages CRDTs to ensure that all local edits are eventually consistent across all peers, flawlessly handling offline edits and network reconnects.
- **User Story:** As a team member, I want to type notes into a shared document at the same time as my colleagues so that we can brainstorm together seamlessly, even if our internet connection drops.

**Feature #2: Local Network Peer Discovery**
- **Description:** Automatic discovery of active Stoa clients on the same local network utilizing zero-configuration networking (mDNS).
- **User Story:** As a user, I want the app to instantly show me who is available on my Wi-Fi network so that I can send them files without needing to enter IP addresses or share invite links.

**Feature #3: High-Speed P2P File Transfer**
- **Description:** Direct file and folder sharing utilizing unbuffered TCP sockets for maximum LAN throughput. 
- **User Story:** As a user, I want to send a large folder of assets directly to my coworker's computer quickly, bypassing cloud upload/download times.

## 6. Authorization Matrix
Since Stoa is a decentralized P2P application, traditional role-based access control (RBAC) relies heavily on device ownership and group administration rather than a central server matrix. 

| Role | Access Level |
| :--- | :--- |
| **Group Owner** | Full access to create the group, invite peers, remove members, and delete the shared space. |
| **Group Member** | Access to read/write messages, upload files to the group, and collaboratively edit shared documents. |
| **Local Peer** | Access to discoverable profiles; can send and receive direct messages and 1-on-1 file transfer offers. |

## 7. Assumptions
- Users are operating on a local area network (LAN/Wi-Fi) that permits mDNS multicast traffic and direct TCP socket connections.
- The underlying operating systems (Windows, Linux, macOS, Android) permit the app through local firewall restrictions.
- Team members possess the necessary knowledge of Flutter, Drift, and P2P networking protocols to execute the implementation.

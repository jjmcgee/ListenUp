# AGENTS.md — ListenUp Project Instructions

## Project Overview
- **App Name:** ListenUp
- **Purpose:** A native, subscription-free audio player for iOS and watchOS, tailored for both long-form fiction audiobooks and structured learning courses (e.g., Pimsleur language series).
- **Target OS:** iOS 26+, watchOS
- **IDE & Toolchain:** Xcode 26.6, Swift 6 (Strict Concurrency enabled)
- **Primary Frameworks:** SwiftUI, SwiftData, AVFoundation, MediaPlayer, WatchConnectivity, CloudKit

## Fundamental Architecture & Technical Invariants

### 1. Data Layer (SwiftData & CloudKit)
- Use a single, unified, hierarchical model: `LibraryItem`.
- An item can be a `.singleFile`, a `.multiPart` book (composed of multiple ordered child tracks), or a `.folder` (containing sub-levels or collections).
- **CloudKit Constraint:** All relationships between entities must be optional (`var parent: LibraryItem?`, `var children: [LibraryItem] = []`).
- Every model item must have an `id: UUID`, `lastUpdated: Date`, and `currentPosition: Double`.

### 2. Audio Playback Engine
- Virtual playback over physical files: Never concatenate multi-part audio files into giant monolithic files. Chain them dynamically using `AVQueuePlayer` or indexed offset math.
- Configure `AVAudioSession` with `.playback` category and `.spokenAudio` mode.
- All playback mutations, scrub updates, and `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` interactions must be strictly bound to the `@MainActor`.

### 3. File System & Security Scoping
- External audio imports must be securely handled using `startAccessingSecurityScopedResource()`, copied directly into the app sandbox's `Documents/` directory, and guaranteed to close with `defer { stopAccessingSecurityScopedResource() }`.
- Run file traversal and `AVURLAsset` metadata parsing off the main thread (`Task.detached`).

### 4. Apple Watch Integration
- Watch connectivity is split:
  - Lightweight scrub/position sync via `WCSession.sendMessage` or CloudKit.
  - Audio file sync via `WCSession.transferFile` with metadata dictionaries (`bookID`, `partIndex`).

## Coding Conventions
- Use modern Swift 6 paradigms: `@Observable` macros only (do not use `ObservableObject` or `@Published`).
- No data races. Ensure background workers pass sendable values back to the UI thread.
- Keep UI components small, modular, and reusable with dedicated SwiftUI preview mocks.

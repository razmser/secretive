# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Secretive is a macOS app for managing SSH keys stored in the Secure Enclave. It also supports Smart Cards (like YubiKey) as an alternative. Keys stored in Secure Enclave cannot be exported, providing strong security guarantees.

## Build Commands

**Build the Xcode project:**
```bash
xcrun xcodebuild -project Sources/Secretive.xcodeproj -scheme Secretive -configuration Debug build
```

**Run tests:**
```bash
# Test main packages via Xcode scheme
xcrun xcodebuild -project Sources/Secretive.xcodeproj -scheme PackageTests test

# Test SecretKit packages via SPM (from repo root)
swift test --build-system swiftbuild
```

**Archive for release:**
```bash
xcrun xcodebuild -project Sources/Secretive.xcodeproj -scheme Secretive -configuration Release -archivePath Archive.xcarchive archive
```

## Architecture

### Two-App Model
- **Secretive.app** (`Sources/Secretive/`): Main SwiftUI app for managing secrets (creating, deleting, viewing keys). Runs in foreground when user interacts.
- **SecretAgent.app** (`Sources/SecretAgent/`): Background SSH agent that runs as a Login Item inside Secretive.app. Handles all SSH signing requests via Unix socket.

### Swift Packages (`Sources/Packages/`)

The core logic is organized into Swift packages:

- **SecretKit**: Core protocols (`Secret`, `SecretStore`, `SecretStoreModifiable`) and type erasers. Defines the contract for all secret storage backends.
- **SecureEnclaveSecretKit**: Secure Enclave implementation using CryptoKit. Stores keys in Keychain with Secure Enclave protection.
- **SmartCardSecretKit**: Smart Card (PIV/YubiKey) implementation using CryptoTokenKit.
- **SecretAgentKit**: SSH agent implementation. Contains `Agent` (handles SSH protocol), `SocketController` (Unix socket management), and request tracing for notifications.
- **SSHProtocolKit**: OpenSSH protocol parsing/writing (public key format, signatures, certificates).
- **Brief**: Update checking and release management.
- **Common**: Shared utilities and bundle IDs.
- **XPCWrappers**: XPC service helpers for sandboxed communication.

### XPC Services
- **SecretiveUpdater**: Handles update checks in a sandboxed XPC service.
- **SecretAgentInputParser**: Parses SSH agent input in a sandboxed XPC service.

### Key Data Flow
1. SSH client connects to SecretAgent via Unix socket at `~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh`
2. `SocketController` accepts connection and traces request provenance (which app is requesting)
3. `Agent` receives parsed request, finds matching secret in `SecretStoreList`
4. `SigningWitness` (Notifier) is consulted before signing
5. Store performs signing operation (Secure Enclave requires Touch ID/Watch auth)
6. Notification shown to user about the signing event

## Important Constraints

- **No third-party dependencies**: All code must be auditable without external dependencies
- **Bundle ID consistency**: Keychain restricts key access to the bundle ID that created them. Changing bundle ID loses access to existing keys
- **Swift 6 with strict concurrency**: Uses `.swiftLanguageMode(.v6)` and `.strictMemorySafety()`
- **macOS 14+ required**: Minimum deployment target is macOS Sonoma

## Local Development (local-run branch)

The `local-run` branch contains a Justfile and modified bundle IDs for local development:

**Prerequisites:** Install [just](https://github.com/casey/just) and have Fish shell available.

**Common commands:**
```bash
just build    # Build SecretAgent (debug)
just open     # Build and launch Secretive.app GUI
just run      # Kill existing agent, rebuild, and run in foreground
just kill     # Stop any running SecretAgent processes
just clean    # Remove derived data and logs
```

**Debug socket path:** `~/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh`

**To use the debug agent:**
```bash
export SSH_AUTH_SOCK="$HOME/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh"
```

**View debug logs:**
```bash
log stream --style compact --level debug \
  --predicate 'subsystem == "com.razmser.secretive.secretagent"'
```

## Code Organization

- `Sources/Secretive.xcodeproj`: Main Xcode project containing all targets
- `Sources/Config/Config.xcconfig`: Build configuration (version numbers updated by CI)
- `Sources/Packages/Package.swift`: Swift package definition used by Xcode
- `Package.swift` (root): Thinned package for SPM compatibility (separate from Xcode package)

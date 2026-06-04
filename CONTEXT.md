# TruthID - PRD v1.0

## Vision

TruthID is a decentralized authentication platform that replaces traditional identity providers such as Google, Microsoft and Apple.

Users own their identity through a blockchain-backed root identity and authenticate using trusted devices instead of passwords.

The system prioritizes:

* User sovereignty
* Privacy
* Device trust
* Open source architecture
* Blockchain as source of truth

The project is NOT a password manager, NFT marketplace or crypto wallet.

The project only focuses on authentication and identity management.

---

# Core Problem

Current authentication systems depend on centralized providers.

Examples:

* Login with Google
* Login with Apple
* Login with Microsoft

Problems:

* Account lockouts
* Privacy concerns
* Data collection
* Vendor dependency
* Single point of failure

TruthID allows users to control their identity through wallet ownership and trusted devices.

---

# Core Concepts

## Identity

An identity represents a user.

Properties:

* Identity ID
* Username
* Controller Wallet
* Guardian Set
* Trusted Devices

Example:

username: fabio.id

---

## Root Wallet

The wallet is the highest authority.

Supported:

* MetaMask
* Rabby
* Ledger
* Trezor
* WalletConnect compatible wallets

Responsibilities:

* Create identity
* Add devices
* Remove devices
* Manage guardians
* Recover identity

The wallet is NOT required for daily authentication.

---

## Trusted Device

A trusted device is capable of authenticating on behalf of the user.

Examples:

* Desktop
* Laptop
* Mobile phone

Each device generates:

* Public Key
* Private Key

Private keys never leave the device.

---

## Guardians

Guardians provide identity recovery.

Example:

5 guardians

Threshold:

3 of 5

If root wallet is lost:

3 guardians approve recovery.

New root wallet becomes controller.

---

# User Flow

## Identity Creation

1. User connects wallet.
2. User chooses username.
3. Smart contract creates identity.
4. First trusted device is registered.
5. Identity becomes active.

---

## Add Device

1. Existing trusted device creates pairing QR code.
2. New device scans QR code.
3. New device generates key pair.
4. Root wallet signs approval transaction.
5. Device becomes trusted.

---

## Authentication Flow

1. Website displays QR code.
2. User scans QR code using trusted mobile device.
3. Mobile app displays login request.
4. User approves.
5. Device signs authentication challenge.
6. Website verifies signature.
7. User is logged in.

No password required.

No email required.

No root wallet required.

---

## Device Revocation

1. User opens TruthID Desktop.
2. User connects root wallet.
3. User selects compromised device.
4. User signs revocation transaction.
5. Device becomes revoked.

Future authentications fail.

---

## Session Management

Users can view active sessions.

Users can:

* Keep existing sessions
* Revoke selected sessions
* Revoke all sessions

Revoked sessions must be invalidated by integrated applications.

---

# Blockchain Design

## Network

Base Mainnet

Reasoning:

* EVM compatible
* Low fees
* Strong ecosystem
* Ethereum security model

---

## Smart Contracts

IdentityRegistry

Stores:

* Identity ID
* Username
* Controller Wallet
* Guardian Configuration

DeviceRegistry

Stores:

* Device Public Keys
* Device Metadata
* Revocation Status

RecoveryManager

Stores:

* Guardian approvals
* Recovery operations

---

# Off-Chain Components

## Desktop Application

Tech Stack:

* Tauri
* Rust
* React
* TypeScript

Responsibilities:

* Identity management
* Device management
* Session management
* Wallet interaction

---

## Mobile Application

Tech Stack:

* Flutter

Responsibilities:

* QR authentication
* Authentication approvals
* Device management
* Session visibility

---

## Relay Service

Purpose:

Enable communication between:

* Website
* Mobile App

Responsibilities:

* Relay authentication requests
* Deliver signed responses

Relay does NOT:

* Store identities
* Authenticate users
* Hold private keys

Relay is replaceable.

Any organization can self-host it.

---

# SDK

Provide official SDKs.

Phase 1:

* TypeScript
* Ruby
* Python

Capabilities:

verify_authentication()

verify_session()

check_device_status()

check_revocation()

---

# Security Requirements

Private keys must remain on device.

Use:

* Android Keystore
* iOS Secure Enclave
* Windows TPM
* Linux Keyring

All authentication challenges must be:

* Unique
* Time limited
* Non replayable

Every login must be signed.

Every device modification must require root wallet approval.

---

# Recovery

Default configuration:

5 guardians

Threshold:

3 approvals

Recovery process:

1. User requests recovery.
2. Guardians approve.
3. Timelock begins.
4. New wallet becomes controller.

Recommended timelock:

7 days.

---

# Non Goals

The following are explicitly out of scope:

* Password manager
* Token creation
* Governance token
* NFT marketplace
* DAO functionality
* Cryptocurrency exchange
* Social network

TruthID focuses exclusively on decentralized authentication.

---

# Monetization (Optional Future)

Core protocol remains open source.

Possible monetization:

* Hosted relay service
* Enterprise support
* Managed infrastructure
* Premium analytics

Authentication protocol must remain free and open.
# Authentication Analysis for Today RSS Reader

## Executive Summary

The issue requesting "2FA/Passkey support for web logins" is **not applicable** to the current architecture of Today RSS Reader. This document explains why and provides guidance for future considerations.

## Current Application Architecture

### What Today Is
- **Native iOS application** built with SwiftUI
- **Privacy-first, local-only** RSS reader
- **No authentication system** by design
- **No user accounts** or cloud services
- **No server infrastructure**
- All data stored locally using SwiftData

### Key Privacy Features (from PRIVACY.md)
```
- All data stored locally on your device
- No analytics or tracking
- No ads
- No account creation required
- No data sent to external servers (except fetching RSS feeds)
- AI processing happens on-device
```

### Current Data Storage
- Uses SwiftData (local SQLite database)
- No cloud sync or remote storage
- No user authentication layer
- Complete data portability via OPML export

## Why 2FA/Passkey Doesn't Apply

### 1. No Login System
The application has **zero authentication infrastructure**:
- No login screen
- No user registration
- No password management
- No session handling
- No authentication tokens

### 2. Design Philosophy
Adding authentication would **contradict core values**:
- Privacy-first architecture
- Local-only data storage
- No tracking or user profiling
- No account creation requirement

### 3. Technical Architecture
The app is designed as:
- Single-user, single-device application
- All state managed locally
- No server endpoints
- No API authentication needed

## If Authentication Were to Be Added (Hypothetical)

If the product direction changes and authentication becomes necessary (e.g., for iCloud sync, multi-device support), here's what would be required:

### Phase 1: Basic Infrastructure

#### Required Components
1. **User Account System**
   - User registration flow
   - Login/logout functionality
   - Password management
   - Email verification

2. **Backend Services**
   - Authentication server
   - User database
   - Session management
   - API endpoints for sync

3. **Data Migration**
   - Local-to-cloud data migration
   - Conflict resolution
   - Sync engine

### Phase 2: Two-Factor Authentication

#### TOTP-Based 2FA Implementation

**Required:**
```swift
// Add dependencies
// - SwiftOTP for TOTP generation
// - Keychain Services for secure storage

// Models
class UserAccount {
    var email: String
    var totpSecret: String? // Encrypted in Keychain
    var backupCodes: [String]? // One-time recovery codes
    var twoFactorEnabled: Bool
}

// Services
class TwoFactorAuthService {
    func generateTOTPSecret() -> String
    func verifyTOTPCode(_ code: String, secret: String) -> Bool
    func generateBackupCodes() -> [String]
    func enableTwoFactor(for user: UserAccount)
    func disableTwoFactor(for user: UserAccount)
}

// Views
struct TwoFactorSetupView: View { }
struct TwoFactorVerificationView: View { }
```

**Implementation Steps:**
1. Generate TOTP secret on 2FA enrollment
2. Display QR code for authenticator app
3. Verify setup with test code
4. Store encrypted secret in Keychain
5. Generate and display backup codes
6. Add 2FA check to login flow

**Libraries to Consider:**
- [SwiftOTP](https://github.com/lachlanbell/SwiftOTP) - TOTP/HOTP implementation
- [CoreOTP](https://github.com/moffatman/coreotp) - Another OTP library

### Phase 3: Passkey/WebAuthn Support

#### Passkey Implementation

**Required:**
```swift
import AuthenticationServices

// Passkey Registration
class PasskeyService {
    func registerPasskey(for user: UserAccount) async throws {
        let challenge = try await fetchChallenge(from: server)
        
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "today.app"
        )
        
        let request = platformProvider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: user.email,
            userID: user.id.uuidString.data(using: .utf8)!
        )
        
        // Present authorization controller
        let controller = ASAuthorizationController(authorizationRequests: [request])
        // Handle delegate callbacks
    }
    
    func authenticateWithPasskey() async throws {
        let challenge = try await fetchChallenge(from: server)
        
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "today.app"
        )
        
        let request = platformProvider.createCredentialAssertionRequest(
            challenge: challenge
        )
        
        // Present authorization controller
        let controller = ASAuthorizationController(authorizationRequests: [request])
        // Handle delegate callbacks
    }
}

// View for Passkey Management
struct PasskeySettingsView: View {
    @State private var passkeysEnabled = false
    
    var body: some View {
        List {
            Section("Security") {
                Toggle("Enable Passkeys", isOn: $passkeysEnabled)
                
                if passkeysEnabled {
                    Button("Add Passkey") {
                        Task {
                            try await registerPasskey()
                        }
                    }
                    
                    // List registered passkeys
                    ForEach(registeredPasskeys) { passkey in
                        PasskeyRow(passkey: passkey)
                    }
                }
            }
        }
    }
}
```

**Implementation Steps:**
1. Add "Sign in with Passkey" capability to Xcode project
2. Configure Associated Domains for WebAuthn
3. Implement registration flow (ASAuthorizationPlatformPublicKeyCredentialProvider)
4. Implement authentication flow
5. Add passkey management UI
6. Handle account recovery scenarios

**Apple Documentation:**
- [Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/public-private_key_authentication/supporting_passkeys)
- [ASAuthorizationController](https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller)

### Phase 4: Account Recovery

#### Recovery Mechanisms

**Required:**
1. **Email Recovery**
   - Password reset via email link
   - Time-limited recovery tokens
   - Secure token storage

2. **Backup Codes**
   - One-time use codes for 2FA bypass
   - Generate 10 codes at setup
   - Secure storage, display once

3. **Account Recovery for Lost 2FA Device**
   - Identity verification process
   - Support ticket system
   - Alternative verification methods (SMS, email)

4. **Passkey Recovery**
   - Multiple passkeys (phone + tablet + security key)
   - Account recovery contact
   - Waiting period for recovery

```swift
struct AccountRecoveryService {
    func initiatePasswordReset(email: String) async throws
    func verifyRecoveryToken(_ token: String) async throws -> Bool
    func resetPassword(token: String, newPassword: String) async throws
    
    func verifyBackupCode(_ code: String, for user: UserAccount) -> Bool
    func invalidateBackupCode(_ code: String, for user: UserAccount)
    
    func initiateAccountRecovery(email: String) async throws
    func verifyRecoveryIdentity(method: RecoveryMethod) async throws
}
```

## Security Considerations

If authentication is implemented, consider:

### 1. Data Encryption
- Encrypt local database with user credentials
- Key derivation from password (PBKDF2/Argon2)
- Secure enclave for biometric keys

### 2. Secure Communication
- TLS 1.3 for all API calls
- Certificate pinning
- API authentication tokens (JWT)

### 3. Token Management
- Short-lived access tokens (15 min)
- Refresh tokens (secure storage)
- Automatic token rotation

### 4. Biometric Authentication
```swift
import LocalAuthentication

func authenticateWithBiometrics() async throws -> Bool {
    let context = LAContext()
    var error: NSError?
    
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        throw AuthenticationError.biometricsNotAvailable
    }
    
    return try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Authenticate to access Today"
    )
}
```

## Estimated Implementation Effort

| Phase | Component | Effort (Story Points) |
|-------|-----------|----------------------|
| 1 | User Account System | 13 |
| 1 | Backend Infrastructure | 21 |
| 1 | Data Sync Engine | 13 |
| 2 | TOTP-based 2FA | 8 |
| 2 | Backup Codes | 5 |
| 3 | Passkey Registration | 8 |
| 3 | Passkey Authentication | 8 |
| 3 | Passkey Management UI | 5 |
| 4 | Email Recovery | 5 |
| 4 | 2FA Recovery Flow | 8 |
| 4 | Passkey Recovery | 5 |
| - | **Total** | **99** |

**Time Estimate:** 3-4 months for 1-2 developers

## Privacy Impact Assessment

Adding authentication would require updates to:

### Privacy Policy Changes
- User account data collection
- Server-side data storage
- Authentication logs
- Email communications

### App Store Privacy Labels
- Contact Info (Email)
- User ID
- Authentication data
- Usage Data (if analytics added)

### GDPR Compliance
- User consent flows
- Data deletion requests
- Data portability (already exists via OPML)
- Right to access data

## Alternative Approaches

Instead of traditional authentication, consider:

### 1. iCloud Sync (No Custom Auth)
```swift
import CloudKit

// Use Apple's authentication
class iCloudSyncService {
    let container = CKContainer.default()
    
    func enableSync() async throws {
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw SyncError.iCloudNotAvailable
        }
        // Sync using CloudKit
    }
}
```

**Benefits:**
- No custom authentication needed
- Apple handles security
- Native iOS integration
- Better privacy (data stays in user's iCloud)

### 2. Device-to-Device Sync (No Cloud)
- Use Multipeer Connectivity
- Local WiFi sync between devices
- No server infrastructure
- No authentication needed

### 3. Encrypted Local Storage Only
- Use device biometrics for app access
- No cloud sync, no accounts
- Maintain current privacy-first approach

## Recommendations

1. **Short Term (Current)**: Do NOT implement authentication
   - Maintains privacy-first approach
   - Keeps app simple and focused
   - Avoids server costs and complexity

2. **Medium Term (If Sync Needed)**: Use iCloud Sync
   - Leverages Apple's infrastructure
   - No custom authentication required
   - Maintains privacy principles

3. **Long Term (If Custom Auth Needed)**: Passkey-First Approach
   - Skip traditional passwords
   - Implement passkeys as primary auth
   - Add 2FA as optional additional security
   - Use biometrics for local app access

## Conclusion

The current issue (#XX) requesting "2FA/Passkey support for web logins" is **not applicable** to Today RSS Reader as:

1. The app has no login system
2. The app has no web component
3. The app is designed to be local-only
4. Adding authentication would contradict core design principles

**Suggested Action:** Close this issue as "Won't Fix" or "Not Applicable"

**If authentication is truly desired in the future**, revisit this document for implementation guidance, but carefully consider whether it aligns with the app's privacy-first mission.

---

*Document created: February 18, 2026*
*Last updated: February 18, 2026*

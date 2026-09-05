# CopyClip OSS

An open-source clone of the CopyClip menu bar clipboard manager for macOS, with one big
difference: **your clipboard history is encrypted at rest and locked behind Touch ID or a PIN.**

- Lives in the menu bar. Click the icon, see your last N copied texts, click one to copy it back.
- Search, max-items setting, launch at login. That is the whole feature set, on purpose.
- Every click on the icon asks for Touch ID (PIN as fallback). It stays unlocked for 60 seconds,
  then locks again and wipes the history from memory.
- No other process on the machine can read the stored history. See *Security model* below.

Requires macOS 14+. Touch ID requires a Mac with a Secure Enclave (any Apple Silicon or T2 Mac).

## Install

Download `CopyClipOSS.app.zip` from the [latest release](https://github.com/elitex45/copyclip-oss/releases/latest),
unzip, and drag `CopyClipOSS.app` to `/Applications`. The app is ad-hoc signed, so the first launch needs:

```bash
xattr -dr com.apple.quarantine /Applications/CopyClipOSS.app
```

Or build it yourself in one minute (below).

## Build

```bash
./scripts/make-app.sh          # ad-hoc signed, hardened runtime -> build/CopyClipOSS.app
open build/CopyClipOSS.app
```

Only the Xcode Command Line Tools are needed, not Xcode itself.
Pass a signing identity to sign for distribution: `./scripts/make-app.sh "Developer ID Application: ..."`.

Self-test (crypto, inbox, Secure Enclave):

```bash
./build/CopyClipOSS.app/Contents/MacOS/CopyClipOSS --selftest            # no prompt
./build/CopyClipOSS.app/Contents/MacOS/CopyClipOSS --selftest --touchid  # shows a Touch ID prompt
```

## Security model

Files live in `~/Library/Application Support/CopyClipOSS/` (mode 0700).

| File | Contents | Readable by another process? |
|---|---|---|
| `header.json` | salts, the DEK wrapped by the PIN key, the DEK wrapped by the Secure Enclave, the inbox public key | Yes, but it contains no secrets |
| `vault.enc` | AES-256-GCM of the whole history + inbox private key | No, needs the DEK |
| `inbox/*.bin` | clips captured while locked, sealed to the inbox public key | No, needs the inbox private key (inside `vault.enc`) |

- **DEK** (data encryption key): random 256-bit AES key. Exists in memory only while unlocked.
- **PIN path:** PBKDF2-HMAC-SHA256, 600,000 rounds, 16-byte salt, derives a key that wraps the DEK. The PIN is never stored. A wrong PIN fails the GCM tag.
- **Touch ID path:** a P-256 key generated *inside the Secure Enclave* with `.biometryCurrentSet`. The DEK is wrapped by ECDH with that key. Unwrapping requires the chip to perform the agreement, and the chip refuses without a fresh Touch ID match. The private key never leaves the chip. Re-enrolling fingerprints invalidates it (PIN still works).
- **Recording while locked:** the app must keep capturing clips while locked, but must not be able to read them. Each new clip is sealed with an ephemeral Curve25519 key to the inbox public key. The matching private key lives inside `vault.enc`. On unlock the inbox is decrypted, merged, and deleted.
- **Auto-lock:** 60 seconds after unlock (any click resets the timer) the DEK and history are dropped from memory.
- **Hardened runtime** is enabled, so other processes cannot attach a debugger or inject libraries without root.
- Items marked `org.nspasteboard.ConcealedType` (password managers) are never recorded.

### What this does *not* protect against

- **The live clipboard.** macOS lets any app read the current pasteboard. We protect the history, not the one item you just copied.
- **Root or a debugger during the 60-second unlocked window.** The DEK and plaintext are in process memory then. This is true of every app.
- **Someone who knows your PIN.** Choose a long one. Six characters is the minimum.
- **A malicious app that shows you a Touch ID prompt** and you approve it. The Secure Enclave key blob is on disk; another process could load it, but it would still need *you* to touch the sensor for its prompt. Read the prompt text before you touch.

## Layout

```
Sources/CopyClipOSS/
  App.swift              MenuBarExtra entry point
  Views.swift            Setup / Unlock / History / Settings screens
  LockManager.swift      lock state + 60s timer
  Vault.swift            encrypted store + inbox
  Crypto.swift           PBKDF2, AES-GCM, inbox sealing
  SecureEnclaveKey.swift Touch ID wrap/unwrap
  ClipboardWatcher.swift pasteboard polling
  SelfTest.swift         --selftest
scripts/make-app.sh      build + bundle + sign
```

## Contributing

PRs welcome. Keep the crypto in `Crypto.swift` / `SecureEnclaveKey.swift` small and auditable.
Run `--selftest` before opening a PR. MIT licensed.

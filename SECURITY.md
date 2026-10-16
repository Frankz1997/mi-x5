# Security

Mi X5 stores a device ID, a private IPv4 address and a Tuya local key on your own device. It does not require a Tuya cloud token at runtime.

- Windows encrypts the saved connection with DPAPI, bound to the Windows account. `flutter_secure_storage.dat` remains beside the executable and must not be committed or included in shared ZIPs.
- Android uses Flutter Secure Storage; Android backup is disabled. The widget receives display state only, not the connection credentials.
- macOS is configured to use Keychain; this platform has not been built or validated yet.
- Control traffic uses the implemented Tuya 3.5 protocol over local TCP. This is not a security review of the Tuya device firmware or the network.

Do not attach real keys, cloud tokens, connection exports, private signing keys or screenshots of revealed credentials to issues or pull requests. All examples and UI captures in this repository use public dummy data. `0123456789abcdef` is deliberately a test fixture, not an application default.

For a suspected vulnerability, use GitHub's private vulnerability reporting if it is enabled for this repository. Otherwise open an issue requesting a private contact channel without including the vulnerability details or credentials.

If a real secret is accidentally published, revoke or replace it using the provider's supported process before attempting to remove it from Git history. Ignoring a file does not remove a secret from an existing commit.

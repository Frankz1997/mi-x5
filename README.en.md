# Mi X5

Local Wi-Fi controls for the **Mirage Inverter X5 CVF121Q**, with an animated Flutter desktop panel, Android app and home-screen widget.

[Español](README.md) · [Build instructions](docs/BUILDING.md) · [Device setup](docs/DEVICE_SETUP.md) · [Protocol notes](docs/PROTOCOL.md)

<p align="center"><img src="docs/images/demo.gif" width="420" alt="Animated mini-split and expanding fan control"></p>

The app communicates directly with the AC over local TCP using Tuya 3.5. Runtime control does not require cloud credentials. Each installation uses its own device ID, private IPv4 address and local key. The user interface is currently in Spanish.

## Platforms

| Platform | Status |
| --- | --- |
| Windows | Tray panel, animated UI and clipped native blur on Windows 11; tested with the CVF121Q |
| Android | Full-screen app and native widget; widget network operations verified on an Android 16 emulator with a local simulator |
| macOS | Runner, menu-bar integration, network entitlements and Keychain setup present; **not built or tested yet** |

<p align="center">
  <img src="docs/images/windows.png" width="300" alt="Desktop panel">
  <img src="docs/images/android.png" width="220" alt="Android screen">
  <img src="docs/images/widget.png" width="250" alt="Android widget">
</p>

Screenshots and animation use simulated data. The desktop background is a neutral presentation surface; native Windows blur is platform-specific and has not been implemented on macOS.

## Controls

- Power and temperature, limited to 16–30 °C.
- Cool, Auto, Dry and Fan modes; no heating on this cooling-only model.
- Auto, Silent, Low, Medium, High and Turbo fan settings.
- Sleep, vertical swing on/off and the unit's display light.
- Animated louver and airflow; expanding mode/fan controls; internal settings screen.
- Android widget actions without opening the app, using a temporary service that stops after completion or failure.

Compatibility is limited to the implemented device profile. A Wi-Fi connection, Smart Life account or generic Tuya schema alone does not establish support for another AC. Eco I/II have no identified native Wi-Fi command; infrared captures are separate experimental research. The exact mapping between all fan labels and the original remote still needs calibration.

## Build

Use **Flutter 3.29.2 / Dart 3.7.2**, and keep `pubspec.lock` and both `vendor/` folders.

```sh
git clone https://github.com/Frankz1997/mi-x5.git
cd mi-x5
flutter pub get
flutter analyze lib test tool
flutter test
```

Windows requires Visual Studio's C++ desktop workload. Run `flutter run -d windows`.

On a Mac with Xcode and CocoaPods:

```sh
flutter doctor -v
flutter run -d macos
flutter build macos --release
```

For Android, connect a phone/emulator and run `flutter run`, or build with `flutter build apk --release`. The current Release configuration uses the local debug signing key; configure your own private release signing for distribution. [Detailed requirements](docs/BUILDING.md).

## Configure your own device

Obtain the ID and local key from your own linked Tuya Developer project, and the AC's private IPv4 address from your router. Enter all three in Settings and use **Comprobar y guardar**. The app validates the connection before saving it.

Windows uses DPAPI, Android uses secure storage and macOS is configured for Keychain. Existing saved JSON connections remain readable after the public-source update. Windows-encrypted data is account-bound and cannot be transferred to a Mac; configure the Mac separately. See [device setup](docs/DEVICE_SETUP.md) and [security](SECURITY.md).

Tests use fake clients or a loopback simulator and never require a real AC or cloud account. The physical S23 widget result and macOS still need verification; operation with the router's internet uplink disconnected has not been tested. [Tests and capture generation](docs/TESTING.md).

## License and contributions

Original code: [MIT](LICENSE). Dependencies and assets retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). The mini-split render was generated for this project. This is an independent community project, not affiliated with Mirage or Tuya.

Read [CONTRIBUTING](CONTRIBUTING.md) before proposing device-profile changes. Never include real keys, private connection files or signing material in an issue or pull request.

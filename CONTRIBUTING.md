# Contributing

Please describe the device model, platform and reproducible behavior when reporting a problem. Redact personal identifiers and credentials. This app currently implements the CVF121Q control profile; a shared Tuya category or the presence of Wi-Fi alone does not establish compatibility.

Before submitting a change:

```sh
flutter pub get
flutter analyze lib test tool
flutter test
```

Use the existing Flutter/Dart style and keep changes focused. Add a meaningful regression test for changed behavior. Keep the modified packages under `vendor/` and explain any changes to them.

Do not add unsupported device commands based solely on Tuya's generic schema. State whether a feature was observed in the model, acknowledged over Wi-Fi or physically verified. Automated tests should use fake clients or the loopback simulator, never a real AC or cloud credentials.

See [building](docs/BUILDING.md), [device setup](docs/DEVICE_SETUP.md), [protocol notes](docs/PROTOCOL.md) and [security](SECURITY.md).

# Changelog

## 0.3.0

- Prepare the project for a public source repository, with no personal device ID or IP defaults.
- Configure the Tuya device ID alongside the local IP and local key.
- Keep the existing encrypted connection format readable, without resetting saved settings.
- Add illustrated documentation, build instructions, compatibility notes and third-party credits.
- Add validation tests for device IDs, saved configurations and empty first-run fields.

## 0.2.1

- Use a temporary foreground service for Android widget commands, with bounded network operations and cleanup.
- Fill the available Android screen and keep configuration actions visible above the keyboard.

## 0.2.0

- Integrate the Flutter desktop UI with animated airflow and louver, expanding mode/fan controls and internal settings.
- Add an Android home-screen widget.
- Add clipped native blur and a mini-split tray icon on Windows.

## 0.1.0

- Initial local Tuya 3.5 controls for the Mirage Inverter X5 CVF121Q.
- Validate vertical oscillation through DP 31; keep unsupported heating and horizontal swing out of the controls.

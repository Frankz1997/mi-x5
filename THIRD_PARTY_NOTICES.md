# Third-party notices

The original Mi X5 application code is licensed under [MIT](LICENSE). Included third-party components retain their own licenses.

| Component | Use | License / attribution |
| --- | --- | --- |
| [TinyTuya Dart](https://github.com/sjhorn/tinytuya) | Local Tuya protocol, vendored in `vendor/tinytuya` | [MIT, including the Python TinyTuya attribution](vendor/tinytuya/LICENSE) |
| [Flutter Secure Storage](https://github.com/mogol/flutter_secure_storage) | Encrypted local connection storage; Windows implementation vendored | [BSD 3-Clause](vendor/flutter_secure_storage_windows/LICENSE) |
| [Tabler Icons](https://tabler.io/icons?icon=air-conditioning) | Air conditioning tray/application icon, SVG/PNG/ICO | [MIT, Paweł Kuna](assets/Tabler-LICENSE.txt) |
| Roboto Condensed | Application and preview typography | [Apache 2.0](assets/Roboto-LICENSE.txt) |
| Mini-split render | `assets/mini-split.png` and the matching preview asset | Generated with OpenAI ImageGen for this project; [generation prompt and provenance](ui-preview/assets/mini-split.prompt.txt). No Mirage product photograph or logo is included. |

Local changes to TinyTuya lower its SDK constraint to Dart 3.7.2 for the tested application toolchain. The Windows secure-storage variant uses Dart FFI and DPAPI, stores its encrypted data beside the executable and avoids the legacy native ATL plugin. Keep both vendor folders and their licenses when redistributing source.

Other packages are declared in [pubspec.yaml](pubspec.yaml) and pinned in [pubspec.lock](pubspec.lock): Flutter, Home Widget, Tray Manager, Window Manager, Screen Retriever and their transitive dependencies. Flutter's license registry includes the notices supplied by these packages in application builds.

The `tool/ir_*` sketches use [Arduino-IRremote](https://github.com/Arduino-IRremote/Arduino-IRremote) as an external dependency; the library is not bundled. The IR investigation links to IRremoteESP8266 as a protocol reference and does not bundle that library.

Mirage, Tuya, Smart Life, Windows and Android are names of their respective owners. This is an independent community project with no affiliation or endorsement.

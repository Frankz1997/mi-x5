# Compilar Mi X5

[Volver al README](../README.md)

## Código y herramientas

Versión de referencia: **Flutter 3.29.2 y Dart 3.7.2**. Los paquetes están fijados en `pubspec.lock`; conserva las dependencias modificadas en `vendor/`. Otra versión de Flutter puede requerir ajustes no validados.

```sh
git clone https://github.com/Frankz1997/mi-x5.git
cd mi-x5
flutter doctor -v
flutter pub get
flutter analyze lib test tool
flutter test
```

No copies `.dart_tool/`, `build/`, `local.properties` ni `*/Flutter/ephemeral/` desde otra máquina. Son archivos generados con rutas de esa computadora. Flutter los regenera en el destino.

## macOS

Necesitas una **Mac con Xcode**, sus herramientas de línea de comandos y CocoaPods. Sigue la [configuración oficial de Flutter para macOS](https://docs.flutter.dev/platform-integration/macos/setup) y resuelve los avisos de Flutter Doctor.

```sh
flutter pub get
flutter run -d macos
flutter build macos --release
```

Salida esperada: `build/macos/Build/Products/Release/mirage_x5.app`. El runner incluye `LSUIElement` para la barra de menús, permisos de red cliente y descripción del acceso a red local. Flutter prepara las dependencias nativas durante la primera compilación; no copies un Podfile de Windows.

Configura tus datos nuevamente en la Mac. La conexión cifrada de Windows no es portable entre sistemas. Comprueba lectura, comandos, guardado en Keychain, reapertura y colocación junto al icono. Autoriza el acceso a la red local cuando macOS lo solicite.

**Estado:** no se ha compilado ni probado en macOS. La firma puede necesitar configuración en `macos/Runner.xcworkspace`. Publicar una aplicación para otras Macs requiere revisar firma y distribución. El blur de Windows no tiene implementación macOS. No se entrega un DMG.

## Windows

Necesita Visual Studio con **Desarrollo para el escritorio con C++**, Windows SDK y los componentes que indique Flutter Doctor. Activa Modo de desarrollador si Flutter informa que necesita soporte de enlaces simbólicos.

```sh
flutter run -d windows
flutter build windows --release
```

La salida está en `build/windows/x64/runner/Release/`. Es portable: conserva el ejecutable, las DLL y `data/` juntos. Inicia oculta en la bandeja y abre los controles al pulsar el icono. El blur requiere Windows 11 y transparencia disponible; sin blur los controles siguen siendo utilizables.

Para iniciar con tu sesión, coloca un **acceso directo** al ejecutable en la carpeta que abre `Win + R` → `shell:startup`. La app no registra el inicio automáticamente.

Al preparar un ZIP público, excluye `flutter_secure_storage.dat`: es tu configuración privada. Al actualizar tu instalación personal, consérvalo localmente.

## Android

Configura el SDK y un dispositivo/emulador con Flutter Doctor. El proyecto usa JDK 17 para Gradle/AGP, compile SDK 36, NDK 26.3.11579264 y Gradle 8.10.2. minSdk 24 requiere Android 7 o posterior.

```sh
flutter devices
flutter run
flutter build apk --release
```

Salida: `build/app/outputs/flutter-apk/app-release.apk`. El SDK puede necesitar descargar los componentes declarados. `android/local.properties` se genera localmente.

La configuración Release firma con la clave **debug local** para desarrollo. Para una distribución mantenida configura una clave privada propia y conserva la firma en futuras actualizaciones. No subas el keystore ni sus contraseñas. Una firma distinta impide instalar sobre un APK existente firmado con otra clave.

## HTML

Abre `ui-preview/index.html` conservando CSS, JS y assets. Es una simulación sin comandos ni credenciales reales. [Guía](../ui-preview/README.md). Su rango experimental de 16–32 °C no modifica el límite funcional de 16–30 °C.

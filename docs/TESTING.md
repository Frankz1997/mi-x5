# Pruebas y capturas

[Volver al README](../README.md)

## Verificación automatizada

```sh
flutter pub get
flutter analyze lib test tool
flutter test
```

La suite cubre configuración e ID, lectura del JSON anterior, límites de comandos, lecturas sin parpadeo, serialización, UI móvil/escritorio, navegación, colocación en bandeja, acciones del widget y tiempos de espera sin escrituras tardías.

`test/widget_protocol_test.dart` conecta a un simulador ligado a `127.0.0.1` en un puerto efímero, con clave ficticia. Comprueba negociación Tuya 3.5, órdenes cifradas y estado. Comparte funciones del paquete con el cliente: no es una implementación independiente ni una certificación Tuya.

Los tests no leen conexiones personales ni necesitan una cuenta Tuya; tampoco operan hardware real.

## Capturas de documentación

```sh
flutter test tool/capture_docs.dart
```

Renderiza la UI Flutter con ID, IP y clave ficticios. Escribe PNG en `docs/images/` y 72 fotogramas para el GIF en `build/docs-frames/`. Carga la fuente incluida, mantiene la clave oculta y no inicia `X5Client`.

Para ensamblar `docs/images/demo.gif` desde esos fotogramas, instala Pillow en tu entorno Python de documentación y ejecuta `python tool/assemble_demo.py`. El GIF muestra el render y las transiciones reales de Flutter a unos 12 fps. `widget.png` procede de una prueba nativa aislada en emulador con datos ficticios; el generador Flutter no crea ese widget nativo.

## Widget Android

El harness `android/app/src/androidTest/.../WidgetReviewInstrumentation.java` está limitado a emuladores. La prueba anterior del APK 0.2.1 en Android 16 incluyó diez clics reales, nueve escrituras, app cerrada, conexión segura y simulador local. También comprobó recuperación sin conexión y cierre del servicio.

Para repetirla, configura **solo un emulador** con IP `10.0.2.2`, clave ficticia `0123456789abcdef` e ID `demo-x5-device`. Inicia el servidor:

```sh
dart run tool/widget_tuya_simulator.dart
```

Compila la app y `:app:assembleReleaseAndroidTest` con Gradle, instala ambos APK en el emulador y ejecuta:

```sh
adb shell am instrument -w -e network true local.mirage.mirage_x5.test/local.mirage.mirage_x5.WidgetReviewInstrumentation
```

El harness requiere un emulador nuevo de pruebas; no lo uses en tu teléfono personal. Con el servidor detenido, `-e offline true` comprueba recuperación. No se requiere desactivar optimización de batería. Falta verificarlo en un S23 físico con el minisplit.

## Límites

- UI verificada con datos simulados; aceptación Wi-Fi no equivale al efecto físico de todos los modos.
- macOS sin construir ni ejecutar.
- Sin prueba de control con la salida a internet del router desconectada.
- Las muestras breves de CPU/GPU en Windows Debug no acreditan el consumo prolongado de Release o Android.

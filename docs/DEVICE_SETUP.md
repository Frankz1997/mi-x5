# Configurar tu equipo

[Volver al README](../README.md)

## Compatibilidad

Perfil implementado: **Mirage Inverter X5 CVF121Q, solo frío**, protocolo local **Tuya 3.5**. Aceptar el ID de otra unidad no convierte el perfil en universal. Otro modelo necesita verificar protocolo, parámetros y respuesta física.

## Datos necesarios

| Dato | Qué introducir | Dónde obtenerlo |
| --- | --- | --- |
| ID del dispositivo | Identificador de tu minisplit, sin espacios | Tu propio proyecto Tuya Developer vinculado a Smart Life |
| IP local | IPv4 privada actual | Lista de dispositivos o reservas DHCP de tu router |
| Clave local | Clave de 16 caracteres | Datos del dispositivo/API correspondiente en tu proyecto de Tuya |

Una instalación nueva empieza con campos vacíos. `demo-x5-device`, `192.168.1.50` y `0123456789abcdef` son ejemplos ficticios; no conectarán a tu minisplit.

El proceso para consultar la clave depende de los permisos y servicios de tu proyecto Tuya. Usa su portal y documentación oficial; no necesitas introducir credenciales de nube en Mi X5. No pegues tokens ni claves en issues o capturas públicas.

## Primera conexión

1. Vincula el equipo a Smart Life según el fabricante.
2. Conecta computadora/teléfono a la misma red local, con comunicación entre dispositivos. Las redes de invitados o el aislamiento Wi-Fi pueden impedirlo.
3. Abre Mi X5; en escritorio usa su icono en bandeja/barra de menús.
4. En Configuración introduce ID, IP y clave; pulsa **Comprobar y guardar**.
5. Espera **Conectado** y comprueba una acción sencilla en el equipo.

Solo se admite IPv4 privada literal: `10.x.x.x`, `172.16.x.x`–`172.31.x.x` y `192.168.x.x`. No direcciones públicas, DNS ni URLs. El transporte usa TCP 6668. Mantén Celsius.

Una reserva DHCP mantiene estable la IP. Si vuelves a vincular el aire, su clave puede cambiar; actualiza cada instalación.

## Almacenamiento y actualizaciones

- **Windows:** `flutter_secure_storage.dat`, cifrado con DPAPI junto al ejecutable y ligado a tu cuenta de Windows. Consérvalo localmente y exclúyelo de copias públicas.
- **Android:** almacenamiento seguro; backup desactivado. El widget comparte la conexión segura de la app y recibe solo datos de visualización en sus preferencias.
- **macOS:** Keychain configurado, aún pendiente de verificar.

El JSON anterior ya guardaba `id`, `ip` y `key`. La versión pública lee el mismo formato y usa el ID guardado. No borres tu conexión para actualizar.

En otra computadora/sistema hay que introducir los tres datos nuevamente. La conexión DPAPI no se puede copiar a macOS.

## Widget Android

Configura la app y abre los controles una vez. Usa **Configuración → Agregar widget**, o mantén pulsado el inicio → Widgets → Mi X5.

Modo y Ventilador cambian cíclicamente al pulsar su tarjeta. Cada acción consulta el estado antes de modificarlo. El widget conserva la última lectura; toca el estado inferior para actualizar. Puede aparecer una notificación temporal mientras se comunica con el equipo.

Ante **Sin conexión**, verifica ID/IP/clave y red desde la app. El servicio se probó en emulador Android 16 con un simulador; falta confirmar el widget corregido en el S23 físico.

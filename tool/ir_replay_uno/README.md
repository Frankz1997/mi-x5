# Prueba de reproducción IR de Eco con Arduino Uno

Usa IRremote 4.7.1 y reproduce las tres capturas completas de 23 °C guardadas en `../ir_capture_uno/captures/`. Conserva los 243 intervalos de cada señal, omitiendo la pausa inicial. No genera paquetes a partir de una fórmula ni modifica la app Flutter.

## Conexión para una primera prueba a corta distancia

Con el Uno desconectado del USB:

```text
Arduino D3 -> resistencia de 330 ohm -> ánodo (+) del LED IR
Cátodo (-) del LED IR -> Arduino GND
```

Esta prueba usa el LED directamente con su resistencia en serie. A 5 V, incluso sin descontar la caída del LED, 5/330 limita la corriente a unos 15,2 mA; está por debajo de los 20 mA recomendados por pin del Uno AVR. El alcance puede ser corto. El 2N2222A no interviene en este montaje y no hace falta una resistencia de base. Para un montaje con transistor habrá que identificar sus pines: la foto no permite confirmar el fabricante.

El RQ-S003 puede seguir conectado a D11, pero este programa solo transmite. Para volver a capturar, carga `../ir_capture_uno/ir_capture_uno.ino`.

## Cargar y probar

1. Abre `ir_replay_uno.ino` en Arduino IDE. Usa la misma biblioteca **IRremote 4.7.1** de la captura, selecciona **Arduino Uno** y el puerto USB.
   Los `#define` deben estar antes de la primera inclusión de `IRremote.hpp`. Si Arduino IDE agrega un `#include <IRremote.hpp>` al principio, elimina esa línea extra y conserva la inclusión después de los tres `#define`. La inicialización especifica D3 con `IrSender.begin(IR_SEND_PIN, USE_DEFAULT_FEEDBACK_LED_PIN)`.
2. Sube el programa; reemplaza el programa receptor cargado en el Uno. No transmite al arrancar.
3. Abre el Monitor serie a **115200 baudios**. Aparecerá `Mi X5: emisor D3 listo`.
4. Con el control Mirage, deja el equipo encendido en **Frío, 23 °C, ventilador medio y Eco apagado**, como en las capturas originales.
5. Apunta el LED al receptor del minisplit desde unos **20–50 cm**. Escribe una sola orden y pulsa Enviar:

| Orden | Captura reproducida |
| --- | --- |
| `1` | Eco I a 23 °C |
| `2` | Eco II a 23 °C |
| `0` | Eco apagado a 23 °C; no es una orden de apagado del equipo |

Espera `LISTO` y al menos dos segundos antes de enviar la siguiente orden. `LISTO` solo confirma que el Uno terminó de emitir. Anota si el minisplit pita y si hay un indicador o cambio observable de Eco. La pantalla del control Mirage no refleja órdenes emitidas por el Arduino.

## Límites de esta prueba

Las capturas incluyen datos de temperatura y podrían restaurar otros ajustes del control, incluido el encendido. No son órdenes aisladas de Eco. Se usa **38 kHz como portadora de prueba**, porque el receptor demodulado no midió la frecuencia original. Un pitido comprueba recepción; para confirmar Eco I/II hace falta un indicador del equipo o verificar el efecto correspondiente.

El programa compila para `arduino:avr:uno`: 3930 bytes de flash y 192 bytes de RAM. Los tres arrays se comprobaron contra los JSON de captura y tienen comprobaciones de longitud en compilación. El alcance máximo y el efecto de Eco todavía no se han comprobado. Esta reproducción por USB e infrarrojos no habilita un comando Eco en Tuya.

## Recepción de las tres señales confirmada: 12 de octubre de 2026

El usuario confirmó que cargó el programa en el Uno y que el montaje usa el LED con 330 Ω, sin transistor. Tras enviar `1`, confirmó que el minisplit emitió un pitido. Después de las indicaciones de enviar `2` y `0`, confirmó que el equipo emitió sonido con ambas órdenes. Hay respuesta física a las tres señales capturadas: Eco I, Eco II y Eco apagado. Estos pitidos no demuestran todavía que se apliquen los límites de potencia de Eco I/II ni que se restaure el funcionamiento sin Eco. Tampoco se ha medido el alcance máximo.

El usuario también confirmó que los indicadores Eco I/II aparecen solo en el control remoto. No hay un indicador Eco visible en el minisplit que permita comprobar el estado aplicado con esta prueba. La pantalla del control no sirve como confirmación de las órdenes enviadas por el Arduino. [Mirage describe](https://mirage.mx/productos/todo/aire-acondicionado/minisplit/inverter/x5/) límites de potencia del 75% para Eco I y del 50% para Eco II; su efecto no se ha medido aquí.

Referencias: [conexión del LED y corriente en IRremote](https://github.com/Arduino-IRremote/Arduino-IRremote#increase-strength-of-sent-output-signal), [corriente recomendada del Uno](https://docs.arduino.cc/retired/boards/arduino-uno-rev3-with-long-pins/).

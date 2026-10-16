# Captura IR del Mirage X5 con Arduino Uno

Este programa solo recibe señales por D11 y las imprime por USB a 115200 baudios. No transmite órdenes al minisplit. Usa IRremote 4.7.1, no IRremoteESP8266.

## Conexión del RQ-S003

Con el Arduino desconectado del USB, conecta según las marcas de los pines de tu módulo:

| RQ-S003 | Arduino Uno |
| --- | --- |
| S | D11 |
| − | GND |
| + | 5V |

## Cargar el programa

1. En Arduino IDE, instala **IRremote de Armin Joachimsmeyer**, versión **4.7.1**, desde el gestor de bibliotecas. También puedes agregar el ZIP descargado en `.dart_tool/ir_capture_check/IRremote-4.7.1.zip` desde **Programa → Incluir biblioteca → Añadir biblioteca .ZIP**.
2. Abre `ir_capture_uno.ino` y conecta el Uno por USB.
3. Selecciona **Arduino Uno** y el puerto USB correspondiente. Subir este programa reemplaza el programa que tenga cargado el Uno; conserva su código si lo necesitas.
4. Sube el programa y abre el monitor serie a **115200 baudios**. Debe aparecer `Mi X5: receptor D11 listo`.

## Capturar Eco

1. Usa el control original y deja Frío, 23 °C, ventilador medio y Eco apagado. Conserva los otros ajustes durante la prueba.
2. Apunta el control al receptor desde unos 20–50 cm. Pulsa Eco una vez, espera `LISTO` y anota qué muestra el control: Eco I, Eco II o apagado.
3. Completa el ciclo **Eco I → Eco II → apagado** dos veces. Deja al menos dos segundos entre pulsaciones.
4. Guarda el texto completo del monitor serie, incluyendo `CAPTURA`, protocolo, `RAW_US` y `LISTO`, y el estado Eco correspondiente a cada pulsación.

`UNKNOWN` no invalida los tiempos capturados. `CAPTURA INCOMPLETA` sí invalida esa lectura: el buffer de 750 intervalos se llenó. El programa conserva intervalos de 16 bits y espera una pausa de 50 ms antes de cerrar la captura, para reunir paquetes consecutivos. Si el control usa pausas mayores, habrá que ajustar ese límite a partir de las lecturas reales.

Capturar no habilita un nuevo comando Tuya. Para reproducir las señales con el LED IR recuperado, usa la [prueba de emisión](../ir_replay_uno/README.md). Las capturas de 24 °C muestran datos que dependen de la temperatura; falta identificar el resto de los ajustes incluidos y probar el efecto de Eco.

## Dos ciclos capturados: 12 de octubre de 2026

Los seis registros de `captures/eco_*_2026-10-12*.txt` contienen 244 intervalos contando la pausa inicial: cabecera, 120 bits y pulso final. Las cantidades y duraciones coinciden con lo impreso por el Uno. Los archivos con sufijo `_repeat1` corresponden al segundo ciclo. Los 15 bytes de cada estado coinciden exactamente entre ambos ciclos. Los JSON guardan los tiempos de la señal sin la pausa inicial y los bytes decodificados en orden LSB primero.

Solo cambian el byte 11 y el byte 15 entre estos tres registros; la numeración comienza en 1.

| Estado indicado por el usuario | Byte 11 | Byte 15 |
| --- | --- | --- |
| Eco apagado | `00` | `1A` |
| Eco I | `20` | `1C` |
| Eco II | `40` | `1E` |

Mensajes completos:

```text
Apagado: 56 73 00 00 23 00 00 00 00 00 00 00 00 00 1A
Eco I:   56 73 00 00 23 00 00 00 00 00 20 00 00 00 1C
Eco II:  56 73 00 00 23 00 00 00 00 00 40 00 00 00 1E
```

El byte 15 coincide en las seis capturas con la suma de los nibbles de los bytes 1–14, módulo 256. El campo Eco y esta hipótesis de checksum se repiten en ambos ciclos con los mismos ajustes de prueba. El usuario confirmó una respuesta por pitido al reproducir las tres señales en el minisplit. Falta comprobar otros ajustes y medir el efecto de Eco. No se ha medido la frecuencia portadora ni se ha confirmado un comando Tuya para estos estados.

## Comparación a 24 °C

Los registros `captures/temp24_eco_off_2026-10-12.*` y `captures/temp24_eco_i_2026-10-12.*` también contienen 120 bits. Sus 243 intervalos de señal suman exactamente 156000 y 157050 µs, respectivamente. Se omitieron únicamente las barras invertidas al final de las líneas pegadas en el chat.

| Temperatura y estado indicados por el usuario | Byte 2 | Byte 11 | Byte 15 |
| --- | --- | --- | --- |
| 23 °C, Eco apagado | `73` | `00` | `1A` |
| 23 °C, Eco I | `73` | `20` | `1C` |
| 24 °C, Eco apagado | `74` | `00` | `1B` |
| 24 °C, Eco I | `74` | `20` | `1D` |

Mensajes completos a 24 °C:

```text
Apagado: 56 74 00 00 23 00 00 00 00 00 00 00 00 00 1B
Eco I:   56 74 00 00 23 00 00 00 00 00 20 00 00 00 1D
```

Al pasar de 23 a 24 °C solo cambian los bytes 2 y 15, tanto con Eco apagado como con Eco I. El byte 5 sigue siendo `23`: no es el campo que cambió con la temperatura. La hipótesis de checksum sigue coincidiendo con las ocho capturas Eco. El byte 11 conserva el mismo cambio de `00` a `20` al activar Eco I.

Estas lecturas muestran que la orden Eco incluye datos que dependen de la temperatura; reproducir un paquete de 23 °C podría cambiar también la consigna. Dos temperaturas no bastan para deducir la codificación de todo el rango ni sus posibles bits de modo o ventilador. Aún no se ha capturado Eco II a 24 °C ni medido la portadora. La reproducción de las tres señales de 23 °C provocó una respuesta por pitido reportada por el usuario.

## Comparación con una implementación pública

La [estructura Mirage de IRremoteESP8266](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/src/ir_Mirage.h) define mensajes de 120 bits con cabecera `56` y temperatura en el byte 2 como grados Celsius más `0x5C`. Su [implementación del checksum](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/src/ir_Mirage.cpp) usa la suma de nibbles. Las ocho capturas Eco coinciden con esos campos y la fórmula de temperatura para los 23 y 24 °C registrados. Es una coincidencia con esa familia de protocolo; el CVF121Q no está identificado explícitamente entre los modelos de la fuente.

No se han aplicado sus mapas de ventilador, oscilación u otros campos al X5. La fuente contiene variantes con cuatro valores de velocidad; [Mirage anuncia seis velocidades para el X5](https://mirage.mx/productos/todo/aire-acondicionado/minisplit/inverter/x5/), de modo que hace falta calibrar esos campos con el control real antes de generar órdenes que los cambien. La prueba de reproducción exacta de las tres señales Eco, con respuesta por pitido reportada por el usuario, está registrada en el [programa emisor](../ir_replay_uno/README.md).

Referencias: [IRremote](https://github.com/Arduino-IRremote/Arduino-IRremote), [tutorial del receptor RexQualis](https://www.scribd.com/document/819399520/Lesson-15-IR-Receiver-Module).

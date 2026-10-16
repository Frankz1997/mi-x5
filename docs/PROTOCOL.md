# Perfil Tuya y evidencia

[Volver al README](../README.md)

Un **DP** (Data Point) es un parámetro Tuya para reportar estado o recibir comandos. Un esquema genérico puede describir opciones no implementadas por el hardware concreto. Este perfil se basa en un **CVF121Q solo frío**.

## Controles implementados

| DP | Código Tuya | Valores usados | Evidencia / límite |
| --- | --- | --- | --- |
| 1 | `switch` | Booleano | Encendido/apagado |
| 2 | `temp_set` | 16–30 | Escritura y lectura posterior; rango completo pendiente de calibración |
| 3 | `temp_current` | Temperatura ambiente | Solo lectura |
| 4 | `mode` | `cold`, `auto`, `wet`, `wind` | Escrituras aceptadas y reportadas; `hot` excluido |
| 5 | `fan_speed_enum` | `auto`, `mute`, `low`, `middle`, `high`, `strong` | Lectura posterior; equivalencia exacta con etiquetas del control pendiente |
| 25 | `sleep` | Booleano | Escritura y restauración comprobadas |
| 31 | `gear_vertical` | `off`, `same` | Movimiento y detención físicos confirmados después de órdenes Wi-Fi |
| 36 | `display` | Booleano | Escritura y restauración de la luz |

La ronda anterior verificó once escrituras con restauración de temperatura, modos, ventilador, Sueño y display. El aire estaba apagado: acredita aceptación/reporte, no el efecto físico de todos los modos. La oscilación se verificó después con el equipo encendido y observación asistida.

## Parámetros del esquema sin controles en la app

| DP | Código | Estado |
| --- | --- | --- |
| 11 | `anion` | Purificación; no confirmado y no representa Eco |
| 12 | `heat` | Calefacción auxiliar, fuera del perfil solo frío |
| 22 | `fault` | Fallas, solo lectura |
| 31 | `vane_1`–`vane_5` | Posiciones individuales no verificadas |
| 33 | `switch_horizontal` | Excluido; no cambió durante la prueba vertical |
| 101 / 102 | `timer_switch_on_en` / `timer_switch_off_en` | Temporizadores del esquema, sin prueba de escritura |
| 103 / 104 | `timer_switch_on` / `timer_switch_off` | Horas descritas como HHmm, sin prueba de escritura |
| 105 | `model_sign_1` | Solo frío/frío-calor, lectura |
| 106 | `model_sign_2` | Inverter/frecuencia fija, lectura |
| 107 | `model_sign_3` | Soporte de posiciones verticales, lectura |
| 108 | `fault_code_bp` | Código de falla, lectura |

El esquema también enumera `hot`, `MediumLow` y `MediumHigh`, no habilitados. Estos códigos no son credenciales de un equipo.

## Eco I / II e infrarrojos

Las lecturas antes y después de Eco apagado → I → II → apagado devolvieron el mismo mapa. El modelo consultado tampoco expuso un control Eco. **No se ha identificado un comando nativo Wi-Fi para esos niveles.** Otra revisión de hardware/firmware podría comportarse distinto.

Se capturaron tramas IR de 120 bits mediante Arduino Uno. Reproducirlas provocó pitidos, pero no se midió el límite de potencia. Son tramas completas con temperatura y posiblemente otros ajustes, no órdenes Eco aisladas.

- [Receptor y capturas IR](../tool/ir_capture_uno/README.md)
- [Reproducción experimental](../tool/ir_replay_uno/README.md)

La app funcional no utiliza Arduino/IR ni muestra Eco como disponible.

## Transporte y herramientas

`X5Client` usa TinyTuya Dart para Tuya 3.5. Cada operación cierra la conexión. Una escritura comprueba el valor reportado, con una segunda lectura si hace falta. La app consulta cada 15 segundos mientras está activa y omite consultas en segundo plano.

`tool/hardware_check.dart` recibe JSON por entrada estándar. `--watch` es lectura; `--write`, `--controls` y `--vertical` envían órdenes y pueden cambiar físicamente el equipo. No los ejecutes en CI ni con un equipo ajeno. Usa clientes falsos o el simulador para desarrollar sin hardware.

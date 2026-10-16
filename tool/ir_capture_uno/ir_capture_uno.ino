// IRremote 4.7.1. RQ-S003: S -> D11, - -> GND, + -> 5V.
#define RAW_BUFFER_LENGTH 750
// shortcut: agrupa pausas de hasta 50 ms; recalibrar si las capturas reales salen partidas.
#define RECORD_GAP_MICROS 50000
#define USE_16_BIT_TIMING_BUFFER
#define DECODE_DISTANCE_WIDTH
#include <IRremote.hpp>

static_assert(sizeof(IRRawbufType) == 2, "Se requieren tiempos de 16 bits para conservar las pausas largas.");

void setup() {
  Serial.begin(115200);
  IrReceiver.begin(11, DISABLE_LED_FEEDBACK);
  Serial.println(F("Mi X5: receptor D11 listo. Pulsa una vez y espera LISTO."));
}

void loop() {
  if (!IrReceiver.decode()) return;

  Serial.print(F("CAPTURA ms="));
  Serial.println(millis());
  if (IrReceiver.decodedIRData.flags & IRDATA_FLAGS_WAS_OVERFLOW) {
    Serial.println(F("CAPTURA INCOMPLETA: buffer lleno; no usar esta lectura."));
  } else {
    IrReceiver.printIRResultShort(&Serial);
    Serial.println(F("RAW_US (incluye pausa inicial):"));
    IrReceiver.printIRResultRawFormatted(&Serial, true);
  }
  IrReceiver.resume();
  Serial.println(F("LISTO"));
}

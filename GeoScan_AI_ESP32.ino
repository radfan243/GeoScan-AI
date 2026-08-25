#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <math.h>

// ============================================================
// GeoScan AI - ESP32 V1
// REAL BLE + REAL ADC
//
// ESP32  <----BLE---->  Flutter App
//
// ESP32 -> الهاتف:
//   signal
//   stability
//   depth = null
//   battery = "--"
//   status
//
// الهاتف -> ESP32:
//   START
//   STOP
//   GET_STATUS
//   CALIBRATE
//   SENSITIVITY:0-100
//   FILTER:منخفضة / متوسطة / عالية
//   AUDIO:ON/OFF
//   VIBRATION:ON/OFF
//
// مهم:
// هذه النسخة لا تدعي اكتشاف معدن أو عمق حقيقي
// قبل بناء دائرة الملف والاستقبال.
// ============================================================


// ============================================================
// BLE UUID
// يجب أن تطابق ScanScreen.dart
// ============================================================

#define SERVICE_UUID \
  "12345678-1234-1234-1234-1234567890ab"

#define NOTIFY_CHARACTERISTIC_UUID \
  "12345678-1234-1234-1234-1234567890ac"

#define WRITE_CHARACTERISTIC_UUID \
  "12345678-1234-1234-1234-1234567890ad"


// ============================================================
// Hardware Pins
// ============================================================

// ADC input
// سيستقبل لاحقًا إشارة مرحلة الاستقبال.
// GPIO34 هو Input Only ومناسب للـADC.
#define SIGNAL_ADC_PIN 34

// Driver output
// حاليًا غير مستخدم في قيادة الملف.
// سنحدد استخدامه النهائي بعد تصميم دائرة الـCoil.
#define DRIVER_PIN 25

// LED المدمج في أغلب لوحات ESP32 DevKit
#define STATUS_LED_PIN 2


// ============================================================
// ADC
// ============================================================

#define ADC_MAX_VALUE 4095.0f


// ============================================================
// BLE objects
// ============================================================

BLEServer* bleServer = nullptr;

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

bool deviceConnected = false;


// ============================================================
// Detector state
// ============================================================

bool scanning = false;

float sensitivity = 75.0f;

String filterMode = "متوسطة";

bool audioEnabled = true;
bool vibrationEnabled = true;

String deviceStatus = "جاهز";


// ============================================================
// Signal processing
// ============================================================

float filteredSignal = 0.0f;

float previousSignal = 0.0f;

float stability = 100.0f;


// ============================================================
// Calibration
// ============================================================

// متوسط ADC في حالة عدم وجود هدف.
// لن نخترع قراءة؛ نستخدم هذه القيمة فقط لإزالة
// الانحراف الأساسي من الإشارة.
float calibrationBaseline = 0.0f;

bool calibrated = false;


// ============================================================
// Timing
// ============================================================

unsigned long lastReadingTime = 0;

const unsigned long READING_INTERVAL = 100;


// ============================================================
// Utility
// ============================================================

float clampFloat(
  float value,
  float minimum,
  float maximum
) {
  if (value < minimum) {
    return minimum;
  }

  if (value > maximum) {
    return maximum;
  }

  return value;
}


// ============================================================
// Read ADC
// ============================================================

int readADC() {

  const int samples = 16;

  long total = 0;

  for (int i = 0; i < samples; i++) {

    total += analogRead(
      SIGNAL_ADC_PIN
    );

    delayMicroseconds(300);
  }

  return (int)(
    total / samples
  );
}


// ============================================================
// Calibration
// ============================================================

void calibrateSensor() {

  Serial.println();
  Serial.println(
    "Starting calibration..."
  );

  const int samples = 100;

  long total = 0;

  for (int i = 0; i < samples; i++) {

    total += analogRead(
      SIGNAL_ADC_PIN
    );

    delay(5);
  }

  calibrationBaseline =
      (float)total / (float)samples;

  calibrated = true;

  filteredSignal = 0.0f;
  previousSignal = 0.0f;
  stability = 100.0f;

  Serial.print(
    "Calibration baseline = "
  );

  Serial.println(
    calibrationBaseline,
    2
  );
}


// ============================================================
// Convert ADC to real signal
// ============================================================
//
// بدون معايرة:
//   نقرأ مستوى ADC مباشرة.
//
// بعد المعايرة:
//   نستخدم الفرق عن خط الأساس.
//
// النتيجة 0..100.
//
// هذه "شدة إشارة كهربائية"، وليست نسبة ذهب
// وليست عمقًا حتى نبني دائرة الحساس ونعايرها.
// ============================================================

float calculateRawSignal(
  int adcValue
) {

  float signalValue;

  if (calibrated) {

    float difference =
        fabs(
          (float)adcValue -
          calibrationBaseline
        );

    signalValue =
        (difference /
         ADC_MAX_VALUE) *
        100.0f;

  } else {

    signalValue =
        ((float)adcValue /
         ADC_MAX_VALUE) *
        100.0f;
  }

  // تطبيق الحساسية
  signalValue *=
      sensitivity / 100.0f;

  return clampFloat(
    signalValue,
    0.0f,
    100.0f
  );
}


// ============================================================
// Signal filter
// ============================================================

float applyFilter(
  float newSignal
) {

  float alpha;

  if (filterMode == "منخفضة") {

    // استجابة أسرع
    alpha = 0.35f;

  } else if (filterMode == "عالية") {

    // أكثر ثباتًا
    alpha = 0.08f;

  } else {

    // متوسطة
    alpha = 0.18f;
  }

  filteredSignal =
      (alpha * newSignal) +
      ((1.0f - alpha) *
       filteredSignal);

  return clampFloat(
    filteredSignal,
    0.0f,
    100.0f
  );
}


// ============================================================
// Stability
// ============================================================

float calculateStability(
  float currentSignal
) {

  float difference =
      fabs(
        currentSignal -
        previousSignal
      );

  previousSignal =
      currentSignal;

  float result =
      100.0f -
      (difference * 8.0f);

  return clampFloat(
    result,
    0.0f,
    100.0f
  );
}


// ============================================================
// Send JSON
// ============================================================

void sendSensorData() {

  if (!deviceConnected) {
    return;
  }

  int adcValue =
      readADC();

  float rawSignal =
      calculateRawSignal(
        adcValue
      );

  float signalValue =
      applyFilter(
        rawSignal
      );

  stability =
      calculateStability(
        signalValue
      );


  // ----------------------------------------------------------
  // لا يوجد عمق حقيقي حتى الآن.
  // لذلك نرسل null.
  // ----------------------------------------------------------

  String json = "{";

  json += "\"signal\":";
  json += String(
    signalValue,
    2
  );

  json += ",\"stability\":";
  json += String(
    stability,
    2
  );

  json += ",\"depth\":null";

  json += ",\"battery\":\"--\"";

  json += ",\"status\":\"";
  json += deviceStatus;
  json += "\"";

  json += "}";


  notifyCharacteristic->setValue(
    json.c_str()
  );

  notifyCharacteristic->notify();


  // Serial Monitor
  Serial.print(
    "ADC="
  );

  Serial.print(
    adcValue
  );

  Serial.print(
    " | "
  );

  Serial.println(
    json
  );
}


// ============================================================
// Send current status
// ============================================================

void sendStatus() {

  if (!deviceConnected) {
    return;
  }

  String json = "{";

  json += "\"signal\":";
  json += String(
    filteredSignal,
    2
  );

  json += ",\"stability\":";
  json += String(
    stability,
    2
  );

  json += ",\"depth\":null";

  json += ",\"battery\":\"--\"";

  json += ",\"status\":\"";
  json += deviceStatus;
  json += "\"";

  json += "}";


  notifyCharacteristic->setValue(
    json.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print(
    "STATUS: "
  );

  Serial.println(
    json
  );
}


// ============================================================
// Process commands from phone
// ============================================================

void processCommand(
  String command
) {

  command.trim();

  if (command.length() == 0) {
    return;
  }

  Serial.print(
    "Command from phone: "
  );

  Serial.println(
    command
  );


  // ==========================================================
  // START
  // ==========================================================

  if (command == "START") {

    scanning = true;

    deviceStatus =
        "يمسح";

    digitalWrite(
      STATUS_LED_PIN,
      HIGH
    );

    Serial.println(
      "Scanning STARTED"
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // STOP
  // ==========================================================

  if (command == "STOP") {

    scanning = false;

    deviceStatus =
        "متوقف";

    digitalWrite(
      STATUS_LED_PIN,
      LOW
    );

    Serial.println(
      "Scanning STOPPED"
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // GET STATUS
  // ==========================================================

  if (command == "GET_STATUS") {

    sendStatus();

    return;
  }


  // ==========================================================
  // CALIBRATE
  // ==========================================================

  if (command == "CALIBRATE") {

    bool wasScanning =
        scanning;

    scanning = false;

    deviceStatus =
        "معايرة";

    digitalWrite(
      STATUS_LED_PIN,
      LOW
    );

    calibrateSensor();

    deviceStatus =
        wasScanning
        ? "يمسح"
        : "جاهز";

    scanning =
        wasScanning;

    if (scanning) {

      digitalWrite(
        STATUS_LED_PIN,
        HIGH
      );
    }

    sendStatus();

    Serial.println(
      "Calibration completed"
    );

    return;
  }


  // ==========================================================
  // SENSITIVITY
  // ==========================================================

  if (
    command.startsWith(
      "SENSITIVITY:"
    )
  ) {

    String value =
        command.substring(
          12
        );

    float newSensitivity =
        value.toFloat();

    sensitivity =
        clampFloat(
          newSensitivity,
          0.0f,
          100.0f
        );

    Serial.print(
      "Sensitivity = "
    );

    Serial.println(
      sensitivity
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // FILTER
  // ==========================================================

  if (
    command.startsWith(
      "FILTER:"
    )
  ) {

    String value =
        command.substring(
          7
        );

    if (
      value == "منخفضة" ||
      value == "متوسطة" ||
      value == "عالية"
    ) {

      filterMode =
          value;
    }

    Serial.print(
      "Filter = "
    );

    Serial.println(
      filterMode
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // AUDIO
  // ==========================================================

  if (command == "AUDIO:ON") {

    audioEnabled = true;

    Serial.println(
      "Audio ON"
    );

    sendStatus();

    return;
  }


  if (command == "AUDIO:OFF") {

    audioEnabled = false;

    Serial.println(
      "Audio OFF"
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // VIBRATION
  // ==========================================================

  if (
    command == "VIBRATION:ON"
  ) {

    vibrationEnabled = true;

    Serial.println(
      "Vibration ON"
    );

    sendStatus();

    return;
  }


  if (
    command == "VIBRATION:OFF"
  ) {

    vibrationEnabled = false;

    Serial.println(
      "Vibration OFF"
    );

    sendStatus();

    return;
  }


  // ==========================================================
  // Unknown command
  // ==========================================================

  Serial.print(
    "Unknown command: "
  );

  Serial.println(
    command
  );
}


// ============================================================
// BLE Server callbacks
// ============================================================

class GeoScanServerCallbacks
    : public BLEServerCallbacks {

  void onConnect(
    BLEServer* server
  ) override {

    deviceConnected =
        true;

    deviceStatus =
        "متصل";

    Serial.println();
    Serial.println(
      "================================"
    );
    Serial.println(
      "GeoScan AI: PHONE CONNECTED"
    );
    Serial.println(
      "================================"
    );

    digitalWrite(
      STATUS_LED_PIN,
      HIGH
    );
  }


  void onDisconnect(
    BLEServer* server
  ) override {

    deviceConnected =
        false;

    scanning =
        false;

    deviceStatus =
        "غير متصل";

    digitalWrite(
      STATUS_LED_PIN,
      LOW
    );

    Serial.println();
    Serial.println(
      "================================"
    );
    Serial.println(
      "GeoScan AI: PHONE DISCONNECTED"
    );
    Serial.println(
      "================================"
    );

    delay(100);

    BLEDevice::startAdvertising();
  }
};


// ============================================================
// BLE Write callback
// ============================================================

class GeoScanWriteCallbacks
    : public BLECharacteristicCallbacks {

  void onWrite(
    BLECharacteristic* characteristic
  ) override {

    std::string value =
        characteristic->getValue();

    if (value.length() == 0) {
      return;
    }

    String command = "";

    for (
      size_t i = 0;
      i < value.length();
      i++
    ) {

      command +=
          (char)value[i];
    }

    command.trim();

    processCommand(
      command
    );
  }
};


// ============================================================
// Setup BLE
// ============================================================

void setupBLE() {

  BLEDevice::init(
    "GeoScan AI"
  );


  // ----------------------------------------------------------
  // Server
  // ----------------------------------------------------------

  bleServer =
      BLEDevice::createServer();

  bleServer->setCallbacks(
    new GeoScanServerCallbacks()
  );


  // ----------------------------------------------------------
  // Service
  // ----------------------------------------------------------

  BLEService* service =
      bleServer->createService(
        SERVICE_UUID
      );


  // ----------------------------------------------------------
  // ESP32 -> Phone
  // ----------------------------------------------------------

  notifyCharacteristic =
      service->createCharacteristic(
        NOTIFY_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_NOTIFY |
        BLECharacteristic::PROPERTY_READ
      );

  notifyCharacteristic->addDescriptor(
    new BLE2902()
  );


  // ----------------------------------------------------------
  // Phone -> ESP32
  // ----------------------------------------------------------

  writeCharacteristic =
      service->createCharacteristic(
        WRITE_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_WRITE_NR
      );

  writeCharacteristic->setCallbacks(
    new GeoScanWriteCallbacks()
  );


  // ----------------------------------------------------------
  // Start service
  // ----------------------------------------------------------

  service->start();


  // ----------------------------------------------------------
  // Advertising
  // ----------------------------------------------------------

  BLEAdvertising* advertising =
      BLEDevice::getAdvertising();

  advertising->addServiceUUID(
    SERVICE_UUID
  );

  advertising->setScanResponse(
    true
  );

  advertising->setMinPreferred(
    0x06
  );

  advertising->setMinPreferred(
    0x12
  );

  BLEDevice::startAdvertising();


  Serial.println();
  Serial.println(
    "================================"
  );
  Serial.println(
    "GeoScan AI BLE READY"
  );
  Serial.println(
    "Name: GeoScan AI"
  );
  Serial.println(
    "Waiting for phone..."
  );
  Serial.println(
    "================================"
  );
}


// ============================================================
// SETUP
// ============================================================

void setup() {

  Serial.begin(
    115200
  );

  delay(1000);


  Serial.println();
  Serial.println(
    "================================"
  );
  Serial.println(
    "GeoScan AI V1"
  );
  Serial.println(
    "REAL BLE + REAL ADC"
  );
  Serial.println(
    "================================"
  );


  // ----------------------------------------------------------
  // LED
  // ----------------------------------------------------------

  pinMode(
    STATUS_LED_PIN,
    OUTPUT
  );

  digitalWrite(
    STATUS_LED_PIN,
    LOW
  );


  // ----------------------------------------------------------
  // Driver
  // ----------------------------------------------------------

  pinMode(
    DRIVER_PIN,
    OUTPUT
  );

  digitalWrite(
    DRIVER_PIN,
    LOW
  );


  // ----------------------------------------------------------
  // ADC
  // ----------------------------------------------------------

  pinMode(
    SIGNAL_ADC_PIN,
    INPUT
  );

  analogReadResolution(
    12
  );


  // ----------------------------------------------------------
  // BLE
  // ----------------------------------------------------------

  setupBLE();


  deviceStatus =
      "جاهز";

  Serial.println(
    "GeoScan AI is ready."
  );
}


// ============================================================
// LOOP
// ============================================================

void loop() {

  // ----------------------------------------------------------
  // إرسال القراءة الحقيقية أثناء المسح
  // ----------------------------------------------------------

  if (
    deviceConnected &&
    scanning
  ) {

    unsigned long now =
        millis();

    if (
      now - lastReadingTime >=
      READING_INTERVAL
    ) {

      lastReadingTime =
          now;

      sendSensorData();
    }
  }


  // ----------------------------------------------------------
  // إبقاء BLE سريعًا
  // ----------------------------------------------------------

  delay(5);
}

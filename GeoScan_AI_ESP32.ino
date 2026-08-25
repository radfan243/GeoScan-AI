#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// GeoScan AI - ESP32 BLE Controller
// ============================================================

// -------------------------
// BLE UUIDs
// يجب أن تطابق ScanScreen.dart
// -------------------------

#define SERVICE_UUID \
"12345678-1234-1234-1234-1234567890ab"

#define NOTIFY_CHARACTERISTIC_UUID \
"12345678-1234-1234-1234-1234567890ac"

#define WRITE_CHARACTERISTIC_UUID \
"12345678-1234-1234-1234-1234567890ad"

// ============================================================
// Pins
// ============================================================

// مدخل ADC للإشارة القادمة من دائرة الاستقبال.
// مهم: لا توصل أي جهد أعلى من الحد المسموح لـ ADC مباشرة.
#define SIGNAL_ADC_PIN 34

// لاحقًا يمكن توصيل قياس البطارية هنا.
// حاليًا -1 يعني لا يوجد قياس بطارية فعلي.
#define BATTERY_ADC_PIN -1

// ============================================================
// BLE objects
// ============================================================

BLEServer* bleServer = nullptr;

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

bool deviceConnected = false;
bool oldDeviceConnected = false;

// ============================================================
// Detector state
// ============================================================

bool scanning = false;

float sensitivity = 75.0f;

String filterMode = "متوسطة";

bool audioEnabled = true;
bool vibrationEnabled = true;

float lastSignal = 0.0f;

unsigned long lastSendTime = 0;

// إرسال البيانات كل 200ms تقريبًا
const unsigned long SEND_INTERVAL = 200;

// ============================================================
// Calibration
// ============================================================

float calibrationBaseline = 0.0f;
bool calibrated = false;

// ============================================================
// BLE Server callbacks
// ============================================================

class GeoScanServerCallbacks : public BLEServerCallbacks {

  void onConnect(BLEServer* server) override {

    deviceConnected = true;

    Serial.println();
    Serial.println("================================");
    Serial.println("GeoScan AI: PHONE CONNECTED");
    Serial.println("================================");
  }

  void onDisconnect(BLEServer* server) override {

    deviceConnected = false;

    scanning = false;

    Serial.println();
    Serial.println("================================");
    Serial.println("GeoScan AI: PHONE DISCONNECTED");
    Serial.println("================================");

    delay(100);

    BLEDevice::startAdvertising();
  }
};

// ============================================================
// Helpers
// ============================================================

float clampFloat(
  float value,
  float minimum,
  float maximum
) {

  if (value < minimum) return minimum;

  if (value > maximum) return maximum;

  return value;
}

// ============================================================
// ADC reading
// ============================================================

float readRawSignal() {

  // قراءة ADC فعلية من ESP32
  int raw = analogRead(SIGNAL_ADC_PIN);

  // تحويل 0..4095 إلى 0..100
  float value =
      ((float)raw / 4095.0f) * 100.0f;

  return clampFloat(
    value,
    0.0f,
    100.0f
  );
}

// ============================================================
// Baseline calibration
// ============================================================

void calibrateSensor() {

  Serial.println();
  Serial.println("Starting calibration...");

  const int samples = 100;

  unsigned long total = 0;

  for (int i = 0; i < samples; i++) {

    total += analogRead(
      SIGNAL_ADC_PIN
    );

    delay(5);
  }

  calibrationBaseline =
      (float)total / samples;

  calibrated = true;

  Serial.print(
    "Calibration baseline: "
  );

  Serial.println(
    calibrationBaseline
  );
}

// ============================================================
// Calculate signal
// ============================================================

float calculateSignal() {

  int raw =
      analogRead(
        SIGNAL_ADC_PIN
      );

  float value =
      ((float)raw / 4095.0f) * 100.0f;

  // إزالة خط الأساس بعد المعايرة
  if (calibrated) {

    float difference =
        ((float)raw -
         calibrationBaseline);

    // نحول مقدار التغير إلى إشارة
    value =
        fabs(difference) /
        4095.0f *
        100.0f;
  }

  // تطبيق الحساسية
  value =
      value *
      (sensitivity / 100.0f);

  return clampFloat(
    value,
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
        lastSignal
      );

  float stability =
      100.0f -
      (difference * 5.0f);

  return clampFloat(
    stability,
    0.0f,
    100.0f
  );
}

// ============================================================
// Battery
// ============================================================

String readBattery() {

  // لا نريد اختلاق نسبة بطارية.
  // لذلك إذا لم يتم تركيب دائرة قياس البطارية
  // نرسل "--".

#if BATTERY_ADC_PIN >= 0

  int raw =
      analogRead(
        BATTERY_ADC_PIN
      );

  // هذه المعادلة مؤقتة حتى نحدد
  // مقسم الجهد الفعلي للبطارية.
  //
  // لا تستخدمها قبل تصميم مقسم الجهد.

  float voltage =
      ((float)raw / 4095.0f) * 3.3f;

  float percentage =
      (voltage - 3.0f) /
      (4.2f - 3.0f) *
      100.0f;

  percentage =
      clampFloat(
        percentage,
        0.0f,
        100.0f
      );

  return String(
    (int)percentage
  );

#else

  return "--";

#endif
}

// ============================================================
// Send JSON data to phone
// ============================================================

void sendSensorData() {

  if (!deviceConnected) {
    return;
  }

  float signalValue =
      calculateSignal();

  float stabilityValue =
      calculateStability(
        signalValue
      );

  String battery =
      readBattery();

  // العمق لا نختلقه.
  // إلى أن نبني خوارزمية حقيقية تعتمد
  // على دائرة القياس، نرسل null.

  String json = "{";

  json += "\"signal\":";
  json += String(
    signalValue,
    2
  );

  json += ",\"stability\":";
  json += String(
    stabilityValue,
    2
  );

  json += ",\"depth\":null";

  json += ",\"battery\":\"";
  json += battery;
  json += "\"";

  json += ",\"status\":\"";

  if (scanning) {
    json += "SCANNING";
  } else {
    json += "READY";
  }

  json += "\"";

  json += "}";

  notifyCharacteristic->setValue(
    json.c_str()
  );

  notifyCharacteristic->notify();

  lastSignal =
      signalValue;

  Serial.println(json);
}

// ============================================================
// Command processing
// ============================================================

void processCommand(
  String command
) {

  command.trim();

  if (command.length() == 0) {
    return;
  }

  Serial.print(
    "Command received: "
  );

  Serial.println(command);

  String upper =
      command;

  upper.toUpperCase();

  // ----------------------------------------------------------
  // START
  // ----------------------------------------------------------

  if (upper == "START") {

    scanning = true;

    Serial.println(
      "Scanning STARTED"
    );

    return;
  }

  // ----------------------------------------------------------
  // STOP
  // ----------------------------------------------------------

  if (upper == "STOP") {

    scanning = false;

    Serial.println(
      "Scanning STOPPED"
    );

    return;
  }

  // ----------------------------------------------------------
  // CALIBRATE
  // ----------------------------------------------------------

  if (upper == "CALIBRATE") {

    scanning = false;

    calibrateSensor();

    return;
  }

  // ----------------------------------------------------------
  // AUDIO
  // ----------------------------------------------------------

  if (upper == "AUDIO:ON") {

    audioEnabled = true;

    Serial.println(
      "Audio ON"
    );

    return;
  }

  if (upper == "AUDIO:OFF") {

    audioEnabled = false;

    Serial.println(
      "Audio OFF"
    );

    return;
  }

  // ----------------------------------------------------------
  // VIBRATION
  // ----------------------------------------------------------

  if (upper == "VIBRATION:ON") {

    vibrationEnabled = true;

    Serial.println(
      "Vibration ON"
    );

    return;
  }

  if (upper == "VIBRATION:OFF") {

    vibrationEnabled = false;

    Serial.println(
      "Vibration OFF"
    );

    return;
  }

  // ----------------------------------------------------------
  // GET STATUS
  // ----------------------------------------------------------

  if (upper == "GET_STATUS") {

    sendSensorData();

    return;
  }

  // ----------------------------------------------------------
  // SENSITIVITY
  // ----------------------------------------------------------

  if (
    upper.startsWith(
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
      "Sensitivity: "
    );

    Serial.println(
      sensitivity
    );

    return;
  }

  // ----------------------------------------------------------
  // FILTER
  // ----------------------------------------------------------

  if (
    upper.startsWith(
      "FILTER:"
    )
  ) {

    filterMode =
        command.substring(
          7
        );

    Serial.print(
      "Filter: "
    );

    Serial.println(
      filterMode
    );

    return;
  }

  // ----------------------------------------------------------
  // Unknown command
  // ----------------------------------------------------------

  Serial.print(
    "Unknown command: "
  );

  Serial.println(
    command
  );
}

// ============================================================
// BLE write callback
// ============================================================

class GeoScanCommandCallbacks
  : public BLECharacteristicCallbacks {

  void onWrite(
    BLECharacteristic* characteristic
  ) override {

    String value =
        characteristic->getValue();

    if (value.length() == 0) {
      return;
    }

    processCommand(
      value
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

  bleServer =
      BLEDevice::createServer();

  bleServer->setCallbacks(
    new GeoScanServerCallbacks()
  );

  BLEService* service =
      bleServer->createService(
        SERVICE_UUID
      );

  // ----------------------------------------------------------
  // ESP32 -> PHONE
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
  // PHONE -> ESP32
  // ----------------------------------------------------------

  writeCharacteristic =
      service->createCharacteristic(

        WRITE_CHARACTERISTIC_UUID,

        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_WRITE_NR
      );

  writeCharacteristic->setCallbacks(
    new GeoScanCommandCallbacks()
  );

  // ----------------------------------------------------------

  service->start();

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
// Setup
// ============================================================

void setup() {

  Serial.begin(
    115200
  );

  delay(1000);

  // ADC configuration
  analogReadResolution(
    12
  );

  // GPIO34 input only
  pinMode(
    SIGNAL_ADC_PIN,
    INPUT
  );

  Serial.println();
  Serial.println(
    "GeoScan AI V1"
  );

  Serial.println(
    "Real ADC + BLE communication"
  );

  setupBLE();
}

// ============================================================
// Main loop
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
      now - lastSendTime >=
      SEND_INTERVAL
    ) {

      lastSendTime =
          now;

      sendSensorData();
    }
  }

  // ----------------------------------------------------------
  // إعادة الإعلان بعد فصل الهاتف
  // ----------------------------------------------------------

  if (
    !deviceConnected &&
    oldDeviceConnected
  ) {

    delay(500);

    BLEDevice::startAdvertising();

    oldDeviceConnected =
        deviceConnected;
  }

  if (
    deviceConnected &&
    !oldDeviceConnected
  ) {

    oldDeviceConnected =
        deviceConnected;
  }

  delay(5);
}

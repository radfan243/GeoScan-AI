#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ============================================================
// GeoScan AI - ESP32 BLE
// الهاتف <-> ESP32
// ============================================================

// -----------------------------
// اسم الجهاز
// -----------------------------
#define DEVICE_NAME "GeoScan-AI"

// -----------------------------
// UUIDs - يجب أن تطابق Flutter
// -----------------------------
#define SERVICE_UUID \
  "12345678-1234-1234-1234-1234567890ab"

#define NOTIFY_UUID \
  "12345678-1234-1234-1234-1234567890ac"

#define WRITE_UUID \
  "12345678-1234-1234-1234-1234567890ad"

// ============================================================
// إعدادات الهاردوير
// ============================================================

// مدخل قراءة الإشارة التناظرية
// GPIO34 مدخل ADC فقط في ESP32 التقليدي
#define SENSOR_PIN 34

// اختياري:
// خرج صوت
#define BUZZER_PIN 25

// اختياري:
// خرج اهتزاز
#define VIBRATION_PIN 26

// ============================================================
// إعدادات النظام
// ============================================================

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

bool deviceConnected = false;
bool scanning = false;

bool audioEnabled = true;
bool vibrationEnabled = false;

int sensitivity = 70;

String selectedFilter = "ALL";

// ============================================================
// ADC / Signal
// ============================================================

float baseline = 0.0;
float filteredSignal = 0.0;

int rawValue = 0;

unsigned long lastSendTime = 0;
unsigned long lastStatusTime = 0;

const unsigned long SEND_INTERVAL = 120;
const unsigned long STATUS_INTERVAL = 2000;

// ============================================================
// BLE Server Callbacks
// ============================================================

class GeoScanServerCallbacks : public BLEServerCallbacks {

  void onConnect(BLEServer* server) override {

    deviceConnected = true;

    Serial.println();
    Serial.println("================================");
    Serial.println("GeoScan AI: Phone Connected");
    Serial.println("================================");

  }

  void onDisconnect(BLEServer* server) override {

    deviceConnected = false;

    Serial.println();
    Serial.println("GeoScan AI: Phone Disconnected");

    delay(300);

    BLEDevice::startAdvertising();
  }
};

// ============================================================
// إرسال JSON
// ============================================================

void sendJson(
  const char* type,
  float signal,
  int raw,
  const char* status
) {

  if (!deviceConnected) {
    return;
  }

  StaticJsonDocument<256> doc;

  doc["type"] = type;
  doc["signal"] = signal;
  doc["raw"] = raw;
  doc["status"] = status;
  doc["scanning"] = scanning;
  doc["sensitivity"] = sensitivity;
  doc["filter"] = selectedFilter;

  String output;

  serializeJson(doc, output);

  notifyCharacteristic->setValue(
    output.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print("TX: ");
  Serial.println(output);
}

// ============================================================
// إرسال Status
// ============================================================

void sendStatus() {

  if (!deviceConnected) {
    return;
  }

  StaticJsonDocument<256> doc;

  doc["type"] = "status";
  doc["connected"] = deviceConnected;
  doc["scanning"] = scanning;
  doc["sensitivity"] = sensitivity;
  doc["filter"] = selectedFilter;
  doc["audio"] = audioEnabled;
  doc["vibration"] = vibrationEnabled;
  doc["baseline"] = baseline;

  String output;

  serializeJson(doc, output);

  notifyCharacteristic->setValue(
    output.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print("STATUS TX: ");
  Serial.println(output);
}

// ============================================================
// حساب الإشارة
// ============================================================

float calculateSignal(int raw) {

  // الفرق عن خط الأساس
  float difference =
    abs((float)raw - baseline);

  // تحويل الفرق إلى 0 - 100
  float signal =
    difference * 100.0 / 1000.0;

  // تطبيق الحساسية
  signal =
    signal * (sensitivity / 70.0);

  signal =
    constrain(signal, 0.0, 100.0);

  // فلترة / تنعيم
  filteredSignal =
    (filteredSignal * 0.75) +
    (signal * 0.25);

  return filteredSignal;
}

// ============================================================
// تحديد الحالة
// ============================================================

const char* getSignalStatus(
  float signal
) {

  if (signal < 10) {
    return "STABLE";
  }

  if (signal < 30) {
    return "WEAK";
  }

  if (signal < 60) {
    return "MEDIUM";
  }

  if (signal < 80) {
    return "STRONG";
  }

  return "VERY_STRONG";
}

// ============================================================
// الصوت
// ============================================================

void updateAudio(float signal) {

  if (!audioEnabled) {

    noTone(BUZZER_PIN);

    return;
  }

  if (!scanning || signal < 10) {

    noTone(BUZZER_PIN);

    return;
  }

  int frequency =
    map(
      (int)signal,
      10,
      100,
      500,
      2500
    );

  frequency =
    constrain(
      frequency,
      500,
      2500
    );

  tone(
    BUZZER_PIN,
    frequency
  );
}

// ============================================================
// الاهتزاز
// ============================================================

void updateVibration(float signal) {

  if (!vibrationEnabled) {

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    return;
  }

  if (!scanning || signal < 30) {

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    return;
  }

  digitalWrite(
    VIBRATION_PIN,
    HIGH
  );
}

// ============================================================
// معايرة
// ============================================================

void calibrateSensor() {

  Serial.println();
  Serial.println("Starting calibration...");

  const int samples = 100;

  long total = 0;

  for (int i = 0; i < samples; i++) {

    total += analogRead(
      SENSOR_PIN
    );

    delay(10);
  }

  baseline =
    (float)total / samples;

  filteredSignal = 0;

  Serial.print(
    "Calibration baseline: "
  );

  Serial.println(
    baseline
  );

  sendJson(
    "calibration",
    0,
    0,
    "CALIBRATED"
  );
}

// ============================================================
// معالجة أوامر Flutter
// ============================================================

void handleCommand(
  String command
) {

  command.trim();

  command.toUpperCase();

  Serial.print("RX: ");
  Serial.println(command);

  // -----------------------------------------
  // START
  // -----------------------------------------

  if (command == "START") {

    scanning = true;

    sendJson(
      "command",
      filteredSignal,
      rawValue,
      "STARTED"
    );

    return;
  }

  // -----------------------------------------
  // STOP
  // -----------------------------------------

  if (command == "STOP") {

    scanning = false;

    noTone(BUZZER_PIN);

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    sendJson(
      "command",
      filteredSignal,
      rawValue,
      "STOPPED"
    );

    return;
  }

  // -----------------------------------------
  // CALIBRATE
  // -----------------------------------------

  if (command == "CALIBRATE") {

    calibrateSensor();

    return;
  }

  // -----------------------------------------
  // GET_STATUS
  // -----------------------------------------

  if (command == "GET_STATUS") {

    sendStatus();

    return;
  }

  // -----------------------------------------
  // AUDIO
  // -----------------------------------------

  if (command == "AUDIO:ON") {

    audioEnabled = true;

    sendStatus();

    return;
  }

  if (command == "AUDIO:OFF") {

    audioEnabled = false;

    noTone(BUZZER_PIN);

    sendStatus();

    return;
  }

  // -----------------------------------------
  // VIBRATION
  // -----------------------------------------

  if (command == "VIBRATION:ON") {

    vibrationEnabled = true;

    sendStatus();

    return;
  }

  if (command == "VIBRATION:OFF") {

    vibrationEnabled = false;

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    sendStatus();

    return;
  }

  // -----------------------------------------
  // SENSITIVITY
  // -----------------------------------------

  if (
    command.startsWith(
      "SENSITIVITY:"
    )
  ) {

    String value =
      command.substring(
        strlen("SENSITIVITY:")
      );

    int newSensitivity =
      value.toInt();

    sensitivity =
      constrain(
        newSensitivity,
        0,
        100
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

  // -----------------------------------------
  // FILTER
  // -----------------------------------------

  if (
    command.startsWith(
      "FILTER:"
    )
  ) {

    selectedFilter =
      command.substring(
        strlen("FILTER:")
      );

    Serial.print(
      "Filter = "
    );

    Serial.println(
      selectedFilter
    );

    sendStatus();

    return;
  }

  // -----------------------------------------
  // أمر غير معروف
  // -----------------------------------------

  sendJson(
    "error",
    0,
    0,
    "UNKNOWN_COMMAND"
  );
}

// ============================================================
// Characteristic Callbacks
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

    String command =
      String(value.c_str());

    handleCommand(command);
  }
};

// ============================================================
// إعداد BLE
// ============================================================

void setupBLE() {

  BLEDevice::init(
    DEVICE_NAME
  );

  BLEServer* server =
    BLEDevice::createServer();

  server->setCallbacks(
    new GeoScanServerCallbacks()
  );

  BLEService* service =
    server->createService(
      SERVICE_UUID
    );

  // -----------------------------------------
  // Notify Characteristic
  // ESP32 -> Phone
  // -----------------------------------------

  notifyCharacteristic =
    service->createCharacteristic(
      NOTIFY_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );

  notifyCharacteristic->addDescriptor(
    new BLE2902()
  );

  // -----------------------------------------
  // Write Characteristic
  // Phone -> ESP32
  // -----------------------------------------

  writeCharacteristic =
    service->createCharacteristic(
      WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_WRITE_NR
    );

  writeCharacteristic->setCallbacks(
    new GeoScanWriteCallbacks()
  );

  // -----------------------------------------
  // بدء الخدمة
  // -----------------------------------------

  service->start();

  // -----------------------------------------
  // Advertising
  // -----------------------------------------

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
    "GeoScan AI BLE Started"
  );
  Serial.println(
    "Device: GeoScan-AI"
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

  Serial.begin(115200);

  delay(1000);

  Serial.println();
  Serial.println(
    "GeoScan AI ESP32 Starting..."
  );

  // ADC
  pinMode(
    SENSOR_PIN,
    INPUT
  );

  // Buzzer
  pinMode(
    BUZZER_PIN,
    OUTPUT
  );

  // Vibration
  pinMode(
    VIBRATION_PIN,
    OUTPUT
  );

  digitalWrite(
    VIBRATION_PIN,
    LOW
  );

  noTone(
    BUZZER_PIN
  );

  // إعداد ADC
  analogReadResolution(12);

  // في ESP32 التقليدي
  analogSetPinAttenuation(
    SENSOR_PIN,
    ADC_11db
  );

  // معايرة أولية
  calibrateSensor();

  // BLE
  setupBLE();
}

// ============================================================
// LOOP
// ============================================================

void loop() {

  // -----------------------------------------
  // قراءة ADC الحقيقية
  // -----------------------------------------

  rawValue =
    analogRead(
      SENSOR_PIN
    );

  // -----------------------------------------
  // حساب الإشارة
  // -----------------------------------------

  float signal =
    calculateSignal(
      rawValue
    );

  // -----------------------------------------
  // تشغيل الصوت والاهتزاز
  // -----------------------------------------

  updateAudio(
    signal
  );

  updateVibration(
    signal
  );

  // -----------------------------------------
  // إرسال البيانات للتطبيق
  // -----------------------------------------

  if (
    deviceConnected &&
    scanning &&
    millis() - lastSendTime >= SEND_INTERVAL
  ) {

    lastSendTime =
      millis();

    const char* status =
      getSignalStatus(
        signal
      );

    sendJson(
      "signal",
      signal,
      rawValue,
      status
    );
  }

  // -----------------------------------------
  // إرسال Status دوري
  // -----------------------------------------

  if (
    deviceConnected &&
    millis() - lastStatusTime >= STATUS_INTERVAL
  ) {

    lastStatusTime =
      millis();

    sendStatus();
  }

  delay(5);
}

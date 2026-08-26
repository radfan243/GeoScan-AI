#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ============================================================
// GeoScan AI - ESP32
// REAL SENSOR DATA PROTOCOL v2
// ESP32 -> Flutter
// ============================================================

#define DEVICE_NAME "GeoScan-AI"

// -----------------------------
// BLE UUIDs
// -----------------------------
#define SERVICE_UUID \
  "12345678-1234-1234-1234-1234567890ab"

#define NOTIFY_UUID \
  "12345678-1234-1234-1234-1234567890ac"

#define WRITE_UUID \
  "12345678-1234-1234-1234-1234567890ad"

// ============================================================
// HARDWARE
// ============================================================

#define SENSOR_PIN 34
#define BUZZER_PIN 25
#define VIBRATION_PIN 26

// ============================================================
// BLE
// ============================================================

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

bool deviceConnected = false;
bool scanning = false;

// ============================================================
// SETTINGS
// ============================================================

bool audioEnabled = true;
bool vibrationEnabled = false;

int sensitivity = 70;

String selectedFilter = "ALL";

// ============================================================
// SENSOR
// ============================================================

int rawValue = 0;

float baseline = 0.0;
float filteredSignal = 0.0;
float stability = 100.0;

// آخر قيمة إشارة للمقارنة
float previousSignal = 0.0;

// ============================================================
// TIMING
// ============================================================

unsigned long lastSendTime = 0;
unsigned long lastStatusTime = 0;

const unsigned long SEND_INTERVAL = 120;
const unsigned long STATUS_INTERVAL = 2000;

// ============================================================
// SEQUENCE
// ============================================================

// رقم متسلسل لكل قراءة حقيقية
uint32_t sequenceNumber = 0;

// ============================================================
// BLE SERVER CALLBACKS
// ============================================================

class GeoScanServerCallbacks : public BLEServerCallbacks {

  void onConnect(BLEServer* server) override {

    deviceConnected = true;

    Serial.println();
    Serial.println("================================");
    Serial.println("GeoScan AI: PHONE CONNECTED");
    Serial.println("================================");

    // إرسال الحالة فور الاتصال
    delay(100);

    sendStatus();
  }

  void onDisconnect(BLEServer* server) override {

    deviceConnected = false;
    scanning = false;

    noTone(BUZZER_PIN);
    digitalWrite(VIBRATION_PIN, LOW);

    Serial.println();
    Serial.println("GeoScan AI: PHONE DISCONNECTED");

    delay(300);

    BLEDevice::startAdvertising();
  }
};

// ============================================================
// CALCULATE STABILITY
// ============================================================

float calculateStability(float currentSignal) {

  float difference =
      abs(currentSignal - previousSignal);

  previousSignal = currentSignal;

  // كلما قل التغير زاد الاستقرار
  float calculated =
      100.0 - (difference * 5.0);

  calculated =
      constrain(
          calculated,
          0.0,
          100.0
      );

  // تنعيم الاستقرار
  stability =
      (stability * 0.85) +
      (calculated * 0.15);

  return stability;
}

// ============================================================
// CALCULATE SIGNAL
// ============================================================

float calculateSignal(int raw) {

  // لا توجد قراءة حقيقية قبل المعايرة
  if (baseline <= 0) {
    return 0.0;
  }

  // الفرق الحقيقي عن خط الأساس
  float difference =
      abs((float)raw - baseline);

  // ----------------------------------------------------------
  // تحويل الفرق إلى نسبة
  // ----------------------------------------------------------

  float signal =
      difference * 100.0 / 1000.0;

  // الحساسية
  signal =
      signal * (sensitivity / 70.0);

  signal =
      constrain(
          signal,
          0.0,
          100.0
      );

  // ----------------------------------------------------------
  // فلترة
  // ----------------------------------------------------------

  if (selectedFilter == "LOW") {

    filteredSignal =
        (filteredSignal * 0.90) +
        (signal * 0.10);

  } else if (selectedFilter == "HIGH") {

    filteredSignal =
        (filteredSignal * 0.55) +
        (signal * 0.45);

  } else {

    // MEDIUM / ALL
    filteredSignal =
        (filteredSignal * 0.75) +
        (signal * 0.25);
  }

  filteredSignal =
      constrain(
          filteredSignal,
          0.0,
          100.0
      );

  return filteredSignal;
}

// ============================================================
// SIGNAL STATUS
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
// SEND REAL SENSOR DATA
// ============================================================

void sendSignalData(
    float signal
) {

  if (!deviceConnected ||
      notifyCharacteristic == nullptr) {
    return;
  }

  StaticJsonDocument<512> doc;

  // نوع البيانات
  doc["type"] = "signal";

  // رقم القراءة
  doc["sequence"] = sequenceNumber;

  // القراءة الخام من ADC
  doc["raw"] = rawValue;

  // خط الأساس
  doc["baseline"] = baseline;

  // الإشارة المعالجة
  doc["signal"] = signal;

  // الاستقرار
  doc["stability"] = stability;

  // الوقت منذ تشغيل ESP32
  doc["timestamp"] = millis();

  // الحالة
  doc["status"] =
      getSignalStatus(signal);

  // حالة المسح
  doc["scanning"] = scanning;

  // الحساسية
  doc["sensitivity"] = sensitivity;

  // الفلتر
  doc["filter"] = selectedFilter;

  // مصدر البيانات
  doc["source"] = "ESP32_ADC";

  String output;

  serializeJson(
      doc,
      output
  );

  notifyCharacteristic->setValue(
      output.c_str()
  );

  notifyCharacteristic->notify();

  // Serial Monitor
  Serial.print("REAL DATA: ");
  Serial.println(output);
}

// ============================================================
// SEND STATUS
// ============================================================

void sendStatus() {

  if (!deviceConnected ||
      notifyCharacteristic == nullptr) {
    return;
  }

  StaticJsonDocument<512> doc;

  doc["type"] = "status";

  doc["connected"] =
      deviceConnected;

  doc["scanning"] =
      scanning;

  doc["sensitivity"] =
      sensitivity;

  doc["filter"] =
      selectedFilter;

  doc["audio"] =
      audioEnabled;

  doc["vibration"] =
      vibrationEnabled;

  doc["baseline"] =
      baseline;

  doc["raw"] =
      rawValue;

  doc["signal"] =
      filteredSignal;

  doc["stability"] =
      stability;

  doc["sequence"] =
      sequenceNumber;

  doc["timestamp"] =
      millis();

  doc["source"] =
      "ESP32_ADC";

  String output;

  serializeJson(
      doc,
      output
  );

  notifyCharacteristic->setValue(
      output.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print("STATUS: ");
  Serial.println(output);
}

// ============================================================
// AUDIO
// ============================================================

void updateAudio(
    float signal
) {

  if (!audioEnabled ||
      !scanning ||
      signal < 10) {

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
// VIBRATION
// ============================================================

void updateVibration(
    float signal
) {

  if (!vibrationEnabled ||
      !scanning ||
      signal < 30) {

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
// CALIBRATION
// ============================================================

void calibrateSensor() {

  Serial.println();
  Serial.println("================================");
  Serial.println("STARTING REAL SENSOR CALIBRATION");
  Serial.println("KEEP SENSOR AWAY FROM TARGET");
  Serial.println("================================");

  scanning = false;

  noTone(BUZZER_PIN);

  digitalWrite(
      VIBRATION_PIN,
      LOW
  );

  const int samples = 200;

  double total = 0;

  for (int i = 0; i < samples; i++) {

    int value =
        analogRead(SENSOR_PIN);

    total += value;

    delay(5);
  }

  baseline =
      total / samples;

  filteredSignal = 0;
  previousSignal = 0;
  stability = 100;

  Serial.print(
      "BASELINE = "
  );

  Serial.println(
      baseline,
      2
  );

  sequenceNumber = 0;

  if (deviceConnected) {

    StaticJsonDocument<512> doc;

    doc["type"] =
        "calibration";

    doc["success"] =
        true;

    doc["baseline"] =
        baseline;

    doc["signal"] =
        0;

    doc["stability"] =
        100;

    doc["timestamp"] =
        millis();

    doc["source"] =
        "ESP32_ADC";

    String output;

    serializeJson(
        doc,
        output
    );

    notifyCharacteristic->setValue(
        output.c_str()
    );

    notifyCharacteristic->notify();

    Serial.print(
        "CALIBRATION: "
    );

    Serial.println(
        output
    );
  }
}

// ============================================================
// COMMAND HANDLER
// ============================================================

void handleCommand(
    String command
) {

  command.trim();

  command.toUpperCase();

  Serial.print(
      "RX COMMAND: "
  );

  Serial.println(
      command
  );

  // ==========================================================
  // START
  // ==========================================================

  if (command == "START") {

    if (baseline <= 0) {

      sendStatus();

      Serial.println(
          "Cannot start: SENSOR NOT CALIBRATED"
      );

      return;
    }

    scanning = true;

    sendStatus();

    return;
  }

  // ==========================================================
  // STOP
  // ==========================================================

  if (command == "STOP") {

    scanning = false;

    noTone(
        BUZZER_PIN
    );

    digitalWrite(
        VIBRATION_PIN,
        LOW
    );

    sendStatus();

    return;
  }

  // ==========================================================
  // CALIBRATE
  // ==========================================================

  if (command == "CALIBRATE") {

    calibrateSensor();

    return;
  }

  // ==========================================================
  // STATUS
  // ==========================================================

  if (command == "GET_STATUS") {

    sendStatus();

    return;
  }

  // ==========================================================
  // AUDIO
  // ==========================================================

  if (command == "AUDIO:ON") {

    audioEnabled = true;

    sendStatus();

    return;
  }

  if (command == "AUDIO:OFF") {

    audioEnabled = false;

    noTone(
        BUZZER_PIN
    );

    sendStatus();

    return;
  }

  // ==========================================================
  // VIBRATION
  // ==========================================================

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
            strlen(
                "SENSITIVITY:"
            )
        );

    int newSensitivity =
        value.toInt();

    sensitivity =
        constrain(
            newSensitivity,
            0,
            100
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

    selectedFilter =
        command.substring(
            strlen(
                "FILTER:"
            )
        );

    sendStatus();

    return;
  }

  // ==========================================================
  // UNKNOWN
  // ==========================================================

  if (deviceConnected) {

    StaticJsonDocument<256> doc;

    doc["type"] =
        "error";

    doc["error"] =
        "UNKNOWN_COMMAND";

    doc["command"] =
        command;

    doc["timestamp"] =
        millis();

    String output;

    serializeJson(
        doc,
        output
    );

    notifyCharacteristic->setValue(
        output.c_str()
    );

    notifyCharacteristic->notify();
  }
}

// ============================================================
// WRITE CALLBACK
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
        String(
            value.c_str()
        );

    handleCommand(
        command
    );
  }
};

// ============================================================
// BLE SETUP
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

  // ESP32 -> Phone
  notifyCharacteristic =
      service->createCharacteristic(
          NOTIFY_UUID,
          BLECharacteristic::PROPERTY_NOTIFY
      );

  notifyCharacteristic->addDescriptor(
      new BLE2902()
  );

  // Phone -> ESP32
  writeCharacteristic =
      service->createCharacteristic(
          WRITE_UUID,
          BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR
      );

  writeCharacteristic->setCallbacks(
      new GeoScanWriteCallbacks()
  );

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
      "Device: GeoScan-AI"
  );
  Serial.println(
      "REAL ADC DATA MODE"
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
      "GeoScan AI ESP32 STARTING..."
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

  // ADC resolution
  analogReadResolution(12);

  // ESP32 classic ADC
  analogSetPinAttenuation(
      SENSOR_PIN,
      ADC_11db
  );

  // ----------------------------------------------------------
  // Initial calibration
  // ----------------------------------------------------------

  calibrateSensor();

  // ----------------------------------------------------------
  // BLE
  // ----------------------------------------------------------

  setupBLE();
}

// ============================================================
// LOOP
// ============================================================

void loop() {

  // ==========================================================
  // قراءة ADC الحقيقية
  // ==========================================================

  rawValue =
      analogRead(
          SENSOR_PIN
      );

  // ==========================================================
  // حساب الإشارة
  // ==========================================================

  float signal =
      calculateSignal(
          rawValue
      );

  // ==========================================================
  // حساب الاستقرار
  // ==========================================================

  float currentStability =
      calculateStability(
          signal
      );

  stability =
      currentStability;

  // ==========================================================
  // صوت واهتزاز
  // ==========================================================

  updateAudio(
      signal
  );

  updateVibration(
      signal
  );

  // ==========================================================
  // إرسال القراءة الحقيقية
  // ==========================================================

  if (
      deviceConnected &&
      scanning &&
      millis() - lastSendTime >=
          SEND_INTERVAL
  ) {

    lastSendTime =
        millis();

    // رقم جديد لهذه القراءة
    sequenceNumber++;

    sendSignalData(
        signal
    );
  }

  // ==========================================================
  // Status دوري
  // ==========================================================

  if (
      deviceConnected &&
      millis() - lastStatusTime >=
          STATUS_INTERVAL
  ) {

    lastStatusTime =
        millis();

    sendStatus();
  }

  delay(5);
}

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ============================================================
// GeoScan AI - ESP32 V2
// Real Sensor -> ADC -> Processing -> BLE -> Flutter
// ============================================================

// ============================================================
// BLE
// ============================================================

#define DEVICE_NAME "GeoScan-AI"

#define SERVICE_UUID \
  "12345678-1234-1234-1234-1234567890ab"

#define NOTIFY_UUID \
  "12345678-1234-1234-1234-1234567890ac"

#define WRITE_UUID \
  "12345678-1234-1234-1234-1234567890ad"

// ============================================================
// Hardware
// ============================================================

#define SENSOR_PIN 34
#define BUZZER_PIN 25
#define VIBRATION_PIN 26

// ============================================================
// BLE Objects
// ============================================================

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

// ============================================================
// System State
// ============================================================

bool deviceConnected = false;
bool scanning = false;

bool audioEnabled = true;
bool vibrationEnabled = false;

int sensitivity = 70;

String selectedFilter = "متوسطة";

// ============================================================
// ADC / Signal Variables
// ============================================================

int rawValue = 0;

float baseline = 0.0;

float filteredSignal = 0.0;

float previousSignal = 0.0;

float stability = 100.0;

float depth = 0.0;

// ============================================================
// Timing
// ============================================================

unsigned long lastSendTime = 0;
unsigned long lastStatusTime = 0;

const unsigned long SEND_INTERVAL = 120;
const unsigned long STATUS_INTERVAL = 2000;

// ============================================================
// Signal configuration
// ============================================================

// عدد العينات لكل قراءة
const int ADC_SAMPLES = 16;

// الحد الأدنى للفرق الذي نعتبره ضوضاء
const float NOISE_THRESHOLD = 3.0;

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

    sendStatus();
  }

  void onDisconnect(BLEServer* server) override {

    deviceConnected = false;
    scanning = false;

    noTone(BUZZER_PIN);

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    Serial.println();
    Serial.println("GeoScan AI: PHONE DISCONNECTED");

    delay(300);

    BLEDevice::startAdvertising();
  }
};

// ============================================================
// إرسال JSON إلى Flutter
// ============================================================

void sendJson(
  const char* type,
  float signal,
  int raw,
  const char* status
) {

  if (!deviceConnected ||
      notifyCharacteristic == nullptr) {
    return;
  }

  StaticJsonDocument<512> doc;

  doc["type"] = type;

  doc["signal"] =
    round(signal * 10.0) / 10.0;

  doc["raw"] = raw;

  doc["baseline"] =
    round(baseline * 10.0) / 10.0;

  doc["stability"] =
    round(stability * 10.0) / 10.0;

  doc["depth"] =
    round(depth * 100.0) / 100.0;

  doc["status"] = status;

  doc["scanning"] = scanning;

  doc["connected"] = deviceConnected;

  doc["sensitivity"] = sensitivity;

  doc["filter"] = selectedFilter;

  doc["audio"] = audioEnabled;

  doc["vibration"] = vibrationEnabled;

  String output;

  serializeJson(
    doc,
    output
  );

  notifyCharacteristic->setValue(
    output.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print("TX: ");
  Serial.println(output);
}

// ============================================================
// إرسال الحالة
// ============================================================

void sendStatus() {

  if (!deviceConnected ||
      notifyCharacteristic == nullptr) {
    return;
  }

  StaticJsonDocument<512> doc;

  doc["type"] = "status";

  doc["connected"] = deviceConnected;

  doc["scanning"] = scanning;

  doc["signal"] =
    round(filteredSignal * 10.0) / 10.0;

  doc["raw"] = rawValue;

  doc["baseline"] =
    round(baseline * 10.0) / 10.0;

  doc["stability"] =
    round(stability * 10.0) / 10.0;

  doc["depth"] =
    round(depth * 100.0) / 100.0;

  doc["sensitivity"] = sensitivity;

  doc["filter"] = selectedFilter;

  doc["audio"] = audioEnabled;

  doc["vibration"] = vibrationEnabled;

  String output;

  serializeJson(
    doc,
    output
  );

  notifyCharacteristic->setValue(
    output.c_str()
  );

  notifyCharacteristic->notify();

  Serial.print("STATUS TX: ");
  Serial.println(output);
}

// ============================================================
// قراءة ADC مستقرة
// ============================================================

int readSensorAverage() {

  long total = 0;

  for (
    int i = 0;
    i < ADC_SAMPLES;
    i++
  ) {

    total += analogRead(
      SENSOR_PIN
    );

    delayMicroseconds(300);
  }

  return total / ADC_SAMPLES;
}

// ============================================================
// حساب الفرق عن Baseline
// ============================================================

float calculateDifference(
  int raw
) {

  float difference =
    abs(
      (float)raw -
      baseline
    );

  if (
    difference <
    NOISE_THRESHOLD
  ) {

    difference = 0;
  }

  return difference;
}

// ============================================================
// تحويل الفرق إلى Signal 0-100
// ============================================================

float convertDifferenceToSignal(
  float difference
) {

  /*
   * هذه المعادلة ليست "كشف ذهب".
   *
   * هي تحويل أولي لقوة التغير في
   * إشارة الحساس إلى نطاق 0-100.
   *
   * سيتم ضبطها بعد اختبار دائرة الحساس
   * الحقيقية.
   */

  float signal =
    difference *
    100.0 /
    1000.0;

  // الحساسية

  signal =
    signal *
    (
      sensitivity /
      70.0
    );

  signal =
    constrain(
      signal,
      0.0,
      100.0
    );

  return signal;
}

// ============================================================
// تطبيق الفلترة
// ============================================================

float applyFilter(
  float newSignal
) {

  float alpha = 0.25;

  // فلترة منخفضة
  if (
    selectedFilter ==
    "منخفضة"
  ) {

    alpha = 0.45;
  }

  // فلترة متوسطة
  else if (
    selectedFilter ==
    "متوسطة"
  ) {

    alpha = 0.25;
  }

  // فلترة عالية
  else if (
    selectedFilter ==
    "عالية"
  ) {

    alpha = 0.12;
  }

  filteredSignal =
    (
      filteredSignal *
      (1.0 - alpha)
    ) +
    (
      newSignal *
      alpha
    );

  filteredSignal =
    constrain(
      filteredSignal,
      0.0,
      100.0
    );

  return filteredSignal;
}

// ============================================================
// حساب الاستقرار
// ============================================================

float calculateStability(
  float currentSignal
) {

  float change =
    abs(
      currentSignal -
      previousSignal
    );

  previousSignal =
    currentSignal;

  /*
   * كلما كان تغير الإشارة
   * صغيرًا تكون القراءة أكثر استقرارًا.
   */

  float currentStability =
    100.0 -
    (
      change *
      8.0
    );

  currentStability =
    constrain(
      currentStability,
      0.0,
      100.0
    );

  // تنعيم الاستقرار

  stability =
    (
      stability *
      0.85
    ) +
    (
      currentStability *
      0.15
    );

  return stability;
}

// ============================================================
// تقدير العمق
// ============================================================

float calculateDepth(
  float signal
) {

  /*
   * مهم جدًا:
   *
   * لا يمكن حساب عمق حقيقي بالمتر
   * من قيمة ADC واحدة فقط.
   *
   * لذلك هذه مرحلة مؤقتة.
   *
   * بعد بناء الحساس واختباره سنضع
   * Calibration Table حقيقية.
   */

  if (signal < 10) {
    return 0.0;
  }

  float estimated =
    signal / 100.0;

  estimated =
    estimated * 1.5;

  return constrain(
    estimated,
    0.0,
    1.5
  );
}

// ============================================================
// حالة الإشارة
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
// تحديث الإشارة كاملة
// ============================================================

void processSignal() {

  rawValue =
    readSensorAverage();

  float difference =
    calculateDifference(
      rawValue
    );

  float signal =
    convertDifferenceToSignal(
      difference
    );

  signal =
    applyFilter(
      signal
    );

  calculateStability(
    signal
  );

  depth =
    calculateDepth(
      signal
    );
}

// ============================================================
// الصوت
// ============================================================

void updateAudio(
  float signal
) {

  if (!audioEnabled) {

    noTone(
      BUZZER_PIN
    );

    return;
  }

  if (
    !scanning ||
    signal < 10
  ) {

    noTone(
      BUZZER_PIN
    );

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

void updateVibration(
  float signal
) {

  if (!vibrationEnabled) {

    digitalWrite(
      VIBRATION_PIN,
      LOW
    );

    return;
  }

  if (
    !scanning ||
    signal < 30
  ) {

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
// المعايرة
// ============================================================

void calibrateSensor() {

  Serial.println();
  Serial.println(
    "================================"
  );

  Serial.println(
    "GeoScan AI Calibration"
  );

  Serial.println(
    "Keep sensor away from metal..."
  );

  Serial.println(
    "================================"
  );

  const int samples = 150;

  long total = 0;

  long minimum = 4095;

  long maximum = 0;

  for (
    int i = 0;
    i < samples;
    i++
  ) {

    int value =
      analogRead(
        SENSOR_PIN
      );

    total += value;

    if (value < minimum) {
      minimum = value;
    }

    if (value > maximum) {
      maximum = value;
    }

    delay(10);
  }

  baseline =
    (float)total /
    samples;

  filteredSignal = 0;

  previousSignal = 0;

  stability = 100;

  depth = 0;

  Serial.print(
    "Baseline: "
  );

  Serial.println(
    baseline
  );

  Serial.print(
    "Minimum: "
  );

  Serial.println(
    minimum
  );

  Serial.print(
    "Maximum: "
  );

  Serial.println(
    maximum
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

  Serial.print(
    "RX: "
  );

  Serial.println(
    command
  );

  // ==========================================================
  // START
  // ==========================================================

  if (
    command ==
    "START"
  ) {

    scanning = true;

    filteredSignal = 0;

    stability = 100;

    sendJson(
      "command",
      filteredSignal,
      rawValue,
      "STARTED"
    );

    return;
  }

  // ==========================================================
  // STOP
  // ==========================================================

  if (
    command ==
    "STOP"
  ) {

    scanning = false;

    noTone(
      BUZZER_PIN
    );

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

  // ==========================================================
  // CALIBRATE
  // ==========================================================

  if (
    command ==
    "CALIBRATE"
  ) {

    if (scanning) {

      scanning = false;

      noTone(
        BUZZER_PIN
      );

      digitalWrite(
        VIBRATION_PIN,
        LOW
      );
    }

    calibrateSensor();

    return;
  }

  // ==========================================================
  // GET STATUS
  // ==========================================================

  if (
    command ==
    "GET_STATUS"
  ) {

    sendStatus();

    return;
  }

  // ==========================================================
  // AUDIO
  // ==========================================================

  if (
    command ==
    "AUDIO:ON"
  ) {

    audioEnabled = true;

    sendStatus();

    return;
  }

  if (
    command ==
    "AUDIO:OFF"
  ) {

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

  if (
    command ==
    "VIBRATION:ON"
  ) {

    vibrationEnabled = true;

    sendStatus();

    return;
  }

  if (
    command ==
    "VIBRATION:OFF"
  ) {

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

    selectedFilter =
      command.substring(
        strlen(
          "FILTER:"
        )
      );

    if (
      selectedFilter !=
      "منخفضة" &&
      selectedFilter !=
      "متوسطة" &&
      selectedFilter !=
      "عالية"
    ) {

      selectedFilter =
        "متوسطة";
    }

    Serial.print(
      "Filter = "
    );

    Serial.println(
      selectedFilter
    );

    sendStatus();

    return;
  }

  // ==========================================================
  // UNKNOWN COMMAND
  // ==========================================================

  sendJson(
    "error",
    0,
    0,
    "UNKNOWN_COMMAND"
  );
}

// ============================================================
// BLE WRITE CALLBACK
// ============================================================

class GeoScanWriteCallbacks
  : public BLECharacteristicCallbacks {

  void onWrite(
    BLECharacteristic* characteristic
  ) override {

    std::string value =
      characteristic->getValue();

    if (
      value.length() == 0
    ) {

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

  // ==========================================================
  // NOTIFY
  // ESP32 -> PHONE
  // ==========================================================

  notifyCharacteristic =
    service->createCharacteristic(
      NOTIFY_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );

  notifyCharacteristic->addDescriptor(
    new BLE2902()
  );

  // ==========================================================
  // WRITE
  // PHONE -> ESP32
  // ==========================================================

  writeCharacteristic =
    service->createCharacteristic(
      WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_WRITE_NR
    );

  writeCharacteristic->setCallbacks(
    new GeoScanWriteCallbacks()
  );

  // ==========================================================
  // START SERVICE
  // ==========================================================

  service->start();

  // ==========================================================
  // ADVERTISING
  // ==========================================================

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
    "GeoScan AI BLE V2 STARTED"
  );

  Serial.println(
    "Device: GeoScan-AI"
  );

  Serial.println(
    "Waiting for Flutter..."
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
    "GeoScan AI ESP32 V2"
  );

  Serial.println(
    "Starting..."
  );

  // ==========================================================
  // GPIO
  // ==========================================================

  pinMode(
    SENSOR_PIN,
    INPUT
  );

  pinMode(
    BUZZER_PIN,
    OUTPUT
  );

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

  // ==========================================================
  // ADC
  // ==========================================================

  analogReadResolution(
    12
  );

  analogSetPinAttenuation(
    SENSOR_PIN,
    ADC_11db
  );

  // ==========================================================
  // Calibration
  // ==========================================================

  calibrateSensor();

  // ==========================================================
  // BLE
  // ==========================================================

  setupBLE();
}

// ============================================================
// LOOP
// ============================================================

void loop() {

  // ==========================================================
  // قراءة ومعالجة الحساس
  // ==========================================================

  processSignal();

  // ==========================================================
  // الصوت
  // ==========================================================

  updateAudio(
    filteredSignal
  );

  // ==========================================================
  // الاهتزاز
  // ==========================================================

  updateVibration(
    filteredSignal
  );

  // ==========================================================
  // إرسال القراءة الحقيقية
  // ==========================================================

  if (
    deviceConnected &&
    scanning &&
    (
      millis() -
      lastSendTime >=
      SEND_INTERVAL
    )
  ) {

    lastSendTime =
      millis();

    const char* status =
      getSignalStatus(
        filteredSignal
      );

    sendJson(
      "signal",
      filteredSignal,
      rawValue,
      status
    );
  }

  // ==========================================================
  // Status دوري
  // ==========================================================

  if (
    deviceConnected &&
    (
      millis() -
      lastStatusTime >=
      STATUS_INTERVAL
    )
  ) {

    lastStatusTime =
      millis();

    sendStatus();
  }

  delay(5);
}

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ============================================================
// GeoScan-AI ESP32 firmware
// Real ADC sensor -> BLE -> Flutter
// Flutter -> BLE commands -> ESP32
// ============================================================

#define DEVICE_NAME "GeoScan-AI"

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define NOTIFY_UUID  "12345678-1234-1234-1234-1234567890ac"
#define WRITE_UUID   "12345678-1234-1234-1234-1234567890ad"

// Hardware
#define SENSOR_PIN 34
#define BUZZER_PIN 25
#define VIBRATION_PIN 26

BLECharacteristic* notifyCharacteristic = nullptr;
BLECharacteristic* writeCharacteristic = nullptr;

bool deviceConnected = false;
bool scanning = false;
bool audioEnabled = true;
bool vibrationEnabled = false;

int sensitivity = 70;
String selectedFilter = "MEDIUM";
String selectedTarget = "METAL";

int rawValue = 0;
float baseline = 0.0f;
float filteredSignal = 0.0f;
float stability = 100.0f;
float previousSignal = 0.0f;

uint32_t sequenceNumber = 0;
unsigned long lastSendTime = 0;
unsigned long lastStatusTime = 0;

const unsigned long SEND_INTERVAL = 120;
const unsigned long STATUS_INTERVAL = 2000;

// The project does NOT claim a fake physical depth sensor.
// depthEstimate is an optional signal-based estimate and must be
// field-calibrated with known targets before being treated as depth.
float depthEstimate = 0.0f;
float depthConfidence = 0.0f;

void sendStatus();
void sendSignalData(float signal);
void handleCommand(String command);
void calibrateSensor();

class GeoScanServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    (void)server;
    deviceConnected = true;
    Serial.println("GeoScan-AI: PHONE CONNECTED");
    delay(50);
    sendStatus();
  }

  void onDisconnect(BLEServer* server) override {
    (void)server;
    deviceConnected = false;
    scanning = false;
    noTone(BUZZER_PIN);
    digitalWrite(VIBRATION_PIN, LOW);
    Serial.println("GeoScan-AI: PHONE DISCONNECTED");
    delay(200);
    BLEDevice::startAdvertising();
  }
};

float calculateStability(float currentSignal) {
  const float difference = fabsf(currentSignal - previousSignal);
  previousSignal = currentSignal;
  float calculated = 100.0f - (difference * 5.0f);
  calculated = constrain(calculated, 0.0f, 100.0f);
  stability = (stability * 0.85f) + (calculated * 0.15f);
  return stability;
}

float calculateSignal(int raw) {
  if (baseline <= 0.0f) return 0.0f;

  const float difference = fabsf((float)raw - baseline);
  float signal = difference * 100.0f / 1000.0f;
  signal *= ((float)sensitivity / 70.0f);
  signal = constrain(signal, 0.0f, 100.0f);

  if (selectedFilter == "LOW") {
    filteredSignal = (filteredSignal * 0.90f) + (signal * 0.10f);
  } else if (selectedFilter == "HIGH") {
    filteredSignal = (filteredSignal * 0.55f) + (signal * 0.45f);
  } else {
    filteredSignal = (filteredSignal * 0.75f) + (signal * 0.25f);
  }

  filteredSignal = constrain(filteredSignal, 0.0f, 100.0f);
  return filteredSignal;
}

// Signal-based depth estimate only. It is deliberately marked as an
// estimate; real underground depth requires calibration against the
// actual coil, target, soil and electronics.
void updateDepthEstimate(float signal) {
  if (signal < 8.0f || baseline <= 0.0f) {
    depthEstimate = 0.0f;
    depthConfidence = 0.0f;
    return;
  }

  // Conservative normalized estimate. Do not present as measured depth.
  const float normalized = constrain(signal / 100.0f, 0.0f, 1.0f);
  depthEstimate = 0.10f + (1.0f - normalized) * 1.90f;
  depthConfidence = constrain((stability * 0.6f) + (signal * 0.4f), 0.0f, 100.0f);
}

const char* getSignalStatus(float signal) {
  if (signal < 10.0f) return "STABLE";
  if (signal < 30.0f) return "WEAK";
  if (signal < 60.0f) return "MEDIUM";
  if (signal < 80.0f) return "STRONG";
  return "VERY_STRONG";
}

void notifyJson(JsonDocument& doc) {
  if (!deviceConnected || notifyCharacteristic == nullptr) return;

  String output;
  serializeJson(doc, output);
  notifyCharacteristic->setValue(output.c_str());
  notifyCharacteristic->notify();
  Serial.print("TX: ");
  Serial.println(output);
}

void sendSignalData(float signal) {
  if (!deviceConnected || notifyCharacteristic == nullptr) return;

  StaticJsonDocument<768> doc;
  doc["type"] = "signal";
  doc["sequence"] = sequenceNumber;
  doc["raw"] = rawValue;
  doc["baseline"] = baseline;
  doc["signal"] = signal;
  doc["stability"] = stability;
  doc["depth"] = depthEstimate;
  doc["depthConfidence"] = depthConfidence;
  doc["depthMode"] = "ESTIMATE";
  doc["timestamp"] = millis();
  doc["status"] = getSignalStatus(signal);
  doc["scanning"] = scanning;
  doc["sensitivity"] = sensitivity;
  doc["filter"] = selectedFilter;
  doc["target"] = selectedTarget;
  doc["source"] = "ESP32_ADC";
  notifyJson(doc);
}

void sendStatus() {
  if (!deviceConnected || notifyCharacteristic == nullptr) return;

  StaticJsonDocument<768> doc;
  doc["type"] = "status";
  doc["connected"] = deviceConnected;
  doc["scanning"] = scanning;
  doc["sensitivity"] = sensitivity;
  doc["filter"] = selectedFilter;
  doc["audio"] = audioEnabled;
  doc["vibration"] = vibrationEnabled;
  doc["target"] = selectedTarget;
  doc["baseline"] = baseline;
  doc["raw"] = rawValue;
  doc["signal"] = filteredSignal;
  doc["stability"] = stability;
  doc["depth"] = depthEstimate;
  doc["depthConfidence"] = depthConfidence;
  doc["depthMode"] = "ESTIMATE";
  doc["sequence"] = sequenceNumber;
  doc["timestamp"] = millis();
  doc["source"] = "ESP32_ADC";
  notifyJson(doc);
}

void sendError(const char* error, const String& command) {
  StaticJsonDocument<384> doc;
  doc["type"] = "error";
  doc["error"] = error;
  doc["command"] = command;
  doc["timestamp"] = millis();
  notifyJson(doc);
}

void updateAudio(float signal) {
  if (!audioEnabled || !scanning || signal < 10.0f) {
    noTone(BUZZER_PIN);
    return;
  }

  int frequency = map((int)signal, 10, 100, 500, 2500);
  frequency = constrain(frequency, 500, 2500);
  tone(BUZZER_PIN, frequency);
}

void updateVibration(float signal) {
  const bool active = vibrationEnabled && scanning && signal >= 30.0f;
  digitalWrite(VIBRATION_PIN, active ? HIGH : LOW);
}

void calibrateSensor() {
  scanning = false;
  noTone(BUZZER_PIN);
  digitalWrite(VIBRATION_PIN, LOW);

  Serial.println("GeoScan-AI: calibrating; keep coil away from targets");

  const int samples = 250;
  double total = 0.0;
  for (int i = 0; i < samples; ++i) {
    total += analogRead(SENSOR_PIN);
    delay(4);
  }

  baseline = (float)(total / samples);
  filteredSignal = 0.0f;
  previousSignal = 0.0f;
  stability = 100.0f;
  depthEstimate = 0.0f;
  depthConfidence = 0.0f;
  sequenceNumber = 0;

  StaticJsonDocument<512> doc;
  doc["type"] = "calibration";
  doc["success"] = true;
  doc["baseline"] = baseline;
  doc["signal"] = 0.0f;
  doc["stability"] = 100.0f;
  doc["depth"] = 0.0f;
  doc["depthMode"] = "ESTIMATE";
  doc["timestamp"] = millis();
  doc["source"] = "ESP32_ADC";
  notifyJson(doc);
}

void handleCommand(String command) {
  command.trim();
  command.toUpperCase();
  Serial.print("RX: ");
  Serial.println(command);

  if (command == "START") {
    if (baseline <= 0.0f) {
      sendError("NOT_CALIBRATED", command);
      return;
    }
    scanning = true;
    sendStatus();
    return;
  }

  if (command == "STOP") {
    scanning = false;
    noTone(BUZZER_PIN);
    digitalWrite(VIBRATION_PIN, LOW);
    sendStatus();
    return;
  }

  if (command == "CALIBRATE") {
    calibrateSensor();
    return;
  }

  if (command == "GET_STATUS") {
    sendStatus();
    return;
  }

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

  if (command == "VIBRATION:ON") {
    vibrationEnabled = true;
    sendStatus();
    return;
  }

  if (command == "VIBRATION:OFF") {
    vibrationEnabled = false;
    digitalWrite(VIBRATION_PIN, LOW);
    sendStatus();
    return;
  }

  if (command.startsWith("SENSITIVITY:")) {
    const int value = command.substring(13).toInt();
    sensitivity = constrain(value, 0, 100);
    sendStatus();
    return;
  }

  if (command.startsWith("FILTER:")) {
    String value = command.substring(7);
    if (value == "LOW" || value == "MEDIUM" || value == "HIGH" || value == "ALL") {
      selectedFilter = value;
      sendStatus();
    } else {
      sendError("INVALID_FILTER", command);
    }
    return;
  }

  if (command.startsWith("TARGET:")) {
    String value = command.substring(7);
    if (value.length() > 0 && value.length() <= 24) {
      selectedTarget = value;
      sendStatus();
    } else {
      sendError("INVALID_TARGET", command);
    }
    return;
  }

  sendError("UNKNOWN_COMMAND", command);
}

class GeoScanWriteCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();
    if (value.empty()) return;
    handleCommand(String(value.c_str()));
  }
};

void setupBLE() {
  BLEDevice::init(DEVICE_NAME);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new GeoScanServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);

  notifyCharacteristic = service->createCharacteristic(
      NOTIFY_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  notifyCharacteristic->addDescriptor(new BLE2902());

  writeCharacteristic = service->createCharacteristic(
      WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  writeCharacteristic->setCallbacks(new GeoScanWriteCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("GeoScan-AI BLE READY");
}

void setup() {
  Serial.begin(115200);
  delay(300);

  pinMode(SENSOR_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(VIBRATION_PIN, OUTPUT);
  digitalWrite(VIBRATION_PIN, LOW);

  analogReadResolution(12);
  analogSetPinAttenuation(SENSOR_PIN, ADC_11db);

  setupBLE();
  Serial.println("GeoScan-AI REAL ADC MODE");
  Serial.println("Run CALIBRATE before START.");
}

void loop() {
  rawValue = analogRead(SENSOR_PIN);

  if (scanning && baseline > 0.0f) {
    const float signal = calculateSignal(rawValue);
    calculateStability(signal);
    updateDepthEstimate(signal);
    updateAudio(signal);
    updateVibration(signal);

    if (deviceConnected && millis() - lastSendTime >= SEND_INTERVAL) {
      ++sequenceNumber;
      lastSendTime = millis();
      sendSignalData(signal);
    }
  } else {
    noTone(BUZZER_PIN);
    digitalWrite(VIBRATION_PIN, LOW);
  }

  if (deviceConnected && millis() - lastStatusTime >= STATUS_INTERVAL) {
    lastStatusTime = millis();
    sendStatus();
  }

  delay(5);
}

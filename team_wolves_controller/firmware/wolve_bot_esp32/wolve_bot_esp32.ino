/*
 * Wolve Bot ESP32 UDP receiver for team_wolves_controller.
 * Target: classic ESP32 Dev Module, Arduino-ESP32 core 3.x or 4.x.
 *
 * Pin map transcribed from the supplied diagram:
 *   Right BTS7960: RPWM=GPIO25, LPWM=GPIO26
 *   Left  BTS7960: RPWM=GPIO27, LPWM=GPIO14
 *   R_EN and L_EN on both drivers are tied to 5V as shown.
 *
 * Protocol matches lib/protocol/protocol.dart:
 * [A5 TYPE SEQ LEN PAYLOAD CRC8], CRC-8/0x07, init 0, no reflection.
 * Supports both Wi-Fi UDP and the app's custom BLE GATT fallback. Test with
 * motor power disconnected and wheels raised first.
 */

#include <Arduino.h>
#include <esp_arduino_version.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#if ESP_ARDUINO_VERSION_MAJOR >= 4
#include <BLE.h>
#else
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#endif
#include <string>

// Match the README and connection dialog. Change these to match your setup.
static const char *AP_SSID = "ROBO_BOT";
static const char *AP_PASSWORD = "wolves2026";
static constexpr uint16_t UDP_PORT = 4210;
static const char *BLE_DEVICE_NAME = "ROBO_BOT";
static const char *BLE_SERVICE_UUID = "0000abcd-0000-1000-8000-00805f9b34fb";
static const char *BLE_CONTROL_UUID = "0000ab01-0000-1000-8000-00805f9b34fb";
static const char *BLE_TELEMETRY_UUID = "0000ab03-0000-1000-8000-00805f9b34fb";

// BTS7960 inputs from the supplied connection diagram.
static constexpr uint8_t RIGHT_RPWM = 25;
static constexpr uint8_t RIGHT_LPWM = 26;
static constexpr uint8_t LEFT_RPWM = 27;
static constexpr uint8_t LEFT_LPWM = 14;

static constexpr uint8_t SOF = 0xA5;
static constexpr uint8_t TYPE_DRIVE = 0x01;
static constexpr uint8_t TYPE_SET_MODE = 0x02;
static constexpr uint8_t TYPE_ARM = 0x05;
static constexpr uint8_t TYPE_ESTOP = 0x06;
static constexpr uint8_t TYPE_HEARTBEAT = 0x07;
static constexpr uint8_t TYPE_TELEMETRY = 0x81;

static constexpr uint8_t STATE_BOOT = 0;
static constexpr uint8_t STATE_DISARMED = 1;
static constexpr uint8_t STATE_ARMED = 2;
static constexpr uint8_t STATE_FAILSAFE = 3;
static constexpr uint8_t STATE_ESTOP = 4;

static constexpr uint32_t DRIVE_TIMEOUT_MS = 250;
static constexpr uint16_t PWM_HZ = 20000;
static constexpr uint8_t PWM_BITS = 8;

WiFiUDP udp;
#if ESP_ARDUINO_VERSION_MAJOR >= 4
BLECharacteristic bleTelemetryCharacteristic;
#else
BLECharacteristic *bleTelemetryCharacteristic = nullptr;
#endif
IPAddress appAddress;
uint16_t appPort = 0;
bool haveApp = false;
bool armed = false;
bool estopLatched = false;
bool timedOut = false;
uint8_t requestedMode = 2;  // M2 is the app's initial speed profile.
uint8_t robotState = STATE_BOOT;
int16_t leftOutputPercent = 0;
int16_t rightOutputPercent = 0;
uint16_t droppedFrames = 0;
uint32_t lastDriveMs = 0;

uint8_t crc8(const uint8_t *data, size_t length) {
  uint8_t crc = 0;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x07)
                         : static_cast<uint8_t>(crc << 1);
    }
  }
  return crc;
}

int16_t readI16LE(const uint8_t *p) {
  return static_cast<int16_t>(static_cast<uint16_t>(p[0]) |
                              (static_cast<uint16_t>(p[1]) << 8));
}

void writeFrame(uint8_t type, uint8_t sequence, const uint8_t *payload,
                uint8_t length, bool viaBle = false) {
  uint8_t frame[16];
  frame[0] = SOF;
  frame[1] = type;
  frame[2] = sequence;
  frame[3] = length;
  for (uint8_t i = 0; i < length; ++i) frame[4 + i] = payload[i];
  frame[4 + length] = crc8(&frame[1], 3 + length);
  if (viaBle) {
#if ESP_ARDUINO_VERSION_MAJOR >= 4
    if (bleTelemetryCharacteristic) {
      bleTelemetryCharacteristic.setValue(frame, 5 + length);
      bleTelemetryCharacteristic.notify();
    }
#else
    if (bleTelemetryCharacteristic != nullptr) {
      bleTelemetryCharacteristic->setValue(frame, 5 + length);
      bleTelemetryCharacteristic->notify();
    }
#endif
    return;
  }
  if (!haveApp || appPort == 0) return;
  udp.beginPacket(appAddress, appPort);
  udp.write(frame, 5 + length);
  udp.endPacket();
}

void sendTelemetry(uint8_t sequence, bool viaBle = false) {
  // Signed output values are encoded as int8, matching the Flutter decoder.
  const uint8_t payload[6] = {
      robotState,
      static_cast<uint8_t>(static_cast<int8_t>(leftOutputPercent)),
      static_cast<uint8_t>(static_cast<int8_t>(rightOutputPercent)),
      requestedMode,
      static_cast<uint8_t>(droppedFrames & 0xFF),
      static_cast<uint8_t>((droppedFrames >> 8) & 0xFF),
  };
  writeFrame(TYPE_TELEMETRY, sequence, payload, sizeof(payload), viaBle);
}

void setMotor(uint8_t rpwm, uint8_t lpwm, int16_t percent) {
  percent = constrain(percent, -100, 100);
  const uint8_t duty = static_cast<uint8_t>(abs(percent) * 255 / 100);
  // Never drive RPWM and LPWM high simultaneously.
  if (percent > 0) {
    analogWrite(lpwm, 0);
    analogWrite(rpwm, duty);
  } else if (percent < 0) {
    analogWrite(rpwm, 0);
    analogWrite(lpwm, duty);
  } else {
    analogWrite(rpwm, 0);
    analogWrite(lpwm, 0);
  }
}

void stopMotors() {
  analogWrite(RIGHT_RPWM, 0);
  analogWrite(RIGHT_LPWM, 0);
  analogWrite(LEFT_RPWM, 0);
  analogWrite(LEFT_LPWM, 0);
  leftOutputPercent = 0;
  rightOutputPercent = 0;
}

void updateState() {
  if (estopLatched) {
    robotState = STATE_ESTOP;
  } else if (timedOut) {
    robotState = STATE_FAILSAFE;
  } else if (armed) {
    robotState = STATE_ARMED;
  } else {
    robotState = STATE_DISARMED;
  }
}

uint8_t modeCapPercent() {
  // App protocol: M1 torque cap, M2 standard cap, M3 boost/full cap.
  if (requestedMode == 1) return 45;
  if (requestedMode == 3) return 100;
  return 65;
}

void handleFrame(const uint8_t *frame, size_t size, bool viaBle = false) {
  if (size < 5 || frame[0] != SOF) {
    ++droppedFrames;
    return;
  }
  const uint8_t type = frame[1];
  const uint8_t sequence = frame[2];
  const uint8_t length = frame[3];
  if (size != static_cast<size_t>(5 + length) ||
      crc8(&frame[1], 3 + length) != frame[size - 1]) {
    ++droppedFrames;
    return;
  }

  if (!viaBle) {
    appAddress = udp.remoteIP();
    appPort = udp.remotePort();
    haveApp = true;
  }
  const uint8_t *payload = &frame[4];

  switch (type) {
    case TYPE_DRIVE: {
      if (length != 5) {
        ++droppedFrames;
        return;
      }
      const uint8_t flags = payload[0];
      const bool driveArmed = (flags & 0x01) != 0;
      const bool driveEStop = (flags & 0x02) != 0;
      const int16_t throttle = readI16LE(&payload[1]);
      const int16_t steering = readI16LE(&payload[3]);
      lastDriveMs = millis();
      timedOut = false;

      if (driveEStop) estopLatched = true;
      if (!driveArmed || estopLatched) armed = false;
      updateState();

      if (armed && !estopLatched) {
        // Positive steering is right: left wheel forward, right wheel reverse.
        int32_t left = static_cast<int32_t>(throttle) + steering;
        int32_t right = static_cast<int32_t>(throttle) - steering;
        const int32_t peak = max(abs(left), abs(right));
        if (peak > 1000) {
          left = left * 1000 / peak;
          right = right * 1000 / peak;
        }
        const int16_t cap = modeCapPercent();
        leftOutputPercent = static_cast<int16_t>(left * cap / 1000);
        rightOutputPercent = static_cast<int16_t>(right * cap / 1000);
        setMotor(LEFT_RPWM, LEFT_LPWM, leftOutputPercent);
        setMotor(RIGHT_RPWM, RIGHT_LPWM, rightOutputPercent);
      } else {
        stopMotors();
      }
      updateState();
      sendTelemetry(sequence, viaBle);
      break;
    }

    case TYPE_SET_MODE:
      if (length != 1 || payload[0] < 1 || payload[0] > 3) {
        ++droppedFrames;
        return;
      }
      requestedMode = payload[0];
      sendTelemetry(sequence, viaBle);
      break;

    case TYPE_ARM:
      if (length != 1 || payload[0] > 1) {
        ++droppedFrames;
        return;
      }
      if (payload[0] == 0) {
        armed = false;
        // Deliberate OFF is the app's E-stop recovery action.
        estopLatched = false;
        timedOut = false;
        stopMotors();
      } else if (!estopLatched && !timedOut &&
                 millis() - lastDriveMs <= DRIVE_TIMEOUT_MS) {
        armed = true;
      }
      updateState();
      sendTelemetry(sequence, viaBle);
      break;

    case TYPE_ESTOP:
      // The Flutter source explicitly encodes E-STOP with a zero-length body.
      if (length != 0) {
        ++droppedFrames;
        return;
      }
      estopLatched = true;
      armed = false;
      stopMotors();
      updateState();
      sendTelemetry(sequence, viaBle);
      break;

    case TYPE_HEARTBEAT:
      // Heartbeat is recognized, but does not extend the DRIVE watchdog.
      if (length != 0) {
        ++droppedFrames;
        return;
      }
      sendTelemetry(sequence, viaBle);
      break;

    default:
      ++droppedFrames;
      break;
  }
}

#if ESP_ARDUINO_VERSION_MAJOR >= 4
void onBleControlWrite(BLECharacteristic &characteristic, const BLEConnInfo &) {
  size_t length = 0;
  const uint8_t *value = characteristic.getValue(&length);
  if (value != nullptr && length > 0) {
    handleFrame(value, length, true);
  }
}
#else
class BleControlCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const std::string value = characteristic->getValue();
    if (!value.empty()) {
      handleFrame(reinterpret_cast<const uint8_t *>(value.data()), value.size(), true);
    }
  }
};

class BleServerCallbacks final : public BLEServerCallbacks {
  void onDisconnect(BLEServer *) override {
    BLEDevice::startAdvertising();
  }
};
#endif

void setup() {
  // Set outputs to zero as early as possible. GPIO14 is a boot-strapping pin
  // on some classic ESP32 boards; see the notes before connecting motor power.
  pinMode(RIGHT_RPWM, OUTPUT);
  pinMode(RIGHT_LPWM, OUTPUT);
  pinMode(LEFT_RPWM, OUTPUT);
  pinMode(LEFT_LPWM, OUTPUT);
  analogWriteResolution(RIGHT_RPWM, PWM_BITS);
  analogWriteResolution(RIGHT_LPWM, PWM_BITS);
  analogWriteResolution(LEFT_RPWM, PWM_BITS);
  analogWriteResolution(LEFT_LPWM, PWM_BITS);
  analogWriteFrequency(RIGHT_RPWM, PWM_HZ);
  analogWriteFrequency(RIGHT_LPWM, PWM_HZ);
  analogWriteFrequency(LEFT_RPWM, PWM_HZ);
  analogWriteFrequency(LEFT_LPWM, PWM_HZ);
  stopMotors();

  Serial.begin(115200);
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1),
                    IPAddress(255, 255, 255, 0));
  if (!WiFi.softAP(AP_SSID, AP_PASSWORD)) {
    Serial.println("ERROR: SoftAP start failed");
    return;
  }
  udp.begin(UDP_PORT);

#if ESP_ARDUINO_VERSION_MAJOR >= 4
  const BTStatus bleInitStatus = BLE.begin(BLE_DEVICE_NAME);
  if (!bleInitStatus) {
    Serial.printf("BLE init failed: %s\n", bleInitStatus.toString());
    return;
  }
  BLEServer bleServer = BLE.createServer();
  if (!bleServer) {
    Serial.println("BLE server creation failed");
    return;
  }
  bleServer.onDisconnect([](BLEServer &, const BLEConnInfo &, uint8_t) {
    Serial.println("BLE client disconnected; restarting advertising");
    BLE.startAdvertising();
  });
  bleServer.onConnect([](BLEServer &, const BLEConnInfo &) {
    Serial.println("BLE client connected");
  });
  BLEService bleService = bleServer.createService(BLEUUID(BLE_SERVICE_UUID));
  BLECharacteristic bleControlCharacteristic = bleService.createCharacteristic(
      BLEUUID(BLE_CONTROL_UUID), BLEProperty::Write | BLEProperty::WriteNR,
      BLEPermission::WriteOpen);
  bleControlCharacteristic.onWrite(onBleControlWrite);
  bleTelemetryCharacteristic = bleService.createCharacteristic(
      BLEUUID(BLE_TELEMETRY_UUID), BLEProperty::Notify, BLEPermission::None);
  if (!bleService || !bleControlCharacteristic || !bleTelemetryCharacteristic) {
    Serial.println("BLE GATT service/characteristic creation failed");
    return;
  }
  const BTStatus gattStartStatus = bleServer.start();
  if (!gattStartStatus) {
    Serial.printf("BLE GATT start failed: %s\n", gattStartStatus.toString());
    return;
  }

  BLEAdvertising advertising = BLE.getAdvertising();
  if (!advertising) {
    Serial.println("BLE advertising handle unavailable");
    return;
  }
  advertising.setName(BLE_DEVICE_NAME);
  advertising.addServiceUUID(BLEUUID(BLE_SERVICE_UUID));
  advertising.setScanResponse(true);
  const BTStatus advertisingStatus = advertising.start();
  if (!advertisingStatus) {
    Serial.printf("BLE advertising failed: %s\n", advertisingStatus.toString());
    return;
  }
#else
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer *bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new BleServerCallbacks());
  BLEService *bleService = bleServer->createService(BLE_SERVICE_UUID);
  BLECharacteristic *bleControlCharacteristic = bleService->createCharacteristic(
      BLE_CONTROL_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  bleControlCharacteristic->setCallbacks(new BleControlCallbacks());
  bleTelemetryCharacteristic = bleService->createCharacteristic(
      BLE_TELEMETRY_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  bleTelemetryCharacteristic->addDescriptor(new BLE2902());
  bleService->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
#endif

  robotState = STATE_DISARMED;
  Serial.printf("AP IP: %s\n", WiFi.softAPIP().toString().c_str());
  Serial.printf("RoboRace receiver ready: DISARMED, UDP %u\n", UDP_PORT);
  Serial.printf("BLE ready: %s\n", BLE_DEVICE_NAME);
}

void loop() {
  const int packetSize = udp.parsePacket();
  if (packetSize > 0) {
    uint8_t packet[64];
    if (packetSize > static_cast<int>(sizeof(packet))) {
      while (udp.available()) udp.read();
      ++droppedFrames;
    } else {
      const int bytesRead = udp.read(packet, sizeof(packet));
      if (bytesRead > 0) handleFrame(packet, static_cast<size_t>(bytesRead));
    }
  }

  if (armed && !timedOut && millis() - lastDriveMs > DRIVE_TIMEOUT_MS) {
    timedOut = true;
    armed = false;
    stopMotors();
    updateState();
    Serial.println("DRIVE watchdog: FAILSAFE, outputs stopped");
  }
  delay(1);
}

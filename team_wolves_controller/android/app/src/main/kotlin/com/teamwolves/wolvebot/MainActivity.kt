package com.teamwolves.wolvebot

import io.flutter.embedding.android.FlutterActivity

/**
 * Landscape-only host activity.
 *
 * Keep-screen-on is declared on the activity in the manifest
 * (android:keepScreenOn="true") so it applies from the first frame, before any
 * Dart code runs. No platform channels are used by the controller: the app
 * talks to the ESP32 over sockets and BLE only.
 */
class MainActivity : FlutterActivity()

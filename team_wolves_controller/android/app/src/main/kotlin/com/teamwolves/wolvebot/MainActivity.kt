package com.teamwolves.wolvebot

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Landscape-only host activity. The keep-screen-on flag is declared on the
 * activity in the manifest. BLE permissions are requested only when the user
 * starts a scan or connects to a peripheral.
 */
class MainActivity : FlutterActivity() {
    private val blePermissionRequestCode = 41321
    private var pendingBlePermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.teamwolves.wolvebot/ble_permissions",
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestBlePermissions") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (pendingBlePermissionResult != null) {
                result.error(
                    "permission_request_in_progress",
                    "A Bluetooth permission request is already in progress.",
                    null,
                )
                return@setMethodCallHandler
            }

            val missing = requiredBlePermissions().filter { permission ->
                ContextCompat.checkSelfPermission(this, permission) !=
                    PackageManager.PERMISSION_GRANTED
            }
            if (missing.isEmpty()) {
                result.success(true)
                return@setMethodCallHandler
            }

            pendingBlePermissionResult = result
            ActivityCompat.requestPermissions(
                this,
                missing.toTypedArray(),
                blePermissionRequestCode,
            )
        }
    }

    private fun requiredBlePermissions(): List<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        }

        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        return permissions
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != blePermissionRequestCode) {
            return
        }

        val result = pendingBlePermissionResult ?: return
        pendingBlePermissionResult = null
        val granted = requiredBlePermissions().all { permission ->
            ContextCompat.checkSelfPermission(this, permission) ==
                PackageManager.PERMISSION_GRANTED
        }
        result.success(granted)
    }
}

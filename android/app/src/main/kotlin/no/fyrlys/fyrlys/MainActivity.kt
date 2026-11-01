package no.fyrlys.fyrlys

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Det Fyrlys trenger fra Android (lib/core/android_host.dart): multicast-lås mens Chromecaster letes etter,
 * tjenesten som holder appen i gang mens telefonen sender strømmen videre til en Chromecast, installering av
 * oppdateringer, nettleseren og deling.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fyrlys/android").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "device" -> result.success(
                        "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}"
                    )
                    "multicast" -> {
                        multicast(call.arguments == true)
                        result.success(null)
                    }
                    "casting" -> {
                        casting(call.arguments as? String)
                        result.success(null)
                    }
                    "install" -> result.success(install(call.arguments as String))
                    "openUrl" -> {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)))
                        result.success(null)
                    }
                    "share" -> {
                        share(call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("feil", e.toString(), null)
            }
        }
    }

    override fun onDestroy() {
        multicast(false)
        super.onDestroy()
    }

    /** Wifi slipper bare gjennom multicast (svarene fra Chromecastene) når noen ber om det. */
    private fun multicast(on: Boolean) {
        if (on) {
            if (multicastLock == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val lock = wifi.createMulticastLock("fyrlys-chromecast")
                lock.setReferenceCounted(false)
                lock.acquire()
                multicastLock = lock
            }
        } else {
            multicastLock?.let { if (it.isHeld) it.release() }
            multicastLock = null
        }
    }

    /** Tjenesten med varselet [text] mens det castes; null stopper den. */
    private fun casting(text: String?) {
        val intent = Intent(this, CastService::class.java)
        if (text == null) {
            stopService(intent)
            return
        }
        // Android 13 og nyere: varselet vises bare med lov (tjenesten går uansett)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        intent.putExtra(CastService.EXTRA_TEXT, text)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    /**
     * Åpner Android sin installering av APK-en på [path] (i Fyrlys sin mappe «oppdatering»). Har ikke Fyrlys lov til
     * å installere apper, åpnes innstillingen for det, og svaret er false.
     */
    private fun install(path: String): Boolean {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return false
        }
        val file = ApkProvider.fileIn(this, File(path)) ?: return false
        val base = ApkProvider.base(this)
        val uri = Uri.Builder()
            .scheme("content")
            .authority("$packageName.oppdatering")
            .path(file.path.substring(base.path.length + 1))
            .build()
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, ApkProvider.APK)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun share(args: Map<*, *>) {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, args["text"] as? String ?: "")
            .putExtra(Intent.EXTRA_SUBJECT, args["subject"] as? String ?: "Fyrlys")
        startActivity(Intent.createChooser(send, null))
    }
}

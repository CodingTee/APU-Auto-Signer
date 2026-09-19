package com.apu.apu_auto_signer

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val cookiesChannel = "apu_auto_signer/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cookiesChannel)
            .setMethodCallHandler { call, result ->
                val cm = CookieManager.getInstance()
                // Make sure HttpOnly cookies are returned (Android 5.0+ already
                // returns them, but ensure cookie store is fully flushed first).
                cm.flush()
                when (call.method) {
                    "getCookiesForUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("BAD_ARG", "url required", null)
                            return@setMethodCallHandler
                        }
                        result.success(cm.getCookie(url) ?: "")
                    }
                    "getCookiesForUrls" -> {
                        val urls = call.argument<List<String>>("urls")
                        if (urls == null) {
                            result.error("BAD_ARG", "urls required", null)
                            return@setMethodCallHandler
                        }
                        val out = HashMap<String, String>()
                        for (u in urls) {
                            out[u] = cm.getCookie(u) ?: ""
                        }
                        result.success(out)
                    }
                    "clearCookies" -> {
                        // Android WebView cookies are stored in a singleton
                        // CookieManager, shared across every WebView in the
                        // app process. Wipe them so each Add Student flow
                        // gets a fresh auth.apu.edu.my session -- without
                        // this, a second student's login reuses the first
                        // student's (expired) session cookie and the /token
                        // POST returns 40143 "Login session expired".
                        cm.removeAllCookies(null)
                        cm.removeSessionCookies(null)
                        cm.flush()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
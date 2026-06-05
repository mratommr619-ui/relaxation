package com.mratom.relaxation

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "relaxation/android_telethon"
        ).setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<String, Any?> ?: emptyMap()
            executor.execute {
                try {
                    val module = Python.getInstance().getModule("android_telethon")
                    val pyResult = when (call.method) {
                        "status" -> module.callAttr("status", args)
                        "sendCode" -> module.callAttr("send_code", args)
                        "signIn" -> module.callAttr("sign_in", args)
                        "password" -> module.callAttr("password", args)
                        "resolve" -> module.callAttr("resolve", args)
                        else -> null
                    }
                    mainHandler.post {
                        if (pyResult == null) {
                            result.notImplemented()
                        } else {
                            result.success(pyResult.toString())
                        }
                    }
                } catch (error: Throwable) {
                    mainHandler.post {
                        result.error(
                            "ANDROID_TELETHON",
                            error.message ?: error.toString(),
                            null
                        )
                    }
                }
            }
        }
    }

}

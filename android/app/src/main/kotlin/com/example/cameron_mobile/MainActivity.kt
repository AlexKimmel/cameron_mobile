package com.example.cameron_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cameron/communication")
            .setMethodCallHandler { call, result ->
                val intent = when (call.method) {
                    "prepare_call" -> phoneIntent(call, Intent.ACTION_DIAL, "tel")
                    "draft_message" -> phoneIntent(call, Intent.ACTION_SENDTO, "smsto")
                        ?.putExtra("sms_body", call.argument<String>("body").orEmpty())
                    "draft_email" -> emailIntent(call)
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                if (intent == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }

                try {
                    startActivity(intent)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }

    private fun phoneIntent(call: MethodCall, action: String, scheme: String): Intent? {
        val phone = call.argument<String>("phone") ?: return null
        if (!phone.matches(Regex("\\+?[0-9]{3,15}"))) return null
        return Intent(action, Uri.fromParts(scheme, phone, null))
    }

    private fun emailIntent(call: MethodCall): Intent? {
        val email = call.argument<String>("email") ?: return null
        val body = call.argument<String>("body") ?: return null
        return Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
            .putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
            .putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject").orEmpty())
            .putExtra(Intent.EXTRA_TEXT, body)
    }
}

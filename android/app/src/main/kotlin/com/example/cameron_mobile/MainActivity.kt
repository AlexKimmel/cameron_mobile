package com.example.cameron_mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var calendarPermissionReply: MethodChannel.Result? = null

    private fun hasCalendarAccess(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cameron/calendar")
            .setMethodCallHandler(::handleCalendar)

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

    private fun handleCalendar(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(hasCalendarAccess())
            "requestAccess" -> {
                when {
                    hasCalendarAccess() -> result.success(true)
                    calendarPermissionReply != null ->
                        result.error("calendar_permission", "A calendar request is already open.", null)
                    else -> {
                        calendarPermissionReply = result
                        requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), CALENDAR_PERMISSION)
                    }
                }
            }
            "openSettings" -> {
                try {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("calendar_settings", "Could not open app settings.", null)
                }
            }
            "events" -> readCalendar(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALENDAR_PERMISSION) {
            val reply = calendarPermissionReply
            calendarPermissionReply = null
            reply?.success(hasCalendarAccess())
        }
    }

    private fun readCalendar(call: MethodCall, result: MethodChannel.Result) {
        if (!hasCalendarAccess()) {
            result.error("calendar_permission", "Calendar access is off.", null)
            return
        }
        val start = call.argument<Number>("start")?.toLong()
        val end = call.argument<Number>("end")?.toLong()
        val utcStart = call.argument<Number>("utcStart")?.toLong()
        val utcEnd = call.argument<Number>("utcEnd")?.toLong()
        if (start == null || end == null || utcStart == null || utcEnd == null ||
            end <= start || utcEnd <= utcStart ||
            maxOf(end, utcEnd) - minOf(start, utcStart) > 48 * 60 * 60 * 1000L
        ) {
            result.error("calendar_date", "Invalid calendar date.", null)
            return
        }

        Thread {
            try {
                val columns = arrayOf(
                    CalendarContract.Instances.TITLE,
                    CalendarContract.Instances.BEGIN,
                    CalendarContract.Instances.END,
                    CalendarContract.Instances.ALL_DAY,
                    CalendarContract.Instances.STATUS,
                )
                val events = mutableListOf<Map<String, Any>>()
                val cursor = CalendarContract.Instances.query(
                    contentResolver, columns, minOf(start, utcStart), maxOf(end, utcEnd),
                ) ?: error("Calendar provider unavailable")
                cursor.use {
                    while (it.moveToNext()) {
                        val begin = it.getLong(1)
                        val finish = it.getLong(2)
                        val allDay = it.getInt(3) != 0
                        if (it.getInt(4) == CalendarContract.Events.STATUS_CANCELED) continue
                        if (allDay && (begin >= utcEnd || finish <= utcStart)) continue
                        if (!allDay && (begin >= end || finish <= start)) continue
                        events.add(mapOf(
                            "title" to it.getString(0).orEmpty(),
                            "start" to begin,
                            "end" to finish,
                            "allDay" to allDay,
                        ))
                    }
                }
                runOnUiThread { result.success(events.sortedBy { it["start"] as Long }) }
            } catch (_: SecurityException) {
                runOnUiThread { result.error("calendar_permission", "Calendar access is off.", null) }
            } catch (_: RuntimeException) {
                runOnUiThread { result.error("calendar_read", "Could not read calendar events.", null) }
            }
        }.start()
    }

    companion object {
        private const val CALENDAR_PERMISSION = 1901
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

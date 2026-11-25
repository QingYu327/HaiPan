package cn.gdou.xiuhong

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/** 课表/考试本地通知：用 AlarmManager 定时 + Notification 展示 */
object NotificationHelper {
    // 换新通道：旧通道可能被系统记住为“静音/关闭”，删掉旧通道并重建，恢复默认高优先级
    const val CHANNEL_ID = "lesson_v2"
    const val CHANNEL_NAME = "上课/考试提醒"
    const val ACTION_LESSON = "cn.gdou.xiuhong.action.NOTIFY"
    private const val LEGACY_CHANNEL_ID = "lesson"
    private const val TAG = "HaipanNotify"

    private const val PREFS = "haipan_notify"
    private const val KEY_LESSONS = "lessons"
    private const val KEY_EXAMS = "exams"
    private const val KEY_LAST_AT = "last_fire_at"
    private const val KEY_LAST_TITLE = "last_fire_title"
    private const val KEY_LAST_ERROR = "last_error"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?: return
        try {
            nm.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        } catch (_: Exception) {
        }
        val ch = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "课程与考试时间提醒"
            enableVibration(true)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(ch)
    }

    fun notificationsEnabled(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun scheduleLessons(context: Context, items: List<Map<String, Any?>>) {
        cancelScheduled(context, KEY_LESSONS)
        saveItems(context, KEY_LESSONS, items)
        ensureChannel(context)
        scheduleItems(context, items)
    }

    fun scheduleExams(context: Context, items: List<Map<String, Any?>>) {
        cancelScheduled(context, KEY_EXAMS)
        saveItems(context, KEY_EXAMS, items)
        ensureChannel(context)
        scheduleItems(context, items)
    }

    /** 开机/更新/改时间后按持久化清单重建全部闹钟 */
    fun rescheduleAll(context: Context) {
        ensureChannel(context)
        scheduleItems(context, loadItems(context, KEY_LESSONS))
        scheduleItems(context, loadItems(context, KEY_EXAMS))
    }

    /** 调试用：delaySeconds 秒后走「闹钟 → 广播 → 通知」完整链路弹一条测试提醒 */
    fun scheduleTest(context: Context, delaySeconds: Int = 60) {
        ensureChannel(context)
        val at = System.currentTimeMillis() + delaySeconds * 1000L
        val ts = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date(at))
        val item = mapOf<String, Any?>(
            "id" to 902,
            "title" to "闹钟通道测试 · 海畔",
            "body" to "$delaySeconds 秒后（$ts）由系统闹钟触发",
            "at" to at,
            "page" to 0,
            "kind" to "test",
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        scheduleExact(am, at, pending(context, 902, item))
    }

    /** 是否未加入电池优化白名单（国产 ROM 后台限制常导致提醒不触发） */
    fun batteryRestricted(context: Context): Boolean {
        val pm = ContextCompat.getSystemService(context, android.os.PowerManager::class.java)
            ?: return false
        return !pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** 通知渠道重要度：0 表示被用户关闭，-1 表示渠道不存在 */
    fun channelImportance(context: Context): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return -1
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?: return -1
        return nm.getNotificationChannel(CHANNEL_ID)?.importance ?: -1
    }

    /** 最近一次弹通知失败的异常描述，供调试页展示 */
    fun lastError(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LAST_ERROR, "") ?: ""

    /** 退出登录/切换账号：取消全部提醒并清空持久化清单，避免旧账号提醒继续弹出 */
    fun cancelAll(context: Context) {
        cancelScheduled(context, KEY_LESSONS)
        cancelScheduled(context, KEY_EXAMS)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_LESSONS).remove(KEY_EXAMS).apply()
    }

    /** 已排提醒条数（课程 + 考试），供调试页诊断 */
    fun pendingCount(context: Context): Int =
        loadItems(context, KEY_LESSONS).size + loadItems(context, KEY_EXAMS).size

    /** 下一条提醒的触发时间（毫秒），没有则为 0 */
    fun nextAt(context: Context): Long {
        val now = System.currentTimeMillis()
        val all = loadItems(context, KEY_LESSONS) + loadItems(context, KEY_EXAMS)
        return all.asSequence()
            .mapNotNull { (it["at"] as? Number)?.toLong() }
            .filter { it > now }
            .minOrNull() ?: 0L
    }

    private fun scheduleItems(context: Context, items: List<Map<String, Any?>>) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = System.currentTimeMillis()
        for (item in items) {
            val id = (item["id"] as? Number)?.toInt() ?: continue
            val title = item["title"] as? String ?: continue
            val body = item["body"] as? String ?: ""
            val at = (item["at"] as? Number)?.toLong() ?: continue
            if (at <= now) continue
            scheduleExact(am, at, pending(context, id, item))
        }
    }

    /** 精确闹钟（有权限时）；无权限或受限时退回 allow-while-idle，至少不会丢提醒 */
    private fun scheduleExact(am: AlarmManager, at: Long, pi: PendingIntent) {
        // Android 13+ 由 USE_EXACT_ALARM 自动授予；未授予时 setAlarmClock 会直接抛
        // SecurityException，且非精确闹钟在深度休眠下可能一直推迟到 App 回前台，
        // 所以先判断权限，避免“只有 App 前台才收到提醒”。
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            am.canScheduleExactAlarms()
        if (!exact) {
            Log.w(TAG, "exact alarm not permitted, fallback to inexact at=$at")
            setAllowWhileIdle(am, at, pi)
            return
        }
        // 优先按"闹钟"排程：系统视为用户可见闹钟，不受 Doze/应用待机推迟，
        // 国产 ROM（MIUI 等）的后台限制下也比普通精确闹钟更容易准时触发。
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, null), pi)
            return
        } catch (t: Throwable) {
            Log.w(TAG, "setAlarmClock failed: ${t.javaClass.simpleName}")
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "setExact failed: ${t.javaClass.simpleName}")
            setAllowWhileIdle(am, at, pi)
        }
    }

    private fun setAllowWhileIdle(am: AlarmManager, at: Long, pi: PendingIntent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (_: Throwable) {
            try {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (_: Throwable) {
            }
        }
    }

    private fun pending(
        context: Context, id: Int, item: Map<String, Any?>
    ): PendingIntent {
        val intent = Intent(context, NotifyReceiver::class.java).apply {
            action = ACTION_LESSON
            putExtra("id", id)
            putExtra("title", item["title"] as? String ?: "")
            putExtra("body", item["body"] as? String ?: "")
            putExtra("page", (item["page"] as? Number)?.toInt() ?: 0)
            putExtra("kind", item["kind"] as? String ?: "")
            putExtra("name", item["name"] as? String ?: "")
            putExtra("weekday", (item["weekday"] as? Number)?.toInt() ?: 0)
            putExtra("startSection", (item["startSection"] as? Number)?.toInt() ?: 0)
            putExtra("week", (item["week"] as? Number)?.toInt() ?: 0)
            putExtra("time", item["time"] as? String ?: "")
            putExtra("room", item["room"] as? String ?: "")
        }
        return PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** 只取消上次清单里的 id，避免每次启动遍历 500 个 id 造成掉帧 */
    private fun cancelScheduled(context: Context, key: String) {
        val ids = loadItems(context, key)
            .mapNotNull { (it["id"] as? Number)?.toInt() }
            .distinct()
        if (ids.isEmpty()) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
        for (id in ids) {
            val i = Intent(context, NotifyReceiver::class.java).setAction(ACTION_LESSON)
            val pi = PendingIntent.getBroadcast(
                context, id, i,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: continue
            am.cancel(pi)
            pi.cancel()
            try {
                nm?.cancel(id)
            } catch (_: Exception) {
            }
        }
    }

    // ---------- 持久化：开机/应用更新后恢复闹钟 ----------

    private fun saveItems(context: Context, key: String, items: List<Map<String, Any?>>) {
        try {
            val arr = JSONArray()
            for (item in items) {
                val o = JSONObject()
                o.put("id", (item["id"] as? Number)?.toInt() ?: continue)
                o.put("title", item["title"] as? String ?: continue)
                o.put("body", item["body"] as? String ?: "")
                o.put("at", (item["at"] as? Number)?.toLong() ?: continue)
                o.put("page", (item["page"] as? Number)?.toInt() ?: 0)
                o.put("kind", item["kind"] as? String ?: "")
                o.put("name", item["name"] as? String ?: "")
                o.put("weekday", (item["weekday"] as? Number)?.toInt() ?: 0)
                o.put("startSection", (item["startSection"] as? Number)?.toInt() ?: 0)
                o.put("week", (item["week"] as? Number)?.toInt() ?: 0)
                o.put("time", item["time"] as? String ?: "")
                o.put("room", item["room"] as? String ?: "")
                arr.put(o)
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(key, arr.toString()).apply()
        } catch (_: Exception) {
        }
    }

    private fun loadItems(context: Context, key: String): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        try {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(key, null) ?: return out
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "id" to o.optInt("id"),
                        "title" to o.optString("title"),
                        "body" to o.optString("body"),
                        "at" to o.optLong("at"),
                        "page" to o.optInt("page"),
                        "kind" to o.optString("kind"),
                        "name" to o.optString("name"),
                        "weekday" to o.optInt("weekday"),
                        "startSection" to o.optInt("startSection"),
                        "week" to o.optInt("week"),
                        "time" to o.optString("time"),
                        "room" to o.optString("room"),
                    )
                )
            }
        } catch (_: Exception) {
        }
        return out
    }

    fun show(
        context: Context,
        id: Int,
        title: String,
        body: String,
        page: Int = 0,
        kind: String = "",
        name: String = "",
        weekday: Int = 0,
        startSection: Int = 0,
        week: Int = 0,
        time: String = "",
        room: String = "",
    ) {
        ensureChannel(context)
        // 点击通知拉起主界面，并携带目标 tab 与课程/考试标识，供 Flutter 直达详情
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            )
            putExtra("page", page)
            putExtra("id", id)
            putExtra("kind", kind)
            putExtra("name", name)
            putExtra("weekday", weekday)
            putExtra("startSection", startSection)
            putExtra("week", week)
            putExtra("time", time)
            putExtra("room", room)
        }
        val contentPi = PendingIntent.getActivity(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(contentPi)
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
            // 记录最近一次实际弹出，供 App 内「提醒诊断」确认系统确实触发过
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putLong(KEY_LAST_AT, System.currentTimeMillis())
                .putString(KEY_LAST_TITLE, title)
                .putString(KEY_LAST_ERROR, "")
                .apply()
            android.util.Log.i("HaipanNotify", "show id=$id kind=$kind $title")
        } catch (e: Exception) {
            android.util.Log.w("HaipanNotify", "show failed id=$id: $e")
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LAST_ERROR, e.toString())
                .apply()
        }
    }

    /** 最近一次实际弹出的通知（毫秒 + 标题），从未触发过为 0/空 */
    fun lastFire(context: Context): Pair<Long, String> {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return p.getLong(KEY_LAST_AT, 0L) to (p.getString(KEY_LAST_TITLE, "") ?: "")
    }
}

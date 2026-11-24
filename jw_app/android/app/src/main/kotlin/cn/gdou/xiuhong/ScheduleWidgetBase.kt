package cn.gdou.xiuhong

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 今日课表小组件基类。
 *
 * 两个子类共用同一套布局与渲染逻辑：
 * - [TodayWidgetProvider]：课表 + 考试倒计时（完整信息）
 * - [ScheduleOnlyWidgetProvider]：仅课表，不显示考试
 *
 * 字号、内边距与可见行数都按桌面实际给的尺寸（OPTION_APPWIDGET_MIN_WIDTH /
 * MIN_HEIGHT，单位 dp）实时计算，因此在 2x2、4x3、4x5 等不同空余空间里
 * 都能自动放大或收缩，尽量把当天课程完整显示出来。
 *
 * 数据由 Flutter 侧（HomeWidgetSync）写入 FlutterSharedPreferences 的
 * `flutter.widget.payload`，这里只负责按当前时间筛选并渲染，
 * 因此不打开 App 也能在跨天后通过 updatePeriodMillis 自动刷新。
 */
abstract class ScheduleWidgetBase : AppWidgetProvider() {

    /** 是否展示考试倒计时区块 */
    protected abstract val withExam: Boolean

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, appWidgetManager, id))
        }
    }

    /** 用户拖动改变组件大小后立即按新尺寸重排 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, build(context, appWidgetManager, appWidgetId))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_REFRESH) return
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
        for (id in ids) manager.updateAppWidget(id, build(context, manager, id))
    }

    private fun openIntent(context: Context, page: Int, code: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("page", page)
        }
        return PendingIntent.getActivity(
            context, code, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun build(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setOnClickPendingIntent(R.id.widget_root, openIntent(context, 0, 8801))
        views.setOnClickPendingIntent(R.id.exam_section, openIntent(context, 2, 8802))
        views.setOnClickPendingIntent(R.id.tv_exam, openIntent(context, 2, 8802))
        views.setOnClickPendingIntent(R.id.tv_exam_sub, openIntent(context, 2, 8802))
        views.setOnClickPendingIntent(R.id.tv_exam2, openIntent(context, 2, 8802))
        views.setOnClickPendingIntent(R.id.tv_tomorrow, openIntent(context, 0, 8801))

        val (widthDp, heightDp) = widgetSize(context, manager, widgetId)
        val m = metrics(widthDp)
        // RemoteViews 的 padding 单位是像素，这里把 dp 排版参数换算过去
        val density = context.resources.displayMetrics.density
        fun px(value: Int): Int = (value * density).toInt()

        // 整体排版参数
        views.setViewPadding(
            R.id.widget_root, px(m.padH), px(m.padV), px(m.padH), px(m.padV)
        )
        views.setTextViewTextSize(R.id.tv_title, SP, m.title)
        views.setTextViewTextSize(R.id.tv_meta, SP, m.meta)

        val payload = loadPayload(context)
        val cal = Calendar.getInstance()
        val weekday = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1 // 周一=1 … 周日=7
        val dayNames = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
        val weekLabel = payload?.let { weekOf(it) } ?: 0
        val date = "${cal.get(Calendar.MONTH) + 1}/${cal.get(Calendar.DAY_OF_MONTH)}"
        views.setTextViewText(R.id.tv_title, "今日课表")
        views.setTextViewText(
            R.id.tv_meta,
            if (weekLabel > 0) "第${weekLabel}周 · $date ${dayNames[weekday - 1]}"
            else "$date ${dayNames[weekday - 1]}"
        )

        // 明天的课与之后要考的试，用于填充空余高度
        val courses = payload?.let { coursesFor(it, weekday, weekLabel) } ?: emptyList()
        val tomorrowWeekday = if (weekday == 7) 1 else weekday + 1
        val tomorrowWeek = if (weekday == 7) weekLabel + 1 else weekLabel
        val tomorrow = payload?.let { coursesFor(it, tomorrowWeekday, tomorrowWeek) } ?: emptyList()
        val exams = payload?.let { upcomingExams(it) } ?: emptyList()

        // 高度预算（dp 近似）：先按一行考试估算可见课程行数
        val headerH = m.title * 1.35f + 6f
        val rowH = m.name * 1.22f + m.room * 1.18f + m.gap * 2f + 1f
        val moreH = m.meta * 1.45f + 2f
        val extraH = m.meta * 1.45f + 4f
        val examH = if (withExam) {
            m.examLabel * 1.3f + m.exam * 1.4f + m.examSub * 1.25f + 14f
        } else 0f
        val avail = heightDp - m.padV * 2f - headerH - examH - 4f

        var rows = (avail / rowH).toInt().coerceIn(1, MAX_ROWS)
        if (courses.isNotEmpty() && courses.size > rows) {
            rows = ((avail - moreH) / rowH).toInt().coerceIn(1, MAX_ROWS)
        }
        val visible = courses.size.coerceAtMost(rows)
        val overflow = courses.size > visible
        var rest = avail - visible * rowH - if (overflow) moreH else 0f

        // 空余区域依次补充：明天第一门课 → 下一场考试
        val showTomorrow = rest >= extraH
        if (showTomorrow) rest -= extraH
        val showExam2 = withExam && exams.size >= 2 && rest >= extraH

        // 考试区块：仅「完整」组件显示
        views.setViewVisibility(R.id.exam_section, if (withExam) View.VISIBLE else View.GONE)
        if (withExam) {
            views.setTextViewTextSize(R.id.tv_exam_label, SP, m.examLabel)
            views.setTextViewTextSize(R.id.tv_exam, SP, m.exam)
            views.setTextViewTextSize(R.id.tv_exam_sub, SP, m.examSub)
            views.setTextViewTextSize(R.id.tv_exam2, SP, m.room)
            bindExam(views, exams, showExam2)
        }

        for (i in 0 until MAX_ROWS) {
            if (i >= visible) {
                views.setViewVisibility(ROW_IDS[i], View.GONE)
                continue
            }
            val c = courses[i]
            views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
            views.setViewPadding(ROW_IDS[i], 0, px(m.gap), 0, px(m.gap))
            views.setTextViewTextSize(TIME_IDS[i], SP, m.time)
            views.setTextViewTextSize(NAME_IDS[i], SP, m.name)
            views.setTextViewTextSize(ROOM_IDS[i], SP, m.room)
            views.setTextViewText(NAME_IDS[i], c.optString("n"))

            val time = startTime(c.optInt("s"))
            val room = c.optString("r")
            if (m.showTime) {
                views.setViewVisibility(TIME_IDS[i], View.VISIBLE)
                views.setTextViewText(TIME_IDS[i], time)
                views.setTextViewText(ROOM_IDS[i], room)
            } else {
                // 窄组件把时间并入地点一行，把整行宽度留给课程名
                views.setViewVisibility(TIME_IDS[i], View.GONE)
                views.setTextViewText(
                    ROOM_IDS[i],
                    if (room.isEmpty()) time else "$time · $room"
                )
            }
            views.setViewVisibility(
                ROOM_IDS[i], if (room.isEmpty() && m.showTime) View.GONE else View.VISIBLE
            )
        }

        views.setTextViewTextSize(R.id.tv_empty, SP, m.name)
        views.setViewVisibility(
            R.id.tv_empty,
            if (courses.isEmpty()) View.VISIBLE else View.GONE
        )

        views.setTextViewTextSize(R.id.tv_more, SP, m.meta)
        if (overflow) {
            views.setViewVisibility(R.id.tv_more, View.VISIBLE)
            views.setTextViewText(
                R.id.tv_more, "还有 ${courses.size - visible} 门课 · 点开查看"
            )
        } else {
            views.setViewVisibility(R.id.tv_more, View.GONE)
        }

        views.setTextViewTextSize(R.id.tv_tomorrow, SP, m.room)
        if (showTomorrow) {
            val text = if (tomorrow.isEmpty()) {
                "明天无课"
            } else {
                val first = tomorrow.first()
                val extra = if (tomorrow.size > 1) " 等${tomorrow.size}门" else ""
                "明天 ${startTime(first.optInt("s"))} ${first.optString("n")}$extra"
            }
            views.setTextViewText(R.id.tv_tomorrow, text)
            views.setViewVisibility(R.id.tv_tomorrow, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.tv_tomorrow, View.GONE)
        }
        return views
    }

    private fun bindExam(views: RemoteViews, exams: List<JSONObject>, showSecond: Boolean) {
        val exam = exams.firstOrNull()
        if (exam == null) {
            views.setTextViewText(R.id.tv_exam, "暂无考试安排")
            views.setTextViewText(R.id.tv_exam_sub, "")
            views.setViewVisibility(R.id.tv_exam2, View.GONE)
            return
        }
        val at = exam.optLong("at")
        val days = daysLeft(at)
        val whenText = when {
            days < 0 -> "已结束"
            days == 0 -> "今天"
            else -> "$days 天后"
        }
        views.setTextViewText(R.id.tv_exam, "${exam.optString("n")} · $whenText")
        val c = Calendar.getInstance().apply { timeInMillis = at }
        val hm = String.format(
            "%02d:%02d",
            c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE)
        )
        val place = exam.optString("p")
        views.setTextViewText(
            R.id.tv_exam_sub,
            "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日 $hm" +
                if (place.isEmpty()) "" else " · $place"
        )

        val second = if (showSecond) exams.getOrNull(1) else null
        if (second == null) {
            views.setViewVisibility(R.id.tv_exam2, View.GONE)
        } else {
            val c2 = Calendar.getInstance().apply { timeInMillis = second.optLong("at") }
            val hm2 = String.format(
                "%02d:%02d",
                c2.get(Calendar.HOUR_OF_DAY), c2.get(Calendar.MINUTE)
            )
            views.setTextViewText(
                R.id.tv_exam2,
                "下一场 ${c2.get(Calendar.MONTH) + 1}月${c2.get(Calendar.DAY_OF_MONTH)}日 " +
                    "$hm2 ${second.optString("n")}"
            )
            views.setViewVisibility(R.id.tv_exam2, View.VISIBLE)
        }
    }

    /** 桌面实际分配尺寸（dp），个别桌面拿不到时退回 provider 的最小尺寸 */
    private fun widgetSize(context: Context, manager: AppWidgetManager, widgetId: Int): Pair<Int, Int> {
        val options = manager.getAppWidgetOptions(widgetId)
        val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        // 竖屏时当前宽度取 minWidth、当前高度取 maxHeight（横屏相反）
        val portrait = context.resources.configuration.orientation ==
            android.content.res.Configuration.ORIENTATION_PORTRAIT
        var w = if (portrait) minW else maxW
        var h = if (portrait) maxH else minH
        if (w <= 0) w = if (portrait) maxW else minW
        if (h <= 0) h = if (portrait) minH else maxH
        if (w <= 0 || h <= 0) {
            val info = manager.getAppWidgetInfo(widgetId)
            if (info != null) {
                if (w <= 0) w = info.minWidth
                if (h <= 0) h = info.minHeight
            }
        }
        if (w <= 0) w = 250
        if (h <= 0) h = 180
        return w to h
    }

    /**
     * 三档字号：只由宽度（列数）决定，保证同宽的「仅课表」与「课表 + 考试」字号完全一致；
     * 高度只影响能显示多少行、是否补充明天与下一场考试。
     */
    private fun metrics(widthDp: Int): M {
        return when {
            widthDp < 210 -> M(
                title = 14f, meta = 10.5f, time = 11f, name = 14f, room = 10.5f,
                examLabel = 10.5f, exam = 13f, examSub = 10.5f,
                padH = 12, padV = 10, gap = 2, showTime = widthDp >= 190
            )
            widthDp >= 420 -> M(
                title = 18f, meta = 13.5f, time = 14f, name = 18.5f, room = 13.5f,
                examLabel = 13f, exam = 17f, examSub = 13.5f,
                padH = 18, padV = 14, gap = 5, showTime = true
            )
            else -> M(
                title = 15f, meta = 12f, time = 12f, name = 15.5f, room = 12f,
                examLabel = 12f, exam = 14.5f, examSub = 12f,
                padH = 16, padV = 12, gap = 3, showTime = true
            )
        }
    }

    private fun loadPayload(context: Context): JSONObject? {
        val sp = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val raw = sp.getString("flutter.widget.payload", null) ?: return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    /** 当前周次 = 快照周次 + 距快照周一经过的周数 */
    private fun weekOf(payload: JSONObject): Int {
        val base = payload.optInt("week", 0)
        val monday = payload.optLong("monday", 0L)
        if (base <= 0 || monday <= 0L) return base
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val days = ((today.timeInMillis - monday) / 86400000L).toInt()
        return base + (if (days > 0) days / 7 else 0)
    }

    /** 指定星期与周次的课程，按节次升序 */
    private fun coursesFor(
        payload: JSONObject,
        weekday: Int,
        week: Int
    ): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        val arr = payload.optJSONArray("courses") ?: JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optInt("w") != weekday) continue
            val ws = o.optJSONArray("ws")
            if (ws != null && ws.length() > 0 && week > 0) {
                var hit = false
                for (j in 0 until ws.length()) {
                    if (ws.optInt(j) == week) {
                        hit = true
                        break
                    }
                }
                if (!hit) continue
            }
            out.add(o)
        }
        out.sortBy { it.optInt("s") }
        return out
    }

    /** 未结束的考试，按时间升序（第一场给主展示，第二场填补充信息） */
    private fun upcomingExams(payload: JSONObject): List<JSONObject> {
        val arr = payload.optJSONArray("exams") ?: return emptyList()
        val now = System.currentTimeMillis()
        val out = mutableListOf<JSONObject>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val at = o.optLong("at", 0L)
            if (at <= 0L) continue
            if (at + 2 * 60 * 60 * 1000L < now) continue // 结束超过 2 小时不再展示
            out.add(o)
        }
        out.sortBy { it.optLong("at") }
        return out
    }

    private fun daysLeft(at: Long): Int {
        val exam = Calendar.getInstance().apply {
            timeInMillis = at
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return ((exam.timeInMillis - today.timeInMillis) / 86400000L).toInt()
    }

    private fun startTime(section: Int): String = when (section) {
        1, 2 -> "08:10"
        3, 4 -> "10:15"
        5, 6 -> "14:30"
        7, 8 -> "16:30"
        9, 10 -> "19:30"
        11, 12 -> "21:00"
        else -> ""
    }

    /** 一组排版参数（字号单位 sp，间距单位 dp） */
    private class M(
        val title: Float,
        val meta: Float,
        val time: Float,
        val name: Float,
        val room: Float,
        val examLabel: Float,
        val exam: Float,
        val examSub: Float,
        val padH: Int,
        val padV: Int,
        val gap: Int,
        val showTime: Boolean
    )

    companion object {
        const val ACTION_REFRESH = "cn.gdou.xiuhong.widget.REFRESH"

        private const val MAX_ROWS = 8
        private const val SP = TypedValue.COMPLEX_UNIT_SP

        private val ROW_IDS = intArrayOf(
            R.id.row1, R.id.row2, R.id.row3, R.id.row4,
            R.id.row5, R.id.row6, R.id.row7, R.id.row8
        )
        private val TIME_IDS = intArrayOf(
            R.id.time1, R.id.time2, R.id.time3, R.id.time4,
            R.id.time5, R.id.time6, R.id.time7, R.id.time8
        )
        private val NAME_IDS = intArrayOf(
            R.id.name1, R.id.name2, R.id.name3, R.id.name4,
            R.id.name5, R.id.name6, R.id.name7, R.id.name8
        )
        private val ROOM_IDS = intArrayOf(
            R.id.room1, R.id.room2, R.id.room3, R.id.room4,
            R.id.room5, R.id.room6, R.id.room7, R.id.room8
        )

        /** 由 Flutter 调用：数据更新后主动刷新所有小组件 */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (cls in arrayOf(
                TodayWidgetProvider::class.java,
                ScheduleOnlyWidgetProvider::class.java
            )) {
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) continue
                val intent = Intent(context, cls).apply {
                    action = ACTION_REFRESH
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }

        /** 通过长按图标快捷方式请求把「课表 + 考试」组件固定到桌面（API 26+）。
         *  桌面不支持时回调 [onManual]，由界面引导手动添加。 */
        fun requestPin(activity: android.app.Activity, onManual: () -> Unit) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                onManual()
                return
            }
            // MIUI/HyperOS 桌面虽然声称支持 requestPinAppWidget，但调用后只会回到桌面，
            // 既不弹确认框也不会真正添加组件，因此直接给出手动引导。
            val brand = (Build.MANUFACTURER + Build.BRAND).lowercase()
            if (brand.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco")) {
                android.util.Log.i("HaipanWidget", "requestPin miui=true -> manual")
                onManual()
                return
            }
            val manager = AppWidgetManager.getInstance(activity)
            val supported = manager.isRequestPinAppWidgetSupported
            android.util.Log.i("HaipanWidget", "requestPin supported=$supported")
            if (!supported) {
                onManual()
                return
            }
            val ok = try {
                manager.requestPinAppWidget(
                    ComponentName(activity, TodayWidgetProvider::class.java),
                    null,
                    null
                )
            } catch (e: Exception) {
                android.util.Log.w("HaipanWidget", "requestPin failed", e)
                false
            }
            android.util.Log.i("HaipanWidget", "requestPin result=$ok")
            if (!ok) {
                onManual()
                return
            }
            // 部分桌面（如 MIUI）会返回成功但不弹任何界面：
            // 短暂等待后若 Activity 仍持有焦点，说明系统确认框没有出现，改用手动引导。
            activity.window.decorView.postDelayed({
                if (activity.isFinishing) return@postDelayed
                if (!activity.hasWindowFocus()) return@postDelayed
                onManual()
            }, 1500)
        }
    }
}

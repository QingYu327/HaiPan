package cn.gdou.xiuhong

import android.app.Activity

/**
 * 桌面小组件：今日课表 + 考试倒计时（完整信息）。
 *
 * 渲染逻辑见 [ScheduleWidgetBase]，会按桌面空余尺寸自动调整字号与行数。
 */
class TodayWidgetProvider : ScheduleWidgetBase() {

    override val withExam: Boolean = true

    companion object {
        /** 长按图标快捷方式固定小组件时默认添加「课表 + 考试」 */
        fun requestPin(activity: Activity, onManual: () -> Unit) =
            ScheduleWidgetBase.requestPin(activity, onManual)
    }
}

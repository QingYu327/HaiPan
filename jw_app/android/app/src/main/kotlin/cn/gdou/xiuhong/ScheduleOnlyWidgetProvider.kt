package cn.gdou.xiuhong

/**
 * 桌面小组件：仅今日课表（不含考试区块）。
 *
 * 课程区域会把省下来的高度全部用来显示课程，同样随桌面尺寸自适应字号与行数。
 */
class ScheduleOnlyWidgetProvider : ScheduleWidgetBase() {

    override val withExam: Boolean = false
}

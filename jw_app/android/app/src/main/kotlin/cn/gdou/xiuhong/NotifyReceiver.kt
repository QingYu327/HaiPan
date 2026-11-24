package cn.gdou.xiuhong

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 定时到点后收到系统广播，弹出通知 */
class NotifyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title").orEmpty()
        val body = intent.getStringExtra("body").orEmpty()
        val page = intent.getIntExtra("page", 0)
        val kind = intent.getStringExtra("kind").orEmpty()
        val name = intent.getStringExtra("name").orEmpty()
        val weekday = intent.getIntExtra("weekday", 0)
        val startSection = intent.getIntExtra("startSection", 0)
        val week = intent.getIntExtra("week", 0)
        val time = intent.getStringExtra("time").orEmpty()
        val room = intent.getStringExtra("room").orEmpty()
        if (title.isEmpty()) return
        android.util.Log.i(
            "HaipanNotify",
            "fire id=$id kind=$kind name=$name title=$title"
        )
        NotificationHelper.show(
            context.applicationContext, id, title, body, page,
            kind, name, weekday, startSection, week, time, room
        )
    }
}

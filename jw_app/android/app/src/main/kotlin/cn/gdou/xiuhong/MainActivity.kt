package cn.gdou.xiuhong

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    // 通知排程放到单线程后台执行，避免启动时主线程卡顿
    private val notifyExecutor = Executors.newSingleThreadExecutor()
    private var pendingPinWidget = false
    // Flutter 侧导航通道：既接收 Dart 调用，也主动请求 Dart 展示引导弹窗
    private var navChannel: MethodChannel? = null
    private var pendingGuide = false
    // 首次启动「一键授权」流程的返回回调（通知 → 精确闹钟 → 电池优化 → MIUI 自启动）
    private var pendingPermResult: MethodChannel.Result? = null

    override fun onResume() {
        super.onResume()
        cleanupPendingApk()
        // 等界面恢复后再请求固定小组件，避免在 onCreate 阶段被系统拒绝
        if (pendingPinWidget) {
            pendingPinWidget = false
            window.decorView.post {
                TodayWidgetProvider.requestPin(this) { showPinGuide() }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        maybePinWidget(intent)
    }

    // 通知点击携带新 intent（含 page），供 Flutter 读取并切换对应 tab
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybePinWidget(intent)
    }

    /** 长按图标「添加小组件」快捷方式：请求系统弹出固定小组件确认框 */
    private fun maybePinWidget(i: Intent?) {
        val want = i?.getBooleanExtra("pinWidget", false) ?: false
        if (!want) return
        i?.removeExtra("pinWidget")
        pendingPinWidget = true
    }

    /** 桌面不支持一键固定：请 Flutter 展示与 App 视觉一致的引导弹窗 */
    private fun showPinGuide() {
        if (isFinishing) return
        val ch = navChannel
        if (ch == null) {
            pendingGuide = true
            return
        }
        invokeWidgetGuide(ch, 0)
    }

    private fun invokeWidgetGuide(ch: MethodChannel, attempt: Int) {
        ch.invokeMethod("showWidgetGuide", null, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) {
                retryWidgetGuide(ch, attempt)
            }
            override fun notImplemented() {
                retryWidgetGuide(ch, attempt)
            }
        })
    }

    private fun retryWidgetGuide(ch: MethodChannel, attempt: Int) {
        if (attempt >= 12) {
            // Flutter 侧迟迟未就绪时退回原生弹窗，保证用户始终能看到明确引导
            runOnUiThread { showPinGuideFallback() }
            return
        }
        window.decorView.postDelayed({ invokeWidgetGuide(ch, attempt + 1) }, 250)
    }

    private fun showPinGuideFallback() {
        if (isFinishing) return
        val ctx = android.view.ContextThemeWrapper(
            this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        )
        android.app.AlertDialog.Builder(ctx)
            .setTitle("添加「海畔」桌面小组件")
            .setMessage(
                "当前桌面不支持一键添加，请手动操作：\n\n" +
                    "1. 回到桌面，长按空白处\n" +
                    "2. 点「小组件」或「添加工具」\n" +
                    "3. 找到「海畔」\n" +
                    "4. 选择「今日课表」或「课表 + 考试」拖到桌面"
            )
            .setNegativeButton("取消", null)
            .setPositiveButton("回到桌面") { _, _ -> moveTaskToBack(true) }
            .show()
    }

    // 安装完成返回时自动清除更新包（若进程被重启，首次 onResume 也会清理）
    private fun cleanupPendingApk() {
        try {
            val sp = getSharedPreferences("haipan_cache", MODE_PRIVATE)
            val path = sp.getString("pending_delete_apk", null) ?: return
            sp.edit().remove("pending_delete_apk").apply()
            val f = File(path)
            if (f.exists()) f.delete()
        } catch (_: Exception) {}
    }

    // ---------- 设备认证：Android Keystore EC 密钥（私钥不可导出）----------
    // 首次生成 P-256 密钥对并常驻 Keystore；公钥上送服务端，签名在安全硬件内完成，
    // 即使反编译 APK 也拿不到可用于伪造请求的密钥。
    private fun authKeyPair(): KeyPair {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(AUTH_ALIAS)) {
            val kpg = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            kpg.initialize(
                KeyGenParameterSpec.Builder(
                    AUTH_ALIAS,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build()
            )
            kpg.generateKeyPair()
        }
        val pub = ks.getCertificate(AUTH_ALIAS).publicKey
        val priv = ks.getKey(AUTH_ALIAS, null) as java.security.PrivateKey
        return KeyPair(pub, priv)
    }

    // ---------- 安全存储：Android Keystore AES-GCM ----------
    private val secureKey: SecretKey? by lazy {
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val alias = "haipan_secure_key"
            if (!ks.containsAlias(alias)) {
                val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                kg.init(
                    KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build()
                )
                kg.generateKey()
            }
            (ks.getKey(alias, null) as? SecretKey)
        } catch (_: Exception) { null }
    }

    private fun encryptSecure(plain: String): String {
        val key = secureKey ?: return ""
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
            val body = ByteArray(12 + ct.size)
            System.arraycopy(iv, 0, body, 0, iv.size)
            System.arraycopy(ct, 0, body, iv.size, ct.size)
            Base64.encodeToString(body, Base64.NO_WRAP)
        } catch (_: Exception) { "" }
    }

    private fun decryptSecure(enc: String): String {
        val key = secureKey ?: return ""
        return try {
            val body = Base64.decode(enc, Base64.NO_WRAP)
            val iv = body.copyOfRange(0, 12)
            val ct = body.copyOfRange(12, body.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            String(cipher.doFinal(ct), Charsets.UTF_8)
        } catch (_: Exception) { "" }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // 通知跳转：返回当前 intent 携带的 tab 页码（0课表/1成绩/2考试/3学业/4我的）；无则 -1
        val nav = MethodChannel(messenger, "cn.gdou.xiuhong/nav")
        navChannel = nav
        nav.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchPage" -> {
                        // 读取后清除，避免每次 resume 都重复跳到同一个 tab
                        val page = intent?.getIntExtra("page", -1) ?: -1
                        intent?.removeExtra("page")
                        result.success(page)
                    }
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "getLaunchTarget" -> {
                        val i = intent
                        if (i == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val page = i.getIntExtra("page", -1)
                        val kind = i.getStringExtra("kind").orEmpty()
                        if (page < 0 && kind.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val target = mapOf(
                            "id" to i.getIntExtra("id", 0),
                            "page" to page.coerceAtLeast(0),
                            "kind" to kind,
                            "name" to i.getStringExtra("name").orEmpty(),
                            "weekday" to i.getIntExtra("weekday", 0),
                            "startSection" to i.getIntExtra("startSection", 0),
                            "week" to i.getIntExtra("week", 0),
                            "time" to i.getStringExtra("time").orEmpty(),
                            "room" to i.getStringExtra("room").orEmpty(),
                        )
                        for (k in listOf(
                            "page", "id", "kind", "name", "weekday",
                            "startSection", "week", "time", "room"
                        )) {
                            i.removeExtra(k)
                        }
                        result.success(target)
                    }
                    else -> result.notImplemented()
                }
            }
        if (pendingGuide) {
            pendingGuide = false
            showPinGuide()
        }
        // 设备认证：公钥导出 + 挑战签名（私钥始终留在 Keystore）
        MethodChannel(messenger, "cn.gdou.xiuhong/auth")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "publicKey" -> {
                            val pub = authKeyPair().public.encoded
                            result.success(Base64.encodeToString(pub, Base64.NO_WRAP))
                        }
                        "sign" -> {
                            val data = call.argument<String>("data") ?: ""
                            val sig = Signature.getInstance("SHA256withECDSA")
                            sig.initSign(authKeyPair().private)
                            sig.update(data.toByteArray(Charsets.UTF_8))
                            result.success(
                                Base64.encodeToString(sig.sign(), Base64.NO_WRAP))
                        }
                        "reset" -> {
                            val ks = KeyStore.getInstance("AndroidKeyStore")
                                .apply { load(null) }
                            if (ks.containsAlias(AUTH_ALIAS)) ks.deleteEntry(AUTH_ALIAS)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("AUTH_ERR", e.message, null)
                }
            }
        // 校外通道：让 WebView 走本地隧道代理（仅影响本应用的 WebView）
        MethodChannel(messenger, "cn.gdou.xiuhong/proxy")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "setProxy" -> {
                            val host = call.argument<String>("host") ?: "127.0.0.1"
                            val port = call.argument<Int>("port") ?: 0
                            if (port <= 0) {
                                result.error("PROXY_ERR", "invalid port", null)
                            } else {
                                // 反向 bypass：只有 jw 走本地隧道。
                                // wfw 反代的登录页里仍有指向 authserver 的绝对链接
                                // （如「账号密码登录 / 手机验证码登录」标签），
                                // 个别运营商直连 authserver 会被拒，这里一并交给隧道。
                                val config = ProxyConfig.Builder()
                                    .addProxyRule("$host:$port")
                                    .addBypassRule("jw.gdou.edu.cn")
                                    .addBypassRule("authserver.gdou.edu.cn")
                                    .setReverseBypassEnabled(true)
                                    .build()
                                ProxyController.getInstance().setProxyOverride(
                                    config, Executors.newSingleThreadExecutor()
                                ) { runOnUiThread { result.success(true) } }
                            }
                        }
                        "clearProxy" -> {
                            ProxyController.getInstance().clearProxyOverride(
                                Executors.newSingleThreadExecutor()
                            ) { runOnUiThread { result.success(true) } }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("PROXY_ERR", e.message, null)
                }
            }
        // 网络类型：登录页据此决定“移动数据直接走校外通道 / Wi-Fi 先试直连”
        MethodChannel(messenger, "cn.gdou.xiuhong/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "networkType" -> {
                        try {
                            @Suppress("DEPRECATION")
                            val info = (getSystemService(CONNECTIVITY_SERVICE)
                                as android.net.ConnectivityManager).activeNetworkInfo
                            val type = when {
                                info == null || !info.isConnected -> "none"
                                info.type == android.net.ConnectivityManager.TYPE_WIFI -> "wifi"
                                info.type == android.net.ConnectivityManager.TYPE_MOBILE -> "cellular"
                                info.type == android.net.ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                                else -> "other"
                            }
                            result.success(type)
                        } catch (e: Exception) {
                            result.error("NET_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 应用信息：读取安装包 versionName / versionCode（关于页展示构建版本号）
        MethodChannel(messenger, "cn.gdou.xiuhong/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> {
                        try {
                            @Suppress("DEPRECATION")
                            val p = packageManager.getPackageInfo(packageName, 0)
                            val code = if (android.os.Build.VERSION.SDK_INT >= 28) {
                                p.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                p.versionCode.toLong()
                            }
                            result.success(
                                mapOf(
                                    "version" to (p.versionName ?: ""),
                                    "build" to code.toString()
                                )
                            )
                        } catch (e: Exception) {
                            result.error("APPINFO_ERR", e.message, null)
                        }
                    }
                    // 意见反馈：调起系统邮件客户端（收件人/主题/正文由 Flutter 拼进 mailto）
                    "openMailto" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        try {
                            startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse(uri)))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    // 意见反馈：导出日志作为附件，调起邮件客户端
                    "sendFeedbackMail" -> {
                        val to = call.argument<String>("to") ?: ""
                        val subject = call.argument<String>("subject") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        val logPath = call.argument<String>("path") ?: ""
                        try {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "message/rfc822"
                                putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                                putExtra(Intent.EXTRA_TEXT, body)
                                val log = File(logPath)
                                if (log.exists()) {
                                    putExtra(
                                        Intent.EXTRA_STREAM,
                                        FileProvider.getUriForFile(
                                            this@MainActivity,
                                            "$packageName.fileprovider",
                                            log
                                        )
                                    )
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            }
                            startActivity(Intent.createChooser(intent, "发送反馈"))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 桌面小组件刷新：Flutter 写入数据后通知原生重绘
        MethodChannel(messenger, "cn.gdou.xiuhong/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "refresh") {
                    ScheduleWidgetBase.refreshAll(this)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // 安全存储：Keystore AES-GCM 加密后写入 SharedPreferences（用于记住密码等敏感信息）
        MethodChannel(messenger, "cn.gdou.xiuhong/secure")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "put" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<String>("value") ?: ""
                        val encrypted = encryptSecure(value)
                        getSharedPreferences("haipan_secure", MODE_PRIVATE)
                            .edit().putString(key, encrypted).apply()
                        result.success(true)
                    }
                    "get" -> {
                        val key = call.argument<String>("key") ?: ""
                        val raw = getSharedPreferences("haipan_secure", MODE_PRIVATE)
                            .getString(key, null) ?: ""
                        if (raw.isEmpty()) {
                            result.success(null)
                        } else {
                            result.success(decryptSecure(raw))
                        }
                    }
                    "del" -> {
                        val key = call.argument<String>("key") ?: ""
                        getSharedPreferences("haipan_secure", MODE_PRIVATE)
                            .edit().remove(key).apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // 安装 APK：接收 Flutter 侧下载好的文件路径，用 FileProvider 拉起系统安装
        MethodChannel(messenger, "cn.gdou.xiuhong/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val apk = File(path)
                            // 记录待删除路径：装机完成后（onResume）自动清除更新包
                            getSharedPreferences("haipan_cache", MODE_PRIVATE)
                                .edit().putString("pending_delete_apk", path).apply()
                            val uri: Uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", apk)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERR", e.message, null)
                        }
                    }
                    // 用系统 DownloadManager 下载更新包：自带前台进度通知，
                    // 退出更新页/切后台仍继续，通知进度条也会在状态栏（灵动岛）显示。
                    "startUpdateDownload" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            val filename = call.argument<String>("filename")
                                ?: "haipan_update.apk"
                            val title = call.argument<String>("title") ?: "海畔更新"
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE)
                                as DownloadManager
                            val req = DownloadManager.Request(Uri.parse(url)).apply {
                                setTitle(title)
                                setDescription("正在下载更新包，可在后台继续")
                                setNotificationVisibility(
                                    DownloadManager.Request
                                        .VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                                setDestinationInExternalFilesDir(
                                    this@MainActivity,
                                    Environment.DIRECTORY_DOWNLOADS,
                                    filename)
                                setMimeType("application/vnd.android.package-archive")
                                setAllowedOverMetered(true)
                                setAllowedOverRoaming(false)
                            }
                            result.success(dm.enqueue(req))
                        } catch (e: Exception) {
                            result.error("DL_START", e.message, null)
                        }
                    }
                    "queryUpdateDownload" -> {
                        try {
                            val id = call.argument<Number>("id")?.toLong() ?: 0L
                            result.success(queryDownload(id))
                        } catch (e: Exception) {
                            result.error("DL_QUERY", e.message, null)
                        }
                    }
                    "cancelUpdateDownload" -> {
                        try {
                            val id = call.argument<Number>("id")?.toLong() ?: 0L
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE)
                                as DownloadManager
                            dm.remove(id)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DL_CANCEL", e.message, null)
                        }
                    }
                    "installDownloaded" -> {
                        try {
                            val id = call.argument<Number>("id")?.toLong() ?: 0L
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE)
                                as DownloadManager
                            val uri = dm.getUriForDownloadedFile(id)
                            if (uri == null) {
                                result.success(false)
                            } else {
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(
                                        uri,
                                        "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("DL_INSTALL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 本地通知：请求权限 + 排程课表/考试提醒（AlarmManager）
        MethodChannel(messenger, "cn.gdou.xiuhong/notify")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAllPerms" -> startPermFlow(result)
                    "requestPerm" -> {
                        NotificationHelper.ensureChannel(this)
                        if (android.os.Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                        }
                        result.success(NotificationHelper.notificationsEnabled(this))
                    }
                    "testNotify" -> {
                        // 最新通知通道：仅需通知权限，即时发一条测试通知（不再依赖精确闹钟）
                        NotificationHelper.ensureChannel(this)
                        val ts = java.text.SimpleDateFormat(
                            "HH:mm:ss").format(java.util.Date())
                        NotificationHelper.show(
                            this, 901,
                            "测试通知 · 海畔",
                            "通知通道正常 · $ts")
                        result.success(NotificationHelper.notificationsEnabled(this))
                    }
                    "openNotifySettings" -> {
                        try {
                            val i = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOTIFY_SETTINGS_ERR", e.message, null)
                        }
                    }
                    "notifyStatus" -> {
                        // 供调试页诊断：通知权限、精确闹钟、已排条数、最近触发时间
                        val am = getSystemService(android.content.Context.ALARM_SERVICE)
                            as? android.app.AlarmManager
                        val exact = android.os.Build.VERSION.SDK_INT <
                            android.os.Build.VERSION_CODES.S || (am?.canScheduleExactAlarms() ?: false)
                        val (lastAt, lastTitle) = NotificationHelper.lastFire(this)
                        result.success(
                            mapOf(
                                "enabled" to NotificationHelper.notificationsEnabled(this),
                                "exact" to exact,
                                "pending" to NotificationHelper.pendingCount(this),
                                "nextAt" to NotificationHelper.nextAt(this),
                                "lastAt" to lastAt,
                                "lastTitle" to lastTitle,
                                // 电池优化未白名单 / 通知渠道被关闭 / 上次弹通知异常
                                "batteryRestricted" to NotificationHelper.batteryRestricted(this),
                                "channelImportance" to NotificationHelper.channelImportance(this),
                                "lastError" to NotificationHelper.lastError(this)
                            )
                        )
                    }
                    "testAlarm" -> {
                        // 走真实闹钟链路的自测：60 秒后由系统广播弹出
                        NotificationHelper.scheduleTest(applicationContext, 60)
                        result.success(true)
                    }
                    "requestBatteryOpt" -> {
                        // 电池优化白名单：未加入时后台提醒可能被国产 ROM 拦截
                        try {
                            startActivity(
                                Intent(
                                    android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (_: Exception) {
                            try {
                                startActivity(
                                    Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
                    "openAutoStart" -> {
                        // MIUI 自启动管理页（其他 ROM 不存在时回退到应用详情）
                        try {
                            startActivity(
                                Intent().setComponent(
                                    android.content.ComponentName(
                                        "com.miui.securitycenter",
                                        "com.miui.permcenter.autostart.AutoStartManagementActivity"
                                    )
                                )
                            )
                        } catch (_: Exception) {
                            try {
                                startActivity(
                                    Intent(
                                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
                    "requestExactAlarm" -> {
                        // Android 12+ 未授予精确闹钟时，提醒可能被系统延后
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            try {
                                startActivity(
                                    Intent(
                                        android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
                    "scheduleLessons" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        val app = applicationContext
                        notifyExecutor.execute {
                            try {
                                NotificationHelper.scheduleLessons(app, items)
                            } catch (_: Throwable) {
                            }
                        }
                        result.success(null)
                    }
                    "scheduleExams" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        val app = applicationContext
                        notifyExecutor.execute {
                            try {
                                NotificationHelper.scheduleExams(app, items)
                            } catch (_: Throwable) {
                            }
                        }
                        result.success(null)
                    }
                    "cancelAll" -> {
                        val app = applicationContext
                        notifyExecutor.execute {
                            try {
                                NotificationHelper.cancelAll(app)
                            } catch (_: Throwable) {
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(messenger, "cn.gdou.xiuhong/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        try {
                            val text = call.argument<String>("text") ?: ""
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(send, "分享"))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 自定义背景：从相册选图，压缩后复制到应用私有目录并返回路径
        MethodChannel(messenger, "cn.gdou.xiuhong/pick")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> {
                        if (pendingPickImage != null) {
                            result.error("BUSY", "已有选择任务进行中", null)
                            return@setMethodCallHandler
                        }
                        pendingPickImage = result
                        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "image/*"
                        }
                        try {
                            startActivityForResult(
                                Intent.createChooser(pick, "选择背景图片"), REQ_PICK_IMAGE)
                        } catch (e: Exception) {
                            pendingPickImage = null
                            result.error("PICK_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 导出为 .log 文件：让用户自选保存路径（Storage Access Framework）
        MethodChannel(messenger, "cn.gdou.xiuhong/file")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveLog" -> {
                        val text = call.argument<String>("text") ?: ""
                        val ts = java.text.SimpleDateFormat(
                            "yyyyMMdd_HHmmss").format(java.util.Date())
                        val create = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TITLE, "海畔日志_$ts.log")
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        pendingLogText = text
                        try {
                            startActivityForResult(create, REQ_SAVE_LOG)
                            result.success(null)
                        } catch (e: Exception) {
                            pendingLogText = null
                            result.error("SAVE_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 一次性权限引导：通知权限 → 精确闹钟 → 电池优化白名单 →（MIUI）自启动。
     *
     * 逐页串行打开，全部结束后回传最终状态。跳过任意一步都不影响后续步骤，
     * 用户也可以在「设置 → 权限与后台运行」里重新走一遍。
     */
    private fun startPermFlow(result: MethodChannel.Result) {
        pendingPermResult = result
        NotificationHelper.ensureChannel(this)
        val needNotify = android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (needNotify) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF_PERM)
        } else {
            stepExactAlarm()
        }
    }

    private fun stepExactAlarm() {
        val am = getSystemService(android.content.Context.ALARM_SERVICE)
            as? android.app.AlarmManager
        val need = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
            (am?.canScheduleExactAlarms() != true)
        if (need) {
            try {
                startActivityForResult(
                    Intent(
                        android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName")
                    ),
                    REQ_EXACT_ALARM
                )
                return
            } catch (_: Exception) {
            }
        }
        stepBattery()
    }

    private fun stepBattery() {
        if (NotificationHelper.batteryRestricted(this)) {
            try {
                startActivityForResult(
                    Intent(
                        android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    ),
                    REQ_BATTERY_OPT
                )
                return
            } catch (_: Exception) {
            }
        }
        stepAutoStart()
    }

    private fun stepAutoStart() {
        // 只有 MIUI 有独立的自启动开关页；其他 ROM 没有稳定的跳转入口
        if (android.os.Build.MANUFACTURER.equals("xiaomi", ignoreCase = true)) {
            try {
                startActivityForResult(
                    Intent().setComponent(
                        android.content.ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    ),
                    REQ_AUTOSTART
                )
                return
            } catch (_: Exception) {
            }
        }
        finishPermFlow()
    }

    private fun finishPermFlow() {
        val cb = pendingPermResult ?: return
        pendingPermResult = null
        val am = getSystemService(android.content.Context.ALARM_SERVICE)
            as? android.app.AlarmManager
        val exact = android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S ||
            (am?.canScheduleExactAlarms() ?: false)
        cb.success(
            mapOf(
                "notifications" to NotificationHelper.notificationsEnabled(this),
                "exact" to exact,
                "battery" to !NotificationHelper.batteryRestricted(this)
            )
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF_PERM) stepExactAlarm()
    }

    override fun onActivityResult(
        requestCode: Int, resultCode: Int, data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        // 一键授权流程的中间步骤：返回后继续下一步
        when (requestCode) {
            REQ_EXACT_ALARM -> {
                stepBattery()
                return
            }
            REQ_BATTERY_OPT -> {
                stepAutoStart()
                return
            }
            REQ_AUTOSTART -> {
                finishPermFlow()
                return
            }
        }
        if (requestCode == REQ_PICK_IMAGE) {
            val cb = pendingPickImage
            pendingPickImage = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                cb?.success(null)
                return
            }
            try {
                val dir = File(filesDir, "backgrounds").apply { mkdirs() }
                // 只保留最新一张，避免占用空间
                dir.listFiles()?.forEach { it.delete() }
                val out = File(dir, "bg_${System.currentTimeMillis()}.jpg")
                // 先读尺寸算采样率，避免超大照片直接解码导致 OOM
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                contentResolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, bounds)
                }
                var sample = 1
                val longest = maxOf(bounds.outWidth, bounds.outHeight)
                if (longest > 0) {
                    while (longest / (sample * 2) >= 1920) sample *= 2
                }
                val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
                val bitmap = contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, decodeOpts)
                } ?: throw IllegalStateException("无法读取图片")
                // 限制最长边 1920，压成 JPEG 88% 控制体积
                val maxSide = 1920
                val scale = (maxSide.toFloat() / maxOf(bitmap.width, bitmap.height))
                    .coerceAtMost(1f)
                val target = if (scale < 1f) {
                    Bitmap.createScaledBitmap(
                        bitmap,
                        (bitmap.width * scale).toInt().coerceAtLeast(1),
                        (bitmap.height * scale).toInt().coerceAtLeast(1),
                        true)
                } else bitmap
                out.outputStream().use { os ->
                    target.compress(Bitmap.CompressFormat.JPEG, 88, os)
                }
                if (target !== bitmap) target.recycle()
                bitmap.recycle()
                cb?.success(out.absolutePath)
            } catch (e: Exception) {
                cb?.error("COPY_ERR", e.message, null)
            }
            return
        }
        if (requestCode == REQ_SAVE_LOG && resultCode == Activity.RESULT_OK) {
            val uri = data?.data
            val text = pendingLogText ?: return
            pendingLogText = null
            try {
                contentResolver.openOutputStream(uri!!)?.use { os ->
                    os.write(text.toByteArray())
                }
            } catch (_: Exception) {
            }
        }
    }

    /// 查询系统下载任务：status 与字节进度，页面据此绘制进度并判断完成。
    private fun queryDownload(id: Long): Map<String, Any?> {
        if (id <= 0L) return mapOf("status" to -1)
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        dm.query(DownloadManager.Query().setFilterById(id))?.use { c ->
            if (!c.moveToFirst()) return mapOf("status" to -1)
            fun col(name: String) = c.getColumnIndexOrThrow(name)
            val status = c.getInt(col(DownloadManager.COLUMN_STATUS))
            val downloaded = c.getLong(
                col(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = c.getLong(col(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            return mapOf(
                "status" to status,
                "downloaded" to downloaded,
                "total" to total,
            )
        }
        return mapOf("status" to -1)
    }

    companion object {
        private const val AUTH_ALIAS = "haipan_auth_key"
        private const val REQ_SAVE_LOG = 7001
        private const val REQ_PICK_IMAGE = 7002
        private const val REQ_NOTIF_PERM = 7003
        private const val REQ_EXACT_ALARM = 7004
        private const val REQ_BATTERY_OPT = 7005
        private const val REQ_AUTOSTART = 7006
        private var pendingLogText: String? = null
        private var pendingPickImage: MethodChannel.Result? = null
    }
}
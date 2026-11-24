import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/jw_client.dart';
import '../api/jw_apis.dart';
import '../api/usage_api.dart';
import '../models/models.dart';
import '../util/app_log.dart';
import '../util/campus_tunnel.dart';
import '../util/lesson_notifier.dart';
import '../util/local_cache.dart';
import '../util/term_utils.dart';
import 'data_providers.dart';

enum SessionStatus { unknown, loggedIn, loggedOut }

class SessionState {
  final SessionStatus status;
  final StudentInfo student;
  final String savedUsername;
  final bool guest; // 未登录进入浏览（游客模式）
  final bool stayHome; // 会话失效但暂留主页面（不弹登录页，仅提示）

  const SessionState({
    this.status = SessionStatus.unknown,
    this.student = const StudentInfo(),
    this.savedUsername = '',
    this.guest = false,
    this.stayHome = false,
  });

  /// 是否处于"可在应用内浏览"的未登录态（游客 / 会话失效暂留主页）
  bool get browsing => guest || stayHome;

  SessionState copyWith({
    SessionStatus? status,
    StudentInfo? student,
    String? savedUsername,
    bool? guest,
    bool? stayHome,
  }) =>
      SessionState(
        status: status ?? this.status,
        student: student ?? this.student,
        savedUsername: savedUsername ?? this.savedUsername,
        guest: guest ?? this.guest,
        stayHome: stayHome ?? this.stayHome,
      );
}

/// 会话失效提醒信号：SessionNotifier 每次失效自增，main 监听后弹出提示
final sessionExpiredSignalProvider = StateProvider<int>((ref) => 0);

/// 会话：启动时用历史 Cookie 探测登录态；登录成功后拉课表拿学籍信息
class SessionNotifier extends Notifier<SessionState> {
  static const _kStudent = 'jw.student';
  static const _kUsername = 'jw.username';
  static const _kLoggedOut = 'jw.logged_out';

  /// 上次 SSO 登录成功标记：下次冷启动会话过期时，静默打开认证页续期
  static const _kAutoSso = 'jw.auto_sso';

  /// 保持在线心跳：定期回访教务页面刷新会话活跃度，延长空闲超时
  Timer? _heartbeat;

  @override
  SessionState build() {
    final client = ref.watch(jwClientProvider);
    client.onSessionExpired = () {
      if (state.status != SessionStatus.loggedOut) {
        // 会话失效：不弹回登录页，保留主页面仅置"暂留主页"标志，
        // 并触发一次性提醒弹窗（用户在「我的」页自行重新登录）。
        // 学籍与离线缓存保留，减少重登成本。
        state = state.copyWith(
          status: SessionStatus.loggedOut,
          stayHome: true,
        );
        ref.read(sessionExpiredSignalProvider.notifier).state++;
      }
    };
    ref.onDispose(() {
      client.onSessionExpired = null;
      _heartbeat?.cancel();
    });
    _startHeartbeat();
    _restore();
    return const SessionState();
  }

  /// 每隔 5 分钟在已登录时刷新一次会话，尽量延续服务端活跃态
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 5), (_) => _tick());
  }

  Future<void> _tick() async {
    if (state.status != SessionStatus.loggedIn) return;
    try {
      await ref.read(jwClientProvider).probeLoggedIn();
    } catch (_) {
      // 网络波动忽略，不打断在线状态
    }
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kStudent);
    final username = prefs.getString(_kUsername) ?? '';
    // 主动退出登录过的账号：保留学号用于登录页回填，但冷启动不得凭
    // 缓存学号直接进主页（否则退出后重启又显示在线并弹「登录失效」）。
    if (prefs.getBool(_kLoggedOut) ?? false) {
      AppLog.d('会话', '上次已主动退出登录，冷启动进入登录页');
      LessonNotifier.setSessionActive(false);
      state = SessionState(
        status: SessionStatus.loggedOut,
        savedUsername: username,
      );
      return;
    }
    final cachedStudent = saved != null
        ? StudentInfo.fromJson(jsonDecode(saved) as Map<String, dynamic>)
        : StudentInfo(xh: username);

    // 缓存优先：本地有登录记录时立即进入主页（页面先读离线缓存展示），
    // 通道握手与在线探测放到后台进行。成功则全程无感；握手失败/会话失效
    // 再保留主页面并弹一次续期提示，不再让用户盯着启动页等网络。
    if (saved != null || username.isNotEmpty) {
      AppLog.d('会话', '缓存优先进入主页 学号=$username');
      LessonNotifier.setSessionActive(true);
      state = SessionState(
        status: SessionStatus.loggedIn,
        student: cachedStudent,
        savedUsername: username,
      );
      if (username.isNotEmpty) UsageTracker.reportLogin(username);
      unawaited(_probeInBackground(username));
      return;
    }

    // 无本地登录记录：只能走一次在线探测，再决定进主页还是登录页
    try {
      await ref
          .read(campusTunnelProvider)
          .adapt(ref.read(jwClientProvider), xh: username);
    } catch (e) {
      AppLog.w('通道', '通道自适应失败：$e');
    }
    try {
      final ok = await ref.read(jwClientProvider).probeLoggedIn();
      if (ok) {
        AppLog.d('会话', '在线会话可用（无本地学籍缓存）');
        LessonNotifier.setSessionActive(true);
        state = SessionState(
          status: SessionStatus.loggedIn,
          student: StudentInfo(xh: username),
          savedUsername: username,
        );
        return;
      }
      await ref.read(jwClientProvider).clearCookies();
    } catch (_) {
      // 无任何本地登录记录：进入未登录态，用户可手动重试
    }
    state = SessionState(
      status: SessionStatus.loggedOut,
      savedUsername: username,
    );
  }

  /// 后台握手：先自适应校外通道，再探测会话。
  /// 成功保持无感；失败且当前仍在主页时置为「暂留主页」并触发续期提示；
  /// 网络异常按离线模式继续，不打扰用户。
  Future<void> _probeInBackground(String username) async {
    try {
      await ref
          .read(campusTunnelProvider)
          .adapt(ref.read(jwClientProvider), xh: username);
    } catch (e) {
      AppLog.w('通道', '后台通道自适应失败：$e');
    }
    try {
      final ok = await ref.read(jwClientProvider).probeLoggedIn();
      if (ok) {
        AppLog.d('会话', '后台握手成功，保持在线');
        return;
      }
      await ref.read(jwClientProvider).clearCookies();
      if (state.status == SessionStatus.loggedIn) {
        AppLog.w('会话', '后台握手失败，保留主页面并提示续期');
        state = state.copyWith(
          status: SessionStatus.loggedOut,
          stayHome: true,
        );
        ref.read(sessionExpiredSignalProvider.notifier).state++;
      }
    } catch (e) {
      AppLog.w('会话', '后台握手异常，按离线模式继续：$e');
    }
  }

  /// 新版统一身份认证：WebView 登录后把 jw 域 Cookie 注入 Dio 会话。
  Future<void> loginWithSso(Map<String, String> cookies) async {
    AppLog.d('会话', '统一身份认证回填 Cookie：${cookies.length} 个');
    final client = ref.read(jwClientProvider);
    await client.clearCookies();
    await client.saveCookies(cookies);
    final ok = await client.probeLoggedIn();
    if (!ok) {
      await client.clearCookies();
      throw AuthException('统一身份认证未建立会话，请重试');
    }
    AppLog.d('会话', '统一身份认证登录成功');
    await _completeLogin(state.savedUsername);
  }

  /// 是否允许下次冷启动时静默打开认证页续期（主动退出后为 false）。
  Future<bool> canSilentSso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoSso) ?? false;
  }

  /// 登录成功后：拉课表取学籍、补学院/性别、落盘并刷新数据。
  Future<void> _completeLogin(String username) async {
    // 登录成功：拉一次课表取学籍信息（xsxx）
    StudentInfo student;
    try {
      final timetable =
          await ref.read(timetableApiProvider).fetch(TermUtils.currentTerm());
      student = timetable.student.xh.isEmpty
          ? StudentInfo(xh: username)
          : timetable.student;
    } catch (_) {
      student = StudentInfo(xh: username);
    }
    // 课表接口(xsxx)不含学院/性别；从"个人基本信息"页补全（若有）
    if (student.jgmc.isEmpty) {
      try {
        final resp = await ref.read(jwClientProvider).getHtml(
            '/xsxxxggl/xsgrxxwh_cxXsgrxx.html',
            query: {'gnmkdm': 'N100801', 'layout': 'default'});
        final html = resp.data is String ? resp.data as String : '';
        // 学院值在 id="col_jg_id" 的 <p class="form-control-static">xx学院</p>
        final m = RegExp(r'id="col_jg_id"[\s\S]*?<p[^>]*>\s*(?:<[^>]+>\s*)?([^<]+?)\s*</p>')
            .firstMatch(html);
        final college = m?.group(1)?.trim() ?? '';
        // 性别同理在 id="col_xbm"（页面是"男"/"女"文本）
        final mb = RegExp(r'id="col_xbm"[\s\S]*?<p[^>]*>\s*(?:<[^>]+>\s*)?([^<]+?)\s*</p>')
            .firstMatch(html);
        final sex = mb?.group(1)?.trim() ?? '';
        final xb = sex.contains('男') ? '1' : (sex.contains('女') ? '2' : '');
        final jgmc = college.contains('学院') ? college : '';
        if (jgmc.isNotEmpty || xb.isNotEmpty) {
          student = student.merge(StudentInfo(jgmc: jgmc, xb: xb));
        }
      } catch (_) {
        // 学院/性别补全失败不阻塞登录
      }
    }
    // 以课表实际学号为准；只有拿不到时才回退到传入值（可能是上一个账号）
    final effectiveUser = student.xh.isNotEmpty ? student.xh : username;
    final prefs = await SharedPreferences.getInstance();
    final prevUser = prefs.getString(_kUsername) ?? '';
    if (prevUser.isNotEmpty && prevUser != effectiveUser) {
      // 切换账号：清掉上一账号的离线缓存与已排提醒，避免串号
      AppLog.w('会话', '切换账号 $prevUser → $effectiveUser，清理本地缓存');
      await LocalCache.clearData();
      await LessonNotifier.setSessionActive(false);
    }
    await prefs.setString(_kStudent, jsonEncode(student.toJson()));
    await prefs.setString(_kUsername, effectiveUser);
    // 标记：下次冷启动若会话过期，自动打开认证页静默续期
    await prefs.setBool(_kAutoSso, true);
    await prefs.setBool(_kLoggedOut, false);
    LessonNotifier.setSessionActive(true);
    // 学业页随会话重建，不能直接 invalidate（会触发循环依赖）；
    // 清掉它的离线缓存，避免沿用游客态缓存的空结果
    await LocalCache.removeWhere((k) => k.startsWith('cache_academic'));
    _invalidateData();
    state = SessionState(
      status: SessionStatus.loggedIn,
      student: student,
      savedUsername: effectiveUser,
      guest: false,
      stayHome: false,
    );
    // 登录后匿名上报一次学号（用于统计使用人数，失败静默）
    UsageTracker.reportLogin(effectiveUser);
  }

  /// 游客模式：不登录直接进入浏览（离线缓存可看）
  void enterGuest() {
    state = state.copyWith(guest: true, stayHome: false);
  }

  Future<void> logout() async {
    AppLog.d('会话', '退出登录');
    await ref.read(authApiProvider).logout();
    await LessonNotifier.setSessionActive(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSso, false);
    // 记录主动退出：冷启动据此直接进登录页，而不是凭残留学号回到主页
    await prefs.setBool(_kLoggedOut, true);
    await _clearLocal();
    _invalidateData();
    state = SessionState(
      status: SessionStatus.loggedOut,
      savedUsername: state.savedUsername,
      guest: false,
      stayHome: false,
    );
  }

  /// 异常自修复：清空 Cookie 与本地学籍缓存，重置全部数据 provider，
  /// 保留学号便于重新登录（等价于"干净地回到登录页"）
  Future<void> resetForRepair() async {
    try {
      await ref.read(jwClientProvider).clearCookies();
    } catch (_) {
      // 清理失败不阻塞流程
    }
    await LessonNotifier.setSessionActive(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSso, false);
    await prefs.setBool(_kLoggedOut, true);
    await _clearLocal();
    _invalidateData();
    state = SessionState(
      status: SessionStatus.loggedOut,
      savedUsername: state.savedUsername,
      guest: false,
      stayHome: false,
    );
  }

  Future<void> _clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStudent);
  }

  void _invalidateData() {
    // 注意：academicProvider watch 了本 provider（会随 state 变化自动重建），
    // 在这里 invalidate 它会被 Riverpod 判定为循环依赖（CircularDependencyError）
    ref.invalidate(timetableProvider);
    ref.invalidate(gradesProvider);
    ref.invalidate(examsProvider);
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

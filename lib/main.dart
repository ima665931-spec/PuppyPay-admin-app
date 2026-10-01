import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kApiBase = 'https://puppy-pay-backend.vercel.app/api/admin';
const String kChannelId = 'order_alerts_v3';
const int kAlertNotifId = 99101;

final FlutterLocalNotificationsPlugin localNotifs = FlutterLocalNotificationsPlugin();
final AudioPlayer ringPlayer = AudioPlayer();
final ValueNotifier<bool> isRinging = ValueNotifier<bool>(false);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await setupAlertChannel();
  await showEmergencyAlert(
    title: message.data['title'] ?? message.notification?.title ?? 'NEW ORDER',
    body: message.data['body'] ?? message.notification?.body ?? 'Open PuppyPay Admin',
    data: message.data,
  );
}

Future<void> setupAlertChannel() async {
  final android = localNotifs.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    AndroidNotificationChannel(
      kChannelId,
      'Call-style Order Alerts',
      description: 'Continuous ring until you stop',
      importance: Importance.max,
      playSound: false, // we play custom loop ourselves
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 900]),
      enableLights: true,
      ledColor: const Color(0xFFFF0000),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ),
  );
}

Future<void> startRing() async {
  try {
    await ringPlayer.setReleaseMode(ReleaseMode.loop);
    await ringPlayer.setVolume(1.0);
    await ringPlayer.play(AssetSource('sounds/alert_ring.mp3'));
    isRinging.value = true;
  } catch (e) {
    debugPrint('startRing error: $e');
  }
}

Future<void> stopRing() async {
  try {
    await ringPlayer.stop();
  } catch (_) {}
  isRinging.value = false;
  try {
    await localNotifs.cancel(kAlertNotifId);
  } catch (_) {}
}

Future<void> showEmergencyAlert({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) async {
  try {
    await HapticFeedback.heavyImpact();
  } catch (_) {}

  await startRing();

  await localNotifs.show(
    kAlertNotifId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kChannelId,
        'Call-style Order Alerts',
        channelDescription: 'Continuous ring until you stop',
        importance: Importance.max,
        priority: Priority.max,
        playSound: false,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 900]),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        ongoing: true,
        autoCancel: false,
        ticker: 'NEW ORDER — PuppyPay',
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'stop_ring',
            'STOP RING',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          const AndroidNotificationAction('open', 'OPEN'),
        ],
      ),
    ),
    payload: jsonEncode(data ?? {}),
  );
}

@pragma('vm:entry-point')
void onNotifBackground(NotificationResponse r) {
  if (r.actionId == 'stop_ring') {
    // Best-effort; full stop when app opens
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifs.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: (NotificationResponse r) async {
      if (r.actionId == 'stop_ring') {
        await stopRing();
      }
    },
    onDidReceiveBackgroundNotificationResponse: onNotifBackground,
  );
  await setupAlertChannel();

  final androidPlugin = localNotifs.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
  try {
    await androidPlugin?.requestFullScreenIntentPermission();
  } catch (_) {}

  // Audio focus for loud playback
  try {
    await ringPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  } catch (_) {}

  runApp(const PuppyPayAdminApp());
}

class PuppyPayAdminApp extends StatelessWidget {
  const PuppyPayAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PuppyPay Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF3B82F6),
        useMaterial3: true,
      ),
      home: const Gate(),
    );
  }
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? token;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      token = p.getString('admin_token');
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (token == null || token!.isEmpty) {
      return LoginPage(onLoggedIn: (t) => setState(() => token = t));
    }
    return HomePage(
      token: token!,
      onLogout: () async {
        await stopRing();
        final p = await SharedPreferences.getInstance();
        await p.remove('admin_token');
        setState(() => token = null);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  final void Function(String token) onLoggedIn;
  const LoginPage({super.key, required this.onLoggedIn});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$kApiBase/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': userCtrl.text.trim(),
          'password': passCtrl.text,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true && data['token'] != null) {
        final p = await SharedPreferences.getInstance();
        await p.setString('admin_token', data['token']);
        widget.onLoggedIn(data['token']);
      } else {
        setState(() => error = data['message']?.toString() ?? 'Login failed');
      }
    } catch (e) {
      setState(() => error = 'Network error');
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('PuppyPay Admin', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Call-style order alerts', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 32),
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _login,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String token;
  final VoidCallback onLogout;
  const HomePage({super.key, required this.token, required this.onLogout});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool alertsOn = true;
  bool loading = true;
  List deposits = [];
  List withdrawals = [];
  String? fcmToken;
  String status = '';

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _setupFcm();
    await _refresh();
    FirebaseMessaging.onMessage.listen((m) async {
      await showEmergencyAlert(
        title: m.data['title'] ?? m.notification?.title ?? 'NEW ORDER',
        body: m.data['body'] ?? m.notification?.body ?? 'Open panel',
        data: m.data,
      );
      _refresh();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((_) async {
      await stopRing();
      _refresh();
    });
  }

  Future<void> _setupFcm() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, sound: true, badge: true);
    final token = await messaging.getToken();
    fcmToken = token;
    if (token != null) {
      try {
        final res = await http.post(
          Uri.parse('$kApiBase/fcm/register'),
          headers: headers,
          body: jsonEncode({'token': token, 'platform': 'android', 'label': 'Admin phone'}),
        );
        final data = jsonDecode(res.body);
        if (data['device'] != null) {
          alertsOn = data['device']['alertsEnabled'] != false;
        }
        setState(() => status = 'FCM OK');
      } catch (_) {
        setState(() => status = 'FCM register failed');
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$kApiBase/deposits/pending'), headers: headers),
        http.get(Uri.parse('$kApiBase/withdrawals/pending'), headers: headers),
      ]);
      final dep = jsonDecode(results[0].body);
      final wd = jsonDecode(results[1].body);
      setState(() {
        deposits = dep['deposits'] ?? [];
        withdrawals = wd['withdrawals'] ?? [];
      });
    } catch (_) {}
    setState(() => loading = false);
  }

  Future<void> _toggleAlerts(bool v) async {
    setState(() => alertsOn = v);
    if (!v) await stopRing();
    await http.patch(
      Uri.parse('$kApiBase/fcm/alerts'),
      headers: headers,
      body: jsonEncode({'enabled': v, 'token': fcmToken}),
    );
  }

  Future<void> _testLocal() async {
    await showEmergencyAlert(
      title: 'TEST — NEW ORDER',
      body: 'Ring chalega jab tak STOP na dabao.',
      data: {'kind': 'test'},
    );
  }

  Future<void> _testRemote() async {
    final res = await http.post(Uri.parse('$kApiBase/fcm/test'), headers: headers);
    final data = jsonDecode(res.body);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['success'] == true ? 'Remote test sent' : 'Remote test failed')),
      );
    }
  }

  Future<void> _act(String kind, String id, bool accept) async {
    await stopRing();
    final path = kind == 'deposit'
        ? '/deposits/$id/${accept ? 'accept' : 'reject'}'
        : '/withdrawals/$id/${accept ? 'accept' : 'reject'}';
    await http.post(Uri.parse('$kApiBase$path'), headers: headers, body: '{}');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PuppyPay Orders'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: isRinging,
              builder: (_, ringing, __) {
                if (!ringing) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 64,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: stopRing,
                      child: const Text('⏹ STOP RING', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                  ),
                );
              },
            ),
            Card(
              color: alertsOn ? const Color(0xFF14532D) : const Color(0xFF450A0A),
              child: SwitchListTile(
                title: Text(
                  alertsOn ? 'Alerts ON' : 'Alerts OFF (class mode)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(alertsOn ? 'Call-style ring on new orders' : 'Silent'),
                value: alertsOn,
                onChanged: _toggleAlerts,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _testLocal,
                    child: const Text('Local TEST (ring)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _testRemote,
                    child: const Text('Remote TEST'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(status, style: const TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 16),
            Text('Withdrawals (${withdrawals.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (loading) const LinearProgressIndicator(),
            if (!loading && withdrawals.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending withdrawals', style: TextStyle(color: Colors.white54)),
              ),
            ...withdrawals.map((w) => _orderCard(
                  kind: 'withdraw',
                  id: '${w['_id']}',
                  amount: w['amount'],
                  subtitle: '${w['destination'] ?? ''}\n${w['email'] ?? w['name'] ?? ''}',
                )),
            const SizedBox(height: 20),
            Text('Deposits (${deposits.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (!loading && deposits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending deposits', style: TextStyle(color: Colors.white54)),
              ),
            ...deposits.map((d) => _orderCard(
                  kind: 'deposit',
                  id: '${d['_id']}',
                  amount: d['amount'] ?? d['total'],
                  subtitle: 'UTR ${d['utr'] ?? '—'}\n${d['email'] ?? ''}',
                )),
          ],
        ),
      ),
    );
  }

  Widget _orderCard({
    required String kind,
    required String id,
    required dynamic amount,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('₹${amount ?? 0}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF60A5FA))),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _act(kind, id, true),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () => _act(kind, id, false),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 광고 SDK 초기화는 await로 화면 진입을 막지 않고 백그라운드에서 비동기 실행
  MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 영어단어',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const TodayWordScreen(),
    );
  }
}

class TodayWordScreen extends StatefulWidget {
  const TodayWordScreen({super.key});

  @override
  State<TodayWordScreen> createState() => _TodayWordScreenState();
}

class _TodayWordScreenState extends State<TodayWordScreen> {
  final String dataUrl =
      'https://raw.githubusercontent.com/hyuckiii-real/todays-x-data/main/today.json';

  // 테스트용 배너 ID (테스트 확인 후 출시 직전 본인 실제 ID로 교체)
  final String bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  // 본인 실제 배너 ID: 'ca-app-pub-1402331019363344/4217254550';

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  Map<String, dynamic>? wordData;
  bool isLoading = true;
  String? errorMessage;
  bool isMemorized = false;

  @override
  void initState() {
    super.initState();
    initWordData();
    // 화면이 먼저 그려진 직후(0.3초 뒤) 광고 요청 시작
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) loadBannerAd();
    });
  }

  void loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isBannerLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('배너 광고 로드 실패: $error');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  // 1. 기기에 저장된 캐시가 있으면 0.01초 만에 즉시 화면 표시 후 백그라운드 최신화
  Future<void> initWordData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('cached_today_word');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson);
        final savedKey = 'memorized_${decoded["date"]}';
        final checked = prefs.getBool(savedKey) ?? false;

        if (mounted) {
          setState(() {
            wordData = decoded;
            isMemorized = checked;
            isLoading = false; // 캐시로 즉시 로딩 해제!
          });
        }
      } catch (_) {}
    }

    // 백그라운드에서 최신 JSON 확인 (첫 실행이면 여기서 받아옴)
    await fetchTodayWord(silent: cachedJson != null);
  }

  Future<void> fetchTodayWord({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final res = await http
          .get(Uri.parse(dataUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final rawString = utf8.decode(res.bodyBytes);
        final decoded = json.decode(rawString);
        final prefs = await SharedPreferences.getInstance();

        // 다음 실행 시 0초 로딩을 위해 로컬에 캐싱 저장
        await prefs.setString('cached_today_word', rawString);

        final savedKey = 'memorized_${decoded["date"]}';
        final checked = prefs.getBool(savedKey) ?? false;

        if (mounted) {
          setState(() {
            wordData = decoded;
            isMemorized = checked;
            isLoading = false;
            errorMessage = null;
          });
        }
      } else if (!silent && mounted) {
        setState(() {
          errorMessage = '서버 응답 오류 (HTTP ${res.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          errorMessage = '네트워크 연결을 확인해 주세요.';
          isLoading = false;
        });
      }
    }
  }

  Future<void> toggleMemorized() async {
    if (wordData == null) return;
    final prefs = await SharedPreferences.getInstance();
    final savedKey = 'memorized_${wordData!["date"]}';
    final nextState = !isMemorized;

    await prefs.setBool(savedKey, nextState);
    setState(() {
      isMemorized = nextState;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 첫 실행으로 캐시가 아직 없는 0.5초 동안 보여줄 깔끔한 브랜드 소개 화면
    if (isLoading && wordData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  size: 48,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '오늘의 영어단어',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '하루 한 단어, 가볍게 채우는 영어 습관',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘의 단어', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: buildContent(),
                ),
              ),
            ),
            if (_isBannerLoaded && _bannerAd != null)
              SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              )
            else
              const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget buildContent() {
    if (errorMessage != null && wordData == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => fetchTodayWord(silent: false),
            child: const Text('다시 시도'),
          ),
        ],
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  wordData!['date'] ?? '',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    wordData!['part_of_speech'] ?? '',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              wordData!['word'] ?? '',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              wordData!['phonetic'] ?? '',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Text(
              wordData!['meaning'] ?? '',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const Divider(height: 36),
            Text(
              wordData!['example_en'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              wordData!['example_ko'] ?? '',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: toggleMemorized,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isMemorized ? Colors.green : const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(isMemorized ? Icons.check_circle : Icons.check),
                label: Text(
                  isMemorized ? '외웠어요! (학습 완료)' : '오늘 단어 외우기',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

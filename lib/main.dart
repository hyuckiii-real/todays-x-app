import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 화면 진입을 막지 않도록 runApp() 먼저 실행
  runApp(const TodaysPersonApp());
}

class TodaysPersonApp extends StatelessWidget {
  const TodaysPersonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 인물',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E293B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _dataUrl =
      'https://raw.githubusercontent.com/hyuckiii-real/todays-person-data/main/today.json';

  static const String _bannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  JsonMap? _personData;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isCollected = false;
  JsonList _historyList = [];

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    // 1. 로컬 캐시 즉시 확인 후 0.1초 내 렌더링 + 백그라운드 최신 데이터 동기화
    _initPersonDataFast();
    // 2. 애드몹은 화면이 뜬 뒤 백그라운드에서 비동기 초기화
    _initAdMobInBackground();
  }

  Future<void> _initAdMobInBackground() async {
    try {
      await MobileAds.instance.initialize();
      if (!mounted) return;
      _bannerAd = BannerAd(
        adUnitId: _bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) {
              setState(() => _isBannerLoaded = true);
            }
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
          },
        ),
      )..load();
    } catch (_) {}
  }

  String _getTodayKstString() {
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final y = nowKst.year.toString().padLeft(4, '0');
    final m = nowKst.month.toString().padLeft(2, '0');
    final d = nowKst.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _initPersonDataFast() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKst = _getTodayKstString();

    // 저장된 히스토리 로드
    final historyRaw = prefs.getString('person_history');
    if (historyRaw != null) {
      final decoded = jsonDecode(historyRaw);
      if (decoded is Iterable) {
        _historyList = decoded.map((e) => JsonMap.from(e as Map)).toList();
      }
    }

    // 기기에 저장된 캐시가 있으면 날짜 상관없이 일단 0.01초 만에 화면에 먼저 표시
    final cachedDate = prefs.getString('cached_person_date');
    final cachedJson = prefs.getString('cached_person_json');

    if (cachedJson != null) {
      final cachedData = JsonMap.from(jsonDecode(cachedJson) as Map);
      final idx = _historyList
          .indexWhere((item) => item['date'] == cachedData['date']);
      if (mounted) {
        setState(() {
          _personData = cachedData;
          _isCollected = idx != -1 && _historyList[idx]['collected'] == true;
          _isLoading = false;
        });
      }
      // 오늘 날짜 데이터까지 이미 캐싱되어 있다면 네트워크 요청 없이 즉시 종료
      if (cachedDate == todayKst) {
        return;
      }
    }

    // 첫 실행이거나 날짜가 바뀐 경우 백그라운드에서 최신 인물 가져오기 (최대 5초 타임아웃)
    await _fetchLatestPerson(prefs, todayKst);
  }

  Future<void> _fetchLatestPerson(
      SharedPreferences prefs, String todayKst) async {
    try {
      final response = await http
          .get(Uri.parse(_dataUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = JsonMap.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );

      await prefs.setString('cached_person_date', todayKst);
      await prefs.setString('cached_person_json', jsonEncode(data));

      final existsIdx =
          _historyList.indexWhere((item) => item['date'] == data['date']);
      bool collectedState = false;
      if (existsIdx == -1) {
        data['collected'] = false;
        _historyList.insert(0, data);
        await prefs.setString('person_history', jsonEncode(_historyList));
      } else {
        collectedState = _historyList[existsIdx]['collected'] == true;
      }

      if (mounted) {
        setState(() {
          _personData = data;
          _isCollected = collectedState;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (_) {
      if (mounted && _personData == null) {
        setState(() {
          _errorMessage = '오늘의 인물을 불러오는 중 오류가 발생했습니다.\n인터넷 연결을 확인해 주세요.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _retryLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await _fetchLatestPerson(prefs, _getTodayKstString());
  }

  Future<void> _toggleCollected() async {
    if (_personData == null) return;
    final prefs = await SharedPreferences.getInstance();
    final nextState = !_isCollected;

    final idx =
        _historyList.indexWhere((item) => item['date'] == _personData!['date']);
    if (idx != -1) {
      _historyList[idx]['collected'] = nextState;
      await prefs.setString('person_history', jsonEncode(_historyList));
    }

    setState(() {
      _isCollected = nextState;
    });
  }

  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '내 인물 도감',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '총 ${_historyList.length}명 열람',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _historyList.isEmpty
                        ? const Center(child: Text('아직 기록된 인물이 없습니다.'))
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _historyList.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _historyList[index];
                              final collected = item['collected'] == true;
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                leading: Icon(
                                  collected
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  color: collected
                                      ? const Color(0xFFD97706)
                                      : Colors.grey.shade400,
                                ),
                                title: Text(
                                  item['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item['date']} · ${item['one_liner'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayDisplay =
        _personData?['date']?.toString() ?? _getTodayKstString();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              todayDisplay,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              '오늘의 인물',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openHistorySheet,
            icon: const Icon(
              Icons.auto_stories_outlined,
              color: Color(0xFF1E293B),
            ),
            tooltip: '내 인물 도감',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? _buildBrandIntroLoading()
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _retryLoad,
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildPersonCard(),
          ),
          if (_isBannerLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }

  // 첫 설치 직후 데이터를 받아오는 0.5초 동안 보여줄 깔끔한 브랜드 소개 화면
  Widget _buildBrandIntroLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_search_rounded,
                size: 40,
                color: Color(0xFF3730A3),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '오늘의 인물',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '하루 한 명, 세상을 바꾼 인물을 만나는 시간',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
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

  Widget _buildPersonCard() {
    final data = _personData!;
    final rawAchievements = data['achievements'];
    final achievements = rawAchievements is Iterable
        ? rawAchievements.map((e) => e.toString()).toList()
        : const <String>[];
    final quoteOriginal = data['quote_original']?.toString().trim() ?? '';
    final quoteKo = data['quote_ko']?.toString().trim() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildBadge(
                  data['theme']?.toString() ?? '오늘의 테마',
                  const Color(0xFFE0E7FF),
                  const Color(0xFF3730A3),
                ),
                _buildBadge(
                  data['category']?.toString() ?? '',
                  const Color(0xFFF1F5F9),
                  const Color(0xFF475569),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              data['name']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data['lifespan']?.toString() ?? '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                '“${data['one_liner'] ?? ''}”',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildSectionTitle('📌 왜 오늘 이 인물일까?'),
            const SizedBox(height: 6),
            Text(
              data['why_today']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: Color(0xFF334155),
              ),
            ),
            const Divider(height: 28),
            _buildSectionTitle('🏆 핵심 업적'),
            const SizedBox(height: 8),
            ...achievements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.5,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 28),
            _buildSectionTitle('💬 남긴 말'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (quoteOriginal.isNotEmpty && quoteOriginal != quoteKo) ...[
                    Text(
                      quoteOriginal,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF78350F),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    quoteKo,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildSectionTitle('💡 의외의 TMI'),
            const SizedBox(height: 6),
            Text(
              data['tmi']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _toggleCollected,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isCollected
                      ? const Color(0xFF10B981)
                      : const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: Icon(
                  _isCollected
                      ? Icons.check_circle_rounded
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  _isCollected ? '인물 도감에 수집 완료!' : '오늘의 인물 수집하기',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

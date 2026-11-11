import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  Map<String, dynamic>? wordData;
  bool isLoading = true;
  bool isMemorized = false;

  final Map<String, dynamic> fallbackWord = {
    "date": "TODAY",
    "word": "Serendipity",
    "phonetic": "/ˌser.ənˈdɪp.ə.t̬i/",
    "part_of_speech": "명사",
    "meaning": "뜻밖의 행운, 우연한 발견",
    "example_en": "Finding this great app was pure serendipity.",
    "example_ko": "이 멋진 앱을 발견한 것은 완전한 뜻밖의 행운이었다."
  };

  @override
  void initState() {
    super.initState();
    fetchTodayWord();
  }

  Future<void> fetchTodayWord() async {
    setState(() {
      isLoading = true;
    });

    try {
      final res = await http.get(Uri.parse(dataUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        final prefs = await SharedPreferences.getInstance();
        final savedKey = 'memorized_${data["date"]}';
        final checked = prefs.getBool(savedKey) ?? false;

        setState(() {
          wordData = data;
          isMemorized = checked;
          isLoading = false;
        });
        return;
      }
    } catch (_) {}

    setState(() {
      wordData = fallbackWord;
      isLoading = false;
    });
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
            Container(
              height: 55,
              width: double.infinity,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: Text(
                '구글 AdMob 배너 광고 영역',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildContent() {
    if (isLoading) {
      return const CircularProgressIndicator();
    }

    final data = wordData ?? fallbackWord;

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
                  data['date'] ?? '',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    data['part_of_speech'] ?? '',
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
              data['word'] ?? '',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data['phonetic'] ?? '',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Text(
              data['meaning'] ?? '',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const Divider(height: 36),
            Text(
              data['example_en'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              data['example_ko'] ?? '',
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

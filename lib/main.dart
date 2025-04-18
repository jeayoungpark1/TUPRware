import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_size/window_size.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    setWindowTitle('TUPRware: Thyroid Ultrasound Practice Software');
    setWindowFrame(const Rect.fromLTWH(100, 100, 1440, 960));
  }

  runApp(const TuprWareApp());
}

class TuprWareApp extends StatelessWidget {
  const TuprWareApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUPRware: Thyroid Ultrasound Practice Software',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const FlashcardScreen(),
    );
  }
}

class UserAnswerLog {
  final String imageName;
  final DateTime timestamp;

  /// New: each answer includes index, and maybe label
  final Map<String, Map<String, dynamic>> userAnswers;

  UserAnswerLog({
    required this.imageName,
    required this.timestamp,
    required this.userAnswers,
  });

  Map<String, dynamic> toJson() => {
    'imageName': imageName,
    'timestamp': timestamp.toIso8601String(),
    'userAnswers': userAnswers,
  };

  static UserAnswerLog fromJson(Map<String, dynamic> json) {
    return UserAnswerLog(
      imageName: json['imageName'],
      timestamp: DateTime.parse(json['timestamp']),
      userAnswers: Map<String, Map<String, dynamic>>.from(
        (json['userAnswers'] as Map).map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        ),
      ),
    );
  }
}

class XThumbShape extends SliderComponentShape {
  final double size;
  const XThumbShape({this.size = 16});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(size, size);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required Size sizeWithOverflow,
    required SliderThemeData sliderTheme,
    required ui.TextDirection textDirection,

    required double textScaleFactor,
    required double value,
  }) {
    final canvas = context.canvas;
    final paint =
        Paint()
          ..color = Colors.red.withOpacity(0.7)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

    final double halfSize = size / 2;

    canvas.drawLine(
      Offset(center.dx - halfSize, center.dy - halfSize),
      Offset(center.dx + halfSize, center.dy + halfSize),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + halfSize, center.dy - halfSize),
      Offset(center.dx - halfSize, center.dy + halfSize),
      paint,
    );
  }
}

class BiggerGreenThumb extends RoundSliderThumbShape {
  final double thumbRadius;

  const BiggerGreenThumb({this.thumbRadius = 10});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required Size sizeWithOverflow, // ✅ moved up
    required SliderThemeData sliderTheme,
    required ui.TextDirection textDirection,

    required double textScaleFactor,
    required double value, // ✅ moved to bottom
  }) {
    final canvas = context.canvas;
    final paint = Paint()..color = Colors.green[400]!;
    canvas.drawCircle(center, thumbRadius, paint);
  }
}

class HiddenThumb extends SliderComponentShape {
  const HiddenThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required Size sizeWithOverflow,
    required SliderThemeData sliderTheme,
    required ui.TextDirection textDirection,

    required double textScaleFactor,
    required double value,
  }) {
    // Intentionally empty - invisible thumb
  }
}

class Flashcard {
  final ImageProvider image;
  final Map<String, Map<String, dynamic>> correctAnswers;
  final String explanation;
  final double? dimension;
  final String? followup;

  Flashcard({
    required this.image,
    required this.correctAnswers,
    required this.explanation,
    this.followup,
    this.dimension,
  });
}

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({Key? key}) : super(key: key);

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<UserAnswerLog> _answerLogs = [];
  bool _showStatsScreen = false;
  Set<String> _submittedImages = {};
  bool _initialized = false;
  final List<Flashcard> _cards = [];
  int _currentIndex = 0;
  bool _showAnswer = false;
  final List<String> _followupOptions = [
    'No further followup',
    'Followup ultrasound',
    'FNA',
  ];

  late Map<String, int> _answers;

  final Map<String, List<Map<String, dynamic>>> _options = {
    'Composition': [
      {'label': 'Cystic or almost completely cystic', 'score': 0},
      {'label': 'Spongiform', 'score': 0},
      {'label': 'Mixed cystic and solid', 'score': 1},
      {'label': 'Solid or almost completely solid', 'score': 2},
    ],
    'Echogenicity': [
      {'label': 'Anechoic', 'score': 0},
      {'label': 'NA-Spongiform', 'score': 0},
      {'label': 'Hyperechoic or isoechoic', 'score': 1},
      {'label': 'Hypoechoic', 'score': 2},
      {'label': 'Very hypoechoic', 'score': 3},
    ],
    'Shape': [
      {'label': 'Wider-than-tall', 'score': 0},
      {'label': 'NA-Spongiform', 'score': 0},
      {'label': 'Taller-than-wide', 'score': 3},
    ],
    'Margin': [
      {'label': 'Smooth', 'score': 0},
      {'label': 'Ill-defined', 'score': 0},
      {'label': 'NA-Spongiform', 'score': 0},
      {'label': 'Lobulated or irregular', 'score': 2},
      {'label': 'Extra-thyroidal extension', 'score': 3},
    ],
    'Echogenic Foci': [
      {'label': 'None or large comet-tail artifacts', 'score': 0},
      {'label': 'Macrocalcifications', 'score': 1},
      {'label': 'Peripheral (rim) calcifications', 'score': 2},
      {'label': 'Punctate echogenic foci', 'score': 3},
    ],
  };

  final appTitleStyle = const TextStyle(
    fontFamily: 'Nunito',
    fontSize: 24,
    //fontWeight: FontWeight.bold,
  );
  @override
  void initState() {
    super.initState();
    // Can't use context here for precaching
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_initialized) {
      _loadInitialFlashcards();
      _initialized = true;
    }
  }

  Future<void> _loadInitialFlashcards() async {
    _cards.clear();

    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    // Find all JPG images in assets/flashcards/
    final imagePaths =
        manifestMap.keys
            .where(
              (path) =>
                  path.startsWith('assets/flashcards/') &&
                  path.endsWith('.jpg'),
            )
            .toList();

    for (final imagePath in imagePaths) {
      final baseName = imagePath.split('/').last.split('.').first;
      final jsonPath = 'assets/flashcards/$baseName.json';

      if (!manifestMap.containsKey(jsonPath)) {
        debugPrint('⚠️ Skipping $imagePath — no matching JSON file.');
        continue;
      }

      try {
        final image = AssetImage(imagePath);
        await precacheImage(image, context);

        final jsonString = await rootBundle.loadString(jsonPath);
        final Map<String, dynamic> jsonMap = json.decode(jsonString);

        final explanation = jsonMap['Explanation'] ?? '';
        jsonMap.remove('Explanation');

        final double? dimension = (jsonMap['Dimension'] as num?)?.toDouble();
        jsonMap.remove('Dimension');

        final String? followup = jsonMap['Followup'] as String?;
        jsonMap.remove(
          'Followup',
        ); // Remove to avoid messing up the correctAnswers loop

        final Map<String, Map<String, dynamic>> correctAnswers = {};
        final validKeys = [
          'Composition',
          'Echogenicity',
          'Shape',
          'Margin',
          'Echogenic Foci',
        ];
        for (final label in validKeys) {
          if (jsonMap.containsKey(label)) {
            final value = jsonMap[label];
            correctAnswers[label] = {
              'label': value['label'],
              'score': value['score'],
            };
          }
        }

        _cards.add(
          Flashcard(
            image: image,
            correctAnswers: correctAnswers,
            explanation: explanation,
            dimension: dimension,
            followup: followup,
          ),
        );
      } catch (e) {
        debugPrint('⚠️ Error loading $imagePath: $e');
      }
    }

    setState(() {
      _currentIndex = 0;
      _answers = {for (var category in _options.keys) category: 0};
      _answers['Followup'] = -1;
      _answers.putIfAbsent('Followup', () => 0);

      _showAnswer = false;
    });
  }

  void _nextCard() {
    setState(() {
      if (_currentIndex < _cards.length - 1) {
        _currentIndex++;

        final imageName = (_cards[_currentIndex].image as AssetImage).assetName;
        final matchingLogs = _answerLogs.where(
          (log) => log.imageName == imageName,
        );
        final log = matchingLogs.isNotEmpty ? matchingLogs.first : null;

        if (log != null) {
          _answers.clear();
          for (final entry in log.userAnswers.entries) {
            _answers[entry.key] = entry.value['selectedIndex'];
          }
          _showAnswer = true;
        } else {
          _answers.updateAll((key, value) => 0);
          _answers['Followup'] = -1;
          _answers.putIfAbsent('Followup', () => -1);

          _showAnswer = false;
        }
      }
    });
  }

  void _prevCard() {
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;

        final imageName = (_cards[_currentIndex].image as AssetImage).assetName;
        final matchingLogs = _answerLogs.where(
          (log) => log.imageName == imageName,
        );
        final log = matchingLogs.isNotEmpty ? matchingLogs.first : null;

        if (log != null) {
          _answers.clear();
          for (final entry in log.userAnswers.entries) {
            _answers[entry.key] = entry.value['selectedIndex'];
          }
          _showAnswer = true;
        } else {
          _answers.updateAll((key, value) => 0);
          _answers['Followup'] = -1;
          _answers.putIfAbsent('Followup', () => -1);

          _showAnswer = false;
        }
      }
    });
  }

  int _calculateScore() {
    return _options.keys
        .map((label) => _options[label]![_answers[label] ?? 0]['score'] as int)
        .fold(0, (a, b) => a + b);
  }

  int _correctScore() {
    final correctAnswers = _cards[_currentIndex].correctAnswers;

    return correctAnswers.entries
        .map((entry) => entry.value['score'] as int)
        .fold(0, (a, b) => a + b);
  }

  String _trCategory(int score) {
    if (score <= 1) return 'TR1';
    if (score == 2) return 'TR2';
    if (score == 3) return 'TR3';
    if (score >= 4 && score <= 6) return 'TR4';
    return 'TR5';
  }

  bool _isAnswerCorrect(String label) {
    final entries = _options[label]!;
    final selectedIndex = _answers[label] ?? 0;

    final correctData = _cards[_currentIndex].correctAnswers[label]!;
    final correctScore = correctData['score'];
    final correctLabel = correctData['label'].toString().toLowerCase().trim();

    final selectedEntry = entries[selectedIndex];
    final selectedLabel =
        selectedEntry['label'].toString().toLowerCase().trim();

    final matchingEntries =
        entries.where((e) => e['score'] == correctScore).toList();

    if (matchingEntries.length == 1) {
      return selectedEntry['score'] == correctScore;
    } else {
      final intendedEntry = matchingEntries.firstWhere((e) {
        final optionLabel = e['label'].toString().toLowerCase().trim();
        return optionLabel == correctLabel ||
            optionLabel.contains(correctLabel) ||
            correctLabel.contains(optionLabel);
      }, orElse: () => matchingEntries.first);

      final intendedLabel =
          intendedEntry['label'].toString().toLowerCase().trim();
      return selectedLabel == intendedLabel;
    }
  }

  Future<void> _saveAnswerLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _answerLogs.map((log) => jsonEncode(log.toJson())).toList();
    await prefs.setStringList('answerLogs', encoded);
  }

  Future<void> _loadAnswerLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('answerLogs') ?? [];
    setState(() {
      _answerLogs =
          data.map((str) => UserAnswerLog.fromJson(jsonDecode(str))).toList();
    });
  }

  Future<void> _clearAnswerLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('answerLogs');
    setState(() {
      _answerLogs.clear();
    });
  }

  Widget _buildSlider(String label, BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 700;
    final entries = _options[label]!;
    final selectedIndex = _answers[label] ?? 0;

    final correctData = _cards[_currentIndex].correctAnswers[label]!;
    final correctScore = correctData['score'];
    final correctLabel = correctData['label'].toString().toLowerCase().trim();

    final selectedEntry = entries[selectedIndex];
    final selectedLabel =
        selectedEntry['label'].toString().toLowerCase().trim();

    final matchingEntries =
        entries.where((e) => e['score'] == correctScore).toList();

    late final bool isCorrect;

    if (matchingEntries.length == 1) {
      isCorrect = selectedEntry['score'] == correctScore;
    } else {
      final intendedEntry = matchingEntries.firstWhere((e) {
        final optionLabel = e['label'].toString().toLowerCase().trim();
        return optionLabel == correctLabel ||
            optionLabel.contains(correctLabel) ||
            correctLabel.contains(optionLabel);
      }, orElse: () => matchingEntries.first);

      final intendedLabel =
          intendedEntry['label'].toString().toLowerCase().trim();
      isCorrect = selectedLabel == intendedLabel;
    }

    final intendedEntry = entries.firstWhere((e) {
      final optionLabel = e['label'].toString().toLowerCase().trim();
      return e['score'] == correctScore &&
          (optionLabel == correctLabel ||
              optionLabel.contains(correctLabel) ||
              correctLabel.contains(optionLabel));
    }, orElse: () => entries.firstWhere((e) => e['score'] == correctScore));

    final correctIndex = entries.indexOf(intendedEntry);

    /// 🔀 Return based on layout mode
    return isWideScreen
        ? _buildVerticalSliderLayout(
          label,
          entries,
          selectedIndex,
          correctIndex,
          isCorrect,
        )
        : _buildHorizontalSliderLayout(
          label,
          entries,
          selectedIndex,
          correctIndex,
          isCorrect,
        );
  }

  Widget _buildVerticalSliderLayout(
    String label,
    List<Map<String, dynamic>> entries,
    int selectedIndex,
    int correctIndex,
    bool isCorrect,
  ) {
    return SizedBox(
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ✅ Green Thumb for correct answer
                if (_showAnswer)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RotatedBox(
                        quarterTurns: -1,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbColor: Colors.green[600],
                            thumbShape: const BiggerGreenThumb(thumbRadius: 10),
                            activeTrackColor: Colors.green[400]!.withOpacity(
                              0.5,
                            ),
                            inactiveTrackColor: Colors.green[400]!.withOpacity(
                              0.1,
                            ),
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Slider(
                            value: correctIndex.toDouble(),
                            min: 0,
                            max: (entries.length - 1).toDouble(),
                            divisions: entries.length - 1,
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ),

                // 🔴 User’s Answer Thumb
                Positioned.fill(
                  child: RotatedBox(
                    quarterTurns: -1,
                    child: IgnorePointer(
                      ignoring: _showAnswer,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbColor:
                              _showAnswer
                                  ? (isCorrect
                                      ? Colors.transparent
                                      : Colors.red)
                                  : Colors.indigo[400],
                          thumbShape:
                              _showAnswer
                                  ? (isCorrect
                                      ? const HiddenThumb()
                                      : const XThumbShape(size: 10))
                                  : const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                          activeTrackColor:
                              _showAnswer
                                  ? Colors.transparent
                                  : Colors.indigo[400]!.withOpacity(0.5),
                          inactiveTrackColor:
                              _showAnswer
                                  ? Colors.transparent
                                  : Colors.indigo[400]!.withOpacity(0.1),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: selectedIndex.toDouble(),
                          min: 0,
                          max: (entries.length - 1).toDouble(),
                          divisions: entries.length - 1,
                          onChanged: (value) {
                            setState(() {
                              _answers[label] = value.round();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // 💬 Score bubble
                Positioned(
                  top: 90,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _showAnswer
                              ? (isCorrect
                                  ? Colors.green[100]
                                  : Colors.red[100])
                              : Colors.indigo[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _showAnswer
                          ? '${entries[correctIndex]['score']}'
                          : '${entries[selectedIndex]['score']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSliderLayout(
    String label,
    List<Map<String, dynamic>> entries,
    int selectedIndex,
    int correctIndex,
    bool isCorrect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            if (_showAnswer)
              IgnorePointer(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbColor: Colors.green[600],
                    thumbShape: const BiggerGreenThumb(thumbRadius: 10),
                    activeTrackColor: Colors.green[400]!.withOpacity(0.5),
                    inactiveTrackColor: Colors.green[400]!.withOpacity(0.1),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: correctIndex.toDouble(),
                    min: 0,
                    max: (entries.length - 1).toDouble(),
                    divisions: entries.length - 1,
                    onChanged: (_) {},
                  ),
                ),
              ),

            IgnorePointer(
              ignoring: _showAnswer,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbColor:
                      _showAnswer
                          ? (isCorrect ? Colors.transparent : Colors.red)
                          : Colors.indigo[400],
                  thumbShape:
                      _showAnswer
                          ? (isCorrect
                              ? const HiddenThumb()
                              : const XThumbShape(size: 10))
                          : const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor:
                      _showAnswer
                          ? Colors.transparent
                          : Colors.indigo[400]!.withOpacity(0.5),
                  inactiveTrackColor:
                      _showAnswer
                          ? Colors.transparent
                          : Colors.indigo[400]!.withOpacity(0.1),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: selectedIndex.toDouble(),
                  min: 0,
                  max: (entries.length - 1).toDouble(),
                  divisions: entries.length - 1,
                  onChanged: (value) {
                    setState(() {
                      _answers[label] = value.round();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6), //SCORE BUBBLE
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color:
                  _showAnswer
                      ? (isCorrect ? Colors.green[100] : Colors.red[100])
                      : Colors.indigo[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Score: ${_showAnswer ? entries[correctIndex]['score'] : entries[selectedIndex]['score']}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_showAnswer ? entries[correctIndex]['label'] : entries[selectedIndex]['label']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsView() {
    if (_answerLogs.isEmpty) {
      return const Center(child: Text('No data yet.'));
    }

    final Map<String, int> totalAttempts = {};
    final Map<String, int> totalCorrect = {};

    final List<Widget> logCards = [];

    for (final log in _answerLogs) {
      final filename = log.imageName.split('/').last;

      final matchingCard = _cards.firstWhere(
        (card) => (card.image as AssetImage).assetName == log.imageName,
        orElse:
            () => Flashcard(
              image: const AssetImage(''),
              correctAnswers: {},
              explanation: '',
            ),
      );

      final correctData = matchingCard.correctAnswers;
      int cardCorrectCount = 0;

      // Evaluate TI-RADS criteria (5 categories)
      for (final entry in log.userAnswers.entries) {
        final label = entry.key;
        if (!_options.containsKey(label)) continue;

        final selectedIndex = entry.value['selectedIndex'];
        final selectedLabel =
            entry.value['selectedLabel'].toString().toLowerCase().trim();

        final correctEntry = correctData[label];
        if (correctEntry == null) continue;

        final correctScore = correctEntry['score'];
        final correctLabel =
            correctEntry['label'].toString().toLowerCase().trim();

        final entries = _options[label]!;
        final selectedEntry = entries[selectedIndex];
        final matchingEntries =
            entries.where((e) => e['score'] == correctScore).toList();

        bool isCorrect;
        if (matchingEntries.length == 1) {
          isCorrect = selectedEntry['score'] == correctScore;
        } else {
          final intendedEntry = matchingEntries.firstWhere((e) {
            final optionLabel = e['label'].toString().toLowerCase().trim();
            return optionLabel == correctLabel ||
                optionLabel.contains(correctLabel) ||
                correctLabel.contains(optionLabel);
          }, orElse: () => matchingEntries.first);

          final intendedLabel =
              intendedEntry['label'].toString().toLowerCase().trim();
          isCorrect = selectedLabel == intendedLabel;
        }

        totalAttempts[label] = (totalAttempts[label] ?? 0) + 1;
        if (isCorrect) {
          totalCorrect[label] = (totalCorrect[label] ?? 0) + 1;
          cardCorrectCount++;
        }
      }

      // Followup logic
      final followupIndex = log.userAnswers['Followup']?['selectedIndex'];
      final followupLabel =
          (followupIndex != null &&
                  followupIndex >= 0 &&
                  followupIndex < _followupOptions.length)
              ? _followupOptions[followupIndex]
              : '';

      final actualFollowup = matchingCard.followup ?? '';
      final isFollowupCorrect =
          followupLabel.toLowerCase().trim() ==
          actualFollowup.toLowerCase().trim();

      // Card color logic
      Color cardColor;
      if (cardCorrectCount == 5 && isFollowupCorrect) {
        cardColor = Colors.teal[100]!;
      } else if ((cardCorrectCount == 5 && !isFollowupCorrect) ||
          (cardCorrectCount >= 3 && isFollowupCorrect)) {
        cardColor = Colors.yellow[100]!;
      } else {
        cardColor = Colors.red[100]!;
      }

      final formattedTime = DateFormat(
        'MMM d, yyyy – h:mm a',
      ).format(log.timestamp);

      final trailingText =
          '$cardCorrectCount/5 criteria correct\n${isFollowupCorrect ? "Plan correct" : "Plan incorrect"}';

      logCards.add(
        Card(
          color: cardColor,
          child: ListTile(
            title: Text(filename),
            subtitle: Text('Submitted: $formattedTime'),
            trailing: Text(
              trailingText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: () {
              final cardIndex = _cards.indexWhere(
                (card) => (card.image as AssetImage).assetName == log.imageName,
              );

              if (cardIndex != -1) {
                setState(() {
                  _currentIndex = cardIndex;
                  _showAnswer = true;
                  _showStatsScreen = false;

                  final savedAnswers = log.userAnswers;
                  for (final entry in savedAnswers.entries) {
                    final label = entry.key;
                    final selectedIndex = entry.value['selectedIndex'];
                    _answers[label] = selectedIndex;
                  }
                });

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Jumped to $filename')));
              }
            },
          ),
        ),
      );
    }

    final performanceSummary =
        _options.keys.map((label) {
          final attempted = totalAttempts[label] ?? 0;
          final correct = totalCorrect[label] ?? 0;
          final percent =
              attempted == 0 ? 0 : ((correct / attempted) * 100).round();

          return Text(
            '$label: $correct / $attempted correct (${percent}%)',
            style: const TextStyle(fontSize: 16),
          );
        }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: logCards,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Performance by Category',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...performanceSummary,
                    ],
                  ),
                ),
              ),
            ],
          );
        } else {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...logCards,
              const SizedBox(height: 20),
              const Divider(),
              const Text(
                'Performance by Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...performanceSummary,
            ],
          );
        }
      },
    );
  }

  Widget _buildFollowupSection() {
    final selectedIndex = _answers['Followup'] ?? -1;
    final correctLabel = _cards[_currentIndex].followup ?? '';
    final hasSelected = selectedIndex >= 0;
    final selectedLabel =
        hasSelected && selectedIndex < _followupOptions.length
            ? _followupOptions[selectedIndex]
            : '';

    final isCorrect =
        hasSelected &&
        selectedLabel.toLowerCase().trim() == correctLabel.toLowerCase().trim();

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text(
              'Recommend:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(_followupOptions.length, (index) {
              final label = _followupOptions[index];
              final isSelected = selectedIndex == index;
              final normalizedLabel = label.toLowerCase().trim();
              final normalizedCorrect = correctLabel.toLowerCase().trim();
              final showCorrect =
                  _showAnswer && normalizedLabel == normalizedCorrect;

              return Row(
                children: [
                  Radio<int>(
                    value: index,
                    groupValue: hasSelected ? selectedIndex : null,
                    onChanged:
                        _showAnswer
                            ? null
                            : (value) {
                              setState(() {
                                _answers['Followup'] = value!;
                              });
                            },
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight:
                          isSelected && _showAnswer
                              ? (isCorrect
                                  ? FontWeight.normal
                                  : FontWeight.bold)
                              : FontWeight.normal,
                      color:
                          _showAnswer
                              ? (isSelected
                                  ? (isCorrect
                                      ? Colors.green[700]
                                      : Colors.red[700])
                                  : (showCorrect ? Colors.green[700] : null))
                              : null,
                      decoration:
                          _showAnswer && isSelected && !isCorrect
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 700;
    if (_showStatsScreen) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Statistics', style: appTitleStyle),
          actions:
              isWideScreen
                  ? [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showStatsScreen = false;
                          });
                        },
                        icon: const Icon(Icons.arrow_back, size: 20),
                        label: const Text('Back to Questions'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ]
                  : null,
        ),
        body: _buildStatsView(),
        floatingActionButton:
            isWideScreen
                ? null
                : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      setState(() {
                        _showStatsScreen = false;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Questions'),
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.indigo,
                  ),
                ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      );
    }

    if (_cards.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentCard = _cards[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title:
            _showStatsScreen
                ? Text('Statistics', style: appTitleStyle)
                : Text(
                  'Image ${_currentIndex + 1} of ${_cards.length}',
                  style: appTitleStyle,
                ),
        actions: [
          if (_showStatsScreen)
            TextButton(
              onPressed: () {
                setState(() {
                  _showStatsScreen = false;
                });
              },
              child: const Text(
                'Back to Question',
                style: TextStyle(color: Colors.white),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, // 👈 makes it solid & visible
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.menu,
                    color: Colors.black,
                  ), // ☰ Hamburger icon
                  color: Colors.white,
                  elevation: 8,
                  onSelected: (value) async {
                    if (value == 'stats') {
                      setState(() {
                        _showStatsScreen = true;
                      });
                    } else if (value == 'clear') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('Clear All Data'),
                              content: const Text(
                                'Are you sure you want to delete all your answer history and start over?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Yes, Clear All'),
                                ),
                              ],
                            ),
                      );
                      if (confirm == true) {
                        await _clearAnswerLogs();
                        setState(() {
                          _currentIndex = 0;
                          _answers.updateAll((key, value) => 0);
                          _showAnswer = false;
                          _submittedImages.clear();
                          _showStatsScreen = false;
                        });
                      }
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'stats',
                          child: Text('Statistics'),
                        ),
                        const PopupMenuItem(
                          value: 'clear',
                          child: Text('Clear All Answers'),
                        ),
                      ],
                ),
              ),
            ),
        ],
      ),
      body:
          isWideScreen
              ? _buildWideLayout(currentCard)
              : _buildNarrowLayout(currentCard),
    );
  }

  Widget _buildWideLayout(Flashcard currentCard) {
    final dynamicScore = _calculateScore();
    final dynamicCategory = _trCategory(dynamicScore);

    final correctScore = _correctScore();
    final correctCategory = _trCategory(correctScore);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image(image: currentCard.image, fit: BoxFit.contain),
                    if (_submittedImages.contains(
                      (_cards[_currentIndex].image as AssetImage).assetName,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green[600],
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Submitted',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 20),

          /// Right side – Sliders, score, buttons, explanation
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 Sliders
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      _options.keys.map((label) {
                        final userLabel =
                            _options[label]![_answers[label] ?? 0]['label']
                                as String;
                        final isCorrect = _isAnswerCorrect(label);
                        final correctData =
                            currentCard.correctAnswers[label]!
                                as Map<String, dynamic>;
                        final correctLabelText =
                            correctData['label']?.toString() ?? '';

                        return SizedBox(
                          width: 120,
                          child: Column(
                            children: [
                              _buildSlider(label, context),
                              const SizedBox(height: 8),
                              Text(
                                userLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      !_showAnswer
                                          ? Colors.black
                                          : (isCorrect
                                              ? Colors.black
                                              : Colors.red),
                                  decoration:
                                      !_showAnswer
                                          ? TextDecoration.none
                                          : (isCorrect
                                              ? TextDecoration.none
                                              : TextDecoration.lineThrough),
                                  fontWeight:
                                      !_showAnswer
                                          ? FontWeight.normal
                                          : (isCorrect
                                              ? FontWeight.normal
                                              : FontWeight.bold),
                                ),
                              ),
                              if (_showAnswer && !isCorrect)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    correctLabelText,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'TI-RADS Score: ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_showAnswer && dynamicScore != correctScore) ...[
                          Text(
                            '$dynamicScore',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$correctScore',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ] else ...[
                          Text(
                            '$dynamicScore',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color:
                                  _showAnswer
                                      ? Colors.green[700]
                                      : Colors.black,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (currentCard.dimension != null)
                      Text(
                        '(max. dimension ${currentCard.dimension!.toStringAsFixed(1)} cm)',
                        style: const TextStyle(
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Text(
                      'TI-RADS Category: ',
                      style: const TextStyle(fontSize: 20),
                    ),
                    if (_showAnswer && dynamicCategory != correctCategory) ...[
                      Text(
                        dynamicCategory,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.red,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        correctCategory,
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ] else ...[
                      Text(
                        dynamicCategory,
                        style: TextStyle(
                          fontSize: 20,
                          color: _showAnswer ? Colors.green[700] : Colors.black,
                        ),
                      ),
                    ],
                  ],
                ),
                _buildFollowupSection(),
                const SizedBox(height: 16),

                // 🔹 Buttons
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _currentIndex > 0 ? _prevCard : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _currentIndex > 0 ? null : Colors.grey[300],
                        foregroundColor:
                            _currentIndex > 0 ? null : Colors.grey[600],
                      ),
                      child: const Text('Previous Image'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed:
                          _currentIndex < _cards.length - 1 ? _nextCard : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _currentIndex < _cards.length - 1
                                ? null
                                : Colors.grey[300],
                        foregroundColor:
                            _currentIndex < _cards.length - 1
                                ? null
                                : Colors.grey[600],
                      ),
                      child: const Text('Next Image'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        if ((_answers['Followup'] ?? -1) == -1) {
                          await showDialog<void>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Incomplete Answer'),
                                  content: const Text(
                                    'Please choose the appropriate followup plan for this nodule.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                          );
                          return; // ⛔ Do not submit
                        }
                        final imageName =
                            (_cards[_currentIndex].image as AssetImage)
                                .assetName;

                        // If already submitted, confirm overwrite
                        if (_submittedImages.contains(imageName)) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Resubmit Answer?'),
                                  content: const Text(
                                    'You’ve already submitted an answer for this image. Submitting again will replace your previous submission.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Resubmit'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm != true) return; // ⛔ User cancelled
                        }

                        setState(() {
                          _showAnswer = true;

                          _submittedImages.add(
                            imageName,
                          ); // still track that it's submitted

                          // Build the detailed answer map
                          final userAnswers = <String, Map<String, dynamic>>{};

                          _answers.forEach((label, index) {
                            if (_options.containsKey(label)) {
                              final labelText =
                                  _options[label]![index]['label'];
                              userAnswers[label] = {
                                'selectedIndex': index,
                                'selectedLabel': labelText,
                              };
                            } else if (label == 'Followup') {
                              final labelText = _followupOptions[index];
                              userAnswers[label] = {
                                'selectedIndex': index,
                                'selectedLabel': labelText,
                              };
                            }
                          });

                          // Remove old log (if any), then add updated one
                          _answerLogs.removeWhere(
                            (log) => log.imageName == imageName,
                          );
                          _answerLogs.add(
                            UserAnswerLog(
                              imageName: imageName,
                              timestamp: DateTime.now(),
                              userAnswers: userAnswers,
                            ),
                          );

                          _saveAnswerLogs();
                        });
                      },
                      child: const Text('Submit Answer'),
                    ),
                    const SizedBox(width: 10),
                    //Clear Answer Button
                    ElevatedButton(
                      onPressed: () {
                        final imageName =
                            (_cards[_currentIndex].image as AssetImage)
                                .assetName;
                        setState(() {
                          _showAnswer = false;
                          _answers.updateAll((key, value) => 0);

                          // Remove from submitted images
                          _submittedImages.remove(imageName);

                          // Remove from answer logs
                          _answerLogs.removeWhere(
                            (log) => log.imageName == imageName,
                          );

                          _saveAnswerLogs(); // persist the cleaned logs
                        });
                      },
                      child: const Text('Clear Answer'),
                    ),
                  ],
                ),

                // 🔹 Explanation
                if (_showAnswer && currentCard.explanation.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Explanation',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 150,
                            child: Stack(
                              children: [
                                Scrollbar(
                                  thumbVisibility: true,
                                  radius: const Radius.circular(4),
                                  thickness: 6,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      currentCard.explanation,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 20,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.grey[100]!.withOpacity(0.0),
                                            Colors.grey[100]!,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(Flashcard currentCard) {
    final dynamicScore = _calculateScore();
    final dynamicCategory = _trCategory(dynamicScore);

    final correctScore = _correctScore();
    final correctCategory = _trCategory(correctScore);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              const SizedBox(height: 10),
              Image(image: currentCard.image, fit: BoxFit.contain),
              if (currentCard.dimension != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        '(max. dimension ${currentCard.dimension!.toStringAsFixed(1)} cm)',
        style: const TextStyle(
          fontSize: 14,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  ),
              if (_submittedImages.contains(
                (_cards[_currentIndex].image as AssetImage).assetName,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[600],
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Submitted',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 🔹 Vertical stacked sliders
          ..._options.keys.map(
            (label) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: _buildSlider(label, context),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Text(
                    'TI-RADS Score: ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_showAnswer && dynamicScore != correctScore) ...[
                    Text(
                      '$dynamicScore',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$correctScore',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ] else ...[
                    Text(
                      '$dynamicScore',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _showAnswer ? Colors.green[700] : Colors.black,
                      ),
                    ),
                  ],
                ],
              ),
              
            ],
          ),

          const SizedBox(height: 4),

          Row(
            children: [
              Text('TI-RADS Category: ', style: const TextStyle(fontSize: 20)),
              if (_showAnswer && dynamicCategory != correctCategory) ...[
                Text(
                  dynamicCategory,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.red,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  correctCategory,
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else ...[
                Text(
                  dynamicCategory,
                  style: TextStyle(
                    fontSize: 20,
                    color: _showAnswer ? Colors.green[700] : Colors.black,
                  ),
                ),
              ],
            ],
          ),
          _buildFollowupSection(),

          const SizedBox(height: 16),

          // 🔹 Buttons
          Column(
            children: [
              // 🔹 Row 1: Navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _currentIndex > 0 ? _prevCard : null,
                    child: const Text('Previous Image'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed:
                        _currentIndex < _cards.length - 1 ? _nextCard : null,
                    child: const Text('Next Image'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 🔹 Row 2: Reveal/Clear Answer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      if ((_answers['Followup'] ?? -1) == -1) {
                        await showDialog<void>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('Incomplete Answer'),
                                content: const Text(
                                  'Please choose the appropriate followup plan for this nodule.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                        );
                        return; // ⛔️ Stops submission
                      }
                      final imageName =
                          (_cards[_currentIndex].image as AssetImage).assetName;

                      // If already submitted, confirm overwrite
                      if (_submittedImages.contains(imageName)) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('Resubmit Answer?'),
                                content: const Text(
                                  'You’ve already submitted an answer for this image. Submitting again will replace your previous submission.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    child: const Text('Resubmit'),
                                  ),
                                ],
                              ),
                        );

                        if (confirm != true) return; // ⛔ User cancelled
                      }

                      setState(() {
                        _showAnswer = true;

                        _submittedImages.add(
                          imageName,
                        ); // still track that it's submitted

                        // Build the detailed answer map
                        final userAnswers = <String, Map<String, dynamic>>{};

                        _answers.forEach((label, index) {
                          if (_options.containsKey(label)) {
                            final labelText = _options[label]![index]['label'];
                            userAnswers[label] = {
                              'selectedIndex': index,
                              'selectedLabel': labelText,
                            };
                          } else if (label == 'Followup') {
                            final labelText = _followupOptions[index];
                            userAnswers[label] = {
                              'selectedIndex': index,
                              'selectedLabel': labelText,
                            };
                          }
                        });

                        // Remove old log (if any), then add updated one
                        _answerLogs.removeWhere(
                          (log) => log.imageName == imageName,
                        );
                        _answerLogs.add(
                          UserAnswerLog(
                            imageName: imageName,
                            timestamp: DateTime.now(),
                            userAnswers: userAnswers,
                          ),
                        );

                        _saveAnswerLogs();
                      });
                    },
                    child: const Text('Submit Answer'),
                  ),

                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      final imageName =
                          (_cards[_currentIndex].image as AssetImage).assetName;
                      setState(() {
                        _showAnswer = false;
                        _answers.updateAll((key, value) => 0);

                        // Remove from submitted images
                        _submittedImages.remove(imageName);

                        // Remove from answer logs
                        _answerLogs.removeWhere(
                          (log) => log.imageName == imageName,
                        );

                        _saveAnswerLogs(); // persist the cleaned logs
                      });
                    },
                    child: const Text('Clear Answer'),
                  ),
                ],
              ),
            ],
          ),

          // 🔹 Explanation
          if (_showAnswer && currentCard.explanation.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Explanation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentCard.explanation,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

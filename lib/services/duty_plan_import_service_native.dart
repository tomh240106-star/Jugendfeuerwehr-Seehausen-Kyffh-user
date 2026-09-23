import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'duty_plan_row.dart';

class DutyPlanImportService {
  static bool get isSupported => true;

  static Future<List<DutyPlanRow>> extractFromImage(String filePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final image = InputImage.fromFilePath(filePath);
      final recognized = await recognizer.processImage(image);

      final lines = <_OcrLine>[];
      final words = <_OcrWord>[];

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final lineText = _clean(line.text);
          if (lineText.isNotEmpty) {
            lines.add(
              _OcrLine(
                text: lineText,
                left: line.boundingBox.left,
                right: line.boundingBox.right,
                top: line.boundingBox.top,
                bottom: line.boundingBox.bottom,
              ),
            );
          }

          for (final element in line.elements) {
            final elementText = _clean(element.text);
            if (elementText.isEmpty) continue;

            words.add(
              _OcrWord(
                text: elementText,
                left: element.boundingBox.left,
                right: element.boundingBox.right,
                top: element.boundingBox.top,
                bottom: element.boundingBox.bottom,
              ),
            );
          }
        }
      }

      if (lines.isEmpty || words.isEmpty) return const <DutyPlanRow>[];

      final anchors = <_DateAnchor>[];
      for (final line in lines) {
        final date = _extractDate(line.text);
        if (date == null) continue;

        anchors.add(
          _DateAnchor(
            date: date,
            centerY: line.centerY,
          ),
        );
      }

      anchors.sort((a, b) => a.centerY.compareTo(b.centerY));

      final dedupedAnchors = <_DateAnchor>[];
      for (final anchor in anchors) {
        if (dedupedAnchors.isNotEmpty &&
            (dedupedAnchors.last.centerY - anchor.centerY).abs() < 8) {
          continue;
        }
        dedupedAnchors.add(anchor);
      }

      if (dedupedAnchors.isEmpty) return const <DutyPlanRow>[];

      double headerCenter(String label, double fallback) {
        final normalizedLabel = label.toLowerCase();

        for (final line in lines) {
          final normalized =
              line.text.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß]'), '');

          if (normalized == normalizedLabel) {
            return line.centerX;
          }
        }

        return fallback;
      }

      var maxRight = 0.0;
      for (final word in words) {
        if (word.right > maxRight) maxRight = word.right;
      }
      if (maxRight <= 0) maxRight = 1000;

      final xDate = headerCenter('datum', maxRight * 0.13);
      final xTime = headerCenter('uhrzeit', maxRight * 0.34);
      final xTopic = headerCenter('thema', maxRight * 0.60);
      final xLocation = headerCenter('ort', maxRight * 0.86);

      final boundaryDateTime = (xDate + xTime) / 2;
      final boundaryTimeTopic = (xTime + xTopic) / 2;
      final boundaryTopicLocation = (xTopic + xLocation) / 2;

      final rows = <DutyPlanRow>[];

      for (var i = 0; i < dedupedAnchors.length; i++) {
        final current = dedupedAnchors[i];

        final previousY = i == 0 ? null : dedupedAnchors[i - 1].centerY;
        final nextY = i == dedupedAnchors.length - 1
            ? null
            : dedupedAnchors[i + 1].centerY;

        final defaultHalfHeight = i < dedupedAnchors.length - 1
            ? (dedupedAnchors[i + 1].centerY - current.centerY) / 2
            : i > 0
                ? (current.centerY - dedupedAnchors[i - 1].centerY) / 2
                : 28.0;

        final top = previousY == null
            ? current.centerY - defaultHalfHeight
            : (previousY + current.centerY) / 2;

        final bottom = nextY == null
            ? current.centerY + defaultHalfHeight
            : (current.centerY + nextY) / 2;

        final rowWords = words
            .where(
              (word) => word.centerY >= top && word.centerY < bottom,
            )
            .toList();

        final timeWords = <_OcrWord>[];
        final topicWords = <_OcrWord>[];
        final locationWords = <_OcrWord>[];

        for (final word in rowWords) {
          if (word.centerX < boundaryDateTime) {
            continue;
          } else if (word.centerX < boundaryTimeTopic) {
            timeWords.add(word);
          } else if (word.centerX < boundaryTopicLocation) {
            topicWords.add(word);
          } else {
            locationWords.add(word);
          }
        }

        final timeText = _joinWords(timeWords);
        final topic = _normalizeCell(_joinWords(topicWords));
        final location = _normalizeCell(_joinWords(locationWords));

        if (_isEmptyCell(topic)) continue;

        final times = _extractTimes(timeText);
        if (times.$1 == null) continue;

        rows.add(
          DutyPlanRow(
            date: current.date,
            startTime: times.$1!,
            endTime: times.$2,
            topic: topic,
            location: _isEmptyCell(location) ? '' : location,
          ),
        );
      }

      rows.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.startTime.compareTo(b.startTime);
      });

      return rows;
    } finally {
      await recognizer.close();
    }
  }

  static DateTime? _extractDate(String raw) {
    final text = raw.replaceAll('O', '0').replaceAll('o', '0');

    final match = RegExp(
      r'(?<!\d)(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(20\d{2})(?!\d)',
    ).firstMatch(text);

    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);

    if (day == null || month == null || year == null) return null;

    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) {
      return null;
    }

    return date;
  }

  static (String?, String?) _extractTimes(String raw) {
    final text = raw.replaceAll('O', '0').replaceAll('o', '0');

    final matches = RegExp(
      r'(?<!\d)(\d{1,2})\s*[:.]\s*(\d{2})(?!\d)',
    ).allMatches(text).toList();

    if (matches.isEmpty) return (null, null);

    String? format(RegExpMatch match) {
      final hour = int.tryParse(match.group(1)!);
      final minute = int.tryParse(match.group(2)!);

      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        return null;
      }

      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}:00';
    }

    final start = format(matches.first);
    final end = matches.length >= 2 ? format(matches[1]) : null;

    return (start, end);
  }

  static String _joinWords(List<_OcrWord> words) {
    if (words.isEmpty) return '';

    final sorted = [...words]..sort((a, b) {
        if ((a.centerY - b.centerY).abs() > 6) {
          return a.centerY.compareTo(b.centerY);
        }
        return a.left.compareTo(b.left);
      });

    final groups = <List<_OcrWord>>[];

    for (final word in sorted) {
      if (groups.isEmpty) {
        groups.add([word]);
        continue;
      }

      final lastGroup = groups.last;
      final averageY = lastGroup.map((w) => w.centerY).reduce((a, b) => a + b) /
          lastGroup.length;

      final tolerance = word.height > 0 ? word.height * 0.8 : 12.0;

      if ((word.centerY - averageY).abs() <= tolerance) {
        lastGroup.add(word);
      } else {
        groups.add([word]);
      }
    }

    final lines = <String>[];

    for (final group in groups) {
      group.sort((a, b) => a.left.compareTo(b.left));
      lines.add(group.map((word) => word.text).join(' '));
    }

    return _clean(lines.join(' '));
  }

  static String _normalizeCell(String value) {
    return _clean(value)
        .replaceAll(RegExp(r'\s*/\s*'), '/')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isEmptyCell(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .trim();

    return normalized.isEmpty || normalized == '-';
  }

  static String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _OcrLine {
  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;

  const _OcrLine({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

class _OcrWord {
  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;

  const _OcrWord({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

class _DateAnchor {
  final DateTime date;
  final double centerY;

  const _DateAnchor({
    required this.date,
    required this.centerY,
  });
}

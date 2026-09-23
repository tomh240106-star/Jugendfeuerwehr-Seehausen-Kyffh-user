// Web-only OCR implementation for Flutter Web.
// Uses modern dart:js_interop and dynamically imports Tesseract.js as an ES module.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'duty_plan_row.dart';

extension type _TesseractModule(JSObject _) implements JSObject {
  external JSPromise<_TesseractWorker> createWorker(String langs);
}

extension type _TesseractWorker(JSObject _) implements JSObject {
  external JSPromise<_TesseractResult> recognize(
    String image, [
    _EmptyOptions? options,
    _RecognizeOutput? output,
  ]);

  external JSPromise<JSAny?> terminate();
}

extension type _TesseractResult(JSObject _) implements JSObject {
  external _TesseractData get data;
}

extension type _TesseractData(JSObject _) implements JSObject {
  external String? get tsv;
}

extension type _EmptyOptions._(JSObject _) implements JSObject {
  external _EmptyOptions({bool? unused});
}

extension type _RecognizeOutput._(JSObject _) implements JSObject {
  external _RecognizeOutput({bool? tsv});
}

class DutyPlanWebOcr {
  static bool get isSupported => true;

  static const _tesseractModuleUrl =
      'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.esm.min.js';

  static _TesseractModule? _module;

  static Future<_TesseractModule> _loadModule() async {
    final cached = _module;
    if (cached != null) return cached;

    final jsModule = await importModule(_tesseractModuleUrl.toJS).toDart;
    final module = _TesseractModule(jsModule);
    _module = module;
    return module;
  }

  static Future<List<DutyPlanRow>> extractFromImageBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    if (bytes.isEmpty) return const <DutyPlanRow>[];

    final module = await _loadModule();
    final worker = await module.createWorker('deu').toDart;

    try {
      final mime = _mimeType(fileName);
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

      final result = await worker
          .recognize(
            dataUrl,
            _EmptyOptions(),
            _RecognizeOutput(tsv: true),
          )
          .toDart;

      final tsv = result.data.tsv ?? '';

      if (tsv.trim().isEmpty) {
        return const <DutyPlanRow>[];
      }

      return _parseTsv(tsv);
    } finally {
      try {
        await worker.terminate().toDart;
      } catch (_) {
        // Cleanup failures must not hide an OCR result/error.
      }
    }
  }

  static String _mimeType(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return 'image/jpeg';
    }

    if (name.endsWith('.png')) {
      return 'image/png';
    }

    if (name.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'application/octet-stream';
  }

  static List<DutyPlanRow> _parseTsv(String tsv) {
    final words = <_OcrWord>[];
    final rows = const LineSplitter().convert(tsv);

    if (rows.length <= 1) {
      return const <DutyPlanRow>[];
    }

    for (final row in rows.skip(1)) {
      if (row.trim().isEmpty) continue;

      final columns = row.split('\t');
      if (columns.length < 12) continue;

      // Tesseract TSV level 5 represents individual words.
      if (columns[0] != '5') continue;

      final text = _clean(columns.sublist(11).join('\t'));
      if (text.isEmpty) continue;

      final left = double.tryParse(columns[6]);
      final top = double.tryParse(columns[7]);
      final width = double.tryParse(columns[8]);
      final height = double.tryParse(columns[9]);

      if (left == null || top == null || width == null || height == null) {
        continue;
      }

      words.add(
        _OcrWord(
          text: text,
          left: left,
          right: left + width,
          top: top,
          bottom: top + height,
          lineKey: '${columns[1]}:${columns[2]}:${columns[3]}:${columns[4]}',
        ),
      );
    }

    if (words.isEmpty) {
      return const <DutyPlanRow>[];
    }

    final groupedLines = <String, List<_OcrWord>>{};

    for (final word in words) {
      groupedLines.putIfAbsent(word.lineKey, () => <_OcrWord>[]).add(word);
    }

    final lines = <_OcrLine>[];

    for (final group in groupedLines.values) {
      if (group.isEmpty) continue;

      group.sort((a, b) => a.left.compareTo(b.left));

      final text = _clean(group.map((e) => e.text).join(' '));
      if (text.isEmpty) continue;

      var left = group.first.left;
      var right = group.first.right;
      var top = group.first.top;
      var bottom = group.first.bottom;

      for (final word in group.skip(1)) {
        if (word.left < left) left = word.left;
        if (word.right > right) right = word.right;
        if (word.top < top) top = word.top;
        if (word.bottom > bottom) bottom = word.bottom;
      }

      lines.add(
        _OcrLine(
          text: text,
          left: left,
          right: right,
          top: top,
          bottom: bottom,
        ),
      );
    }

    lines.sort((a, b) => a.centerY.compareTo(b.centerY));

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

    if (dedupedAnchors.isEmpty) {
      return const <DutyPlanRow>[];
    }

    var maxRight = 0.0;

    for (final word in words) {
      if (word.right > maxRight) maxRight = word.right;
    }

    if (maxRight <= 0) maxRight = 1000;

    double headerCenter(String label, double fallback) {
      final normalizedLabel = label
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-zäöüß]'), '');

      for (final word in words) {
        final normalized = word.text
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-zäöüß]'), '');

        if (normalized == normalizedLabel) {
          return word.centerX;
        }
      }

      return fallback;
    }

    final xDate = headerCenter('datum', maxRight * 0.13);
    final xTime = headerCenter('uhrzeit', maxRight * 0.34);
    final xTopic = headerCenter('thema', maxRight * 0.60);
    final xLocation = headerCenter('ort', maxRight * 0.86);

    final boundaryDateTime = (xDate + xTime) / 2;
    final boundaryTimeTopic = (xTime + xTopic) / 2;
    final boundaryTopicLocation = (xTopic + xLocation) / 2;

    final result = <DutyPlanRow>[];

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
          .where((word) => word.centerY >= top && word.centerY < bottom)
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

      result.add(
        DutyPlanRow(
          date: current.date,
          startTime: times.$1!,
          endTime: times.$2,
          topic: topic,
          location: _isEmptyCell(location) ? '' : location,
        ),
      );
    }

    result.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    return result;
  }

  static DateTime? _extractDate(String raw) {
    final text = raw.replaceAll('O', '0').replaceAll('o', '0');

    final match = RegExp(
      r'(?<!\d)(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(20\d{2}|\d{2})(?!\d)',
    ).firstMatch(text);

    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);

    if (day == null || month == null || year == null) return null;

    if (year < 100) year += 2000;

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
  final String lineKey;

  const _OcrWord({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.lineKey,
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

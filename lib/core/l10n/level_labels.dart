import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// What the workspace calls its two academic levels (FND-03): Class / Section,
/// Course / Batch, or its own words. Messages name them with tokens, as on the
/// web (frontend/i18n/levelLabels.ts):
///
///   [[class]] [[Class]] [[classes]] [[Classes]] [[section]] [[Section]] [[sections]] [[Sections]]
///
/// Lower case for the middle of a sentence, capitalised for the start; Bangla
/// has one word per level.
@immutable
class LevelName {
  const LevelName({required this.one, required this.other, required this.bn});

  final String one;
  final String other;
  final String bn;

  static const maxLength = 30;

  static LevelName? fromJson(Object? json) {
    if (json is! Map) return null;
    final en = json['en'];
    if (en is! Map) return null;
    final one = en['one'], other = en['other'], bn = json['bn'];
    bool ok(Object? v) =>
        v is String && v.trim().isNotEmpty && v.length <= maxLength;
    if (!ok(one) || !ok(other) || !ok(bn)) return null;
    return LevelName(
      one: one as String,
      other: other as String,
      bn: bn as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LevelName &&
      other.one == one &&
      other.other == this.other &&
      other.bn == bn;

  @override
  int get hashCode => Object.hash(one, other, bn);
}

@immutable
class LevelLabels {
  const LevelLabels({
    required this.preset,
    required this.classLevel,
    required this.sectionLevel,
  });

  static const classSection = LevelLabels(
    preset: 'CLASS_SECTION',
    classLevel: LevelName(one: 'Class', other: 'Classes', bn: 'ক্লাস'),
    sectionLevel: LevelName(one: 'Section', other: 'Sections', bn: 'সেকশন'),
  );

  static const courseBatch = LevelLabels(
    preset: 'COURSE_BATCH',
    classLevel: LevelName(one: 'Course', other: 'Courses', bn: 'কোর্স'),
    sectionLevel: LevelName(one: 'Batch', other: 'Batches', bn: 'ব্যাচ'),
  );

  /// Class / Section, as on the web when nothing else is known.
  static const defaults = classSection;

  final String preset;
  final LevelName classLevel;
  final LevelName sectionLevel;

  /// From `GET /workspace/level-labels`; Class / Section when missing or malformed.
  static LevelLabels fromJson(Object? json) {
    if (json is! Map) return defaults;
    switch (json['preset']) {
      case 'CLASS_SECTION':
        return classSection;
      case 'COURSE_BATCH':
        return courseBatch;
      case 'CUSTOM':
        final c = LevelName.fromJson(json['class']);
        final s = LevelName.fromJson(json['section']);
        if (c != null && s != null) {
          return LevelLabels(preset: 'CUSTOM', classLevel: c, sectionLevel: s);
        }
    }
    return defaults;
  }

  static final tokenPattern = RegExp(
    r'\[\[(class|Class|classes|Classes|section|Section|sections|Sections)\]\]',
  );

  /// The word for one token in a language.
  String word(String token, String languageCode) {
    final lower = token.toLowerCase();
    final level = lower.startsWith('class') ? classLevel : sectionLevel;
    if (languageCode == 'bn') return level.bn;
    final plural = lower == 'classes' || lower == 'sections';
    final w = plural ? level.other : level.one;
    final capital = token[0] == token[0].toUpperCase();
    return capital ? _upperFirst(w) : _lowerFirst(w);
  }

  /// [text] with every level token replaced.
  String apply(String text, String languageCode) =>
      text.replaceAllMapped(tokenPattern, (m) => word(m[1]!, languageCode));

  @override
  bool operator ==(Object other) =>
      other is LevelLabels &&
      other.preset == preset &&
      other.classLevel == classLevel &&
      other.sectionLevel == sectionLevel;

  @override
  int get hashCode => Object.hash(preset, classLevel, sectionLevel);
}

/// Keeps acronyms such as "HSC" as they are.
String _lowerFirst(String w) =>
    RegExp(r'^\p{Lu}\p{Lu}', unicode: true).hasMatch(w)
    ? w
    : w[0].toLowerCase() + w.substring(1);

String _upperFirst(String w) => w[0].toUpperCase() + w.substring(1);

/// The current workspace's labels (`GET /workspace/level-labels`, FND-03).
/// Class / Section while loading, without a workspace, or if the call fails;
/// reloaded whenever the workspace changes, dropped on sign-out.
final levelLabelsProvider =
    NotifierProvider<LevelLabelsController, LevelLabels>(
      LevelLabelsController.new,
    );

class LevelLabelsController extends Notifier<LevelLabels> {
  @override
  LevelLabels build() {
    final workspace = ref.watch(workspaceKeyProvider);
    if (workspace != null) Future.microtask(() => _load(workspace));
    return LevelLabels.defaults;
  }

  Future<void> _load(String workspace) async {
    try {
      final r = await ref
          .read(apiClientProvider)
          .get('/workspace/level-labels');
      // Still the same workspace? (A switch may have happened meanwhile.)
      if (ref.mounted && ref.read(workspaceKeyProvider) == workspace) {
        state = LevelLabels.fromJson(r.payload);
      }
    } on ApiException {
      // Keep Class / Section.
    }
  }

  void set(LevelLabels labels) => state = labels;
}

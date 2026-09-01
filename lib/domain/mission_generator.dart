/// §17 — Daily mission generator.
library;

import 'dart:math' as math;
import 'models.dart';
import 'adaptive_selector.dart';

class MissionGenerator {
  /// Mistake review is time-boxed, not proportional: it has a floor so it
  /// survives short sessions, and a ceiling so it never eats the day.
  static const int mistakeFloorMinutes = 10;
  static const int mistakeCeilMinutes = 20;
  static const double mistakeShare = 0.12;

  /// Below this, three subjects would each get a block too small to be useful.
  static const int threeSubjectThreshold = 45;
  static const int minBlockMinutes = 5;

  final AdaptiveSelector selector;
  const MissionGenerator({this.selector = const AdaptiveSelector()});

  DailyMission generate({
    required StudentProfile profile,
    required List<ConceptContext> concepts,
    required Map<String, String> subjectNames,  // subjectId -> "Mathematics"
    required Map<String, String> conceptNames,  // conceptId -> "Quadratic Equations"
    required int openMistakeCount,
    required DateTime now,
  }) {
    final total = profile.dailyMinutes;
    final blocks = <MissionBlock>[];

    // 1. Carve out mistake review first.
    var mistakeMinutes = 0;
    if (openMistakeCount > 0) {
      mistakeMinutes = _round5((total * mistakeShare).round())
          .clamp(mistakeFloorMinutes, mistakeCeilMinutes);
      // Never let review outweigh actual study on very short days.
      mistakeMinutes = math.min(mistakeMinutes, (total / 3).floor());
      mistakeMinutes = _round5(mistakeMinutes);
      if (mistakeMinutes < minBlockMinutes) mistakeMinutes = 0;
    }

    final studyMinutes = total - mistakeMinutes;
    final ranked = selector.rank(concepts, now);

    // 2. Pick the top concept per subject, best subject first.
    final perSubject = <String, Candidate>{};
    for (final c in ranked) {
      final ctx = concepts.firstWhere((x) => x.conceptId == c.conceptId);
      perSubject.putIfAbsent(ctx.subjectId, () => c);
    }

    final maxSubjects = total < threeSubjectThreshold ? 2 : 3;
    final chosen = perSubject.entries.toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));
    final picks = chosen.take(maxSubjects).toList();

    if (picks.isNotEmpty) {
      // 3. Split study time by relative urgency, not evenly.
      final weights = picks.map((e) => math.max(e.value.score, 1.0)).toList();
      final alloc = _allocate(studyMinutes, weights);

      for (var i = 0; i < picks.length; i++) {
        if (alloc[i] < minBlockMinutes) continue;
        final subjectId = picks[i].key;
        final conceptId = picks[i].value.conceptId;
        blocks.add(MissionBlock(
          label: '${subjectNames[subjectId] ?? subjectId} — '
                 '${conceptNames[conceptId] ?? conceptId}',
          subjectId: subjectId,
          conceptId: conceptId,
          minutes: alloc[i],
          kind: picks[i].value.priority == Priority.reviewDue
              ? MissionBlockKind.review
              : MissionBlockKind.study,
        ));
      }
    }

    if (mistakeMinutes >= minBlockMinutes) {
      blocks.add(MissionBlock(
        label: 'Mistake Review',
        minutes: mistakeMinutes,
        kind: MissionBlockKind.mistakeReview,
      ));
    }

    return DailyMission(date: DateTime(now.year, now.month, now.day), blocks: blocks);
  }

  static int _round5(int v) => (v / 5).round() * 5;

  /// Split [total] minutes across [weights] in 5-minute blocks.
  /// Largest-remainder method, so the blocks always sum back to a rounded total
  /// and no share silently vanishes.
  List<int> _allocate(int total, List<double> weights) {
    final n = weights.length;
    if (n == 0 || total <= 0) return List.filled(n, 0);

    final units = total ~/ minBlockMinutes; // number of 5-min blocks
    final sum = weights.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return List.filled(n, 0);

    final exact = weights.map((w) => units * w / sum).toList();
    final floors = exact.map((e) => e.floor()).toList();
    var used = floors.fold<int>(0, (a, b) => a + b);

    // Guarantee every chosen subject at least one block while units allow.
    for (var i = 0; i < n && used < units; i++) {
      if (floors[i] == 0) {
        floors[i] = 1;
        used++;
      }
    }

    final order = List.generate(n, (i) => i)
      ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
    var idx = 0;
    while (used < units) {
      floors[order[idx % n]]++;
      used++;
      idx++;
    }
    // If min-guarantee overshot, claw back from the largest.
    while (used > units) {
      final biggest = List.generate(n, (i) => i)
          .reduce((a, b) => floors[a] >= floors[b] ? a : b);
      if (floors[biggest] <= 1) break;
      floors[biggest]--;
      used--;
    }

    return floors.map((f) => f * minBlockMinutes).toList();
  }
}

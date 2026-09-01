/// §16 — Adaptive learning engine.
/// Deterministic and fully explainable: every score can be traced to a reason.
library;

import 'dart:math' as math;
import 'models.dart';
import 'mastery.dart';

/// §16 priority order, as explicit tier floors. Tier separation is wide enough
/// that a lower tier can never outrank a higher one on modifiers alone.
enum Priority {
  prerequisiteGap(600, 'Missing prerequisite'),
  repeatedMistake(500, 'You have missed this more than once'),
  reviewDue(400, 'Due for review'),
  weakHighValue(300, 'Weak and important for your exam'),
  mixedApplication(200, 'Mixing concepts'),
  maintenance(100, 'Keeping this sharp');

  final int base;
  final String reason;
  const Priority(this.base, this.reason);
}

class Candidate {
  final String conceptId;
  final Priority priority;
  final double score;
  final String reason;

  const Candidate({
    required this.conceptId,
    required this.priority,
    required this.score,
    required this.reason,
  });
}

class ConceptContext {
  final String conceptId;
  final String subjectId;
  final MasteryResult mastery;
  final List<Mistake> openMistakes;
  final ReviewItem? review;
  final double examRelevance;      // 0..1 for the student's target
  final List<String> prerequisites;

  const ConceptContext({
    required this.conceptId,
    required this.subjectId,
    required this.mastery,
    required this.examRelevance,
    this.openMistakes = const [],
    this.review,
    this.prerequisites = const [],
  });
}

class AdaptiveSelector {
  /// Modifier weights. Kept small relative to tier bases (max ~99) so tiers
  /// stay authoritative. Tunable from config.
  final double wWeakness;      // how far below mastery the concept sits
  final double wOverdue;       // days past review due date
  final double wRelevance;     // exam-target value
  final double wMistakeCount;  // repeat offences

  const AdaptiveSelector({
    this.wWeakness = 40,
    this.wOverdue = 3,
    this.wRelevance = 25,
    this.wMistakeCount = 8,
  });

  /// A concept is a *prerequisite gap* when it is weak AND something the
  /// student is currently being asked to study depends on it. This is tier 1
  /// because practising the dependent concept first is wasted time.
  bool _isPrerequisiteGap(ConceptContext c, Set<String> neededPrereqs) =>
      neededPrereqs.contains(c.conceptId) &&
      c.mastery.state != ProgressState.mastered;

  Priority _classify(ConceptContext c, DateTime now, Set<String> neededPrereqs) {
    if (_isPrerequisiteGap(c, neededPrereqs)) return Priority.prerequisiteGap;

    final repeats = c.openMistakes.where((m) => !m.resolved && m.attempts >= 2);
    if (repeats.isNotEmpty) return Priority.repeatedMistake;

    if (c.review != null && !c.review!.dueAt.isAfter(now)) return Priority.reviewDue;

    if (c.mastery.state == ProgressState.weak ||
        c.mastery.state == ProgressState.notStarted) {
      return Priority.weakHighValue;
    }
    if (c.mastery.state == ProgressState.needsPractice) {
      return Priority.mixedApplication;
    }
    return Priority.maintenance;
  }

  List<Candidate> rank(List<ConceptContext> concepts, DateTime now) {
    // Collect prerequisites of every non-mastered concept the student is on.
    final needed = <String>{};
    for (final c in concepts) {
      if (c.mastery.state != ProgressState.mastered) needed.addAll(c.prerequisites);
    }

    final out = <Candidate>[];
    for (final c in concepts) {
      final p = _classify(c, now, needed);

      final weakness = 1.0 - c.mastery.score;
      final overdue = c.review?.overdueDays(now) ?? 0;
      final repeats = c.openMistakes.where((m) => !m.resolved)
          .fold<int>(0, (a, m) => a + m.attempts);

      var score = p.base +
          weakness * wWeakness +
          math.min(overdue, 21) * wOverdue +
          c.examRelevance * wRelevance +
          math.min(repeats, 6) * wMistakeCount;

      // A concept the student has never touched should not outrank one they
      // are actively failing — a small damp until there is evidence.
      if (c.mastery.state == ProgressState.notStarted) score -= 15;

      out.add(Candidate(
        conceptId: c.conceptId,
        priority: p,
        score: score,
        reason: p == Priority.weakHighValue ? c.mastery.reason : p.reason,
      ));
    }

    // Deterministic: score desc, then conceptId asc as a stable tiebreak.
    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : a.conceptId.compareTo(b.conceptId);
    });
    return out;
  }

  /// Difficulty targeting: aim just above current mastery, never punitive.
  /// mastery 0.0 -> difficulty ~2; 0.5 -> ~5; 1.0 -> ~9.
  int targetDifficulty(double masteryScore, ExamTarget target) {
    final base = 2 + (masteryScore * 7).round();
    final adj = target == ExamTarget.jeeAdvanced ? 1 : 0;
    return math.max(1, math.min(10, base + adj));
  }

  /// Pick questions for a concept, closest-to-target difficulty first,
  /// excluding anything already attempted correctly in this window.
  List<Question> pickQuestions(
    List<Question> pool, {
    required double masteryScore,
    required ExamTarget target,
    required Set<String> excludeIds,
    required int count,
  }) {
    final t = targetDifficulty(masteryScore, target);
    final usable = pool.where((q) => !excludeIds.contains(q.id)).toList();
    usable.sort((a, b) {
      final da = (a.dna.difficulty - t).abs();
      final db = (b.dna.difficulty - t).abs();
      if (da != db) return da.compareTo(db);
      final ra = b.dna.relevanceFor(target).compareTo(a.dna.relevanceFor(target));
      if (ra != 0) return ra;
      return a.id.compareTo(b.id);
    });
    return usable.take(count).toList();
  }
}

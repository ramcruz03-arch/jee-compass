/// §12, §13 — retention engine and mistake repair.
library;

import 'dart:math' as math;
import 'models.dart';

class ReviewScheduler {
  /// §13 — Day 1, 3, 7, 14, 30. Beyond the ladder, intervals keep growing.
  static const List<int> ladder = [1, 3, 7, 14, 30];
  static const int maxIntervalDays = 90;
  static const double minEase = 0.6;
  static const double maxEase = 1.6;

  const ReviewScheduler();

  ReviewItem schedule(String conceptId, DateTime now) => ReviewItem(
        conceptId: conceptId,
        ladderStep: 0,
        ease: 1.0,
        dueAt: now.add(Duration(days: ladder[0])),
      );

  /// Advance or demote after a review attempt.
  /// Success lengthens; failure shortens and drops back two rungs (§13).
  ReviewItem record(ReviewItem item, {required bool success, required DateTime now}) {
    int step;
    double ease;
    int streak;
    int failures = item.failureCount;

    if (success) {
      step = math.min(item.ladderStep + 1, ladder.length - 1);
      ease = math.min(item.ease * 1.05, maxEase);
      streak = item.successStreak + 1;
    } else {
      step = math.max(item.ladderStep - 2, 0);
      ease = math.max(item.ease * 0.85, minEase);
      streak = 0;
      failures += 1;
    }

    // Past the top rung, keep stretching by ease rather than repeating 30 days.
    var days = ladder[step];
    if (success && item.ladderStep >= ladder.length - 1) {
      days = math.min((ladder.last * math.pow(ease, streak)).round(), maxIntervalDays);
    } else {
      days = math.min((days * ease).round(), maxIntervalDays);
    }
    if (days < 1) days = 1;

    return ReviewItem(
      conceptId: item.conceptId,
      ladderStep: step,
      ease: ease,
      dueAt: now.add(Duration(days: days)),
      successStreak: streak,
      failureCount: failures,
    );
  }

  List<ReviewItem> due(List<ReviewItem> all, DateTime now) =>
      all.where((r) => !r.dueAt.isAfter(now)).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
}

/// §12 — repair sequence. Five steps by default; a calculation slip does not
/// need a re-teach, so the sequence is trimmed by mistake type.
enum RepairStep { explanation, easyQuestion, similarQuestion, changedContext, jeeQuestion }

class RepairPlan {
  final String conceptId;
  final MistakeType cause;
  final List<RepairStep> steps;
  final int currentIndex;

  const RepairPlan({
    required this.conceptId,
    required this.cause,
    required this.steps,
    this.currentIndex = 0,
  });

  bool get isComplete => currentIndex >= steps.length;
  RepairStep? get current => isComplete ? null : steps[currentIndex];

  RepairPlan advance() => RepairPlan(
        conceptId: conceptId, cause: cause, steps: steps,
        currentIndex: currentIndex + 1);

  /// A failure inside repair rewinds one step rather than restarting — the
  /// student should not be punished for stumbling mid-repair.
  RepairPlan stumble() => RepairPlan(
        conceptId: conceptId, cause: cause, steps: steps,
        currentIndex: math.max(0, currentIndex - 1));
}

class RepairEngine {
  const RepairEngine();

  RepairPlan build(String conceptId, MistakeType cause) {
    final steps = switch (cause) {
      MistakeType.conceptGap => RepairStep.values,
      MistakeType.wrongMethod => RepairStep.values,
      MistakeType.formulaForgotten => const [
          RepairStep.explanation, RepairStep.easyQuestion,
          RepairStep.similarQuestion, RepairStep.jeeQuestion],
      MistakeType.calculation => const [
          RepairStep.easyQuestion, RepairStep.similarQuestion,
          RepairStep.jeeQuestion],
      MistakeType.misread => const [
          RepairStep.similarQuestion, RepairStep.changedContext],
      MistakeType.ranOutOfTime => const [
          RepairStep.similarQuestion, RepairStep.jeeQuestion],
      MistakeType.guessed => RepairStep.values,
    };
    return RepairPlan(conceptId: conceptId, cause: cause, steps: List.of(steps));
  }

  /// §12 — "Concept repaired", but NOT permanently mastered. Repair always
  /// hands the concept back to the review ladder at step 0.
  ({Mistake mistake, ReviewItem review}) complete(
      Mistake m, DateTime now, ReviewScheduler scheduler) {
    return (
      mistake: m.copyWith(resolved: true, lastSeen: now),
      review: scheduler.schedule(m.conceptId, now),
    );
  }
}

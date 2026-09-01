/// JEE Compass — complete learning engine in a single library.
///
/// Mastery scoring with fake-understanding gates, spaced repetition,
/// mistake repair sequencing, adaptive selection, daily mission generation.
///
/// Pure Dart. No Flutter imports, no I/O, no clock reads — every function
/// takes `now` as a parameter, so all behaviour is deterministic.
library;

import 'dart:math' as math;

// ===========================================================================
// models
// ===========================================================================


enum ExamTarget { jeeMain, jeeAdvanced, both }

enum ExamLevel { foundation, jeeMain, jeeAdvanced }

enum QuestionType { singleCorrect, multipleCorrect, numerical, integer, matchTheFollowing }

/// Why a student got something wrong (§11). Stored verbatim; never inferred silently.
enum MistakeType {
  conceptGap,      // I didn't know the concept
  formulaForgotten,// I forgot the formula
  wrongMethod,     // I used the wrong method
  calculation,     // Calculation mistake
  misread,         // I misunderstood the question
  ranOutOfTime,    // I ran out of time
  guessed,         // I guessed
}

extension MistakeTypeCopy on MistakeType {
  /// Student-facing label (§41 — plain, non-shaming).
  String get label => switch (this) {
        MistakeType.conceptGap => "I didn't know the concept",
        MistakeType.formulaForgotten => 'I forgot the formula',
        MistakeType.wrongMethod => 'I used the wrong method',
        MistakeType.calculation => 'Calculation mistake',
        MistakeType.misread => 'I misunderstood the question',
        MistakeType.ranOutOfTime => 'I ran out of time',
        MistakeType.guessed => 'I guessed',
      };

  /// Does this mistake mean the concept itself is broken?
  /// Drives repair depth — a calculation slip does not need a re-teach.
  bool get isConceptual => this == MistakeType.conceptGap ||
      this == MistakeType.wrongMethod ||
      this == MistakeType.formulaForgotten;
}

enum ProgressState { notStarted, weak, needsPractice, mastered }

/// Skills a question exercises. Used by the DNA profile (§10).
enum Skill { recall, conceptualReasoning, multiStep, application, transfer, speed }

class QuestionDna {
  final int difficulty;          // 1..10
  final double calculationLoad;  // 0..1
  final double conceptualLoad;   // 0..1
  final bool multiConcept;
  final int estimatedTimeSeconds;
  final double mainRelevance;    // 0..1
  final double advancedRelevance;// 0..1

  const QuestionDna({
    required this.difficulty,
    required this.calculationLoad,
    required this.conceptualLoad,
    required this.multiConcept,
    required this.estimatedTimeSeconds,
    required this.mainRelevance,
    required this.advancedRelevance,
  });

  double relevanceFor(ExamTarget t) => switch (t) {
        ExamTarget.jeeMain => mainRelevance,
        ExamTarget.jeeAdvanced => advancedRelevance,
        ExamTarget.both => (mainRelevance + advancedRelevance) / 2,
      };
}

class Question {
  final String id;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String conceptId;
  final QuestionType type;
  final ExamLevel examLevel;
  final Set<Skill> skills;
  final QuestionDna dna;

  /// True only for questions from a licensed/verified source (§19, §20).
  /// AI-generated items are never marked verified.
  final bool verifiedSolution;

  const Question({
    required this.id,
    required this.subjectId,
    required this.chapterId,
    required this.topicId,
    required this.conceptId,
    required this.type,
    required this.examLevel,
    required this.skills,
    required this.dna,
    this.verifiedSolution = false,
  });
}

class QuestionAttempt {
  final String id;
  final String questionId;
  final String conceptId;
  final bool correct;
  final int timeTakenSeconds;
  final int estimatedTimeSeconds;
  final DateTime at;
  final Set<Skill> skills;
  final bool multiConcept;
  final bool wasReviewItem; // attempt served by the review queue
  final MistakeType? mistakeType;

  const QuestionAttempt({
    required this.id,
    required this.questionId,
    required this.conceptId,
    required this.correct,
    required this.timeTakenSeconds,
    required this.estimatedTimeSeconds,
    required this.at,
    required this.skills,
    this.multiConcept = false,
    this.wasReviewItem = false,
    this.mistakeType,
  });
}

class Mistake {
  final String id;
  final String conceptId;
  final String questionId;
  final MistakeType mistakeType;
  final int attempts;
  final bool resolved;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const Mistake({
    required this.id,
    required this.conceptId,
    required this.questionId,
    required this.mistakeType,
    required this.attempts,
    required this.resolved,
    required this.firstSeen,
    required this.lastSeen,
  });

  Mistake copyWith({int? attempts, bool? resolved, DateTime? lastSeen}) => Mistake(
        id: id,
        conceptId: conceptId,
        questionId: questionId,
        mistakeType: mistakeType,
        attempts: attempts ?? this.attempts,
        resolved: resolved ?? this.resolved,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
      );
}

class ReviewItem {
  final String conceptId;
  final int ladderStep;   // index into ReviewScheduler.ladder
  final double ease;      // interval multiplier, 0.6..1.6
  final DateTime dueAt;
  final int successStreak;
  final int failureCount;

  const ReviewItem({
    required this.conceptId,
    required this.ladderStep,
    required this.ease,
    required this.dueAt,
    this.successStreak = 0,
    this.failureCount = 0,
  });

  int overdueDays(DateTime now) {
    final d = now.difference(dueAt).inDays;
    return d > 0 ? d : 0;
  }
}

class StudentProfile {
  final String userId;
  final ExamTarget target;
  final int dailyMinutes;
  final DateTime joinedAt;

  const StudentProfile({
    required this.userId,
    required this.target,
    required this.dailyMinutes,
    required this.joinedAt,
  });
}

class MissionBlock {
  final String label;      // "Mathematics — Quadratic Equations"
  final String? subjectId; // null for the mistake-review block
  final String? conceptId;
  final int minutes;
  final MissionBlockKind kind;

  const MissionBlock({
    required this.label,
    required this.minutes,
    required this.kind,
    this.subjectId,
    this.conceptId,
  });
}

enum MissionBlockKind { study, review, mistakeReview }

class DailyMission {
  final DateTime date;
  final List<MissionBlock> blocks;
  int get totalMinutes => blocks.fold(0, (a, b) => a + b.minutes);

  const DailyMission({required this.date, required this.blocks});
}

// ===========================================================================
// mastery
// ===========================================================================


/// The six tracked signals (§14). Each 0..1.
class MasterySignals {
  final double accuracy;
  final double speed;
  final double recall;
  final double application;
  final double transfer;
  final double retention;

  const MasterySignals({
    this.accuracy = 0,
    this.speed = 0,
    this.recall = 0,
    this.application = 0,
    this.transfer = 0,
    this.retention = 0,
  });

  Map<String, double> asMap() => {
        'accuracy': accuracy,
        'speed': speed,
        'recall': recall,
        'application': application,
        'transfer': transfer,
        'retention': retention,
      };
}

/// model can be retuned without an app release.
class MasteryWeights {
  final double accuracy, speed, recall, application, transfer, retention;

  const MasteryWeights({
    required this.accuracy,
    required this.speed,
    required this.recall,
    required this.application,
    required this.transfer,
    required this.retention,
  });

  /// Defaults exactly as specified in §15 (recall tracked but unweighted).
  static const specDefault = MasteryWeights(
    accuracy: 0.30, application: 0.25, transfer: 0.20,
    retention: 0.15, speed: 0.10, recall: 0.0,
  );

  /// Alternative profile that prices recall in. Selectable from config.
  static const recallAware = MasteryWeights(
    accuracy: 0.26, application: 0.22, transfer: 0.18,
    retention: 0.14, speed: 0.08, recall: 0.12,
  );

  double get sum => accuracy + speed + recall + application + transfer + retention;

  factory MasteryWeights.fromJson(Map<String, dynamic> j) => MasteryWeights(
        accuracy: (j['accuracy'] as num).toDouble(),
        speed: (j['speed'] as num).toDouble(),
        recall: (j['recall'] as num? ?? 0).toDouble(),
        application: (j['application'] as num).toDouble(),
        transfer: (j['transfer'] as num).toDouble(),
        retention: (j['retention'] as num).toDouble(),
      );
}

class MasteryResult {
  final double score;              // 0..1 weighted composite
  final MasterySignals signals;
  final ProgressState state;
  final String? blockedBy;         // which gate failed, if any
  final int sampleSize;

  const MasteryResult({
    required this.score,
    required this.signals,
    required this.state,
    required this.sampleSize,
    this.blockedBy,
  });

  /// §23 — "tap a topic to see why it is weak". Student-facing, §41 tone.
  String get reason {
    if (sampleSize < MasteryEngine.minSample) {
      return 'Not enough practice yet to judge this one.';
    }
    return switch (blockedBy) {
      'transfer' => "You solve familiar questions well, but unfamiliar ones are still hard. Let's work on this.",
      'retention' => 'This fades between sessions. A few more reviews will lock it in.',
      'application' => 'The idea is there — applying it to problems needs another pass.',
      _ => state == ProgressState.mastered
          ? "You've got this one."
          : 'This concept needs another practice.',
    };
  }
}

class MasteryEngine {
  final MasteryWeights weights;

  /// Recency half-life. Older attempts count less — a student who has improved
  /// should not be held down by month-old failures.
  final Duration halfLife;

  /// Gates (§14). A high weighted score alone must NOT grant mastery.
  final double transferGate;
  final double retentionGate;
  final double applicationGate;
  final double masteryThreshold;

  static const int minSample = 5;

  const MasteryEngine({
    this.weights = MasteryWeights.specDefault,
    this.halfLife = const Duration(days: 21),
    this.transferGate = 0.55,
    this.retentionGate = 0.50,
    this.applicationGate = 0.55,
    this.masteryThreshold = 0.75,
  });

  double _decay(DateTime at, DateTime now) {
    final days = now.difference(at).inMinutes / 1440.0;
    if (days <= 0) return 1.0;
    return math.pow(0.5, days / halfLife.inDays).toDouble();
  }

  /// Weighted-mean helper.
  ///
  /// [fallback] is what an UNMEASURED signal reads as. Every caller passes 0,
  /// deliberately: if a concept has no transfer questions attempted, transfer
  /// is 0 and the gate stays shut. Inheriting accuracy here would let a student
  /// reach "mastered" on familiar questions alone — exactly the failure §14
  /// exists to prevent. The cost is that content MUST include transfer items.
  double _mean(Iterable<({double w, double v})> xs, double fallback) {
    double numer = 0, den = 0;
    for (final x in xs) {
      numer += x.w * x.v;
      den += x.w;
    }
    return den == 0 ? fallback : numer / den;
  }

  MasterySignals computeSignals(List<QuestionAttempt> attempts, DateTime now) {
    if (attempts.isEmpty) return const MasterySignals();

    final weighted = attempts.map((a) => (a: a, w: _decay(a.at, now))).toList();

    final accuracy = _mean(
      weighted.map((e) => (w: e.w, v: e.a.correct ? 1.0 : 0.0)), 0);

    // Speed: ratio of expected to actual, capped at 1. Only scored on correct
    // attempts — being fast and wrong is not speed.
    final speed = _mean(
      weighted.where((e) => e.a.correct).map((e) {
        final t = e.a.timeTakenSeconds;
        if (t <= 0) return (w: e.w, v: 0.0);
        return (w: e.w, v: math.min(1.0, e.a.estimatedTimeSeconds / t));
      }), 0);

    // Recall: attempts made 3+ days after the previous attempt on this concept.
    final sorted = [...attempts]..sort((x, y) => x.at.compareTo(y.at));
    final recallIds = <String>{};
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].at.difference(sorted[i - 1].at).inDays >= 3) {
        recallIds.add(sorted[i].id);
      }
    }
    final recall = _mean(
      weighted.where((e) => recallIds.contains(e.a.id))
              .map((e) => (w: e.w, v: e.a.correct ? 1.0 : 0.0)), 0);

    final application = _mean(
      weighted.where((e) => e.a.skills.contains(Skill.application) ||
                            e.a.skills.contains(Skill.multiStep))
              .map((e) => (w: e.w, v: e.a.correct ? 1.0 : 0.0)), 0);

    // Transfer: unfamiliar framing — multi-concept items or explicit transfer tag.
    final transfer = _mean(
      weighted.where((e) => e.a.multiConcept || e.a.skills.contains(Skill.transfer))
              .map((e) => (w: e.w, v: e.a.correct ? 1.0 : 0.0)), 0);

    final retention = _mean(
      weighted.where((e) => e.a.wasReviewItem)
              .map((e) => (w: e.w, v: e.a.correct ? 1.0 : 0.0)), 0);

    return MasterySignals(
      accuracy: accuracy, speed: speed, recall: recall,
      application: application, transfer: transfer, retention: retention,
    );
  }

  MasteryResult evaluate(List<QuestionAttempt> attempts, DateTime now) {
    final s = computeSignals(attempts, now);
    final w = weights;
    final raw = s.accuracy * w.accuracy +
        s.speed * w.speed +
        s.recall * w.recall +
        s.application * w.application +
        s.transfer * w.transfer +
        s.retention * w.retention;
    final score = w.sum == 0 ? 0.0 : raw / w.sum;

    if (attempts.isEmpty) {
      return MasteryResult(
        score: 0, signals: s, state: ProgressState.notStarted, sampleSize: 0);
    }
    if (attempts.length < minSample) {
      return MasteryResult(
        score: score, signals: s, state: ProgressState.needsPractice,
        sampleSize: attempts.length);
    }

    // §14 — the fake-understanding gate. Order matters: report the deepest
    // failure first, because transfer is the one students mistake for mastery.
    String? blocked;
    if (s.transfer < transferGate) {
      blocked = 'transfer';
    } else if (s.retention < retentionGate) {
      blocked = 'retention';
    } else if (s.application < applicationGate) {
      blocked = 'application';
    }

    final ProgressState state;
    if (blocked == null && score >= masteryThreshold) {
      state = ProgressState.mastered;
    } else if (score >= 0.5) {
      state = ProgressState.needsPractice;
    } else {
      state = ProgressState.weak;
    }

    return MasteryResult(
      score: score, signals: s, state: state,
      blockedBy: blocked, sampleSize: attempts.length);
  }

  /// §15 — roll concept scores up to topic / chapter / subject / overall.
  /// Weighted by sample size so one lightly-practised concept cannot swing a
  /// chapter's number.
  double rollUp(Map<String, MasteryResult> children) {
    if (children.isEmpty) return 0;
    double numer = 0, den = 0;
    for (final r in children.values) {
      final w = math.min(r.sampleSize, 20).toDouble();
      numer += r.score * w;
      den += w;
    }
    return den == 0 ? 0 : numer / den;
  }
}

// ===========================================================================
// retention
// ===========================================================================


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

// ===========================================================================
// adaptive_selector
// ===========================================================================


/// that a lower tier can 

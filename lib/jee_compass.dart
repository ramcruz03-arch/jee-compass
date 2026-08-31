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
        dueAt: now.add(const Duration(days: ladder[0])),
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

// ===========================================================================
// mission_generator
// ===========================================================================


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


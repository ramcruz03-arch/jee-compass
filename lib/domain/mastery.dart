/// §14, §15 — Mastery model and fake-understanding detection.
library;

import 'dart:math' as math;
import 'models.dart';

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

/// §15 — weights are DATA, not constants. Ship as a remote-config row so the
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

// §46 — unit tests for mastery, review scheduling, adaptive selection,
// mistake classification and mission generation.
//
// Run: dart test   (add `test: ^1.25.0` to dev_dependencies)

import 'package:test/test.dart';
import 'package:jee_compass/domain/models.dart';
import 'package:jee_compass/domain/mastery.dart';
import 'package:jee_compass/domain/retention.dart';
import 'package:jee_compass/domain/adaptive_selector.dart';
import 'package:jee_compass/domain/mission_generator.dart';

final now = DateTime(2026, 3, 1, 18, 0);

QuestionAttempt att({
  required String id,
  required bool correct,
  int seconds = 100,
  int estimated = 120,
  Set<Skill> skills = const {},
  bool multiConcept = false,
  bool review = false,
  Duration ago = Duration.zero,
}) =>
    QuestionAttempt(
      id: id,
      questionId: 'q_$id',
      conceptId: 'friction',
      correct: correct,
      timeTakenSeconds: seconds,
      estimatedTimeSeconds: estimated,
      at: now.subtract(ago),
      skills: skills,
      multiConcept: multiConcept,
      wasReviewItem: review,
    );

void main() {
  group('MasteryEngine', () {
    const engine = MasteryEngine();

    test('no attempts means notStarted, not weak', () {
      final r = engine.evaluate([], now);
      expect(r.state, ProgressState.notStarted);
      expect(r.score, 0);
    });

    test('below minimum sample never reports mastered', () {
      final attempts = List.generate(4, (i) => att(id: 'a$i', correct: true));
      expect(engine.evaluate(attempts, now).state, ProgressState.needsPractice);
    });

    test('§14 fake understanding: high accuracy, low transfer is NOT mastered', () {
      final attempts = [
        // Ten familiar questions, all correct.
        for (var i = 0; i < 10; i++)
          att(id: 'easy$i', correct: true, seconds: 90,
              skills: {Skill.application, Skill.multiStep}),
        // Five unfamiliar transfer questions, all wrong.
        for (var i = 0; i < 5; i++)
          att(id: 'tr$i', correct: false, multiConcept: true,
              skills: {Skill.transfer}),
        for (var i = 0; i < 3; i++) att(id: 'rev$i', correct: true, review: true),
      ];
      final r = engine.evaluate(attempts, now);
      expect(r.signals.accuracy, greaterThan(0.6));
      expect(r.signals.transfer, lessThan(0.55));
      expect(r.state, isNot(ProgressState.mastered));
      expect(r.blockedBy, 'transfer');
      expect(r.reason, contains('unfamiliar'));
    });

    test('strong across all signals is mastered', () {
      final attempts = [
        for (var i = 0; i < 8; i++)
          att(id: 'a$i', correct: true, seconds: 80,
              skills: {Skill.application, Skill.multiStep}),
        for (var i = 0; i < 4; i++)
          att(id: 't$i', correct: true, multiConcept: true, skills: {Skill.transfer}),
        for (var i = 0; i < 4; i++)
          att(id: 'r$i', correct: true, review: true, ago: Duration(days: 5 * i)),
      ];
      final r = engine.evaluate(attempts, now);
      expect(r.state, ProgressState.mastered);
      expect(r.blockedBy, isNull);
    });

    test('recent attempts outweigh stale ones', () {
      final improving = [
        for (var i = 0; i < 6; i++)
          att(id: 'old$i', correct: false, ago: const Duration(days: 60)),
        for (var i = 0; i < 6; i++)
          att(id: 'new$i', correct: true, ago: const Duration(days: 1)),
      ];
      final decaying = [
        for (var i = 0; i < 6; i++)
          att(id: 'old$i', correct: true, ago: const Duration(days: 60)),
        for (var i = 0; i < 6; i++)
          att(id: 'new$i', correct: false, ago: const Duration(days: 1)),
      ];
      expect(engine.evaluate(improving, now).signals.accuracy,
          greaterThan(engine.evaluate(decaying, now).signals.accuracy));
    });

    test('weights are configurable, not baked in', () {
      const transferHeavy = MasteryEngine(
        weights: MasteryWeights(
          accuracy: 0.1, speed: 0, recall: 0, application: 0.1,
          transfer: 0.8, retention: 0),
      );
      final attempts = [
        for (var i = 0; i < 10; i++) att(id: 'a$i', correct: true),
        for (var i = 0; i < 4; i++)
          att(id: 't$i', correct: false, multiConcept: true, skills: {Skill.transfer}),
      ];
      expect(transferHeavy.evaluate(attempts, now).score,
          lessThan(const MasteryEngine().evaluate(attempts, now).score));
    });
  });

  group('ReviewScheduler §13', () {
    const s = ReviewScheduler();

    test('first schedule is one day out', () {
      expect(s.schedule('c1', now).dueAt.difference(now).inDays, 1);
    });

    test('success walks the 1/3/7/14/30 ladder', () {
      var item = s.schedule('c1', now);
      final gaps = <int>[];
      var t = now;
      for (var i = 0; i < 4; i++) {
        t = item.dueAt;
        item = s.record(item, success: true, now: t);
        gaps.add(item.dueAt.difference(t).inDays);
      }
      expect(gaps.first, greaterThanOrEqualTo(3));
      // Monotonically lengthening.
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThanOrEqualTo(gaps[i - 1]));
      }
    });

    test('failure shortens the interval and lowers ease', () {
      var item = s.schedule('c1', now);
      for (var i = 0; i < 3; i++) {
        item = s.record(item, success: true, now: item.dueAt);
      }
      final before = item;
      final after = s.record(item, success: false, now: item.dueAt);
      expect(after.ladderStep, lessThan(before.ladderStep));
      expect(after.ease, lessThan(before.ease));
      expect(after.successStreak, 0);
      expect(after.failureCount, before.failureCount + 1);
    });

    test('no single interval exceeds the 90-day cap', () {
      var item = s.schedule('c1', now);
      for (var i = 0; i < 20; i++) {
        final at = item.dueAt;
        item = s.record(item, success: true, now: at);
        expect(item.dueAt.difference(at).inDays,
            lessThanOrEqualTo(ReviewScheduler.maxIntervalDays));
      }
      expect(item.ease, lessThanOrEqualTo(ReviewScheduler.maxEase));
    });

    test('repeated failure bottoms out at one day, never zero', () {
      var f = s.schedule('c2', now);
      for (var i = 0; i < 10; i++) {
        final at = f.dueAt;
        f = s.record(f, success: false, now: at);
        expect(f.dueAt.difference(at).inDays, greaterThanOrEqualTo(1));
      }
      expect(f.ladderStep, 0);
      expect(f.ease, ReviewScheduler.minEase);
      expect(f.failureCount, 10);
    });

    test('due() returns only items at or past their date, oldest first', () {
      final items = [
        ReviewItem(conceptId: 'a', ladderStep: 0, ease: 1,
            dueAt: now.subtract(const Duration(days: 2))),
        ReviewItem(conceptId: 'b', ladderStep: 0, ease: 1,
            dueAt: now.add(const Duration(days: 3))),
        ReviewItem(conceptId: 'c', ladderStep: 0, ease: 1,
            dueAt: now.subtract(const Duration(days: 5))),
      ];
      final d = s.due(items, now);
      expect(d.map((e) => e.conceptId), ['c', 'a']);
    });
  });

  group('RepairEngine §12', () {
    const r = RepairEngine();

    test('concept gap gets the full five-step sequence', () {
      expect(r.build('friction', MistakeType.conceptGap).steps.length, 5);
    });

    test('calculation slip skips the re-teach', () {
      final plan = r.build('friction', MistakeType.calculation);
      expect(plan.steps, isNot(contains(RepairStep.explanation)));
      expect(plan.steps.length, lessThan(5));
    });

    test('stumbling rewinds one step, never restarts', () {
      var p = r.build('friction', MistakeType.conceptGap).advance().advance();
      expect(p.currentIndex, 2);
      expect(p.stumble().currentIndex, 1);
      expect(r.build('x', MistakeType.conceptGap).stumble().currentIndex, 0);
    });

    test('§12 repair marks resolved but re-enters the review ladder', () {
      final m = Mistake(
        id: 'm1', conceptId: 'friction', questionId: 'q1',
        mistakeType: MistakeType.conceptGap, attempts: 3,
        resolved: false, firstSeen: now, lastSeen: now);
      final out = r.complete(m, now, const ReviewScheduler());
      expect(out.mistake.resolved, isTrue);
      // Repaired is NOT mastered — it goes back to day 1 of the ladder.
      expect(out.review.ladderStep, 0);
      expect(out.review.dueAt.difference(now).inDays, 1);
    });
  });

  group('AdaptiveSelector §16', () {
    const sel = AdaptiveSelector();

    MasteryResult m(double score, ProgressState st, {int n = 10}) =>
        MasteryResult(score: score, signals: const MasterySignals(),
            state: st, sampleSize: n);

    test('priority order is respected across tiers', () {
      final concepts = [
        ConceptContext(conceptId: 'maintain', subjectId: 'phy',
            mastery: m(0.9, ProgressState.mastered), examRelevance: 1.0),
        ConceptContext(conceptId: 'weak', subjectId: 'math',
            mastery: m(0.3, ProgressState.weak), examRelevance: 0.5),
        ConceptContext(conceptId: 'repeat', subjectId: 'chem',
            mastery: m(0.6, ProgressState.needsPractice),
            examRelevance: 0.2,
            openMistakes: [Mistake(id: 'x', conceptId: 'repeat',
                questionId: 'q', mistakeType: MistakeType.conceptGap,
                attempts: 3, resolved: false, firstSeen: now, lastSeen: now)]),
        ConceptContext(conceptId: 'duereview', subjectId: 'phy',
            mastery: m(0.7, ProgressState.needsPractice), examRelevance: 0.1,
            review: ReviewItem(conceptId: 'duereview', ladderStep: 1,
                ease: 1, dueAt: now.subtract(const Duration(days: 4)))),
      ];
      final ranked = sel.rank(concepts, now);
      expect(ranked.map((c) => c.conceptId).toList(),
          ['repeat', 'duereview', 'weak', 'maintain']);
    });

    test('prerequisite gaps outrank everything, including repeat mistakes', () {
      final concepts = [
        ConceptContext(conceptId: 'quadratics', subjectId: 'math',
            mastery: m(0.2, ProgressState.weak), examRelevance: 1.0,
            prerequisites: const ['basic_algebra']),
        ConceptContext(conceptId: 'basic_algebra', subjectId: 'math',
            mastery: m(0.35, ProgressState.weak), examRelevance: 0.4),
      ];
      expect(sel.rank(concepts, now).first.conceptId, 'basic_algebra');
    });

    test('ranking is deterministic — same input, same order', () {
      final concepts = List.generate(12, (i) => ConceptContext(
          conceptId: 'c$i', subjectId: 'phy',
          mastery: m(0.5, ProgressState.needsPractice), examRelevance: 0.5));
      final a = sel.rank(concepts, now).map((c) => c.conceptId).toList();
      final b = sel.rank(concepts.reversed.toList(), now)
          .map((c) => c.conceptId).toList();
      expect(a, b);
    });

    test('difficulty targets just above current mastery', () {
      expect(sel.targetDifficulty(0.0, ExamTarget.jeeMain), 2);
      expect(sel.targetDifficulty(1.0, ExamTarget.jeeMain), 9);
      expect(sel.targetDifficulty(0.5, ExamTarget.jeeAdvanced),
          greaterThan(sel.targetDifficulty(0.5, ExamTarget.jeeMain)));
    });
  });

  group('MissionGenerator §17', () {
    const gen = MissionGenerator();

    MasteryResult m(double s, ProgressState st) =>
        MasteryResult(score: s, signals: const MasterySignals(),
            state: st, sampleSize: 12);

    final concepts = [
      ConceptContext(conceptId: 'quadratic', subjectId: 'math',
          mastery: m(0.30, ProgressState.weak), examRelevance: 1.0),
      ConceptContext(conceptId: 'newton', subjectId: 'phy',
          mastery: m(0.55, ProgressState.needsPractice), examRelevance: 0.9),
      ConceptContext(conceptId: 'bonding', subjectId: 'chem',
          mastery: m(0.70, ProgressState.needsPractice), examRelevance: 0.8),
    ];
    const names = {'math': 'Mathematics', 'phy': 'Physics', 'chem': 'Chemistry'};
    const cnames = {'quadratic': 'Quadratic Equations',
                    'newton': "Newton's Laws", 'bonding': 'Chemical Bonding'};

    DailyMission build(int minutes, {int mistakes = 4}) => gen.generate(
        profile: StudentProfile(userId: 'u1', target: ExamTarget.both,
            dailyMinutes: minutes, joinedAt: now),
        concepts: concepts, subjectNames: names, conceptNames: cnames,
        openMistakeCount: mistakes, now: now);

    test('blocks always sum to the available time', () {
      for (final t in [30, 45, 60, 90, 120, 180]) {
        expect(build(t).totalMinutes, t, reason: 'failed at $t minutes');
      }
    });

    test('90 minutes yields three subjects plus mistake review', () {
      final mission = build(90);
      expect(mission.blocks.length, 4);
      expect(mission.blocks.last.kind, MissionBlockKind.mistakeReview);
      expect(mission.blocks.last.minutes, 10);
      // Weakest subject gets the largest block.
      expect(mission.blocks.first.subjectId, 'math');
    });

    test('30 minutes drops to two subjects, mistake review survives', () {
      final mission = build(30);
      final study = mission.blocks
          .where((b) => b.kind != MissionBlockKind.mistakeReview);
      expect(study.length, 2);
      expect(mission.blocks.any((b) => b.kind == MissionBlockKind.mistakeReview),
          isTrue);
      expect(mission.totalMinutes, 30);
    });

    test('no mistakes means no mistake block and all time to study', () {
      final mission = build(90, mistakes: 0);
      expect(mission.blocks.any((b) => b.kind == MissionBlockKind.mistakeReview),
          isFalse);
      expect(mission.totalMinutes, 90);
    });

    test('every block is a usable size — never a 2-minute stub', () {
      for (final t in [15, 30, 45, 60, 90, 120, 180]) {
        for (final b in build(t).blocks) {
          expect(b.minutes, greaterThanOrEqualTo(5));
          expect(b.minutes % 5, 0);
        }
      }
    });

    test('mission changes when mastery changes — today feeds tomorrow', () {
      final before = build(90).blocks.first.conceptId;
      final improved = [
        ConceptContext(conceptId: 'quadratic', subjectId: 'math',
            mastery: m(0.92, ProgressState.mastered), examRelevance: 1.0),
        ...concepts.skip(1),
      ];
      final after = gen.generate(
          profile: StudentProfile(userId: 'u1', target: ExamTarget.both,
              dailyMinutes: 90, joinedAt: now),
          concepts: improved, subjectNames: names, conceptNames: cnames,
          openMistakeCount: 4, now: now);
      expect(after.blocks.first.conceptId, isNot(before));
    });
  });
}

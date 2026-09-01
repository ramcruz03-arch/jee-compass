/// JEE Compass — core domain entities.
/// Pure Dart. No Flutter imports. No I/O. Deterministic.
library;

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

/// §10 — hidden from the student, consumed by the adaptive engine.
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

/// §11 — Mistake DNA. One record per (concept, mistakeType) pair, not per attempt.
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

/// §13 — one row per concept in the retention engine.
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

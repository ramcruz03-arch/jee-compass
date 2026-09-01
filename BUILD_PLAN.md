# JEE Compass — Build Plan & Agent Brief

Hand this file, plus `lib/domain/` and `test/`, to the coding agent that will
build the Flutter app. It resolves the decisions your spec left open (§50: "if a
technical decision is not explicitly specified, choose the simplest
production-quality solution and document it") so the agent does not re-litigate
them mid-build.

---

## 0. What is already done

`lib/domain/` contains the finished learning engine — pure Dart, no Flutter
imports, no I/O, fully deterministic:

| File | Covers |
|---|---|
| `models.dart` | §29 entities, §10 Question DNA, §11 mistake types |
| `mastery.dart` | §14 six signals + fake-understanding gate, §15 configurable weights |
| `retention.dart` | §13 spaced repetition, §12 repair sequences |
| `adaptive_selector.dart` | §16 priority tiers and scoring function |
| `mission_generator.dart` | §17 daily mission, 5-minute block allocation |
| `test/engine_test.dart` | §46 unit tests for all of the above |

**Do not rewrite these.** Build the app around them. If a UI need conflicts with
the engine's shape, change the UI or extend the engine — do not fork the logic.

The allocation algorithm has been verified against both §17 examples:
90 min → 35/25/20 + 10 mistake review; 30 min → 15/5 + 10.

---

## 1. Decisions locked

| Question | Decision | Why |
|---|---|---|
| Backend | **Supabase** | Postgres + row-level security + auth + edge functions in one. RLS is the cleanest way to satisfy §39 "never trust client-side scores". |
| Local DB | **Drift** (SQLite) | Typed queries, migrations, and it is the offline-first source of truth (§27). |
| State | **Riverpod** | Testable without a widget tree; the engine stays pure. |
| Sync | **Local-first, push-on-reconnect** | Attempts write locally, queue, then sync. The app must work on a train. |
| AI transport | **Supabase Edge Function only** | §32 — no key ever reaches the APK. |
| Math rendering | `flutter_math_fork` | §26 requires math rendering; it is the maintained fork. |
| Auth | Supabase anon session → upgrade | §28 guest mode with no data loss on sign-up. |
| Analytics | Self-hosted events table | §30/§40 — no third-party SDK on a minors' app. |

### Authority split (§39)
- **Client computes** mastery for instant UI feedback.
- **Server recomputes** on sync and its value wins.
- The engine is the *same Dart code* — run it in a Supabase edge function via
  a Dart-to-server port, or reimplement in TypeScript with the test suite ported
  as the contract. Pick one and note it; do not let the two drift.

---

## 2. Content schema (§33)

Questions live in JSON/Postgres, never in Dart source. Minimum viable row:

```json
{
  "id": "phy_nlm_friction_007",
  "subject": "physics",
  "chapter": "laws_of_motion",
  "topic": "newtons_laws",
  "concept": "friction",
  "type": "singleCorrect",
  "examLevel": "jeeAdvanced",
  "skills": ["conceptualReasoning", "multiStep", "application"],
  "dna": {
    "difficulty": 7,
    "calculationLoad": 0.4,
    "conceptualLoad": 0.8,
    "multiConcept": true,
    "estimatedTimeSeconds": 180,
    "mainRelevance": 0.6,
    "advancedRelevance": 0.95
  },
  "stem": "...",
  "options": [],
  "answer": {},
  "solution": { "verified": true, "source": "in_house" },
  "published": true
}
```

`solution.verified` is the §19 firewall. AI-generated explanations write to a
**separate** field and render with a visible "AI explanation" label. AI content
can never set `verified: true` (§36).

---

## 3. Phase order

Follow your §44 phases, with two amendments:

- **Phase 1 must include the JSON content loader and Drift schema.** Building UI
  against hardcoded lists then swapping the source later is the single most
  common way this kind of project rots.
- **Phase 3 is already written.** Phase 3 becomes *wiring*: attempts → repository
  → engine → mastery table → mission. Budget the saved time for Phase 6.

Ship gate per phase: `flutter analyze` clean, `dart test` green, app launches on
a real device. Report in the §51 format.

---

## 4. The three things most likely to go wrong

1. **Transfer questions do not exist yet.** The fake-understanding gate (§14) is
   the product's whole differentiator, and it needs questions tagged
   `multiConcept: true` that place a concept in an unfamiliar frame. If the MVP
   content set has none, every concept stalls at "not yet mastered" forever and
   the app feels broken. **Author transfer items deliberately, ~15% of each
   concept's pool, before shipping.**

2. **Cold start.** A new student who skips the diagnostic has no attempts, so
   every concept is `notStarted` and the selector has nothing to rank. Seed the
   first mission from syllabus order + `examRelevance` alone, and say so in the
   UI: "We'll tune this once we see you work."

3. **PYQ licensing (§20).** The architecture supports licensed content, but you
   still need the licence. Do not let "we'll sort content later" run past Phase
   2 — an adaptive engine with no questions is a demo, not a product.

---

## 5. Known gaps in what is delivered here

- Engine code is **written but not compiled** — no Dart SDK was available in the
  authoring environment. Expect to fix import paths and possibly a type nit on
  first `dart analyze`. The logic and the tests are the contract.
- `pickQuestions` excludes by ID only; it does not yet enforce spacing between
  questions from the same template family.
- Prerequisite edges are read from `ConceptContext.prerequisites` but nothing
  populates them — that is a content-authoring task, not a code task.
- On extremely lopsided weightings (one subject scoring ~95% of total urgency),
  a third subject can allocate to zero minutes and get dropped from the mission.
  This is intended, but verify it reads as calm rather than broken in the UI.

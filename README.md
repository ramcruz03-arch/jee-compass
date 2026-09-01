# JEE Compass — Learning Engine

The adaptive core of JEE Compass: mastery scoring with fake-understanding
detection, spaced repetition, mistake repair sequencing, and daily mission
generation.

Pure Dart. No Flutter imports, no I/O, no clock reads — every function takes
`now` as a parameter, so all behaviour is deterministic and testable.

## Status

**Engine: written and reviewed. Not yet compiled.** This code was authored in an
environment without a Dart SDK. The logic and the test suite are the contract;
expect to fix an import path or a type nit on your first `dart analyze`. Run the
tests before trusting anything here.

**Verified independently:** the mission time-allocation algorithm was ported to
Python and executed against the product spec's worked examples. 90 minutes
yields 35/25/20 plus 10 minutes of mistake review; 30 minutes yields 15/5 plus
10. Blocks sum exactly to available time at 15/30/45/60/90/120/180 minutes with
no sub-5-minute fragments.

## Run it

```bash
dart pub get
dart analyze
dart test
```

## What's here

| File | Responsibility |
|---|---|
| `lib/domain/models.dart` | Entities, Question DNA, mistake taxonomy |
| `lib/domain/mastery.dart` | Six-signal mastery model, configurable weights, mastery gates |
| `lib/domain/retention.dart` | 1/3/7/14/30 review ladder, repair sequences |
| `lib/domain/adaptive_selector.dart` | Six-tier priority ranking, difficulty targeting |
| `lib/domain/mission_generator.dart` | Daily mission, largest-remainder time allocation |
| `test/engine_test.dart` | Unit tests for all of the above |
| `BUILD_PLAN.md` | Locked architecture decisions for the Flutter app |

## The one idea worth understanding

Accuracy does not equal mastery. A student can answer ten familiar questions
correctly and still not understand the concept. `MasteryEngine` tracks six
signals and applies **gates**: if transfer, retention, or application sits below
threshold, the concept is not mastered regardless of how high the weighted score
is.

This has a hard content requirement. An unmeasured signal reads as zero, so a
concept with no transfer questions in its pool will never reach mastered. That
is deliberate — but it means **roughly 15% of each concept's question pool must
be deliberately authored transfer items** before this ships, or every concept
stalls and the app looks broken.

## Using it in the Flutter app

Two options:

1. **Path dependency** (recommended) — keep this as its own package and add
   `jee_compass_engine: {path: ../engine}` to the app's pubspec. Keeps the
   engine Flutter-free and independently testable.
2. **Merge into the app** — copy `lib/domain/` in. If you do, change the test
   import from `package:test/test.dart` to
   `package:flutter_test/flutter_test.dart` and run with `flutter test`.

## Configuration, not constants

Mastery weights are a data class with two shipped profiles and a `fromJson`
constructor. Load them from remote config so the model can be retuned without an
app release. Do not inline the numbers.

## Licence

MIT — see `LICENSE`.

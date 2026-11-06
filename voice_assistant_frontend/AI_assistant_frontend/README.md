# Virasoi Kitchen Assistant — Flutter Frontend

MVVM architecture · Provider state management · Dark theme · WebSocket voice
assistant · STT/TTS · Hero/shimmer/flip animations.

## ⚠️ Before you run this

**I could not reach your Swagger UI** (`virasoi-kitchen-assistant.onrender.com/swagger-ui`)
from this sandbox — Render free-tier services sleep and the URL isn't
publicly indexed, so my search/fetch tools returned nothing, and no GitHub
repo link was actually included in the request. So every endpoint path in
this app is my best-guess REST convention based on your feature
description, **not** verified against your real API.

👉 Open your Swagger UI yourself and compare it to:
**`lib/core/constants/api_constants.dart`**

That file is the *only* place endpoint strings live — every service reads
from it, so fixing paths there is the only change you'll need to make to
point this at your real backend. Same for the Unsplash access key
(`unsplashAccessKey` — get one free at unsplash.com/developers; for a real
release, proxy that call through your own backend instead of shipping the
key client-side).

## Setup

```bash
flutter pub get
flutter run
```

Android: microphone permission is required for `speech_to_text` — add to
`android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```
iOS: add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need your microphone to hear your cooking questions.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>We use speech recognition to understand your voice commands.</string>
```

## Architecture

```
lib/
  core/            # constants, theme, network (HTTP + WebSocket), routes, utils
  models/          # plain data classes (User, Recipe, Ingredient, Step, ChatMessage)
  services/        # talk to the backend / device APIs (Auth, Recipe, Ingredient,
                   # Unsplash, Voice STT/TTS, Timer/alarm)
  view_models/     # ChangeNotifier per screen — all business logic lives here
  views/           # dumb UI, one folder per screen, reads only from its ViewModel
  widgets/         # shared components (buttons, cards, voice orb, flip card...)
```

Every screen follows: **View → watches a ChangeNotifier ViewModel → calls a
Service → calls ApiClient/WebSocket**. No view ever calls `http`/`dio`
directly.

## Feature map → your screen spec

1. **Login/Register** — `views/auth/` — centered card, Hero'd logo, animated
   entrance, calls `ApiConstants.login` / `register`.
2. **Home** — `views/home/` — drawer with circular admin avatar, animated
   "kitchen" intro card, feature list, pulsing FAB → Create.
3. **Recipe list** — `views/recipe/recipe_list_page.dart` — search bar +
   filter bottom sheet (time asc/desc, alphabetical, total time), shimmer
   skeletons while loading, AI vs. user-made badge on each card.
4. **Recipe detail** — Hero'd cover image, ingredients with Unsplash photos
   that zoom into an `InteractiveViewer` on tap, numbered steps with a
   per-step timer button wired to `TimerService`.
5. **Create recipe** — comma-separated dish input, stove-count and
   servings steppers, Start → `RecipeService.generateRecipes`.
6. **Ingredient gathering** — 3-column grid of `IngredientFlipCard`s;
   `IngredientViewModel` opens a WebSocket keyed to the same session the
   Voice screen uses, so when the assistant hears "I have onions" the
   matching card animates out of the grid live. Missing-but-important
   items surface in a banner ("please pick up: ...").
7. **Voice assistant** — `VoiceOrb` (idle/listening/thinking/speaking states,
   see Rive section below), live partial transcript, and a draggable
   bottom sheet with the full conversation — **kept only in memory**
   (`VoiceViewModel.transcript`), never persisted, cleared when the screen
   closes.

## Rive animations

I could not generate real binary `.riv` files from here, so
`widgets/voice_orb.dart` and `views/home/home_page.dart` ship with
hand-built Flutter `CustomPainter` equivalents that work out of the box.
Each file has a comment block spelling out exactly what to build in the
Rive editor to upgrade them:

- **`assets/rive/voice_orb.riv`** — one State Machine `OrbStateMachine`
  with a single number input `state` (0=idle, 1=listening, 2=thinking,
  3=speaking), 4 looping timeline states cross-fading in ~200ms.
- **`assets/rive/kitchen_hero.riv`** — a single looping ambient scene
  (steam off a pot / a whisk turning) for the home screen intro card, one
  State Machine `HeroLoop`, no inputs needed.

Once you've exported those, register them in `pubspec.yaml` (already done
under `assets:`) and swap in:
```dart
RiveAnimation.asset('assets/rive/voice_orb.riv', stateMachines: ['OrbStateMachine']);
```

## WebSocket / real-time

`core/network/websocket_service.dart` is a generic reconnecting client
used for:
- Ingredient live-sync (screen 6) — server → client `item_confirmed` /
  `item_missing` events.
- Voice assistant (screen 7) — client → server `user_text`, server →
  client `assistant_text`.

Both currently connect to `ApiConstants.wsVoiceAssistant(sessionId)` —
split this into two separate endpoints in `api_constants.dart` if your
backend expects that.

## Timers / alarm system

`services/timer_service.dart` is an in-memory, app-wide `ChangeNotifier`
singleton. Tapping the play icon on a recipe step starts a countdown;
any screen can subscribe to `TimerService.instance` to show live
progress. Drop an alarm sound at `assets/audio/timer_done.mp3` (and add
it to `pubspec.yaml` assets) to enable the chime — it fails silently
without one.

## Known gaps to close once you have the real API

- Confirm exact JSON field names in `models/*.dart` `fromJson` — I used
  permissive fallbacks (`json['x'] ?? json['y']`) but your real payloads
  may differ.
- Token refresh flow (`ApiConstants.refreshToken`) is defined but not yet
  wired into `ApiClient` — add a 401-retry interceptor once you confirm
  the refresh contract.
- Unsplash calls are made directly from the client for simplicity; move
  them behind your backend before shipping to avoid exposing the key.

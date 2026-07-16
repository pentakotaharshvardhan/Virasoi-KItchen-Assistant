# Voice Kitchen Assistant — Backend

Your uploaded project was an empty Spring Initializr skeleton (just the pom.xml + main class,
no controllers/services/entities). I built the full backend described in your spec on top of it.
Everything below is new.

## What was added

**Dependencies** (in `pom.xml`):
- `spring-boot-starter-web` — REST controllers
- `spring-boot-starter-websocket` — the continuous-listening audio socket + push notifications
- `spring-boot-starter-data-jpa` + `postgresql` — persistence
- `spring-boot-starter-validation` — request validation
- `spring-boot-starter-security` + `io.jsonwebtoken:jjwt-*` — JWT login/auth for the Flutter app
- `spring-boot-starter-webflux` — only used for its `WebClient`, to call Gemini + Google Cloud STT/TTS over plain REST (no vendor SDKs)

**Config**: `src/main/resources/application.yml` replaces `application.properties` — datasource,
AI provider, STT provider, and kitchen tuning knobs, all documented inline.

## Architecture

```
voice (mic) ──▶ /ws/audio (WebSocket, continuous listening)
                    │  buffers audio, transcribes via SpeechToTextService
                    ▼
        AudioStreamWebSocketHandler (routes by "field": ancestor_transcript / dish_name / num_serves / step_command)
                    │
      ┌─────────────┼───────────────────────┐
      ▼             ▼                       ▼
RecipeService   CookingSessionService   SchedulerService  ◀── the "brain"
      │             │                       │
      ▼             ▼                       ▼
 AiFormattingService (AI: format/generate recipe JSON)   TimerService (async timers)
      │
      ▼
  Postgres (Recipe / RecipeIngredient / RecipeStep, CookingSession / SessionDish / SessionDishStep / StoveResource)
```

### 1. Ancestor recipes (voice → AI → Postgres)
`AiFormattingService.formatAncestorRecipe()` sends the raw transcript to Google's Gemini API
chat-completions endpoint with a strict JSON-schema system prompt, and `RecipeService` persists the
parsed result as a `Recipe` with ordered `RecipeIngredient`/`RecipeStep` children. The raw AI JSON is
also kept in `Recipe.rawAiJson` for audit.

### 2. "Find or generate" a dish
`RecipeService.findOrGenerate(dishName)` looks the dish up by normalized name; if missing, it calls
`AiFormattingService.generateRecipe()` and saves the result — exactly your "check DB, else ask AI" flow.
All quantities/timers are authored for **1 serve**.

### 3. Serving-size scaling
`CookingSessionService.addDish()` scales every ingredient (`quantityPerServe * servesRequested`) and,
for steps flagged `scalesWithServes` by the AI, grows the timer by a configurable
`kitchen.recipe.timer-scale-factor-per-serve` (default +12% per extra serve). Fixed-duration steps
(e.g. "let dough rest 10 min") are left untouched regardless of servings.

### 4. The scheduler — "the brain"
This is the core of your spec, in `SchedulerService`. It models the kitchen as a tiny OS-style
resource scheduler:

- **N stove resources** (`StoveResource` rows, one per `numberOfStoves` you told it about)
- **1 user resource** (there's only one cook)

Every `RecipeStep` is tagged by the AI as one of:
- `STOVE` — needs a free stove (boiling, frying, simmering)
- `USER_ACTION` — needs the cook's hands, no stove (chopping, whisking, plating)
- `PASSIVE` — needs nobody right now (resting dough, marinating) — starts immediately in the background

`SchedulerService.tick()` is the dispatch loop: for every active dish (FCFS by the order dishes were
added), if its current step's required resource is free, it gets dispatched. This is exactly how a
second dish gets a chopping task handed to the user while the first dish simmers unattended on a
stove — and how a dish simply waits its turn when all stoves are busy. `tick()` is re-run after every
event (dish added, step completed, timer elapsed).

### 5. Timers & the "next step or wait" loop
`TimerService` schedules completions on a background thread pool (no request thread is blocked). When
a timer elapses, the step becomes `TIMER_COMPLETED_AWAITING_USER` and a push notification asks the
user to say "next" or "wait" — matching your spec exactly. "Wait" just re-confirms state and holds the
resource; "next"/"done" frees the resource and advances the dish, which re-triggers the scheduler so
anything freed up gets picked up immediately. There's also `startOptionalTimer()` for steps the recipe
didn't pre-time (e.g. "want a timer while you chop?" → "yes, 3 minutes").

## Auth (JWT)

`POST /api/auth/register` / `POST /api/auth/login` return `{token, tokenType, expiresInSeconds,
userId, username}`. Send `Authorization: Bearer <token>` on every other REST call; connect the audio
socket as `ws://host/ws/audio?token=<jwt>&sessionId=<uuid>` (the JWT goes in the query string since
WebSocket upgrades can't carry custom headers from most clients). `/api/auth/**` and `/ws/audio/**`
are the only public paths — everything else returns 401 without a valid token. `CookingSessionController.start()`
always uses the authenticated user, ignoring any `userId` sent in the request body.

## WebSocket protocol — `/ws/audio?token=<jwt>&sessionId=<uuid optional>`

JSON text control frames interleaved with raw binary audio frames, one utterance at a time:

```
→ {"action":"start_utterance","field":"dish_name","meta":{}}
→ <binary audio chunk(s)>
→ {"action":"end_utterance"}
← {"type":"transcript","field":"dish_name","text":"paneer butter masala"}
← {"type":"recipe_found","data":{...}}
← {"type":"prompt","field":"num_serves","message":"Got it. How many people?"}
```

Supported `field` values: `ancestor_transcript` (meta: `dishNameHint`, `createdBy`), `dish_name`,
`num_serves` (needs `sessionId` + a prior `dish_name` in the same connection), `step_command`
(free-speech "done"/"next"/"wait"/"yes <n> minutes"/"no").

Every push (timer done, task assignment, dish added) is broadcast to all sockets open on that
`sessionId` as `{"type":"session_snapshot","data":{...}}`. Both `session_snapshot` (`messageAudioBase64`)
and `prompt` (`audioBase64`) messages carry synthesized speech (Google Cloud TTS, Base64 MP3) for
their text, alongside `audioEncoding: "MP3"` — the Flutter app can just decode + play it instead of
doing on-device TTS. If synthesis fails, the field is simply omitted and the text still arrives.

## REST API (typed equivalents of every voice action — handy for testing / the non-voice UI)

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/auth/register` | Create an account, returns a JWT |
| POST | `/api/auth/login` | Log in, returns a JWT |
| POST | `/api/recipes/ancestor` | Upload an ancestor recipe from already-transcribed text |
| POST | `/api/recipes/find-or-generate` | Find a dish, or AI-generate + save it if missing |
| POST | `/api/recipes/generate` | Force a fresh AI-generated recipe |
| GET | `/api/recipes/search?dishName=` | Look up a saved recipe |
| GET | `/api/recipes/{id}` / `/api/recipes` | Get / list recipes |
| POST | `/api/sessions/start` | Start a cooking session (`numberOfStoves`; user comes from the JWT) |
| GET | `/api/sessions/{id}/status` | Full live snapshot (stoves, current user task, dish progress) |
| POST | `/api/sessions/{id}/dishes` | Add a dish (`dishName`, `servesRequested`) — scales + queues it |
| POST | `/api/sessions/{id}/steps/{stepId}/complete` | User says "done"/"next" |
| POST | `/api/sessions/{id}/steps/{stepId}/wait` | User says "wait" after a timer |
| POST | `/api/sessions/{id}/steps/{stepId}/timer/start?seconds=` | Opt-in timer on an untimed step |
| POST | `/api/sessions/{id}/tick` | Manually force a re-evaluation (rarely needed) |
| POST | `/api/speech/transcribe` (multipart `file`) | One-shot REST transcription fallback |
| POST | `/api/speech/synthesize` (`{"text":"..."}`) | One-shot REST TTS fallback, returns Base64 MP3 |

## Before running

1. **Postgres**: create a `voice_assistant` DB and update `spring.datasource.*` in `application.yml`
   (or override via env vars). `ddl-auto: update` will create the schema automatically on first run.
2. **AI + STT + TTS keys**:
   - `ai.api-key` — a free [Gemini API key](https://aistudio.google.com/apikey). `ai.model` defaults to
     `gemini-3.5-flash` (Google's free-tier, rate-limited Flash model). `AiFormattingService` calls
     Gemini's `generateContent` endpoint with `responseMimeType: "application/json"`.
   - `stt.api-key` / `tts.api-key` — a Google Cloud API key (Cloud Console → APIs & Services →
     Credentials), with the **Cloud Speech-to-Text API** and **Cloud Text-to-Speech API** enabled on
     that project. Google's standard STT model includes ~60 minutes/month free; TTS Standard voices
     (not WaveNet/Neural2 - that's why `tts.voice-name` defaults to `hi-IN-Standard-A`) sit in a much
     larger free monthly character quota. Double-check current limits in your Cloud Console, since
     free-tier terms can change.
   - `stt.audio-encoding` / `stt.sample-rate-hertz` **must match** whatever format your Flutter
     recorder actually produces — Google's REST API needs an explicit encoding, unlike Whisper's
     format-sniffing multipart upload. Defaults assume 16kHz mono LINEAR16 (WAV/PCM); switch to
     `WEBM_OPUS` if you're streaming compressed audio instead.
   - `stt.language-code` / `tts.language-code` default to `en-IN` / `hi-IN` — set both to `hi-IN` if
     your users speak Hindi, or add a per-request override later if you need bilingual support.
3. `SpeechToTextService` (default bean: `GoogleCloudSpeechToTextService`) and `TextToSpeechService`
   (default bean: `GoogleCloudTextToSpeechService`) are both plain interfaces — swap in Azure
   Speech/Deepgram/AWS Polly etc. by adding a new implementation and removing `@Service` from the
   default one.
4. Run with `./mvnw spring-boot:run`.

⚠️ I wasn't able to compile this in my sandbox (no Maven Central access here), so please run
`mvn clean install` on your machine as a first check — I did verify every file parses cleanly with
`javac` and reviewed the code closely, but a real build is worth doing before you wire up the Flutter
app.

## Notes / assumptions I made

- Recipes are always authored for **1 serve** (per your spec) and scaled up from there.
- Only one dish's `USER_ACTION` step is assigned per scheduler tick — the user is a single resource,
  matching "OS scheduling" language in your spec.
- I kept the AI/STT layer behind interfaces so you can swap providers without touching business logic.

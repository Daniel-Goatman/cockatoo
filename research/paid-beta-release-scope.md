# Paid Beta Release Scope And Product Analysis

Date: 2026-05-28
Project: Mac Language Learner / Cockatoo
Target: paid beta within 2-4 weeks

## Executive Summary

Cockatoo has a real product wedge: it is a Mac-first, Safari-native ambient
language-learning companion that introduces a target language into the web the
user already reads. The current implementation is not yet a complete learning
system, but it is already more coherent than a prototype: Safari inline
replacement works, state is shared with the native app, sensitive fields are
excluded, the dashboard has overview/vocabulary/tutor surfaces, and both Swift
and extension tests pass.

The strongest beta thesis is not "an alternative to Duolingo" or "an AI tutor."
It is:

> Cockatoo helps Mac users learning Spanish, French, German, Italian, or
> Portuguese turn normal Safari reading into a lightweight vocabulary habit,
> then uses a tutor and reviews to convert encounters into memory.

That is narrower, easier to ship, and easier to defend. Toucan already owns the
general "replace words while browsing" idea in Chrome/Edge, but Safari is
underserved. LingQ, Readlang, Language Reactor, and Migaku all validate the
broader market for authentic-content learning, vocabulary tracking, review, and
AI explanation. None of them are exactly this: an opinionated native Mac plus
Safari workflow that passively injects a small amount of target language into
ordinary English-language pages.

For a paid beta in the next few weeks, cut the local Ollama path, do not attempt
all-language depth parity, do not attempt arbitrary pattern/sentence grammar
generation across the whole page, and do not build a full course. Ship one
polished five-language beta loop with one active language at a time:

1. Inline word and exact safe phrase replacement in Safari.
2. Vocabulary library with seen counts and status.
3. A small daily review queue.
4. A constrained OpenAI-powered tutor for selected words and short phrases.
5. Privacy controls and clear setup.

The single most important product change before charging is adding a real review
state. Exposure counts alone are useful telemetry, but they are not learning.

## Current Product Reality

### What Exists Now

From the project docs and source, the current app consists of:

- Native SwiftUI dashboard and Safari Web Extension.
- German-only starter curriculum with 12 entries across four tiers. This should
  become a versioned five-language pack model before paid beta.
- Safari DOM transformer that replaces at most one eligible word per paragraph
  or message-like block.
- Exclusions for inputs, editable text, code, navigation, buttons, scripts,
  styles, hidden content, and sensitive forms.
- Shared learning state through an App Group, with extension-local storage as a
  development fallback.
- Toolbar popup with total seen count, page count, current tier, site toggle,
  global pause, and reset.
- Native dashboard with Overview, Vocabulary, Tutor, Sites, and Settings.
- Learn screen exists only as a placeholder.
- Native Tutor screen using a local Ollama OpenAI-compatible endpoint and a
  Qwen model.
- Tests covering progression, persistence, provider boundaries, native message
  shape, prompt privacy, extension policy, transformation, rollback, and
  duplicate exposure prevention.

Verification run on 2026-05-28:

- `npm test`: 10 extension tests passed.
- `swift test`: 23 Swift tests passed.

### What The Current App Is Actually Teaching

The app currently teaches recognition of a small set of very frequent German
function words by replacing their English equivalents inline. This is useful,
but limited, and the same model needs to generalize to Spanish, French, Italian,
and Portuguese.

It does not yet teach:

- Phrase-level meaning.
- Grammar changes caused by word order, case, gender, tense, or agreement.
- Productive recall.
- Listening or pronunciation.
- Writing beyond free-form tutor chat.
- Mastery based on spaced retrieval.

The product should not pretend otherwise. The beta should frame the experience
as "ambient vocabulary plus review and tutor," not as "learn a language from
scratch."

### Strong Existing Assets

- The privacy boundary is strong. Page text stays in the content script; only
  word IDs and exposure increments are reported.
- The Safari-specific approach is differentiated. Most comparable products are
  Chrome-first.
- The UI direction has a real identity. It feels calmer and more adult than a
  streak-heavy gamified app.
- The extension architecture is safer than the old Accessibility overlay path.
  Inline DOM replacement scrolls and lays out naturally with the page.
- The bounded tutor prompt is already constrained around a selected learning
  token rather than raw page context.

### Current Beta Blockers

- Learning state is exposure-only. Vocabulary "recall" is currently derived
  from seen count, which is pedagogically misleading.
- The Learn/review screen is a placeholder.
- The tutor depends on Ollama local setup, which is too fragile for a paid beta.
- There is no OpenAI API provider yet.
- There is no packaged paid-beta distribution story.
- There is no onboarding that gets a user from install to working Safari
  extension access.
- There is no "today" model. The UI says "today" or "this week" in places, but
  state only stores lifetime counts.
- The curriculum is too small for more than a short beta demo.
- There is no feedback channel, crash/log bundle, or visible beta disclaimer.

## Market Scan

### Toucan By Babbel

Toucan is the closest direct analogue. Babbel describes it as a browser
extension that integrates new vocabulary into daily browsing. It automatically
translates certain words and phrases on a page into the language being learned,
supports saved words, pause/site controls, level adjustment, and several
languages. It currently supports Chrome and Edge, not Safari. Babbel acquired
Toucan in 2023 and stated that it would remain free while acting as a gateway
into Babbel's broader premium ecosystem.

Implication: the core mechanic is validated, but charging for only word
replacement will be hard. Cockatoo needs to charge for Mac/Safari polish,
privacy, review, and tutor integration, not just the replacement trick.

Sources:

- https://support.babbel.com/hc/en-gb/articles/18269893246738-Toucan-browser-extension
- https://www.babbel.com/press/en-us/releases/keep-learning-while-browsing-babbel-to-integrate-toucan-browser-extension

### Readlang

Readlang is a reading-first product. It lets learners click words or phrases in
texts/websites to translate, uses AI for context explanations, tracks word
highlights, and supports flashcard practice/export. Its pricing page currently
lists Premium at $6/month or $48/year, and Premium Plus at $15/month or
$120/year with GPT-4o-powered features.

Implication: users already pay for clean reading, fast lookup, phrase
translation, context explanation, and flashcard review. Cockatoo's opportunity
is to invert the flow: instead of requiring the user to enter a reader, it meets
them inside Safari and then pulls weak words into review.

Sources:

- https://readlang.com/pricing
- https://readlang.com/features

### LingQ

LingQ is a mature authentic-content platform. It centers on importing/consuming
books, podcasts, transcripts, and lessons; saving words and phrases; flashcard
quizzes; full sentence translations; stats; offline access; and AI features in
higher tiers. Its public pricing page currently lists Premium at $14.99 monthly,
$10/month billed annually, or $8.99/month billed every two years; Premium Plus
is listed at $29.99 monthly or $22.50/month billed annually.

Implication: a full content library/import platform is outside Cockatoo's beta
scope. LingQ validates the value of authentic content and vocabulary tracking,
but Cockatoo should avoid competing on library depth.

Source:

- https://www.lingq.com/en/signup/

### Language Reactor

Language Reactor focuses on YouTube/Netflix-style video learning. Its official
FAQ says Pro primarily adds machine translations and saving words/phrases, with
one subscription covering Netflix, YouTube, and LanguageReactor.com. It is not a
general Safari webpage replacement product.

Implication: video immersion is a different job. Do not chase subtitles,
streaming controls, or media workflows for beta.

Sources:

- https://www.languagereactor.com/help/faq
- https://www.languagereactor.com/pro-mode

### Migaku

Migaku is a power-user immersion suite. Its official docs describe a Chrome
desktop extension, mobile apps, courses, text analysis, interactive subtitles
and webpage text, recommendations based on known vocabulary, difficulty ratings,
dictionary lookup, AI-powered sentence breakdowns, one-click flashcards, spaced
repetition, video workflows, clipboard import, and OCR.

Implication: Migaku is strong but complex. Cockatoo should not become a power
tool in beta. The opportunity is the opposite: a tasteful, low-friction Mac app
for learners who do not want to manage Anki, dictionaries, subtitle pipelines,
and browser-specific workflows.

Sources:

- https://migaku.com/faq/features
- https://migaku.com/faq/getting-started

### Pricing And Positioning Takeaways

The market has a clear ladder:

- Free: Toucan, Language Reactor free features, basic Readlang/LingQ limits.
- Low paid: Readlang Premium around $6/month, Language Reactor Pro commonly
  cited around $5/month, niche reading/video tools in the $4-10/month range.
- Higher paid: LingQ Premium around $10-15/month, Premium Plus around
  $22-30/month, broader AI/media platforms above that.

Cockatoo should not launch at a high subscription price until it has a durable
review loop, enough curriculum depth, and cloud costs under control. A paid beta
should be framed as early access:

- Recommended beta price if users bring their own OpenAI API key: $19-29 one
  time for beta access, or $5/month.
- Recommended beta price if OpenAI usage is included: $8-12/month with explicit
  fair-use limits.
- Avoid lifetime pricing until retention and model costs are understood.

## Niche And Differentiation

### Best Niche

The best niche is:

> Mac/Safari users learning Spanish, French, German, Italian, or Portuguese who
> want a low-friction way to keep the target language present during normal
> browsing, with private progress tracking and a small tutor/review loop.

This is narrower than "language learners" but much more reachable.

### Why This Niche Can Work

- Mac/Safari users are underserved by Chrome-first language extensions.
- The first five languages use Latin script, are strong LLM-supported targets,
  and can share most extension, review, and tutor architecture.
- Adult learners often dislike childish gamification and want something that
  fits their existing reading habit.
- Users who already pay for productivity or learning tools may accept a paid
  beta if the product is honest and polished.
- Privacy can be a differentiator if cloud tutor calls are explicit and bounded.

### What Cockatoo Should Not Claim Yet

- "Learn a language automatically."
- "Replace Duolingo/Babbel."
- "Master grammar through browsing."
- "Full immersion."
- "Private AI tutor" if using hosted OpenAI without a clear disclosure.

### Stronger Claim

Use:

> Learn and review Spanish, French, German, Italian, or Portuguese while reading
> the web in Safari.

Supporting copy:

> Cockatoo gently introduces target-language words and phrases into pages you
> already read, tracks what you have seen, and turns weak items into short
> reviews and tutor moments.

## OpenAI-Only Recommendation

For beta, remove Ollama from the main product path. Keep the provider boundary,
but ship one cloud provider.

Reasons:

- Local model setup is too much friction for a paid beta.
- Local model quality is inconsistent for grammar correction.
- Debugging user machines with Ollama, model downloads, ports, and permissions
  will consume the beta.
- OpenAI gives a more reliable tutor baseline and lets you focus on product
  fit.

Implementation choices:

### Option A: User-Supplied OpenAI API Key

Fastest. The app stores the user's key in Keychain and calls OpenAI directly
from the Mac app.

Pros:

- No backend required.
- Cost risk is pushed to the user.
- Achievable within 2 weeks.
- Good for a small technical beta.

Cons:

- Worse onboarding.
- Less consumer-friendly.
- Users may not know how to create/manage API keys.
- Harder to justify recurring pricing.

### Option B: Hosted OpenAI Proxy

The app authenticates to your backend; your backend calls OpenAI with rate
limits.

Pros:

- Better paid-app experience.
- You can enforce usage limits, swap models, and avoid exposing keys.
- Easier to eventually support subscriptions.

Cons:

- Adds auth, billing, API server, abuse prevention, logs, and privacy policy.
- Hard to do well inside 2 weeks unless kept extremely small.

Recommendation: if the beta group is small and early-adopter-heavy, ship Option
A first and charge a lower early-access price. If the beta is meant for general
consumers, delay toward 4 weeks and build a minimal hosted proxy.

Current OpenAI pricing docs list lower-cost current models such as
`gpt-5.4-nano` and `gpt-5.4-mini` with per-token pricing. Use a configurable
model name rather than hard-coding a marketing claim, because model availability
and pricing change.

Source:

- https://developers.openai.com/api/docs/pricing

## Two-Week Paid Beta Scope

This is the smallest scope I would charge for.

### Keep

- Five target languages: Spanish, French, German, Italian, Portuguese.
- One active language at a time.
- Safari only.
- Native dashboard.
- Inline word and exact safe phrase replacement.
- Popup pause/site controls.
- Vocabulary library.
- Tutor, but constrained to selected word/phrase and user question.
- Basic stats, but label them honestly.
- Privacy boundary.

### Add Or Finish

1. OpenAI provider
   - Replace the Ollama default with an `OpenAITutorProvider`.
   - Store API key in Keychain for BYO-key beta.
   - Add model setting with a sane default.
   - Keep calls bounded: selected word, translation, explanation, and user
     question. Do not send page text by default.

2. Minimal review loop
   - Add a real `ReviewState` per item:
     - `lastSeenAt`
     - `recognitionAttempts`
     - `recognitionCorrect`
     - `nextReviewAt`
     - `status`: new, learning, reviewing, strong
   - Add a Learn screen with one recognition card:
     - Prompt: "What does `und` mean?"
     - Multiple choice answers from the starter curriculum.
     - Correct/incorrect feedback.
     - Schedule next review with a simple interval.
   - Do not add recall typing, cloze, or writing review yet.

3. Honest vocabulary screen
   - Replace fake recall percentage derived from exposure count.
   - Show:
     - seen count
     - review status
     - next review
     - recognition accuracy if available

4. Onboarding and setup
   - First-run checklist:
     - enable Safari extension
     - grant website access
     - choose OpenAI setup
     - open a test page
   - Include an in-app "Test Tutor" button.

5. Beta packaging
   - Create signed/notarized app build or a clear TestFlight/direct beta path.
   - Add beta disclaimer and feedback email/link.
   - Add a short privacy page.

6. Curriculum expansion
   - Expand from 12 German words to versioned starter packs for five languages.
   - Keep to high-frequency, context-safe words and exact safe phrase chunks:
     - conjunctions
     - adverbs
     - prepositions only when safe
     - pronouns only where ambiguity is low
     - exact phrase chunks such as "of course", "I think", and "a little"
   - Avoid automatic pattern and sentence rewriting until after beta.

### Cut

- Ollama setup scripts from the main user path.
- Local model settings UI.
- Additional languages beyond Spanish, French, German, Italian, and Portuguese.
- Simultaneous multi-language learning.
- Pattern/sentence rewriting inside live pages.
- Any native-app replacement outside Safari.
- Voice, pronunciation scoring, speech recognition.
- Imported content/library platform.
- Anki export.
- Complex SRS algorithm. Use simple intervals first.
- Tutor access from hover cards.
- Discord/WhatsApp as promised support. Keep them as "experimental."
- Daily streaks and gamification.

### Two-Week Acceptance Criteria

- A new user can install, enable Safari extension, enter/test OpenAI key, and see
  replacements on a normal article page.
- The user can pause globally and disable a site.
- Exposure counts persist across app/extension restarts.
- Each language has vetted word and phrase entries, but only a small number are
  active at once.
- The Learn screen can review due words and phrases with multiple-choice
  recognition.
- The Vocabulary screen shows real review state, not fake recall.
- The Tutor can answer selected-word questions through OpenAI.
- Page text is not sent to OpenAI unless the user explicitly invokes a future
  context feature.
- Build is signed/notarized or distributed through a beta channel with clear
  instructions.

## Four-Week Paid Beta Scope

If you take four weeks, add just enough depth to make retention plausible.

### Add To The Two-Week Scope

1. Phrase replacement hardening
   - Add curated phrase entries such as:
     - "of course" -> "natuerlich"
     - "I think" -> "ich glaube"
     - "there is" -> "es gibt"
   - Apply exact phrase replacement automatically in Safari when the phrase is
     marked `ambientSafe`.
   - Track phrase exposures and reviews separately from their component words.
   - Keep phrase matching before word matching so larger safe chunks win.

2. Cloze review
   - Prompt: "Ich trinke Kaffee ___ Tee."
   - Multiple choice first.
   - OpenAI can generate candidate cloze cards, but save only approved/generated
     cards that pass simple checks.

3. Better scheduling
   - Simple interval ladder:
     - wrong: later today
     - first correct: tomorrow
     - second correct: 3 days
     - third correct: 7 days
     - strong: 14 days
   - Keep it transparent. Do not overbuild FSRS yet.

4. Context opt-in
   - User can select a sentence and ask the tutor.
   - The app shows exactly what text will be sent.
   - Do not auto-send arbitrary page text.

5. Feedback and diagnostics
   - Export anonymized beta diagnostic bundle:
     - app version
     - Safari extension enabled status if detectable
     - state counts
     - recent non-sensitive errors
   - Include a direct feedback link in Settings.

6. Paywall/licensing
   - If direct paid beta: simple license key verification.
   - If hosted model usage: account + rate limits + cancellation path.

## Product Roadmap After Beta

### Phase 1: Ambient Vocabulary And Phrases

Goal: prove that users keep the extension on.

- More vetted words and exact safe phrases.
- Better replacement selection.
- Stronger site compatibility.
- Review due counts.
- Basic tutor.

### Phase 2: Phrases And Grammar

Goal: graduate from word/phrase replacement to language patterns.

- Exact phrase chunks in Safari.
- Grammar notes attached to patterns.
- Cloze prompts.
- Tutor-generated examples constrained to known words.

### Phase 3: Output

Goal: make the learner produce language.

- "Use today's words" short writing.
- Tutor correction with a small rubric.
- Saved corrected sentences.
- Review production separately from recognition.

### Phase 4: Rich Input

Goal: expand beyond arbitrary web reading without becoming LingQ.

- Article/session recap.
- Optional selected-text explanations.
- Maybe YouTube captions much later.
- Import/export vocabulary.

## Business Risks

### Risk: The Product Feels Too Small To Charge For

Mitigation: charge for early access, not a finished course. Make the beta
promise clear and keep price modest. The app must feel polished and reliable
even if scope is small.

### Risk: Users Compare It To Free Toucan

Mitigation: position on Safari-native Mac experience, privacy, review, and
tutor. Do not sell "word replacement" as the whole value.

### Risk: OpenAI Costs Or Abuse

Mitigation: BYO-key for earliest beta, or hosted proxy with strict daily caps.
Use cheap models for routine work and a better model only for tutor questions
that need it.

### Risk: Pedagogical Credibility

Mitigation: stop calling exposure "recall" or "fluent." Track exposure,
recognition, recall, and production separately. For beta, implement recognition
only and name it honestly.

### Risk: Safari Extension Setup Friction

Mitigation: onboarding must be excellent. If setup takes more than a few
minutes, paid beta users will churn before seeing value.

### Risk: Page Compatibility

Mitigation: guarantee article/document pages only. Keep web apps experimental.
Make disable-site obvious and reversible.

## Recommended Release Positioning

Name:

- Cockatoo

Short description:

- A Safari-native language learning companion for Mac.

Landing page headline:

- Learn a language while reading the web.

Subhead:

- Cockatoo gently introduces target-language words and phrases into Safari
  pages, tracks what you have seen, and turns them into quick reviews and tutor
  moments.

Beta disclaimer:

- Spanish, French, German, Italian, and Portuguese.
- One active language at a time.
- Safari only.
- Best on article-style pages.
- Early paid beta.
- OpenAI key required, unless you choose hosted beta.

What to say it replaces:

- Not "Duolingo replacement."
- Say "a lighter companion to courses and flashcards."
- For users tired of courses, say "a way to keep your target language present
  between study sessions."

## Build Plan For The Next Few Weeks

### Week 1

- Add OpenAI tutor provider and Keychain API-key storage.
- Remove Ollama from visible onboarding/settings.
- Add first-run setup checklist.
- Add review state to `LearningState`.
- Change Vocabulary to show real review fields.
- Add starter packs for Spanish, French, German, Italian, and Portuguese.

### Week 2

- Build Learn screen recognition review.
- Wire due counts into Overview/sidebar/popup.
- Add Settings privacy copy and API-key test.
- Package beta build.
- Create landing page/payment/invite flow.
- Run Safari manual QA on article pages.

### Week 3

- Add cloze review.
- Add simple phrase entries in review only.
- Add diagnostics/feedback export.
- Improve onboarding based on first testers.
- Add hosted proxy only if you decide not to use BYO keys.

### Week 4

- Stabilize, fix setup friction, polish copy.
- Add selected-sentence tutor opt-in if core loop is already stable.
- Prepare paid beta cohort and support docs.

## Final Recommendation

Ship the beta as a narrow, paid, five-language Mac/Safari product with one
active language at a time. Cut everything that expands platform, model, or media
scope. The release should be judged by one question:

> Can a paying beta user keep Cockatoo enabled for a week, see their chosen
> target language in normal Safari reading, review weak items, and feel that the
> tutor helps without getting in the way?

If yes, you have a product worth expanding. If not, phrase replacement,
sentences, local models, and more languages will not fix the core retention
problem.

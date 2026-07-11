# Language Learning With LLMs: Research Brief

Date: 2026-05-27

## Context

The current product is a macOS app plus Safari Web Extension that performs
privacy-preserving inline vocabulary replacement while a learner reads normal
webpages. The extension currently tracks exposure counts, unlocks simple
curriculum tiers, and avoids sending raw page text to the app.

That architecture is a strong wedge for language learning because it attaches
practice to authentic reading. The main product risk is mistaking exposure for
mastery. Research supports exposure and glossing, but durable learning usually
needs retrieval, spacing, production, feedback, and adaptive scaffolding.

## Research Takeaways

### 1. Reading in context is valuable, but only when comprehension survives

Digital reading can support L2 vocabulary learning. A 2024 meta-analysis of 21
studies found significant vocabulary-learning effects from digital reading, and
specifically points toward adaptive algorithms and personalized lexical glosses
as promising design directions.

Product implication: preserve the user's primary reading task. Inline language
learning should be sparse, context-sensitive, and interruptible. The current
"at most one replacement per paragraph/message block" rule is pedagogically
defensible.

Source: Zhu, Zhang, and Irwin, "Second and Foreign Language Vocabulary Learning
through Digital Reading: A Meta-Analysis"
https://link.springer.com/article/10.1007/s10639-023-11969-1

### 2. Lexical coverage matters

L2 reading research commonly treats around 95% known vocabulary as a reasonable
minimum for adequate comprehension, with 98% often associated with comfortable
independent reading. If an app injects too many unknown forms, it can damage the
comprehension that makes incidental learning possible.

Product implication: model replacement density as a first-class learning
parameter. Beginner mode should use very low density and high-frequency words.
Higher density should be earned by stable comprehension and recall, not merely
by time spent.

Sources:
- Uchihara and Clenton, "How much vocabulary is needed to use English?"
  https://www.cambridge.org/core/journals/language-teaching/article/how-much-vocabulary-is-needed-to-use-english-replication-of-van-zeeland-schmitt-2012-nation-2006-and-cobb-2007/1D217A56A2E0056E67802A6A8360FDDE
- Webb and Pellicer-Sanchez, "How does lexical coverage affect the processing
  of L2 texts?"
  https://academic.oup.com/applij/article/45/6/953/7841943

### 3. Exposure builds recognition before production

Vocabulary knowledge is not binary. Learners usually recognize more words than
they can actively produce. Research on digital reading notes that correct
meaning inference is not enough for efficient vocabulary learning; words need
multiple encounters, and productive recall is harder than recognition.

Product implication: progress should not unlock only from exposure counts.
Track separate states: seen, recognized, recalled, produced, and fluent. A word
should graduate only after spaced recall and some production, not after passive
replacement alone.

Source: Zhu, Zhang, and Irwin, lines on repeated meetings and receptive before
productive vocabulary
https://link.springer.com/article/10.1007/s10639-023-11969-1

### 4. Spacing and retrieval are the memory engine

General learning research consistently rates practice testing/retrieval and
distributed practice as high-utility techniques. Spacing research also shows
that the timing between study and review affects long-term retention.

Product implication: every exposure should feed a review scheduler. The app
should create lightweight retrieval prompts: "What did this mean?", cloze
sentences, reverse translation, and "use it in a sentence." Reviews should be
short and attached to natural moments: toolbar popup, dashboard, or optional
end-of-session recap.

Sources:
- Dunlosky et al., "Improving Students' Learning With Effective Learning
  Techniques"
  https://www.psychologicalscience.org/publications/journals/pspi/learning-techniques.html
- Cepeda et al., "Spacing effects in learning: a temporal ridgeline of optimal
  retention"
  https://pubmed.ncbi.nlm.nih.gov/19076480/

### 5. A balanced curriculum needs input, output, language focus, and fluency

Nation's four-strands framework is a useful product lens: meaning-focused
input, meaning-focused output, language-focused learning, and fluency
development. The current app is primarily meaning-focused input plus a small
amount of language-focused learning through hover explanations.

Product implication: do not try to make inline replacement do all the work.
Use the dashboard and optional tutor surfaces to cover the missing strands:
output practice, explicit grammar/vocabulary focus, and fluency work with known
items.

Source: Nation, "The Four Strands"
https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/paul-nations-publications

### 6. LLMs help most when they scaffold interaction, not when they merely answer

A 2025 systematic review of 88 empirical studies on LLMs in education found
common benefits around academic performance, engagement, accessibility, and
tutoring systems, but also flagged over-reliance, fairness, privacy, and
technical reliability. A separate 2025 meta-analysis of digital learning prompts
found prompts improve achievement, with stronger effects for behavior-triggered
and learner-tailored prompts.

Product implication: use models for small, scaffolded, verifiable acts:
generate examples, adapt explanations to level, produce cloze prompts, offer
Socratic hints, and create role-play tasks using known vocabulary. Avoid making
an open chat window the core product.

Sources:
- Shi et al., "Large language models in education: a systematic review of
  empirical applications, benefits, and challenges"
  https://www.sciencedirect.com/science/article/pii/S2666920X25001699
- Thomann and Deutscher, "Scaffolding through prompts in digital learning"
  https://www.sciencedirect.com/science/article/pii/S1747938X25000235

### 7. LLM chatbots show promise for vocabulary, speaking, and writing

An 8-week 2024 study of 52 foreign-language students found that LLM chatbot
support improved both receptive and productive vocabulary knowledge, with
notable effects on productive retention. A 2025 systematic review of 30
empirical chatbot studies in L2 learning found positive outcomes across skills,
especially speaking and writing, due to practice opportunities, real-time
feedback, and reduced anxiety.

Product implication: add conversation and writing practice after the inline
reading loop has built a small known set. The tutor should preferentially reuse
words the learner has recently seen, turning passive encounters into active use.

Sources:
- Zhang and Huang, "The impact of chatbots based on large language models on
  second language vocabulary acquisition"
  https://www.sciencedirect.com/science/article/pii/S2405844024014014
- "AI-driven chatbots in second language education: A systematic review of
  their efficacy and pedagogical implications"
  https://www.sciencedirect.com/science/article/pii/S2215039025000086

### 8. LLM feedback is useful, but inconsistent enough to constrain

ChatGPT-style feedback can improve ESL writing when used as formative feedback
with training. But comparative work on written corrective feedback found GPT
feedback can vary across runs for the same prompt and can produce accurate but
redundant feedback.

Product implication: the app should not let free-form model feedback define the
curriculum truth. Keep a vetted lexical/curricular layer. Let the model propose
examples and exercises, then constrain outputs against known target words,
translation entries, CEFR/frequency metadata, and explicit safety rules.

Sources:
- Mahapatra, "Impact of ChatGPT on ESL students' academic writing skills"
  https://link.springer.com/article/10.1186/s40561-024-00295-9
- Lin and Crosthwaite, "The grass is not always greener: Teacher vs.
  GPT-assisted written corrective feedback"
  https://www.sciencedirect.com/science/article/pii/S0346251X24003117

### 9. AI in SLA transforms learning only when the task is redesigned

A 2025 review of 281 AI-in-SLA studies found most uses still enhance existing
tasks rather than transform them; only about 35% reached higher levels of task
redesign. Generative AI lowers the barrier to dialogic and multimodal learning,
but does not guarantee better pedagogy.

Product implication: "LLM integration" should not mean "add chat." It should
redesign the learning loop:

1. Diagnose from real reading and review behavior.
2. Adapt inline exposure and explanations.
3. Prompt retrieval at the right time.
4. Convert recently encountered words into output tasks.
5. Feed performance back into the next page's replacement choices.

Source: Bao et al., "A systematic review of AI in second language acquisition
using the expanded SAMR model"
https://link.springer.com/article/10.1007/s10791-025-09833-6

## Recommended App Shape

### Product Thesis

The app should be an ambient reading companion with an adaptive tutor loop, not
a general-purpose AI language chatbot. Its distinctive advantage is that it
learns from what the user actually reads while preserving privacy and page
integrity.

### Core Learning Loop

1. **Encounter:** Replace or annotate a small number of high-value words in
   authentic webpages.
2. **Notice:** On hover/focus, show a short gloss, pronunciation, and one
   context-sensitive example.
3. **Retrieve:** Later, ask the user to recall the meaning or complete a cloze.
4. **Produce:** Ask the user to write or say a short sentence using the word.
5. **Schedule:** Update the word's interval, difficulty, and replacement
   priority.
6. **Reuse:** Prefer words that are due for review when selecting future page
   replacements, while maintaining low density.

### Data Model Direction

Replace a single exposure count with per-word learning state:

- `exposureCount`
- `firstSeenAt`, `lastSeenAt`
- `recognitionAttempts`, `recognitionCorrect`
- `recallAttempts`, `recallCorrect`
- `productionAttempts`, `productionAccepted`
- `nextReviewAt`
- `ease` or `difficulty`
- `blockedContexts` for words that generate bad replacements

Exposure should unlock availability. Retrieval and production should unlock
mastery.

### LLM Roles

Good uses:

- Generate context-sensitive glosses from bounded snippets when the user opts in.
- Create cloze sentences from learned words.
- Explain why a learner's sentence is awkward, with one correction and one rule.
- Generate short role-play prompts using known vocabulary.
- Rewrite page-adjacent sentences at the learner's level.
- Suggest curriculum candidates from frequency lists and learner interests.

Risky uses:

- Replacing vetted translations with unconstrained model translations.
- Sending raw webpages or private messages to a cloud model by default.
- Grading open-ended writing with no rubric or consistency checks.
- Letting the model decide that a word is "mastered" without retrieval evidence.

### Privacy Boundary

The existing boundary is a product advantage. Keep raw page text local by
default. If cloud LLM features are added, make them explicit user actions and
send only the minimum selected snippet needed for the task. Prefer local models
for routine generation of examples, quizzes, and explanations.

### MVP-to-LLM Roadmap

1. **Now:** Keep inline replacement sparse. Add richer progress states and a
   review queue.
2. **Next:** Add non-LLM retrieval: recognition cards, cloze cards, reverse
   translation, and spaced scheduling.
3. **Then:** Add constrained LLM-generated examples and cloze prompts for known
   vocabulary.
4. **Then:** Add output practice: "use today's words", short writing feedback,
   and role-play.
5. **Later:** Add speech: pronunciation, shadowing, and spoken conversation,
   likely with automatic speech recognition and text-to-speech.

## Design Principles

- Preserve comprehension before maximizing target-language density.
- Treat exposure as input, not proof.
- Prefer micro-interactions over long lessons.
- Make the model a scaffold, not the authority.
- Keep the app's privacy promise visible in the architecture.
- Optimize for repeated natural encounters plus scheduled recall.
- Build toward production practice once recognition is stable.


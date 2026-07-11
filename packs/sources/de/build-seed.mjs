#!/usr/bin/env node
// Seed German pack generator — the hand-curated stand-in for the full
// pipeline (docs/plan/07-content-pipeline.md). The full ~1000-item pack is
// produced by `packtool author` against a frequency list + LLM authoring
// pass; this seed covers bands 1-4 with carefully hand-checked content so
// the product loop is exercisable end to end.
//
// Usage: node build-seed.mjs > ../../build/de-2026.07.json

const slug = (s) =>
  s.toLowerCase()
    .replaceAll("ä", "ae").replaceAll("ö", "oe").replaceAll("ü", "ue").replaceAll("ß", "ss")
    .replaceAll(/[^a-z0-9]+/g, "-");

const level = (band) => (band <= 3 ? "a1" : "a2");

// Noun with full determiner/number variant set (decision D10).
function noun({ en, de, gender, enPl, dePl, band, explanation, example }) {
  const indef = gender === "die" ? "eine" : "ein";
  const forms = [
    { form: `the ${en}`, target: `${gender} ${de}` },
    { form: `a ${en}`, target: `${indef} ${de}` },
    { form: en, target: de },
  ];
  if (enPl && dePl) {
    forms.push({ form: enPl, target: dePl });
    forms.push({ form: `the ${enPl}`, target: `die ${dePl}` });
  }
  return {
    id: `de.word.${slug(de)}`,
    language: "de", kind: "word",
    sourceForms: forms,
    target: de,
    targetMeta: { gender, plural: dePl ?? null, pos: "noun", pronunciation: null },
    level: level(band), frequencyBand: band,
    replacementPolicy: "ambientSafe", fidelityTier: "formMatched",
    dependencies: [],
    explanation,
    examples: [example],
  };
}

// Invariant word (conjunction / sentence adverb) — fidelity: exact.
function inv({ en, de, pos, band, explanation, example }) {
  return {
    id: `de.word.${slug(de)}`,
    language: "de", kind: "word",
    sourceForms: [{ form: en, target: de }],
    target: de,
    targetMeta: { gender: null, plural: null, pos, pronunciation: null },
    level: level(band), frequencyBand: band,
    replacementPolicy: "ambientSafe", fidelityTier: "exact",
    dependencies: [],
    explanation,
    examples: [example],
  };
}

// Fixed chunk — fidelity: exact.
function chunk({ en, de, band, explanation, example, deps = [] }) {
  return {
    id: `de.chunk.${slug(de)}`,
    language: "de", kind: "chunk",
    sourceForms: [{ form: en, target: de }],
    target: de,
    targetMeta: { gender: null, plural: null, pos: "chunk", pronunciation: null },
    level: level(band), frequencyBand: band,
    replacementPolicy: "ambientSafe", fidelityTier: "exact",
    dependencies: deps,
    explanation,
    examples: [example],
  };
}

const items = [
  // ── Band 1 ──────────────────────────────────────────────────────────
  inv({ en: "and", de: "und", pos: "conjunction", band: 1,
    explanation: "und means and — the most common German word.",
    example: { source: "Bread and butter.", target: "Brot und Butter." } }),
  inv({ en: "but", de: "aber", pos: "conjunction", band: 1,
    explanation: "aber means but.",
    example: { source: "I am coming, but later.", target: "Ich komme, aber später." } }),
  inv({ en: "or", de: "oder", pos: "conjunction", band: 1,
    explanation: "oder means or.",
    example: { source: "Coffee or tea?", target: "Kaffee oder Tee?" } }),
  inv({ en: "also", de: "auch", pos: "adverb", band: 1,
    explanation: "auch means also / too.",
    example: { source: "Me too.", target: "Ich auch." } }),
  inv({ en: "not", de: "nicht", pos: "adverb", band: 1,
    explanation: "nicht negates a statement: not.",
    example: { source: "That is not good.", target: "Das ist nicht gut." } }),
  inv({ en: "here", de: "hier", pos: "adverb", band: 1,
    explanation: "hier means here.",
    example: { source: "We are here.", target: "Wir sind hier." } }),
  inv({ en: "now", de: "jetzt", pos: "adverb", band: 1,
    explanation: "jetzt means now.",
    example: { source: "We are going now.", target: "Wir gehen jetzt." } }),
  inv({ en: "today", de: "heute", pos: "adverb", band: 1,
    explanation: "heute means today.",
    example: { source: "Today is Monday.", target: "Heute ist Montag." } }),
  noun({ en: "house", de: "Haus", gender: "das", enPl: "houses", dePl: "Häuser", band: 1,
    explanation: "das Haus (neuter) — house; plural Häuser.",
    example: { source: "The house is old.", target: "Das Haus ist alt." } }),
  noun({ en: "dog", de: "Hund", gender: "der", enPl: "dogs", dePl: "Hunde", band: 1,
    explanation: "der Hund (masculine) — dog; plural Hunde.",
    example: { source: "The dog is sleeping.", target: "Der Hund schläft." } }),
  noun({ en: "water", de: "Wasser", gender: "das", band: 1,
    explanation: "das Wasser (neuter) — water.",
    example: { source: "The water is cold.", target: "Das Wasser ist kalt." } }),
  noun({ en: "book", de: "Buch", gender: "das", enPl: "books", dePl: "Bücher", band: 1,
    explanation: "das Buch (neuter) — book; plural Bücher.",
    example: { source: "The book is good.", target: "Das Buch ist gut." } }),

  // ── Band 2 ──────────────────────────────────────────────────────────
  inv({ en: "always", de: "immer", pos: "adverb", band: 2,
    explanation: "immer means always.",
    example: { source: "It is always like that.", target: "Es ist immer so." } }),
  inv({ en: "often", de: "oft", pos: "adverb", band: 2,
    explanation: "oft means often.",
    example: { source: "We see that often.", target: "Wir sehen das oft." } }),
  inv({ en: "never", de: "nie", pos: "adverb", band: 2,
    explanation: "nie means never.",
    example: { source: "That never happens.", target: "Das passiert nie." } }),
  inv({ en: "again", de: "wieder", pos: "adverb", band: 2,
    explanation: "wieder means again.",
    example: { source: "We will see each other again.", target: "Wir sehen uns wieder." } }),
  inv({ en: "very", de: "sehr", pos: "adverb", band: 2,
    explanation: "sehr means very.",
    example: { source: "Thank you very much.", target: "Danke sehr." } }),
  inv({ en: "maybe", de: "vielleicht", pos: "adverb", band: 2,
    explanation: "vielleicht means maybe / perhaps.",
    example: { source: "Maybe tomorrow.", target: "Vielleicht morgen." } }),
  inv({ en: "tomorrow", de: "morgen", pos: "adverb", band: 2,
    explanation: "morgen means tomorrow.",
    example: { source: "See you tomorrow!", target: "Bis morgen!" } }),
  inv({ en: "yesterday", de: "gestern", pos: "adverb", band: 2,
    explanation: "gestern means yesterday.",
    example: { source: "Yesterday was Sunday.", target: "Gestern war Sonntag." } }),
  noun({ en: "city", de: "Stadt", gender: "die", enPl: "cities", dePl: "Städte", band: 2,
    explanation: "die Stadt (feminine) — city; plural Städte.",
    example: { source: "The city is big.", target: "Die Stadt ist groß." } }),
  noun({ en: "child", de: "Kind", gender: "das", enPl: "children", dePl: "Kinder", band: 2,
    explanation: "das Kind (neuter) — child; plural Kinder.",
    example: { source: "The child is laughing.", target: "Das Kind lacht." } }),
  noun({ en: "friend", de: "Freund", gender: "der", enPl: "friends", dePl: "Freunde", band: 2,
    explanation: "der Freund (masculine) — friend; plural Freunde.",
    example: { source: "My friend lives here.", target: "Mein Freund wohnt hier." } }),
  noun({ en: "year", de: "Jahr", gender: "das", enPl: "years", dePl: "Jahre", band: 2,
    explanation: "das Jahr (neuter) — year; plural Jahre.",
    example: { source: "A year has twelve months.", target: "Ein Jahr hat zwölf Monate." } }),
  chunk({ en: "there is", de: "es gibt", band: 2,
    explanation: "es gibt is the fixed phrase for 'there is / there are'.",
    example: { source: "There is a lot to see.", target: "Es gibt viel zu sehen." } }),
  chunk({ en: "for example", de: "zum Beispiel", band: 2,
    explanation: "zum Beispiel means for example (abbreviated z. B.).",
    example: { source: "Many cities, for example Berlin.", target: "Viele Städte, zum Beispiel Berlin." } }),

  // ── Band 3 ──────────────────────────────────────────────────────────
  inv({ en: "nevertheless", de: "trotzdem", pos: "adverb", band: 3,
    explanation: "trotzdem means nevertheless / anyway.",
    example: { source: "It is raining; we are going nevertheless.", target: "Es regnet, trotzdem gehen wir." } }),
  inv({ en: "therefore", de: "deshalb", pos: "adverb", band: 3,
    explanation: "deshalb means therefore / that is why.",
    example: { source: "That is why I am here.", target: "Deshalb bin ich hier." } }),
  inv({ en: "almost", de: "fast", pos: "adverb", band: 3,
    explanation: "fast means almost.",
    example: { source: "It is almost done.", target: "Es ist fast fertig." } }),
  inv({ en: "only", de: "nur", pos: "adverb", band: 3,
    explanation: "nur means only.",
    example: { source: "Only today.", target: "Nur heute." } }),
  inv({ en: "already", de: "schon", pos: "adverb", band: 3,
    explanation: "schon means already.",
    example: { source: "I am already there.", target: "Ich bin schon da." } }),
  inv({ en: "together", de: "zusammen", pos: "adverb", band: 3,
    explanation: "zusammen means together.",
    example: { source: "We are here together.", target: "Wir sind zusammen hier." } }),
  inv({ en: "soon", de: "bald", pos: "adverb", band: 3,
    explanation: "bald means soon.",
    example: { source: "See you soon!", target: "Bis bald!" } }),
  inv({ en: "unfortunately", de: "leider", pos: "adverb", band: 3,
    explanation: "leider means unfortunately.",
    example: { source: "Unfortunately not.", target: "Leider nein." } }),
  noun({ en: "world", de: "Welt", gender: "die", enPl: "worlds", dePl: "Welten", band: 3,
    explanation: "die Welt (feminine) — world; plural Welten.",
    example: { source: "The world is small.", target: "Die Welt ist klein." } }),
  noun({ en: "night", de: "Nacht", gender: "die", enPl: "nights", dePl: "Nächte", band: 3,
    explanation: "die Nacht (feminine) — night; plural Nächte.",
    example: { source: "The night was long.", target: "Die Nacht war lang." } }),
  noun({ en: "door", de: "Tür", gender: "die", enPl: "doors", dePl: "Türen", band: 3,
    explanation: "die Tür (feminine) — door; plural Türen.",
    example: { source: "The door is open.", target: "Die Tür ist offen." } }),
  noun({ en: "hand", de: "Hand", gender: "die", enPl: "hands", dePl: "Hände", band: 3,
    explanation: "die Hand (feminine) — hand; plural Hände.",
    example: { source: "My hand is cold.", target: "Meine Hand ist kalt." } }),
  chunk({ en: "of course", de: "natürlich", band: 3,
    explanation: "natürlich as a sentence word means of course.",
    example: { source: "Of course I am coming.", target: "Natürlich komme ich." } }),

  // ── Band 4 ──────────────────────────────────────────────────────────
  inv({ en: "actually", de: "eigentlich", pos: "adverb", band: 4,
    explanation: "eigentlich means actually / in fact.",
    example: { source: "Actually yes.", target: "Eigentlich ja." } }),
  inv({ en: "exactly", de: "genau", pos: "adverb", band: 4,
    explanation: "genau means exactly — also used alone as agreement.",
    example: { source: "Exactly!", target: "Genau!" } }),
  inv({ en: "immediately", de: "sofort", pos: "adverb", band: 4,
    explanation: "sofort means immediately / right away.",
    example: { source: "I am coming immediately.", target: "Ich komme sofort." } }),
  inv({ en: "finally", de: "endlich", pos: "adverb", band: 4,
    explanation: "endlich means finally / at last.",
    example: { source: "Finally the weekend!", target: "Endlich Wochenende!" } }),
  inv({ en: "sometimes", de: "manchmal", pos: "adverb", band: 4,
    explanation: "manchmal means sometimes.",
    example: { source: "Sometimes it rains.", target: "Manchmal regnet es." } }),
  inv({ en: "everywhere", de: "überall", pos: "adverb", band: 4,
    explanation: "überall means everywhere.",
    example: { source: "Water is everywhere.", target: "Wasser ist überall." } }),
  inv({ en: "at first", de: "zuerst", pos: "adverb", band: 4,
    explanation: "zuerst means (at) first.",
    example: { source: "Breakfast first.", target: "Zuerst das Frühstück." } }),
  inv({ en: "by the way", de: "übrigens", pos: "adverb", band: 4,
    explanation: "übrigens means by the way.",
    example: { source: "By the way, thanks.", target: "Übrigens, danke." } }),
  noun({ en: "time", de: "Zeit", gender: "die", enPl: "times", dePl: "Zeiten", band: 4,
    explanation: "die Zeit (feminine) — time; plural Zeiten.",
    example: { source: "I have no time.", target: "Ich habe keine Zeit." } }),
  noun({ en: "day", de: "Tag", gender: "der", enPl: "days", dePl: "Tage", band: 4,
    explanation: "der Tag (masculine) — day; plural Tage.",
    example: { source: "The day starts early.", target: "Der Tag beginnt früh." } }),
  noun({ en: "week", de: "Woche", gender: "die", enPl: "weeks", dePl: "Wochen", band: 4,
    explanation: "die Woche (feminine) — week; plural Wochen.",
    example: { source: "The week has seven days.", target: "Die Woche hat sieben Tage." } }),
  noun({ en: "month", de: "Monat", gender: "der", enPl: "months", dePl: "Monate", band: 4,
    explanation: "der Monat (masculine) — month; plural Monate.",
    example: { source: "The month is almost over.", target: "Der Monat ist fast vorbei." } }),
  chunk({ en: "good morning", de: "guten Morgen", band: 4,
    explanation: "guten Morgen is the standard morning greeting.",
    example: { source: "Good morning, how are you?", target: "Guten Morgen, wie geht's?" } }),
  chunk({ en: "thank you", de: "danke", band: 4,
    explanation: "danke means thank you.",
    example: { source: "Thank you for everything.", target: "Danke für alles." } }),
  chunk({ en: "see you soon", de: "bis bald", band: 4, deps: ["de.word.bald"],
    explanation: "bis bald means see you soon.",
    example: { source: "See you soon, Anna!", target: "Bis bald, Anna!" } }),
];

const pack = {
  schema: 1,
  language: "de",
  version: "2026.07",
  provenance: {
    corpus: "hand-curated seed (full pipeline: FrequencyWords/OpenSubtitles pending)",
    license: "project-original content",
    packtool: "seed-generator-1.0",
    authoringModel: null,
    generatedAt: "2026-07-11",
  },
  grading: { articles: ["der", "die", "das", "ein", "eine"] },
  items,
};

process.stdout.write(JSON.stringify(pack, null, 2) + "\n");

import type { Snapshot, SnapshotItem } from "./types";

// Surface-form matcher. Built once per snapshot; inflection was resolved at
// authoring time (R1a) so matching is exact per form. Determiner-extended
// forms win via longest-match (D10).

export interface Match {
  item: SnapshotItem;
  form: string; // the matched surface form (lowercased)
  display: string; // target text to render
  start: number; // offsets into the searched text
  end: number;
}

const BOUNDARY = /[a-z0-9]/i;

export class Matcher {
  /** first word of a form -> candidate forms, longest first */
  private byFirstWord = new Map<string, { form: string; display: string; item: SnapshotItem }[]>();

  constructor(snapshot: Snapshot) {
    for (const item of snapshot.items) {
      for (const form of item.forms) {
        const match = form.match.toLowerCase();
        const firstWord = match.split(/\s+/)[0];
        const list = this.byFirstWord.get(firstWord) ?? [];
        list.push({ form: match, display: form.display, item });
        this.byFirstWord.set(firstWord, list);
      }
    }
    // Longest form first so "the house" beats "house".
    for (const list of this.byFirstWord.values()) {
      list.sort((a, b) => b.form.length - a.form.length);
    }
  }

  get isEmpty(): boolean {
    return this.byFirstWord.size === 0;
  }

  /** All non-overlapping matches in a text node's content, left to right. */
  matches(text: string): Match[] {
    const lower = text.toLowerCase();
    const results: Match[] = [];
    const wordRe = /[a-zäöüß0-9']+/gi;
    let m: RegExpExecArray | null;

    while ((m = wordRe.exec(lower)) !== null) {
      const candidates = this.byFirstWord.get(m[0]);
      if (!candidates) continue;

      for (const candidate of candidates) {
        const start = m.index;
        const end = start + candidate.form.length;
        if (lower.slice(start, end) !== candidate.form) continue;
        // Word boundaries on both sides.
        if (start > 0 && BOUNDARY.test(lower[start - 1])) continue;
        if (end < lower.length && BOUNDARY.test(lower[end])) continue;

        results.push({
          item: candidate.item,
          form: candidate.form,
          display: applyCapitalization(text.slice(start, end), candidate.display),
          start,
          end,
        });
        // Skip past this match; continue scanning after it.
        wordRe.lastIndex = end;
        break;
      }
    }
    return results;
  }
}

/** Sentence-start capitalization: "The house" → "Das Haus". German noun
 * capitalization comes from the display form itself. */
export function applyCapitalization(source: string, display: string): string {
  if (source.length > 0 && source[0] === source[0].toUpperCase() && /[a-z]/i.test(source[0])) {
    return display[0].toUpperCase() + display.slice(1);
  }
  return display;
}

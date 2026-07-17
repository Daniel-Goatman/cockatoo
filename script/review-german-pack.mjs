#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const packPath = resolve(root, "packs/build/de-2026.10.json");
const expectedChecksum = "7597229f6257cb51160e8992058fd0cbfe5f575aa3359dbef3c507d0b14041e9";
const sampleSeed = "cockatoo-de-2026.10-review-v1";
const data = readFileSync(packPath);
const checksum = createHash("sha256").update(data).digest("hex");

if (checksum !== expectedChecksum) {
  console.error("German review packet is stale.");
  console.error(`expected ${expectedChecksum}`);
  console.error(`actual   ${checksum}`);
  console.error("Update the pack, provenance, review record, and sample together.");
  process.exit(1);
}

const pack = JSON.parse(data);
const sample = pack.items
  .map((item) => ({
    item,
    order: createHash("sha256").update(`${sampleSeed}:${item.id}`).digest("hex"),
  }))
  .sort((a, b) => a.order.localeCompare(b.order))
  .slice(0, 50)
  .map(({ item }) => item)
  .sort((a, b) => a.frequencyBand - b.frequencyBand || a.id.localeCompare(b.id));

console.log("German 2026.10 deterministic human-review sample");
console.log(`Pack SHA-256: ${checksum}`);
console.log(`Selection seed: ${sampleSeed}`);
console.log(`Coverage: ${sample.length}/${pack.items.length} items; ${sample.reduce((sum, item) => sum + item.examples.length, 0)} examples`);
console.log("");

for (const item of sample) {
  const meta = [item.targetMeta?.gender, item.targetMeta?.pos, `band ${item.frequencyBand}`]
    .filter(Boolean)
    .join("; ");
  console.log(`[ ] ${item.id} — ${item.target} (${meta})`);
  console.log(`    Explanation: ${item.explanation}`);
  console.log(`    Forms: ${item.sourceForms.map((form) => `${form.form} → ${form.target}`).join(" | ")}`);
  item.examples.forEach((example, index) => {
    console.log(`    Example ${index + 1}: ${example.source} → ${example.target}`);
  });
  console.log("");
}

console.log("For every item, check dominant sense, forms, gender/plural/POS, explanation, and all examples.");
console.log("Record pass/fail and corrections in docs/pack-review-2026.10.md; the reviewer must be human.");

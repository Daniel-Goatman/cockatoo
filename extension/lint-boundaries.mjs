import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

// Boundary rule (docs/plan/05-extension.md): sendNativeMessage may appear
// ONLY under src/adapters/safari/. Everything in src/core must stay
// browser-agnostic behind the Transport interface.

const violations = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      walk(path);
    } else if (name.endsWith(".ts")) {
      const text = readFileSync(path, "utf8");
      const isAdapter = path.includes("adapters/safari");
      if (!isAdapter && text.includes("sendNativeMessage")) {
        violations.push(`${path}: sendNativeMessage outside adapters/safari/`);
      }
      if (path.includes("src/core") && /\bbrowser\./.test(text)) {
        violations.push(`${path}: core module references the browser namespace`);
      }
    }
  }
}

walk("src");

if (violations.length > 0) {
  console.error(violations.join("\n"));
  process.exit(1);
}
console.log("boundaries clean");

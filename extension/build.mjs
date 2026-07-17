import { build } from "esbuild";
import { cpSync, mkdirSync } from "node:fs";

// Bundle TS entry points and stage everything the appex Resources need into
// build/ (single output — no dual-location copies, an explicit anti-goal).

mkdirSync("build", { recursive: true });

for (const entry of ["content", "background", "popup"]) {
  await build({
    entryPoints: [`src/${entry}.ts`],
    bundle: true,
    format: "esm",
    target: "safari17",
    outfile: `build/${entry}.js`,
    logLevel: "info",
  });
}

// Stage the complete extension for the Xcode appex target.
mkdirSync("dist-resources", { recursive: true });
for (const file of ["manifest.json", "styles.css", "popup.html", "popup.css"]) {
  cpSync(file, `dist-resources/${file}`);
}
cpSync("build", "dist-resources/build", { recursive: true });
console.log("staged extension into extension/dist-resources/");

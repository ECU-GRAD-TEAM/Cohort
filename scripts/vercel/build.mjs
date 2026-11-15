// Builds the Vercel deployment in Vercel's Build Output API format (.vercel/output), which Vercel
// serves as is:
// - the web app (apps/web) as static files, with every unknown path falling back to index.html;
// - the API (apps/api) as one Node.js function that serves every request under /api.
// The API is bundled with esbuild here because Vercel's own TypeScript compilation does not
// support this repository's TypeScript 7 setup or the Prisma client generated during the build.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { build } from "esbuild";

const output = ".vercel/output";
const apiFunction = `${output}/functions/api.func`;

const run = (args) => execFileSync("npm", args, { stdio: "inherit" });
const writeJson = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);

rmSync(output, { recursive: true, force: true });

run(["run", "build", "-w", "@cohort/web"]);
cpSync("apps/web/dist", `${output}/static`, { recursive: true });

run(["run", "db:generate", "-w", "@cohort/api"]);
mkdirSync(apiFunction, { recursive: true });
await build({
  entryPoints: ["apps/api/src/vercel.ts"],
  outfile: `${apiFunction}/index.mjs`,
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node22",
  // pg loads its optional native binding lazily; the function never uses it.
  external: ["pg-native"],
  // CommonJS dependencies call require() for Node built-ins, which an ES module lacks.
  banner: { js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);" },
  logLevel: "info",
});
writeJson(`${apiFunction}/.vc-config.json`, {
  runtime: "nodejs22.x",
  handler: "index.mjs",
  launcherType: "Nodejs",
  shouldAddHelpers: false,
  // Dublin, next to the Supabase project (eu-west-1).
  regions: ["dub1"],
});

writeJson(`${output}/config.json`, {
  version: 3,
  routes: [
    { src: "^/api(?:/.*)?$", dest: "/api" },
    { handle: "filesystem" },
    { src: "^/.*$", dest: "/index.html" },
  ],
});

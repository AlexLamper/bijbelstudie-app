import { readdirSync, statSync, readFileSync } from 'fs';
import { join, extname, relative } from 'path';

const ROOT = 'C:/Projects/bijbelstudie-app';

const SKIP_DIRS = new Set([
  'build', '.dart_tool', '.git', 'Pods', '.symlinks', '.gradle', 'ephemeral',
  'node_modules', '.idea',
]);
const BINARY = new Set([
  '.ttf', '.otf', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.jar', '.dll',
  '.exe', '.dat', '.lib', '.exp', '.pdb', '.so', '.apk', '.aab',
]);

// Blocked content ids are named on purpose in the licensing documentation —
// the whole point of README.md and docs/ is to tell the next person which
// sources are banned and why. So the content-id checks skip Markdown, while
// the credential checks still cover every file.
function isDoc(rel) {
  return rel.endsWith('.md');
}

// The build brief is the input spec, not shipped output: it quotes every string
// to be replaced and the grep list itself.
// This file also skips itself: it necessarily contains every pattern it hunts.
const SKIP_FILES = new Set(['bijbelstudie-ios-build-prompt.md', 'tools/audit.mjs']);

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const CHECKS = [
  { name: 'bijbelquiz', re: /bijbelquiz/i, docs: false },
  { name: 'com.bijbelquiz', re: /com\.bijbelquiz/, docs: true },
  { name: 'appl_ (RevenueCat iOS key)', re: /appl_[A-Za-z0-9]{10,}/, docs: true },
  { name: 'goog_ (RevenueCat Android key)', re: /goog_[A-Za-z0-9]{10,}/, docs: true },
  { name: 'nbg51', re: /nbg51/i, docs: false },
  { name: 'kingcomments', re: /kingcomments/i, docs: false },
  // `net` only counts as a content id, not as the English word or `.net`.
  {
    name: "'net' as a content id",
    re: /(version|versionId|source|sourceId|id|bible|translation)\s*[:=]\s*['"]net['"]/i,
    docs: false,
  },
  { name: 'Google client id from another app', re: /1036826851129/, docs: true },
  { name: 'Stripe link in the binary', re: /stripe\.com|checkout\.stripe/i, docs: false },
];

const findings = new Map(CHECKS.map((c) => [c.name, []]));

for (const file of walk(ROOT)) {
  if (BINARY.has(extname(file).toLowerCase())) continue;
  const rel = relative(ROOT, file).replace(/\\/g, '/');
  if (SKIP_FILES.has(rel)) continue;
  const doc = isDoc(rel);

  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }

  const lines = text.split(/\r?\n/);
  for (const check of CHECKS) {
    if (doc && !check.docs) continue;
    lines.forEach((line, i) => {
      if (check.re.test(line)) {
        findings.get(check.name).push(`${rel}:${i + 1}: ${line.trim().slice(0, 140)}`);
      }
    });
  }
}

let clean = true;
for (const [name, hits] of findings) {
  if (hits.length === 0) {
    console.log(`OK    ${name}: 0 occurrences`);
  } else {
    clean = false;
    console.log(`FAIL  ${name}: ${hits.length} occurrence(s)`);
    for (const hit of hits.slice(0, 12)) console.log(`        ${hit}`);
  }
}

console.log(clean ? '\nAUDIT CLEAN' : '\nAUDIT FAILED');
process.exit(clean ? 0 : 1);

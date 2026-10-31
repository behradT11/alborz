// بازسازی فهرست فایل‌های کش آفلاین و نسخهٔ Service Worker بر اساس هش محتوا.
// اجرا (اختیاری، پس از هر تغییر فایل‌ها):  node scripts/build-sw.mjs
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';

const ROOT = new URL('..', import.meta.url).pathname;
const SKIP_DIRS = new Set(['tests', 'supabase', 'scripts', 'node_modules', '.git']);
const SKIP_EXT = /\.(md|sql|txt|toml|mjs)$|^(sw\.js|_headers|_redirects|package\.json|vercel\.json|netlify\.toml)$|maskable\.svg$|LICENSE/;
const files = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) { if (!SKIP_DIRS.has(name)) walk(p); continue; }
    const rel = relative(ROOT, p).split('\\').join('/');
    // ماژول‌های منبع در بسته‌ی app.bundle.js هستند و جداگانه کش نمی‌شوند
    if (/^js\/(lib|views|data)\//.test(rel) || rel === 'js/app.js') continue;
    if (!SKIP_EXT.test(rel)) files.push(rel);
  }
})(ROOT);
files.sort();
const hash = createHash('sha256');
for (const f of files) hash.update(f).update(readFileSync(join(ROOT, f)));
const version = 'og-' + hash.digest('hex').slice(0, 10);
const sw = readFileSync(join(ROOT, 'sw.js'), 'utf8')
  .replace(/const VERSION = '[^']*';/, `const VERSION = '${version}';`)
  .replace(/const ASSETS = \[[\s\S]*?\];/, `const ASSETS = ${JSON.stringify(files, null, 2)};`);
writeFileSync(join(ROOT, 'sw.js'), sw);
console.log(`sw.js → ${version} (${files.length} files)`);

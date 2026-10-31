// ساخت js/app.bundle.js از ماژول‌های js/ (فقط بعد از تغییر فایل‌های js/lib، js/views، js/data یا js/app.js لازم است).
// ویرایش js/config.js به بیلد نیاز ندارد.
// اجرا:  npx esbuild@0.25 --version  (یک بار برای نصب)،  سپس  node scripts/build.mjs
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
execFileSync('npx', ['--yes', 'esbuild@0.25', join(ROOT, 'js/app.js'), '--bundle', '--format=iife', '--target=es2020',
  '--legal-comments=none', '--charset=utf8', `--outfile=${join(ROOT, 'js/app.bundle.js')}`,
  '--banner:js=/* فایل ساخته‌شده با scripts/build.mjs — مستقیم ویرایش نکنید؛ منبع: js/app.js و پوشه‌های js/lib, js/views, js/data */'],
  { stdio: 'inherit', cwd: ROOT });
await import('./build-sw.mjs');

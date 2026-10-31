# مسیر طلا

پلتفرم فارسی برنامه‌ریزی و تمرین برای المپیاد مدیریت، اقتصاد و حکمرانی (مرحلهٔ اول، دوم و دورهٔ تابستان).

- **راه‌اندازی و انتشار:** [`SETUP.md`](SETUP.md)
- **معماری:** کد منبع HTML/CSS/JS ماژولار (ES Modules) که در `js/app.bundle.js` بسته‌بندی شده (`node scripts/build.mjs`) تا با دوبار کلیک هم اجرا شود · Supabase (Auth + Postgres + Storage، RLS) · حالت آزمایشی محلی · PWA آفلاین.

## ساختار
```
index.html            صفحهٔ فرود
app.html              پوستهٔ اپ (مسیریاب hash)
privacy.html, terms.html
css/app.css           سیستم طراحی (روشن/تیره، RTL، دسترس‌پذیری)
css/landing.css
js/app.js             راه‌اندازی، احراز هویت، مسیریاب، ناوبری
js/config.js          ← آدرس و کلید عمومی Supabase (اسکریپت معمولی، بدون نیاز به بیلد)
js/app.bundle.js      ← فایل ساخته‌شده؛ مستقیم ویرایش نکنید
js/boot-check.js      نگهبان: به‌جای صفحهٔ خالی پیام خطا
css/fonts.css         فونت وزیرمتن داخلی
js/lib/
  planner.js          برنامه‌ریز (تابع خالص، آزمون‌شده)
  store.js            لایهٔ داده: مهمان (localStorage/IndexedDB) | ابر (Supabase + صف آفلاین)
  auth.js             Supabase Auth، ترجمهٔ خطا، محدودیت نرخ سمت کاربر
  jalali.js           تقویم شمسی و ارقام فارسی
  srs.js              مرور فاصله‌دار
  dom.js, widgets.js, charts.js, ctx.js, validate.js
js/data/              کاتالوگ منابع، واژه‌نامه، سؤال‌های تمرینی
js/views/             هر صفحه یک ماژول
supabase/schema.sql   جدول‌ها، RLS، Storage، توابع گروه و حذف حساب
sw.js                 Service Worker
scripts/build.mjs     ساخت app.bundle.js + sw
scripts/build-sw.mjs  بازسازی فهرست کش و نسخه
tests/                آزمون‌های برنامه‌ریز و SRS (node --test)
```

## اصول امنیتی
- هیچ رمزی در کد یا localStorage نیست؛ فقط Supabase Auth (PKCE).
- RLS روی همهٔ جدول‌ها؛ ادمین فقط از طریق جدول `admins` که از سمت کاربر قابل نوشتن نیست.
- همهٔ رندر با `textContent`/DOM API (بدون `innerHTML` برای دادهٔ کاربر) + CSP سخت‌گیر بدون `unsafe-inline`.
- اعتبارسنجی دولایه: سمت کاربر + CHECK constraint در دیتابیس (مثلاً URL فقط http/https).

## مجوزها
- فونت وزیرمتن: SIL Open Font License (`assets/fonts/OFL.txt`)
- supabase-js: MIT (`vendor/LICENSE`)

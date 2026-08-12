# App Store screenshots

`6.5/` holds seven PNGs at **1284 × 2778**, the native pixel size of the 6.5"
iPhone display slot in App Store Connect. Apple derives every smaller size from
this one, so it is the only slot that has to be filled.

| File | Screen | Use |
|---|---|---|
| `01-dashboard.png` | Dashboard — streak, book map, recommended studies | store |
| `02-lezen.png` | Reader — Genesis 1, Statenvertaling | store |
| `03-commentaar.png` | Commentaar tab — Matthew Henry | store |
| `04-studies.png` | Studies and leesplannen | store |
| `05-notities.png` | Notities, markeringen, bladwijzers | store |
| `06-profiel.png` | Profiel, settings, licence attribution | store |
| `07-pro.png` | Paywall | store **and** the review screenshot both subscriptions need |

Upload the first three at minimum; App Store Connect uses only the first three
on the install sheet.

`07-pro.png` doubles as the **Review Information → screenshot** for
`bijbelstudie_pro_monthly` and `bijbelstudie_pro_yearly`. Both products sit in
*Missing Metadata* until it is attached to each of them.

## Regenerating

```bash
cd bijbelstudie_mobile
flutter test test/screenshots_test.dart
```

Then flatten the alpha channel — App Store Connect rejects screenshots that
carry one, and Flutter's `toImage` always writes RGBA:

```bash
cd ../screenshots/6.5
python -c "
from PIL import Image
import glob
for f in glob.glob('*.png'):
    im = Image.open(f).convert('RGBA')
    flat = Image.new('RGB', im.size, (255,255,255))
    flat.paste(im, mask=im.split()[3])
    flat.save(f, 'PNG', optimize=True)
"
```

## Why they come out of a test and not a simulator

iOS cannot be built or run on Windows, so there is no simulator to press ⌘S in.
`test/screenshots_test.dart` sets the test surface to 428 × 926 logical at
devicePixelRatio 3 — exactly 1284 × 2778 physical — and captures the render
tree through a `RepaintBoundary` at that same ratio. Nothing is scaled or
resampled, so the output is pixel-identical to what the device would produce.

Two things the test has to do by hand, both of which fail silently otherwise:

- **Load the Material icon font** from the Flutter cache. It ships with the
  framework rather than the app, and without it every `Icon()` renders as an
  empty box.
- **Mock `shared_preferences`.** The reader screens read their preferences on
  mount and throw `MissingPluginException` under the test binding.

The screens are fed the same canned fixtures as `screen_render_test.dart`, plus
a stub RevenueCat offering so the paywall shows € 9,99 / € 69,99 instead of the
`—` an empty offering would render.

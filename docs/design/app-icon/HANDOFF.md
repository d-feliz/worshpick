# Worshpick — macOS app icon handoff

Chosen design: **"W · Lavanda"**. A lavender glass W whose last stroke is a golden-amber eighth note (the note head sits at the W's bottom-right vertex, the stem forms the final upstroke, the flag curls right). The background is a deep indigo to warm violet gradient.

## Files

| Path | Use |
|---|---|
| `worshpick-icon.svg` | Master vector, 1024×1024. Squircle with the macOS margin (body 824 px, 100 px margin), drop shadow and glass highlights baked in. Transparent outside the squircle. |
| `worshpick-icon-1024.png` | Master PNG render of the SVG, transparent background. |
| `AppIcon.appiconset/` | Drop-in Xcode asset (16–512 @1x/@2x, `Contents.json`, idiom `mac`). |
| `AppIcon.icns` | Prebuilt icns for non-Xcode builds (Electron, Tauri, etc.). |
| `icon-composer-layers/` | Flat layers for Apple **Icon Composer** (macOS 26 Tahoe Liquid Glass): `1-background`, `2-w`, `3-note`, each as SVG and PNG, 1024×1024, unmasked. |

## Which one to use

- **Target macOS 26+ with native Liquid Glass:** build a `.icon` in Icon Composer from `icon-composer-layers/` in that order (back to front). Do not add your own shadow or specular highlights. The system applies the mask, glass and lighting. Then add the `.icon` file to the Xcode project and set it as the app icon.
- **Xcode, older macOS or a mixed target:** drag `AppIcon.appiconset` into `Assets.xcassets`, replacing the existing `AppIcon`.
- **Electron / Tauri / other:** use `AppIcon.icns` (macOS) and `worshpick-icon-1024.png` as the source for other platforms.

## Colors

- Background gradient (top-left → bottom-right): `#1C1858` → `#352A86` → `#5E3399` → `#7C3FA3`
- W (lavender): `#EFE8FF` → `#A996F2`, flat layer `#C9BBF8`
- Note (gold): `#FFE3A1` → `#FFC356` → `#E98320`, flat layer `#F7B544`

## Notes

- The PNG sizes were downscaled from the 1024 master. The icns does not include separate 16@1x and 32@1x images, so macOS will downscale for those. If a pixel-perfect 16 px icon matters, render a simplified 16/32 px version.
- Icon only, no text. No other assets were made (no menu-bar or document icons).

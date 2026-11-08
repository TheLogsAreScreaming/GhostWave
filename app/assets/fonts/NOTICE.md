# Bundled fonts

All three families are licensed under the SIL Open Font License 1.1. Each folder holds that family's
license as `OFL.txt`, copied unchanged from the release. The fonts are bundled as app assets; the app
does not download fonts at runtime.

| Family | Use | Source (official release) | Files |
|---|---|---|---|
| Space Grotesk | headlines | [floriankarsten/space-grotesk](https://github.com/floriankarsten/space-grotesk) release `2.0.0`, `SpaceGrotesk-2.0.0.zip` (sha256 `53b41557…abffd`), `ttf/static/` | Medium (500), Bold (700) |
| Inter | body and UI | [rsms/inter](https://github.com/rsms/inter) release `v4.1`, `Inter-4.1.zip` (sha256 `9883fdd4…6b11e`), `extras/ttf/` | Regular (400), Medium (500), SemiBold (600) |
| JetBrains Mono | node IDs, keys | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) release `v2.304`, `JetBrainsMono-2.304.zip` (sha256 `6f6376c6…f7bbf`), `fonts/ttf/` | Regular (400), Medium (500) |

Full archive checksums (SHA-256):

```
53b415577d4139248555300710bea0d268c7a5be67b93de53b716a9736cabffd  SpaceGrotesk-2.0.0.zip
9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e  Inter-4.1.zip
6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf  JetBrainsMono-2.304.zip
```

Only the weights the theme uses are bundled (`lib/src/ui/theme.dart`). To add a weight, take it from
the same release and add it to `pubspec.yaml`.

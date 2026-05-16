# Jigen logos

Canonical asset hosting for the Jigen brand marks. **Source of truth: `Jigen-lab/brand-kit`** (`design-system/ds-visual.html` §"Logo system"). The files here are pre-rendered for direct embedding (email signatures, GitHub READMEs, social, OG images) without a build step.

Public, raw-fetchable from:

```
https://raw.githubusercontent.com/Jigen-lab/.github/main/logos/<file>
```

## The 5 canonical lockups

| # | Variant | Files | When to use |
|---|---|---|---|
| 1 | **Lockup completo** — mascot + JIGEN. | `jigen-lockup-{light,dark}.{svg,@1x.png,@2x.png}` | Hero pages, product covers, "About" pages, first-impression brand. Min width 320px. |
| 2 | **Wordmark** — JIGEN. with red accent | `jigen-wordmark-{light,dark}.{svg,@1x.png,@2x.png}` | Nav header, footer, formal documents (contracts, invoices), email signature header. Use under 200px wide. |
| 3 | **Mascot only** — pixel character | `jigen-mascot-{64,128,256,512}.png` | Social avatars, app icon, inline signature accent, sticker. **Never** as formal logo (invoices/contracts/legal). |
| 4 | **Lockup + kanji (vertical)** — mascot + JIGEN. + 次元 stacked | `jigen-lockup-stacked-{light,dark}.{svg,@1x.png,@2x.png}` | Press kit, ceremonial pages, brand-introduction surfaces. Min width 320px. |
| 5 | **Lockup + kanji (horizontal)** — mascot + JIGEN. + 次元 in a row | `jigen-lockup-horizontal-{light,dark}.{svg,@1x.png,@2x.png}` | Site headers, OG cards, broad horizontal surfaces. Min width 420px. |

There is also a **wordmark + kanji** variant (no mascot — variant 5 without the pixel character):

| Files | When to use |
|---|---|
| `jigen-wordmark-jp-{light,dark}.{svg,@1x.png,@2x.png}` | Whenever you'd use the wordmark (variant 2) but want the kanji subtitle. Header/footer of bilingual surfaces. |

## File-format conventions

- **`-light`** = ink on cream — for light backgrounds (paper `#F4ECD8`, white).
- **`-dark`** = cream on ink — for dark backgrounds (ink `#111`).
- **SVG** = source. Wordmark-only variants are pure vector (~500B). Composite lockups (with mascot) embed the raster mascot as a base64 data URI (~470KB each) so they remain a single self-contained file.
- **`@1x.png`** = standard density — lockups rendered at 200px height, wordmarks at 120px height.
- **`@2x.png`** = retina density — exactly 2× the @1x. Use this in `srcset` or wherever HiDPI matters.

## Hard rules (from the design system)

- Never deform the lockup (no stretch).
- The dot is always red `#FF2A54`; the wordmark is always ink `#111` or cream `#F4ECD8`. Don't recolor.
- No drop-shadow, glow, or bevel. Logo stays flat.
- Use only on neutral backgrounds (paper, ink, soft). No busy patterns.
- The mascot is expressive, not representative — **never** use it as the formal logo on invoices, contracts, or legal headers.

## Quick-pick examples

Email signature (HTML):

```html
<img src="https://raw.githubusercontent.com/Jigen-lab/.github/main/logos/jigen-lockup-stacked-light@1x.png"
     alt="Jigen 次元" width="120" height="120"
     style="display:block;border:0;" />
```

Markdown (README header):

```markdown
![Jigen](https://raw.githubusercontent.com/Jigen-lab/.github/main/logos/jigen-lockup-light@1x.png)
```

GitHub profile avatar / Discord / Slack:

```
https://raw.githubusercontent.com/Jigen-lab/.github/main/logos/jigen-mascot-512.png
```

## Regenerating

These files are produced from the brand-kit sources by `scripts/build-logos.py` (not in this repo — kept under `Jigen-lab/brand-kit` tooling). To regenerate:

1. `brew install librsvg`
2. `brew install --cask font-inter font-noto-sans-jp`
3. Run the build script in the brand-kit.

The spec the script implements lives at `brand-kit/design-system/style.css` lines 913-922 (lockup-mini classes) and `brand-kit/brand/wordmark/*.svg` (wordmark sources).

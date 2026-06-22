# CycleBalance Media Index

This directory contains all media assets used by the CycleBalance website (cyclebalance.app), served from GitHub Pages out of `/docs/`.

## Folder map

```
docs/assets/
├── css/
│   └── blog.css                  # Shared styles for /blog and /<lang>/blog
├── images/
│   ├── app-icon-1024.png         # 1024×1024 app icon (App Store source)
│   ├── site/                     # Homepage, app mockup, and extracted UI assets
│   └── blog/                     # 134 PCOS educational images, by topic
│       ├── README.md             # Full image index with alt text + sizes
│       ├── alt-text-reference.csv
│       ├── alt-text-reference.json
│       ├── app-and-branding/         (20 images)
│       ├── nutrition-general/        (14 images)
│       ├── nutrition-protein/        (12 images)
│       ├── nutrition-fruits/         (14 images)
│       ├── nutrition-carbs/          (12 images)
│       ├── nutrition-fats/           (6  images)
│       ├── nutrition-vegetables/     (9  images)
│       ├── supplements/              (26 images)
│       ├── cycle-tracking-symptoms/  (6  images)
│       ├── hormone-insulin/          (4  images)
│       ├── lifestyle/                (6  images)
│       └── misc-flagged/             (5  images, off-topic — review before use)
└── videos/
    └── cyclebalance-promo-v1.mp4
```

## Public URLs

Once deployed, all assets are served at predictable paths:

| File on disk                                           | Public URL                                                    |
|--------------------------------------------------------|---------------------------------------------------------------|
| `docs/assets/css/blog.css`                             | `https://cyclebalance.app/assets/css/blog.css`                |
| `docs/assets/images/site/mockup/extracted/`            | `https://cyclebalance.app/assets/images/site/mockup/extracted/` |
| `docs/assets/images/blog/<topic>/<slug>.webp`          | `https://cyclebalance.app/assets/images/blog/<topic>/<slug>.webp` |
| `docs/assets/videos/cyclebalance-promo-v1.mp4`         | `https://cyclebalance.app/assets/videos/cyclebalance-promo-v1.mp4` |

## Homepage media notes

- `docs/assets/images/site/mockup/extracted/testimonial-avatar.png` is a cropped representative stock portrait from Pexels: <https://www.pexels.com/photo/portrait-of-indian-woman-in-sunlight-15602468/>. It is used only as representative marketing media, not as a named testimonial or real endorsement.
- `docs/assets/images/site/mockup/extracted/feature-*-icon.png`, `support-*-icon.png`, and `trust-*-icon.png` are cropped from the supplied CycleBalance homepage mockup concept art.

## How to use these assets

### In a blog post (HTML)

```html
<link rel="stylesheet" href="/assets/css/blog.css">

<figure class="article-figure">
  <img src="/assets/images/blog/nutrition-fruits/why-fruit-choice-matters-for-pcos.webp"
       alt="Why fruit choice matters for PCOS: high vs low glycemic fruits"
       loading="lazy" width="1600">
  <figcaption>High-fiber, low-glycemic fruits are the smart choice for PCOS blood sugar.</figcaption>
</figure>
```

### Programmatic image lookup

`alt-text-reference.json` contains every image with category, suggested alt text, file size, and slug. Use it to:

- Generate sitemap image entries (`<image:image>` tags)
- Emit schema.org `ImageObject` markup
- Feed into a CMS or static-site generator

```json
{
  "category": "nutrition-protein",
  "filename": "why-protein-matters-for-pcos.webp",
  "alt": "Why protein matters for PCOS: blood sugar, satiety, hormone support",
  "size_kb": 119.6
}
```

## Image conventions

- **Format:** WebP, quality 85, max width 1600px
- **EXIF:** all GPS/metadata stripped at conversion time
- **Naming:** descriptive, keyword-rich slug (kebab-case, ASCII only)
- **Alt text:** always provided in `alt-text-reference.csv`/`.json`

## Adding new media

1. Drop new images into the appropriate topic folder under `images/blog/<topic>/`.
2. Use a descriptive kebab-case filename ending in `.webp` (convert from PNG/JPG first).
3. Add a row to `images/blog/alt-text-reference.csv` with category, filename, alt text, and size.
4. Run `git add` and commit with `feat(media): add X images for Y topic`.

For new topic categories, also update:
- `images/blog/README.md` (add a section)
- This file (add a row to the folder map)

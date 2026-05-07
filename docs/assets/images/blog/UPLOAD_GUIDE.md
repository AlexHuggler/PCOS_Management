# Upload Guide — PCOS_Management_Images → GitHub

This folder is ready to drag-drop into your repo at <https://github.com/AlexHuggler/PCOS_Management>.

## Recommended target path in your repo

```
PCOS_Management/
└── assets/
    └── images/
        └── blog/
            ├── app-and-branding/
            ├── cycle-tracking-symptoms/
            ├── hormone-insulin/
            ├── lifestyle/
            ├── misc-flagged/
            ├── nutrition-carbs/
            ├── nutrition-fats/
            ├── nutrition-fruits/
            ├── nutrition-general/
            ├── nutrition-protein/
            ├── nutrition-vegetables/
            └── supplements/
```

`assets/images/blog/` is conventional for GitHub Pages sites. Adjust the prefix if your Jekyll/Hugo setup uses a different path (e.g. `static/images/`, `_assets/`, `public/img/`).

## Drag-drop steps

1. Go to <https://github.com/AlexHuggler/PCOS_Management>
2. Click **Add file** → **Upload files**
3. Navigate into (or create) `assets/images/blog/` first
4. **Upload one folder at a time** (GitHub web UI caps at ~100 files per upload — most of your folders are under that, but `supplements/` has 26 so it's fine; the largest single batch is the 26 supplements)
5. For each folder upload:
   - Drag the entire folder from Finder into the upload area
   - GitHub preserves the folder structure
   - Add a commit message like `Add supplement infographics for blog`
   - Click **Commit changes** directly to `main` (or open a PR)
6. After all 12 folders are uploaded, also upload:
   - `README.md` → could go at repo root or in `assets/images/blog/README.md`
   - `alt-text-reference.csv` and `alt-text-reference.json` → useful for your blog tooling

## Faster alternative: GitHub CLI

If you have `gh` and `git` configured locally, this is one command from inside your local clone:

```bash
cd /path/to/your/local/PCOS_Management
mkdir -p assets/images/blog
cp -R "/Users/alexhuggler/Downloads/CycleBalance Media/PCOS_Management_Images/"* assets/images/blog/
git add assets/images/blog
git commit -m "Add optimized PCOS blog image library (134 images, WebP)"
git push origin main
```

## Using these images in blog posts

Markdown:
```markdown
![Why fruit choice matters for PCOS](/assets/images/blog/nutrition-fruits/why-fruit-choice-matters-for-pcos.webp)
```

HTML (best for SEO — gives lazy loading + explicit dimensions):
```html
<img src="/assets/images/blog/nutrition-fruits/why-fruit-choice-matters-for-pcos.webp"
     alt="Why fruit choice matters for PCOS: high vs low glycemic fruits"
     loading="lazy" decoding="async">
```

For richer SEO, add `schema.org/ImageObject` JSON-LD per page using the alt text from `alt-text-reference.json`.

## What was excluded

- 2 videos (.mp4, .mov) — GitHub isn't a great host for video; recommend YouTube or Vimeo for blog embedding
- 1 exact byte-for-byte duplicate (` 2.PNG` variant) was removed automatically
- 5 off-topic items (rabbit memes, EPA dashboard, Ben Franklin schedule) were kept per your direction in `misc-flagged/` — review before using

## Privacy

All EXIF metadata (including iPhone GPS coordinates and device fingerprints) was stripped during WebP conversion. Safe for a public repo.

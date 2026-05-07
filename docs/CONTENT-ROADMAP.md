# CycleBalance Content Roadmap

Last updated: 2026-05-07

## Completed in this wave
- Repaired the multilingual blog graph so 18 evidence-backed articles are available in all seven supported languages.
- Backfilled previously advertised localized pages that were missing from the repository.
- Added 10 new PCOS education articles across nutrition, supplements, symptom tracking, and lifestyle.
- Added `docs/content/blog-manifest.json` as the blog metadata source and `docs/content/media-manifest.json` as the normalized media library.
- Added `tools/render-blog.mjs` and `tools/validate-site.mjs` so blog pages, indexes, sitemap, `llms.txt`, and validation can be repeated.
- Kept existing image URLs stable and excluded `misc-flagged` assets from public blog usage.
- Updated the sitemap and `llms.txt` so they describe only pages that exist.
- Standardized managed health articles with BlogPosting schema, MedicalWebPage schema, BreadcrumbList schema, citations, medical disclaimers, and large image/snippet robots controls.

## Validation results
- Latest validation status: PASS with `node tools/validate-site.mjs --external` on 2026-05-07.
- Managed evidence articles: 18
- Managed localized article pages: 126
- Legacy English-only articles: 3
- HTML files checked: 171
- Sitemap URLs checked: 171
- Internal references checked: 5859
- Hreflang links checked: 1344
- JSON-LD blocks parsed: 482
- Image references checked: 1110
- External references checked: 14
- Local validation errors: 0
- External reference result: 0 broken 404/410 URLs; 5 bot-protected/manual-review warnings for reputable sources that block scripted requests.
- Validation report: `docs/VALIDATION-REPORT.md`
- Static smoke checks covered `/blog`, `/de/blog`, `/ja/blog/how-to-track-pcos-symptoms`, and `/blog/pcos-supplement-safety-guide`.

## Remaining known gaps
- Legacy English-only posts remain intentionally English-only; they should be upgraded only if a future wave needs them as full evidence-backed health posts.
- Content is evidence-backed and carefully worded, but it has not been reviewed by a named clinician.
- Some useful images remain unused because they overlap with current post topics or live in `misc-flagged`.
- External search performance still needs Search Console monitoring after deployment and recrawl.

## Future improvements
- Add deeper content clusters for fertility planning, metformin, GLP-1 conversations, hair growth/hirsutism, mental health, sleep apnea, pregnancy/postpartum, and doctor visit preparation.
- Add image sitemap extensions once the current HTML image usage has been indexed cleanly.
- Create a dedicated video landing page with VideoObject schema and transcript for `/assets/videos/cyclebalance-promo-v1.mp4`.
- Add clinician/reviewer bios and a documented editorial review process for stronger YMYL trust signals.
- Run localized keyword research for German, French, Italian, Japanese, Korean, and Dutch instead of translating English search intent directly.
- Add analytics-free performance monitoring, such as server-side Search Console review and App Store conversion tracking.
- Test App Store CTA placement by article type without adding advertising trackers.

## Maintenance checklist
1. Add or update a post in `docs/content/blog-manifest.json`.
2. Add new media under `docs/assets/images/blog/<topic>/` and update `alt-text-reference.json`.
3. Run `node tools/render-blog.mjs`.
4. Run `node tools/validate-site.mjs`.
5. Review `docs/VALIDATION-REPORT.md`.
6. Spot-check at least one English page and one localized page in a browser.
7. Submit the updated sitemap in Search Console after deployment.

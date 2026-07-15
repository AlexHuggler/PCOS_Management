#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const DOCS = path.join(ROOT, 'docs');
const SITE = 'https://cyclebalance.app';
const LOCALES = ['en', 'de', 'fr', 'it', 'ja', 'ko', 'nl'];
const LOCALE_PREFIXES = new Set(LOCALES.filter(locale => locale !== 'en'));

const errors = [];
const warnings = [];
const stats = {
  htmlFiles: 0,
  sitemapUrls: 0,
  internalLinks: 0,
  hreflangLinks: 0,
  jsonLdBlocks: 0,
  imageRefs: 0,
  externalReferences: 0
};

function fail(message) {
  errors.push(message);
}

function warn(message) {
  warnings.push(message);
}

async function exists(file) {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...await walk(full));
    else files.push(full);
  }
  return files;
}

function sitePathToFile(urlPath) {
  const clean = urlPath.split('#')[0].split('?')[0];
  if (clean === '' || clean === '/') return path.join(DOCS, 'index.html');
  if (path.extname(clean)) return path.join(DOCS, clean.replace(/^\//, ''));
  return path.join(DOCS, `${clean.replace(/^\//, '').replace(/\/$/, '/index')}.html`);
}

function expectedLangFor(file) {
  const rel = path.relative(DOCS, file).replaceAll(path.sep, '/');
  const first = rel.split('/')[0];
  return LOCALE_PREFIXES.has(first) ? first : 'en';
}

function normalizeInternal(value) {
  if (!value || value.startsWith('#')) return null;
  if (/^(https?:)?\/\//.test(value)) {
    if (!value.startsWith(SITE)) return null;
    return value.slice(SITE.length) || '/';
  }
  if (/^(mailto:|tel:|data:|javascript:)/.test(value)) return null;
  if (!value.startsWith('/')) return null;
  return value;
}

function extractAll(pattern, text) {
  return [...text.matchAll(pattern)].map(match => match[1]);
}

function requireText(source, label, required) {
  for (const value of required) {
    if (!source.includes(value)) fail(`${label}: missing required text: ${value}`);
  }
}

function forbidText(source, label, forbidden) {
  const normalized = source.toLowerCase();
  for (const value of forbidden) {
    if (normalized.includes(value.toLowerCase())) fail(`${label}: forbidden claim present: ${value}`);
  }
}

async function readRequiredArtifact(file, label) {
  if (!await exists(file)) {
    fail(`${label}: missing file ${path.relative(ROOT, file)}`);
    return null;
  }
  return fs.readFile(file, 'utf8');
}

async function validateMealScanLaunch() {
  const page = await readRequiredArtifact(path.join(DOCS, 'meal-scan.html'), 'Meal scan page');
  if (page) {
    requireText(page, 'Meal scan page', [
      '<title>Meal Scan Preview — CycleBalance</title>',
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
      '<link rel="canonical" href="https://cyclebalance.app/meal-scan">',
      '<meta property="og:title" content="Start with a photo. Stay in control. — CycleBalance">',
      '<meta property="og:description" content="A staged preview of consent-first photo meal logging with an editable draft and local save.">',
      '<meta property="og:url" content="https://cyclebalance.app/meal-scan">',
      '<meta property="og:image" content="https://cyclebalance.app/assets/images/site/cyclebalance-og-1200x630.jpg">',
      '<meta name="twitter:card" content="summary_large_image">',
      '<meta name="twitter:title" content="Start with a photo. Stay in control. — CycleBalance">',
      '<meta name="twitter:description" content="Preview a review-before-save approach to photo meal logging.">',
      '<meta name="twitter:image" content="https://cyclebalance.app/assets/images/site/cyclebalance-og-1200x630.jpg">',
      'Start with a photo. Stay in control.',
      'Meal context, not meal judgment.',
      'From plate to pattern-ready record.',
      '<h3>Photo</h3>',
      '<h3>Consent</h3>',
      '<h3>Correct</h3>',
      '<h3>Save</h3>',
      '<h3>Context</h3>',
      'Google Gemini',
      'explicit consent',
      'editable draft',
      'up to 55 days',
      'abuse monitoring',
      'The CycleBalance proxy does not retain raw image bytes',
      'Exact reviewed-meal reuse can remain on your device',
      'Manual and barcode alternatives stay available',
      'Coming after release verification',
      '<a class="skip-link" href="#main-content">',
      '<main id="main-content">',
      '@media (prefers-reduced-motion: reduce)',
      'href="/"',
      'href="/support"',
      'href="/privacy"',
      'href="/terms"',
      'href="https://apps.apple.com/us/app/cyclebalance/id6760353511"',
      'src="/assets/images/site/cyclebalance-app-icon-96.png"'
    ]);
    forbidText(page, 'Meal scan page', [
      'diagnosis',
      'treatment',
      'causal insight',
      'exact nutrition',
      'Zero Data Retention',
      'guaranteed accuracy',
      'cycle-aware nutrition',
      'meal-balance score',
      'meal balance score'
    ]);
  }

  const social = await readRequiredArtifact(
    path.join(ROOT, '.superpowers/sdd/task-4-social-demo-handoff.md'),
    'Social/demo handoff'
  );
  if (social) {
    requireText(social, 'Social/demo handoff', [
      '15-second Photo → Consent → Correct → Save storyboard',
      'What the AI guessed—and what I corrected',
      'What a meal photo cannot see',
      'Same meal again? Reuse your reviewed version',
      'Context, not conclusions',
      'Demonstration using synthetic meal details — not a testimonial or accuracy result.'
    ]);
  }

  const launchDelta = await readRequiredArtifact(
    path.join(ROOT, '.superpowers/sdd/task-4-launch-delta-handoff.md'),
    'Launch-delta handoff'
  );
  if (launchDelta) {
    requireText(launchDelta, 'Launch-delta handoff', [
      'This is a staging document, not a live policy edit.',
      '## Current live-state correction — verified July 14, 2026',
      'Privacy Policy and Terms were updated July 12 with detailed Photo Estimate, Google Gemini, cache, and quota language.',
      'The live Support FAQ currently has one privacy FAQ that names Google Gemini.',
      '| Privacy Policy | Verify/reconcile',
      '| Terms | Verify/reconcile',
      '| Support FAQ | Expand',
      '| Homepage FAQ | Confirmed contradiction',
      '| App Store description | Confirmed contradiction',
      'health logs stay on-device unless exported',
      'No accounts required, no cloud uploads, no ads.',
      'Privacy Policy',
      'Terms',
      'Support FAQ',
      'App Privacy',
      'Review notes',
      'Live website copy',
      'App Store copy',
      'Paid: 10 fresh scans per rolling 24 hours (immutable max 15).',
      'Trial/sandbox: 5 fresh scans per rolling 24 hours and 25 lifetime.',
      'Exact cache, barcode, and manual paths are non-billable.',
      'Apple Campaign Link',
      'Custom Product Page',
      '`symptoms-food-glucose`',
      'optional scanner page',
      'Do not invent current performance results or unverified platform algorithm claims.'
    ]);
  }

  const sitemap = await fs.readFile(path.join(DOCS, 'sitemap.xml'), 'utf8');
  requireText(sitemap, 'Sitemap', ['<loc>https://cyclebalance.app/meal-scan</loc>']);

  const llms = await fs.readFile(path.join(DOCS, 'llms.txt'), 'utf8');
  requireText(llms, 'llms.txt', ['- Meal scan staged preview: https://cyclebalance.app/meal-scan']);
}

async function validateSitemap() {
  const sitemapPath = path.join(DOCS, 'sitemap.xml');
  const xml = await fs.readFile(sitemapPath, 'utf8');
  const locs = extractAll(/<loc>([^<]+)<\/loc>/g, xml);
  stats.sitemapUrls = locs.length;
  for (const loc of locs) {
    if (!loc.startsWith(SITE)) fail(`Sitemap URL is outside site: ${loc}`);
    const file = sitePathToFile(loc.slice(SITE.length) || '/');
    if (!await exists(file)) fail(`Sitemap URL has no file: ${loc} -> ${path.relative(ROOT, file)}`);
  }
}

async function validateHtmlFile(file) {
  const rel = path.relative(ROOT, file);
  const html = await fs.readFile(file, 'utf8');
  stats.htmlFiles += 1;

  const langMatch = html.match(/<html[^>]*\slang="([^"]+)"/i);
  if (!langMatch) fail(`${rel}: missing html lang`);
  else if (langMatch[1] !== expectedLangFor(file)) fail(`${rel}: html lang ${langMatch[1]} does not match path locale ${expectedLangFor(file)}`);

  const canonicals = extractAll(/<link[^>]+rel="canonical"[^>]+href="([^"]+)"/g, html);
  if (canonicals.length > 1) fail(`${rel}: multiple canonical links`);
  if (canonicals.length === 1) {
    const canonicalPath = normalizeInternal(canonicals[0]);
    if (canonicalPath && !await exists(sitePathToFile(canonicalPath))) fail(`${rel}: canonical points to missing file ${canonicals[0]}`);
  }

  const hreflangs = [...html.matchAll(/<link[^>]+rel="alternate"[^>]+hreflang="([^"]+)"[^>]+href="([^"]+)"/g)];
  stats.hreflangLinks += hreflangs.length;
  const seenHreflang = new Set();
  for (const [, code, href] of hreflangs) {
    seenHreflang.add(code);
    const hrefPath = normalizeInternal(href);
    if (!hrefPath) fail(`${rel}: hreflang ${code} is not internal absolute site URL: ${href}`);
    else if (!await exists(sitePathToFile(hrefPath))) fail(`${rel}: hreflang ${code} points to missing file ${href}`);
  }
  if (hreflangs.length > 0) {
    const expected = [...LOCALES, 'x-default'];
    for (const code of expected) {
      if (!seenHreflang.has(code)) fail(`${rel}: missing hreflang ${code}`);
    }
  }

  const internalAttrs = [...html.matchAll(/\s(?:href|src)="([^"]+)"/g)];
  for (const [, raw] of internalAttrs) {
    const internal = normalizeInternal(raw);
    if (!internal) continue;
    stats.internalLinks += 1;
    if (internal.includes('/assets/images/blog/misc-flagged/')) fail(`${rel}: public page references misc-flagged asset ${internal}`);
    const filePath = sitePathToFile(internal);
    if (!await exists(filePath)) fail(`${rel}: internal reference missing ${internal}`);
    if (/\.(png|jpe?g|webp|gif|svg|ico)$/i.test(internal)) stats.imageRefs += 1;
  }

  const jsonLdBlocks = [...html.matchAll(/<script type="application\/ld\+json">\s*([\s\S]*?)\s*<\/script>/g)];
  for (const [, json] of jsonLdBlocks) {
    stats.jsonLdBlocks += 1;
    try {
      JSON.parse(json.trim());
    } catch (error) {
      fail(`${rel}: invalid JSON-LD (${error.message})`);
    }
  }
}

async function validateMediaManifest() {
  const manifestPath = path.join(DOCS, 'content/media-manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  const paths = new Set();
  for (const media of manifest.media) {
    if (paths.has(media.path)) fail(`Duplicate media manifest path ${media.path}`);
    paths.add(media.path);
    if (!media.alt) fail(`Media missing alt text: ${media.path}`);
    if (media.category === 'misc-flagged' && !media.excludeFromPublicUse) fail(`misc-flagged asset is not excluded: ${media.path}`);
    if (!await exists(sitePathToFile(media.path))) fail(`Media manifest path missing file: ${media.path}`);
  }
}

async function validateBlogManifest() {
  const manifestPath = path.join(DOCS, 'content/blog-manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  const slugs = new Set();
  for (const article of manifest.articles) {
    if (slugs.has(article.slug)) fail(`Duplicate article slug ${article.slug}`);
    slugs.add(article.slug);
    for (const locale of LOCALES) {
      if (!article.localized?.[locale]) fail(`${article.slug}: missing locale ${locale}`);
      const prefix = locale === 'en' ? '' : `/${locale}`;
      const expectedFile = sitePathToFile(`${prefix}/blog/${article.slug}`);
      if (!await exists(expectedFile)) fail(`${article.slug}: missing rendered ${locale} page`);
    }
    for (const id of article.referenceIds) {
      if (!manifest.references[id]) fail(`${article.slug}: missing reference id ${id}`);
    }
  }
}

async function validateExternalReferences() {
  const manifestPath = path.join(DOCS, 'content/blog-manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  for (const [id, ref] of Object.entries(manifest.references)) {
    stats.externalReferences += 1;
    try {
      let response = await fetch(ref.url, { method: 'HEAD', redirect: 'follow' });
      if (response.status === 405 || response.status === 403) {
        response = await fetch(ref.url, { method: 'GET', redirect: 'follow' });
      }
      if (response.status === 404 || response.status === 410) {
        fail(`Reference ${id} returned ${response.status}: ${ref.url}`);
      } else if (response.status >= 400) {
        warn(`Reference ${id} returned HTTP ${response.status}; verify manually: ${ref.url}`);
      }
    } catch (error) {
      warn(`Reference ${id} could not be checked (${error.message}): ${ref.url}`);
    }
  }
}

async function writeReport() {
  const status = errors.length === 0 ? 'PASS' : 'FAIL';
  const lines = [
    '# CycleBalance Validation Report',
    '',
    `Status: ${status}`,
    `Generated: 2026-05-07`,
    '',
    '## Counts',
    `- HTML files checked: ${stats.htmlFiles}`,
    `- Sitemap URLs checked: ${stats.sitemapUrls}`,
    `- Internal references checked: ${stats.internalLinks}`,
    `- Hreflang links checked: ${stats.hreflangLinks}`,
    `- JSON-LD blocks parsed: ${stats.jsonLdBlocks}`,
    `- Image references checked: ${stats.imageRefs}`,
    `- External references checked: ${stats.externalReferences}`,
    '',
    '## Errors',
    ...(errors.length ? errors.map(error => `- ${error}`) : ['- None']),
    '',
    '## Warnings',
    ...(warnings.length ? warnings.map(item => `- ${item}`) : ['- None']),
    ''
  ];
  await fs.writeFile(path.join(DOCS, 'VALIDATION-REPORT.md'), `${lines.join('\n')}`);
}

async function main() {
  await validateMealScanLaunch();
  await validateSitemap();
  await validateBlogManifest();
  await validateMediaManifest();
  if (process.argv.includes('--external')) await validateExternalReferences();

  const htmlFiles = (await walk(DOCS)).filter(file => file.endsWith('.html'));
  for (const file of htmlFiles) {
    if (file.endsWith('/blog/_TEMPLATE.html')) continue;
    await validateHtmlFile(file);
  }

  await writeReport();
  console.log(`Validation ${errors.length === 0 ? 'PASS' : 'FAIL'}: ${errors.length} errors, ${warnings.length} warnings`);
  if (errors.length) {
    errors.slice(0, 20).forEach(error => console.error(`- ${error}`));
    process.exit(1);
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});

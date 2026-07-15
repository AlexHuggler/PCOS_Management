#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const DOCS = path.join(ROOT, 'docs');
const MEAL_SCAN_PREVIEW = path.join(ROOT, '.superpowers/sdd/staging/meal-scan-preview.html');
const SITE = 'https://cyclebalance.app';
const APP_STORE_APP_ID_PATH_SEGMENT = 'id6760353511';
const REPORT_TIME_ZONE = 'America/Chicago';
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
    if (normalized.includes(value.toLowerCase())) fail(`${label}: forbidden text present: ${value}`);
  }
}

function normalizeClaimText(source) {
  return source
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[‐‑‒–—]/g, '-')
    .replace(/&nbsp;|&#160;/g, ' ')
    .replace(/\s+/g, ' ')
    .replace(/\s*-\s*/g, '-');
}

const FORBIDDEN_CLAIM_PATTERNS = [
  ['diagnosis', /\bdiagnos(?:is|e[sd]?|ing|tic)\b/],
  ['treatment', /\btreat(?:ment|s|ed|ing)?\b/],
  ['causal insight', /\bcausal\s+(?:insight|conclusion)s?\b/],
  ['exact nutrition', /\bexact\s+nutrition(?:al)?\b/],
  ['Zero Data Retention', /\bzero\s+data\s+retention\b/],
  ['guaranteed accuracy', /\bguaranteed\s+accur(?:acy|ate)\b/],
  ['100% accurate', /\b100\s*%\s+accurate\b/],
  ['cycle-aware nutrition', /\bcycle-aware\s+nutrition\b/],
  ['meal-balance score', /\bmeal-?balance\s+score\b/]
];

function findForbiddenClaims(source) {
  const normalized = normalizeClaimText(source);
  return FORBIDDEN_CLAIM_PATTERNS
    .filter(([, pattern]) => pattern.test(normalized))
    .map(([name]) => name);
}

function forbidClaimPatterns(source, label) {
  for (const name of findForbiddenClaims(source)) {
    fail(`${label}: forbidden claim pattern present: ${name}`);
  }
}

const FORBIDDEN_CLAIM_NEGATIVE_FIXTURES = [
  ['diagnosing variant', 'The scanner is diagnosing a health condition.', 'diagnosis'],
  ['diagnosed variant', 'The meal was diagnosed from a photo.', 'diagnosis'],
  ['guaranteed accurate variant', 'Guaranteed accurate meal estimates.', 'guaranteed accuracy'],
  ['100% accurate variant', '100% accurate meal estimates.', '100% accurate']
];

function validateForbiddenClaimFixtures() {
  for (const [label, source, expected] of FORBIDDEN_CLAIM_NEGATIVE_FIXTURES) {
    if (!findForbiddenClaims(source).includes(expected)) {
      fail(`Forbidden-claim negative fixture "${label}" was not rejected as ${expected}`);
    }
  }
}

function reportDate(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: REPORT_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function argumentValue(name) {
  const inline = process.argv.find(argument => argument.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = process.argv.indexOf(name);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  return value && !value.startsWith('--') ? value : '';
}

function validateCampaignLinkArgs() {
  const optionNames = ['--campaign-link', '--approved-ct', '--approved-ppid'];
  const evidenceFlags = ['--cpp-approved-visible', '--signed-out-storefront-verified'];
  const requested = [...optionNames, ...evidenceFlags].some(name => (
    process.argv.includes(name) || process.argv.some(argument => argument.startsWith(`${name}=`))
  ));
  if (!requested) return;

  const rawLink = argumentValue('--campaign-link');
  const approvedCt = argumentValue('--approved-ct');
  const approvedPpid = argumentValue('--approved-ppid');
  if (!rawLink) fail('Campaign Link: --campaign-link must contain the final Apple-generated CPP URL');
  if (!approvedCt) fail('Campaign Link: --approved-ct must contain the stable owner-approved campaign token');
  if (!approvedPpid) fail('Campaign Link: --approved-ppid must contain the final approved CPP destination ID');
  for (const flag of evidenceFlags) {
    if (!process.argv.includes(flag)) fail(`Campaign Link: ${flag} evidence flag is required`);
  }
  if (!rawLink) return;

  let campaignLink;
  try {
    campaignLink = new URL(rawLink);
  } catch {
    fail('Campaign Link: --campaign-link is not a valid absolute URL');
    return;
  }
  if (campaignLink.protocol !== 'https:' || campaignLink.hostname !== 'apps.apple.com') {
    fail('Campaign Link: URL must use https://apps.apple.com');
  }
  if (!campaignLink.pathname.split('/').includes(APP_STORE_APP_ID_PATH_SEGMENT)) {
    fail('Campaign Link: pathname must target CycleBalance app ID 6760353511');
  }

  const values = Object.fromEntries(['pt', 'ct', 'ppid'].map(name => [name, campaignLink.searchParams.getAll(name)]));
  for (const [name, entries] of Object.entries(values)) {
    if (entries.length !== 1 || !entries[0]) fail(`Campaign Link: URL must contain exactly one non-empty ${name} parameter`);
  }
  const [pt] = values.pt;
  const [ct] = values.ct;
  const [ppid] = values.ppid;
  if (pt && !/^[0-9]+$/.test(pt)) fail('Campaign Link: pt must contain ASCII digits only');
  if (ct && !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(ct)) {
    fail('Campaign Link: ct must be a stable non-empty token using letters, digits, period, underscore, or hyphen');
  }
  if (approvedCt && ct !== approvedCt) fail('Campaign Link: ct does not match --approved-ct');
  if (approvedPpid && ppid !== approvedPpid) fail('Campaign Link: ppid does not match --approved-ppid');
}

function cssHexToken(source, token) {
  const match = source.match(new RegExp(`--${token}:\\s*(#[0-9A-Fa-f]{6});`));
  if (!match) {
    fail(`Meal scan preview: missing CSS token --${token}`);
    return null;
  }
  return match[1].toUpperCase();
}

function relativeLuminance(hex) {
  const channels = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255);
  const linear = channels.map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2]);
}

function contrastRatio(foreground, background) {
  const first = relativeLuminance(foreground);
  const second = relativeLuminance(background);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

function requireContrast(label, foreground, background, minimum) {
  if (!foreground || !background) return;
  const ratio = contrastRatio(foreground, background);
  if (ratio < minimum) fail(`${label}: contrast ${ratio.toFixed(2)}:1 is below ${minimum}:1 (${foreground} on ${background})`);
}

function validateMealScanContrast(page) {
  const tokens = Object.fromEntries([
    'cream', 'paper', 'paper-strong', 'sage-dark', 'sage-pale', 'coral', 'coral-dark',
    'coral-pale', 'ink', 'muted', 'soft-muted', 'line', 'dark-line', 'focus-inner',
    'focus-outer', 'chip-text', 'text-on-dark', 'muted-on-dark', 'accent-on-dark',
    'footer-muted'
  ].map(token => [token, cssHexToken(page, token)]));

  requireText(page, 'Meal scan preview focus styles', [
    'outline: 3px solid var(--focus-inner);',
    'box-shadow: 0 0 0 6px var(--focus-outer);'
  ]);
  requireContrast('Primary button text', '#FFFFFF', tokens.coral, 4.5);
  requireContrast('Accent text on cream', tokens['coral-dark'], tokens.cream, 4.5);
  requireContrast('Accent text on paper', tokens['coral-dark'], tokens.paper, 4.5);
  for (const background of [tokens.cream, tokens.paper, tokens['paper-strong']]) {
    requireContrast('Muted text', tokens.muted, background, 4.5);
    requireContrast('Small muted text', tokens['soft-muted'], background, 4.5);
    requireContrast('Interface border', tokens.line, background, 3);
    requireContrast('Outer focus indicator', tokens['focus-outer'], background, 3);
  }
  requireContrast('Sage text on sage surface', tokens['sage-dark'], tokens['sage-pale'], 4.5);
  requireContrast('Edit chip text', tokens['chip-text'], tokens['coral-pale'], 4.5);
  requireContrast('Dark-surface interface border', tokens['dark-line'], tokens.ink, 3);
  requireContrast('Text on dark surface', tokens['text-on-dark'], tokens.ink, 4.5);
  requireContrast('Muted text on dark surface', tokens['muted-on-dark'], tokens.ink, 4.5);
  requireContrast('Accent text on dark surface', tokens['accent-on-dark'], tokens.ink, 4.5);
  requireContrast('Footer muted text', tokens['footer-muted'], tokens.ink, 4.5);
  requireContrast('White text on dark surface', '#FFFFFF', tokens.ink, 4.5);
  requireContrast('Inner focus indicator on dark surface', tokens['focus-inner'], tokens.ink, 3);
}

async function readRequiredArtifact(file, label) {
  if (!await exists(file)) {
    fail(`${label}: missing file ${path.relative(ROOT, file)}`);
    return null;
  }
  return fs.readFile(file, 'utf8');
}

async function validateMealScanLaunch() {
  const deployedPage = path.join(DOCS, 'meal-scan.html');
  if (await exists(deployedPage)) fail('Merge safety: staged meal scan preview must not exist under deployed docs/meal-scan.html');

  let page = await readRequiredArtifact(MEAL_SCAN_PREVIEW, 'Non-public meal scan preview');
  if (!page && await exists(deployedPage)) page = await fs.readFile(deployedPage, 'utf8');
  if (page) {
    requireText(page, 'Meal scan preview', [
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
      'Declining skips the photo estimate.',
      'Manual entry and exact reviewed-meal reuse can stay on your device.',
      'Barcode lookup is a separate optional network request.',
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
    forbidText(page, 'Meal scan preview', ['Declining keeps you on local alternatives']);
    forbidClaimPatterns(page, 'Meal scan preview');
    validateMealScanContrast(page);

    const internalAttrs = [...page.matchAll(/\s(?:href|src)="([^"]+)"/g)];
    for (const [, raw] of internalAttrs) {
      const internal = normalizeInternal(raw);
      if (!internal || internal === '/meal-scan') continue;
      if (!await exists(sitePathToFile(internal))) fail(`Meal scan preview: internal reference missing ${internal}`);
    }
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
      'The preview remains outside the deployed `docs` tree at `.superpowers/sdd/staging/meal-scan-preview.html`.',
      'A separate publication commit may move it to `docs/meal-scan.html` and add `/meal-scan` discovery only after every release gate is approved.',
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
      'Publication-time owner inputs: Apple provider token (`pt`) and final approved Custom Product Page ID (`ppid`); do not hardcode or invent either value.',
      '`pt`: non-empty ASCII digits only',
      '`ct`: stable, non-empty approved campaign token',
      '`ppid`: non-empty and exactly equal to the approved destination',
      '`symptoms-food-glucose` is Approved and publicly visible',
      'Campaign Link pathname must target CycleBalance app ID `6760353511`.',
      '`--campaign-link`',
      '`--approved-ct`',
      '`--approved-ppid`',
      '`--cpp-approved-visible`',
      '`--signed-out-storefront-verified`',
      'signed-out device',
      'target storefront',
      'optional scanner page',
      'Do not invent current performance results or unverified platform algorithm claims.'
    ]);
    if (/https:\/\/apps\.apple\.com\/[^\s`]+[?&](?:pt|ppid)=/i.test(launchDelta)) {
      fail('Launch-delta handoff: publication-time pt/ppid values must not be hardcoded in staging');
    }
  }

  const sitemap = await fs.readFile(path.join(DOCS, 'sitemap.xml'), 'utf8');
  forbidText(sitemap, 'Deployed sitemap', ['<loc>https://cyclebalance.app/meal-scan</loc>']);

  const llms = await fs.readFile(path.join(DOCS, 'llms.txt'), 'utf8');
  forbidText(llms, 'Deployed llms.txt', ['https://cyclebalance.app/meal-scan']);
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
    `Generated: ${reportDate()}`,
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
  validateForbiddenClaimFixtures();
  validateCampaignLinkArgs();
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

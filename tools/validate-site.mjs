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

  const placeholderMatch = html.match(/\{\{[^}]+\}\}/);
  if (placeholderMatch) fail(`${rel}: unresolved template placeholder ${placeholderMatch[0]}`);

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
    `Generated: ${new Date().toISOString().slice(0, 10)}`,
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
  await validateSitemap();
  await validateBlogManifest();
  await validateMediaManifest();
  if (process.argv.includes('--external')) await validateExternalReferences();

  const htmlFiles = (await walk(DOCS)).filter(file => file.endsWith('.html'));
  for (const file of htmlFiles) {
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

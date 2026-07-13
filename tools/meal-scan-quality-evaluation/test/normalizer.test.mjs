import assert from "node:assert/strict";
import { mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { compileSwiftImageNormalizer } from "../src/normalizer.mjs";

const onePixelPNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+3zQ1WQAAAABJRU5ErkJggg==",
  "base64",
);

test("compiled normalizer emits an owner-only metadata-free JPEG", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-image-normalizer-"));
  const sourcePath = join(directory, "source.png");
  const outputPath = join(directory, "normalized.jpg");
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  writeFileSync(sourcePath, onePixelPNG);

  const normalizeImage = compileSwiftImageNormalizer({ temporaryDirectory: directory });
  const output = normalizeImage(sourcePath, outputPath);

  assert.equal(output[0], 0xff);
  assert.equal(output[1], 0xd8);
  assert.equal(output.at(-2), 0xff);
  assert.equal(output.at(-1), 0xd9);
  assert.equal(statSync(outputPath).mode & 0o777, 0o600);
});

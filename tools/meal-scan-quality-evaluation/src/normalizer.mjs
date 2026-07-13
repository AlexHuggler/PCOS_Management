import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

const helperPath = join(dirname(fileURLToPath(import.meta.url)), "..", "normalize-image.swift");

function fail(message) {
  throw new Error(message);
}

export function compileSwiftImageNormalizer({
  temporaryDirectory,
  execFile = execFileSync,
  readFile = readFileSync,
} = {}) {
  if (typeof temporaryDirectory !== "string" || !isAbsolute(temporaryDirectory)) {
    fail("normalizer temporary directory must be absolute");
  }
  const executablePath = join(temporaryDirectory, "cyclebalance-normalize-image");
  const commandOptions = { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] };
  try {
    execFile("xcrun", ["swiftc", helperPath, "-o", executablePath], commandOptions);
  } catch {
    fail("unable to compile the CycleBalance image normalizer");
  }

  return (sourcePath, outputPath) => {
    if (!isAbsolute(sourcePath) || !isAbsolute(outputPath)) fail("normalizer image paths must be absolute");
    try {
      execFile(executablePath, [sourcePath, outputPath], commandOptions);
      return readFile(outputPath);
    } catch {
      fail("unable to normalize a public benchmark image");
    }
  };
}

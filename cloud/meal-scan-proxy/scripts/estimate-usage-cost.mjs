#!/usr/bin/env node

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .filter((arg) => arg.startsWith("--"))
    .map((arg) => {
      const [key, value = "true"] = arg.slice(2).split("=");
      return [key, value];
    })
);

const users = numberArg("users", 100);
const scansPerUserPerDay = numberArg("scans-per-user-per-day", 15);
const days = numberArg("days", 30);
const inputTokens = numberArg("input-tokens", 1_184);
const outputTokens = numberArg("output-tokens", 189);
const allInLowCostPerScan = numberArg("all-in-low-cost-per-scan", 0.001);
const allInHighCostPerScan = numberArg("all-in-high-cost-per-scan", 0.003);

const dailyScans = users * scansPerUserPerDay;
const periodScans = dailyScans * days;

const modelRates = [
  ["Gemini 3.1 Flash-Lite model only", 0.25, 1.50],
  ["OpenAI GPT-5.6 Luna model only", 1.00, 6.00],
  ["OpenAI GPT-5.6 Terra model only", 2.50, 15.00],
];

const rows = modelRates
  .map(([label, inputPerMillion, outputPerMillion]) => [
    label,
    (inputTokens * inputPerMillion + outputTokens * outputPerMillion) / 1_000_000,
  ])
  .concat([
    ["Gemini 3.1 all-in planning low", allInLowCostPerScan],
    ["Gemini 3.1 all-in planning high", allInHighCostPerScan],
  ])
  .map(([label, costPerScan]) => ({
    label,
    costPerScan,
    dailyCost: dailyScans * costPerScan,
    periodCost: periodScans * costPerScan,
  }));

console.log(`Users: ${users}`);
console.log(`Scans/user/day: ${scansPerUserPerDay}`);
console.log(`Daily scans: ${dailyScans}`);
console.log(`Period scans (${days} days): ${periodScans}`);
console.log(`Representative tokens/scan: ${inputTokens} input + ${outputTokens} output`);
console.log("");
console.log("| Scenario | Cost/scan | Daily cost | Period cost |");
console.log("|---|---:|---:|---:|");
for (const row of rows) {
  console.log(
    `| ${row.label} | ${usd(row.costPerScan, 6)} | ${usd(row.dailyCost, 2)} | ${usd(row.periodCost, 2)} |`
  );
}

function numberArg(name, fallback) {
  const value = Number(args[name] ?? fallback);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`Invalid --${name}: ${args[name]}`);
  }
  return value;
}

function usd(value, digits) {
  return `$${value.toFixed(digits)}`;
}

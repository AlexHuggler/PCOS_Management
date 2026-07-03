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
const lowCostPerScan = numberArg("low-cost-per-scan", 0.0002);
const baselineCostPerScan = numberArg("baseline-cost-per-scan", 0.0005448);
const highCostPerScan = numberArg("high-cost-per-scan", 0.001);

const dailyScans = users * scansPerUserPerDay;
const periodScans = dailyScans * days;

const rows = [
  ["Lower Lite estimate", lowCostPerScan],
  ["Current proxy sample Lite estimate", baselineCostPerScan],
  ["Upper Flash/escalation estimate", highCostPerScan],
].map(([label, costPerScan]) => ({
  label,
  costPerScan,
  dailyCost: dailyScans * costPerScan,
  periodCost: periodScans * costPerScan,
}));

console.log(`Users: ${users}`);
console.log(`Scans/user/day: ${scansPerUserPerDay}`);
console.log(`Daily scans: ${dailyScans}`);
console.log(`Period scans (${days} days): ${periodScans}`);
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

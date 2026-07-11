import assert from "node:assert/strict";
import test from "node:test";

import {
  budgetControlFromNotification,
  createBudgetNotificationHandler,
} from "../src/index.js";

const environment = {
  EXPECTED_BUDGET_DISPLAY_NAME: "CycleBalance Production 100-User Scanner Budget",
  MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD: "75",
  MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD: "90",
  MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD: "120",
};

test("maps spend into normal alert degraded and disabled budget modes", () => {
  assert.equal(budgetControlFromNotification(notification(40), environment).billingMode, "normal");
  assert.equal(budgetControlFromNotification(notification(75), environment).billingMode, "alert");
  assert.equal(budgetControlFromNotification(notification(90), environment).billingMode, "degraded");
  assert.equal(budgetControlFromNotification(notification(120), environment).billingMode, "disabled");
});

test("rejects notifications for another budget", () => {
  assert.throws(
    () => budgetControlFromNotification({ ...notification(120), budgetDisplayName: "Another budget" }, environment),
    /unexpected budget/
  );
});

test("writes a merge-only billing control and leaves manual override ownership separate", async () => {
  const writes = [];
  const handler = createBudgetNotificationHandler({
    environment,
    writeControl: async (value, options) => writes.push({ value, options }),
    logger: { info() {}, warn() {}, error() {} },
  });
  const encoded = Buffer.from(JSON.stringify(notification(121)), "utf8").toString("base64");

  await handler({
    data: {
      message: {
        data: encoded,
        messageId: "message-1",
      },
    },
  });

  assert.equal(writes.length, 1);
  assert.equal(writes[0].value.billingMode, "disabled");
  assert.equal(writes[0].value.spendUsd, 121);
  assert.equal("manualMode" in writes[0].value, false);
  assert.deepEqual(writes[0].options, { merge: true });
});

test("accepts the Pub/Sub background-event shape used by the deployed function", async () => {
  const writes = [];
  const logs = [];
  const handler = createBudgetNotificationHandler({
    environment,
    writeControl: async (value, options) => writes.push({ value, options }),
    logger: { info: (...args) => logs.push(args) },
  });
  const encoded = Buffer.from(JSON.stringify(notification(121)), "utf8").toString("base64");

  await handler(
    {
      data: encoded,
      attributes: {},
    },
    {
      eventId: "background-message-1",
    }
  );

  assert.equal(writes.length, 1);
  assert.equal(writes[0].value.billingMode, "disabled");
  assert.equal(logs[0][1].messageId, "background-message-1");
});

test("rejects malformed Pub/Sub payloads without writing", async () => {
  let writeCount = 0;
  const handler = createBudgetNotificationHandler({
    environment,
    writeControl: async () => {
      writeCount += 1;
    },
    logger: { info() {}, warn() {}, error() {} },
  });

  await assert.rejects(() => handler({ data: { message: { data: "not-base64-json" } } }), /invalid budget notification/);
  assert.equal(writeCount, 0);
});

function notification(costAmount) {
  return {
    budgetDisplayName: "CycleBalance Production 100-User Scanner Budget",
    costAmount,
    budgetAmount: 150,
    budgetAmountType: "SPECIFIED_AMOUNT",
    costIntervalStart: "2026-07-01T00:00:00Z",
    currencyCode: "USD",
  };
}

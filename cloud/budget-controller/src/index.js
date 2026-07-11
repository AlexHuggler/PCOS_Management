const DEFAULT_BUDGET_DISPLAY_NAME = "CycleBalance Production 100-User Scanner Budget";
const DEFAULT_CONTROL_COLLECTION = "mealScanControls";
const DEFAULT_CONTROL_DOCUMENT = "global";
const VALID_MODES = new Set(["normal", "alert", "degraded", "disabled"]);

export function budgetControlFromNotification(notification, environment = process.env) {
  if (!notification || typeof notification !== "object") {
    throw new Error("invalid budget notification");
  }

  const expectedBudgetName = environment.EXPECTED_BUDGET_DISPLAY_NAME ?? DEFAULT_BUDGET_DISPLAY_NAME;
  if (notification.budgetDisplayName !== expectedBudgetName) {
    throw new Error("unexpected budget notification");
  }

  const spendUsd = finiteNonNegativeNumber(notification.costAmount, "costAmount");
  const budgetUsd = finitePositiveNumber(notification.budgetAmount, "budgetAmount");
  if (notification.currencyCode !== "USD") {
    throw new Error("invalid budget notification currency");
  }

  const alertAtUsd = finiteNonNegativeNumber(
    environment.MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD ?? "75",
    "alert threshold"
  );
  const degradeAtUsd = finiteNonNegativeNumber(
    environment.MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD ?? "90",
    "degrade threshold"
  );
  const disableAtUsd = finitePositiveNumber(
    environment.MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD ?? "120",
    "disable threshold"
  );
  if (!(alertAtUsd <= degradeAtUsd && degradeAtUsd <= disableAtUsd && disableAtUsd <= budgetUsd)) {
    throw new Error("invalid budget control thresholds");
  }

  let billingMode = "normal";
  if (spendUsd >= disableAtUsd) {
    billingMode = "disabled";
  } else if (spendUsd >= degradeAtUsd) {
    billingMode = "degraded";
  } else if (spendUsd >= alertAtUsd) {
    billingMode = "alert";
  }

  return {
    billingMode,
    spendUsd,
    budgetUsd,
    alertAtUsd,
    degradeAtUsd,
    disableAtUsd,
    costIntervalStart: stringOrNull(notification.costIntervalStart),
    currencyCode: "USD",
    updatedAt: new Date(),
    source: "cloud_billing_budget",
  };
}

export function createBudgetNotificationHandler({
  environment = process.env,
  writeControl = defaultWriteControl(environment),
  logger = console,
} = {}) {
  return async (event, context) => {
    const notification = decodeBudgetNotification(event);
    const control = budgetControlFromNotification(notification, environment);
    if (!VALID_MODES.has(control.billingMode)) {
      throw new Error("invalid budget control mode");
    }

    await writeControl(control, { merge: true });
    logger.info?.("cyclebalance_budget_control_updated", {
      messageId:
        event?.data?.message?.messageId ??
        event?.message?.messageId ??
        event?.messageId ??
        context?.eventId ??
        null,
      billingMode: control.billingMode,
      spendUsd: control.spendUsd,
      budgetUsd: control.budgetUsd,
    });
    return control;
  };
}

function decodeBudgetNotification(event) {
  const encoded =
    event?.data?.message?.data ??
    event?.message?.data ??
    (typeof event?.data === "string" ? event.data : undefined);
  if (typeof encoded !== "string" || encoded.length === 0) {
    throw new Error("invalid budget notification payload");
  }

  try {
    const decoded = Buffer.from(encoded, "base64").toString("utf8");
    return JSON.parse(decoded);
  } catch {
    throw new Error("invalid budget notification payload");
  }
}

function defaultWriteControl(environment) {
  let document;
  return async (control, options) => {
    if (!document) {
      const { Firestore } = await import("@google-cloud/firestore");
      const firestore = new Firestore();
      document = firestore
        .collection(environment.MEAL_SCAN_CONTROL_COLLECTION ?? DEFAULT_CONTROL_COLLECTION)
        .doc(environment.MEAL_SCAN_CONTROL_DOCUMENT ?? DEFAULT_CONTROL_DOCUMENT);
    }
    await document.set(control, options);
  };
}

function finiteNonNegativeNumber(value, field) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new Error(`invalid budget notification ${field}`);
  }
  return number;
}

function finitePositiveNumber(value, field) {
  const number = finiteNonNegativeNumber(value, field);
  if (number === 0) {
    throw new Error(`invalid budget notification ${field}`);
  }
  return number;
}

function stringOrNull(value) {
  return typeof value === "string" && value.length <= 64 ? value : null;
}

export const handleBudgetNotification = createBudgetNotificationHandler();

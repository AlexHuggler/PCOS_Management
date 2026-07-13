#!/usr/bin/env bash
set -euo pipefail

PINNED_PROJECT_ID="cyclebalance-prod-20260710"
PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
APPLY="${APPLY:-false}"
SERVICE_NAME="cyclebalance-meal-scan-proxy"
PROVIDER_DISPATCH_THRESHOLD_PER_MINUTE=60
ERROR_RATIO_THRESHOLD="0.05"
ERROR_RATIO_DURATION_SECONDS=600
AUTH_REJECTION_THRESHOLD_PER_MINUTE=20

if [[ "$PROJECT_ID" != "$PINNED_PROJECT_ID" ]]; then
  echo "PROJECT_ID must equal the pinned production project $PINNED_PROJECT_ID" >&2
  exit 1
fi
if [[ "$APPLY" != "true" && "$APPLY" != "false" ]]; then
  echo "APPLY must be exactly true or false" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-monitoring.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

BASE_LOG_FILTER="resource.type=\"cloud_run_revision\" resource.labels.service_name=\"$SERVICE_NAME\" jsonPayload.event=\"meal_scan_scanner_event\""
BUDGET_SIGNAL_FILTER='jsonPayload.eventType="budget_state" (jsonPayload.outcome=~"transitioned|stale|unavailable" OR jsonPayload.budgetMode=~"alert|degraded|disabled")'
PROVIDER_DISPATCH_FILTER='jsonPayload.eventType="provider_call" jsonPayload.outcome="started"'
REQUEST_RESULT_FILTER='jsonPayload.eventType="request_result"'
AUTH_REJECTION_FILTER='jsonPayload.eventType="authorization_rejection" jsonPayload.outcome="rejected" jsonPayload.control=~"app_check|storekit_jws"'

json_string() {
  node -e 'process.stdout.write(JSON.stringify(process.argv[1]));' "$1"
}

write_metric_configs() {
  local budget_filter_json
  local provider_filter_json
  local request_filter_json
  local auth_filter_json
  budget_filter_json="$(json_string "$BASE_LOG_FILTER $BUDGET_SIGNAL_FILTER")"
  provider_filter_json="$(json_string "$BASE_LOG_FILTER $PROVIDER_DISPATCH_FILTER")"
  request_filter_json="$(json_string "$BASE_LOG_FILTER $REQUEST_RESULT_FILTER")"
  auth_filter_json="$(json_string "$BASE_LOG_FILTER $AUTH_REJECTION_FILTER")"
  cat >"$WORK_DIR/budget-signal-metric.json" <<EOF
{
  "name": "cyclebalance_meal_scan_budget_signal_total",
  "description": "Identifier-free scanner budget transitions, restrictive modes, stale states, and unavailable states.",
  "filter": $budget_filter_json,
  "metricDescriptor": {
    "metricKind": "DELTA",
    "valueType": "INT64",
    "unit": "1"
  }
}
EOF

  cat >"$WORK_DIR/provider-dispatch-metric.json" <<EOF
{
  "name": "cyclebalance_meal_scan_provider_dispatch_total",
  "description": "Fresh provider calls started by the identifier-free scanner event stream.",
  "filter": $provider_filter_json,
  "metricDescriptor": {
    "metricKind": "DELTA",
    "valueType": "INT64",
    "unit": "1"
  }
}
EOF

  cat >"$WORK_DIR/request-result-metric.json" <<EOF
{
  "name": "cyclebalance_meal_scan_request_result_total",
  "description": "Identifier-free terminal scanner responses labeled only by bounded HTTP status class.",
  "filter": $request_filter_json,
  "metricDescriptor": {
    "metricKind": "DELTA",
    "valueType": "INT64",
    "unit": "1",
    "labels": [
      {
        "key": "status_class",
        "valueType": "STRING",
        "description": "Bounded HTTP status class such as 2xx or 5xx."
      }
    ]
  },
  "labelExtractors": {
    "status_class": "EXTRACT(jsonPayload.statusClass)"
  }
}
EOF

  cat >"$WORK_DIR/auth-rejection-metric.json" <<EOF
{
  "name": "cyclebalance_meal_scan_auth_rejection_total",
  "description": "Combined rejected App Check and StoreKit JWS decisions without submitted evidence or identifiers.",
  "filter": $auth_filter_json,
  "metricDescriptor": {
    "metricKind": "DELTA",
    "valueType": "INT64",
    "unit": "1"
  }
}
EOF
}

write_policy_configs() {
  cat >"$WORK_DIR/budget-state-policy.json" <<'EOF'
{
  "displayName": "CycleBalance Meal Scan - Budget State",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "Budget transition, restrictive mode, stale state, or unavailable state",
      "conditionPrometheusQueryLanguage": {
        "query": "sum(increase({\"logging.googleapis.com/user/cyclebalance_meal_scan_budget_signal_total\", monitored_resource=\"cloud_run_revision\"}[5m])) >= 1",
        "duration": "0s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "documentation": {
    "content": "The scanner observed a budget-mode transition, a restrictive budget mode, a state older than 24 hours, or an unavailable budget control. Keep the service private and scanner-disabled while investigating.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "component": "meal_scan",
    "managed_by": "cyclebalance"
  }
}
EOF

  cat >"$WORK_DIR/provider-dispatch-policy.json" <<'EOF'
{
  "displayName": "CycleBalance Meal Scan - Provider Dispatch 60 per minute",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "Provider dispatch is at or above 60 per minute",
      "conditionPrometheusQueryLanguage": {
        "query": "sum(increase({\"logging.googleapis.com/user/cyclebalance_meal_scan_provider_dispatch_total\", monitored_resource=\"cloud_run_revision\"}[1m])) >= 60",
        "duration": "0s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "documentation": {
    "content": "Fresh Gemini dispatch reached the immutable 60-per-minute ceiling. Check abuse controls, quota decisions, and budget mode before changing any limit.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "component": "meal_scan",
    "managed_by": "cyclebalance"
  }
}
EOF

  cat >"$WORK_DIR/error-ratio-policy.json" <<'EOF'
{
  "displayName": "CycleBalance Meal Scan - 5xx Ratio over 5 percent for 10 minutes",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "5xx response ratio is above 5 percent for 10 minutes",
      "conditionPrometheusQueryLanguage": {
        "query": "(sum(rate({\"logging.googleapis.com/user/cyclebalance_meal_scan_request_result_total\", monitored_resource=\"cloud_run_revision\", status_class=\"5xx\"}[10m])) / clamp_min(sum(rate({\"logging.googleapis.com/user/cyclebalance_meal_scan_request_result_total\", monitored_resource=\"cloud_run_revision\"}[10m])), 0.000001)) > 0.05",
        "duration": "600s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "documentation": {
    "content": "The identifier-free scanner terminal-event stream reports a 5xx ratio above 5 percent for 10 minutes. Inspect bounded rejection reasons and provider latency without searching for customer evidence.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "component": "meal_scan",
    "managed_by": "cyclebalance"
  }
}
EOF

  cat >"$WORK_DIR/auth-rejection-policy.json" <<'EOF'
{
  "displayName": "CycleBalance Meal Scan - Auth Rejections over 20 per minute",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "Combined App Check and StoreKit JWS rejection count is above 20 per minute",
      "conditionPrometheusQueryLanguage": {
        "query": "sum(increase({\"logging.googleapis.com/user/cyclebalance_meal_scan_auth_rejection_total\", monitored_resource=\"cloud_run_revision\"}[1m])) > 20",
        "duration": "0s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "documentation": {
    "content": "Combined rejected App Check and StoreKit JWS decisions exceeded 20 in one minute. Events contain only bounded control and reason dimensions.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "component": "meal_scan",
    "managed_by": "cyclebalance"
  }
}
EOF
}

validate_json_file() {
  node -e 'const fs=require("node:fs"); JSON.parse(fs.readFileSync(process.argv[1], "utf8"));' "$1"
}

validate_configs() {
  local file
  for file in "$WORK_DIR"/*.json; do
    validate_json_file "$file"
  done
  [[ "$PROVIDER_DISPATCH_THRESHOLD_PER_MINUTE" == "60" ]]
  [[ "$ERROR_RATIO_THRESHOLD" == "0.05" ]]
  [[ "$ERROR_RATIO_DURATION_SECONDS" == "600" ]]
  [[ "$AUTH_REJECTION_THRESHOLD_PER_MINUTE" == "20" ]]
}

upsert_log_metric() {
  local name="$1"
  local config_file="$2"
  if gcloud logging metrics describe "$name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud logging metrics update "$name" --project "$PROJECT_ID" --config-from-file "$config_file" --quiet
  else
    gcloud logging metrics create "$name" --project "$PROJECT_ID" --config-from-file "$config_file" --quiet
  fi
}

upsert_alert_policy() {
  local display_name="$1"
  local config_file="$2"
  local existing
  existing="$(gcloud monitoring policies list \
    --project "$PROJECT_ID" \
    --filter="displayName=\"$display_name\"" \
    --format='value(name)' \
    --limit=2)"
  if [[ "$(printf '%s\n' "$existing" | sed '/^$/d' | wc -l | tr -d ' ')" -gt 1 ]]; then
    echo "Multiple alert policies already use display name: $display_name" >&2
    exit 1
  fi
  if [[ -n "$existing" ]]; then
    gcloud monitoring policies update "$existing" \
      --project "$PROJECT_ID" \
      --policy-from-file "$config_file" \
      --quiet
  else
    gcloud monitoring policies create \
      --project "$PROJECT_ID" \
      --policy-from-file "$config_file" \
      --quiet
  fi
}

write_metric_configs
write_policy_configs
validate_configs

echo "Validated monitoring resources for $PROJECT_ID:"
for policy_file in "$WORK_DIR"/*-policy.json; do
  node -e 'const fs=require("node:fs"); console.log(`- ${JSON.parse(fs.readFileSync(process.argv[1], "utf8")).displayName}`);' "$policy_file"
done

if [[ "$APPLY" != "true" ]]; then
  echo "Validation-only dry run complete. No Cloud Logging or Monitoring resources were created or changed."
  echo "Re-run with APPLY=true only after reviewing notification routing and the rendered policy contract."
  exit 0
fi

command -v gcloud >/dev/null 2>&1 || {
  echo "gcloud is required when APPLY=true" >&2
  exit 1
}
ACTIVE_PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [[ "$ACTIVE_PROJECT" != "$PINNED_PROJECT_ID" ]]; then
  echo "Active gcloud project must equal the pinned production project $PINNED_PROJECT_ID" >&2
  exit 1
fi
gcloud auth print-access-token --project "$PROJECT_ID" >/dev/null

upsert_log_metric "cyclebalance_meal_scan_budget_signal_total" "$WORK_DIR/budget-signal-metric.json"
upsert_log_metric "cyclebalance_meal_scan_provider_dispatch_total" "$WORK_DIR/provider-dispatch-metric.json"
upsert_log_metric "cyclebalance_meal_scan_request_result_total" "$WORK_DIR/request-result-metric.json"
upsert_log_metric "cyclebalance_meal_scan_auth_rejection_total" "$WORK_DIR/auth-rejection-metric.json"

upsert_alert_policy "CycleBalance Meal Scan - Budget State" "$WORK_DIR/budget-state-policy.json"
upsert_alert_policy "CycleBalance Meal Scan - Provider Dispatch 60 per minute" "$WORK_DIR/provider-dispatch-policy.json"
upsert_alert_policy "CycleBalance Meal Scan - 5xx Ratio over 5 percent for 10 minutes" "$WORK_DIR/error-ratio-policy.json"
upsert_alert_policy "CycleBalance Meal Scan - Auth Rejections over 20 per minute" "$WORK_DIR/auth-rejection-policy.json"

echo "Monitoring metrics and alert policies were idempotently applied to $PROJECT_ID."

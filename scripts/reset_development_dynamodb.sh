#!/usr/bin/env bash
set -euo pipefail

readonly TABLE_NAME="${TABLE_NAME:-ExpenseTrackerData}"
readonly AWS_REGION="${AWS_REGION:-ap-south-2}"
readonly EXPECTED_TABLE="ExpenseTrackerData"
readonly EXPECTED_REGION="ap-south-2"
readonly CONFIRMATION="${CONFIRM_DELETE_ALL_DATA:-}"

if [[ "$TABLE_NAME" != "$EXPECTED_TABLE" || "$AWS_REGION" != "$EXPECTED_REGION" ]]; then
  echo "Refusing to reset unexpected DynamoDB target: ${TABLE_NAME} in ${AWS_REGION}" >&2
  exit 1
fi

if [[ "$CONFIRMATION" != "DELETE" ]]; then
  echo "Set CONFIRM_DELETE_ALL_DATA=DELETE to erase all ${TABLE_NAME} records." >&2
  exit 1
fi

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

delete_batch() {
  local request="$1"
  local response
  response="$(aws dynamodb batch-write-item \
    --region "$AWS_REGION" \
    --request-items "$request" \
    --output json)"

  local unprocessed
  unprocessed="$(jq -c '.UnprocessedItems' <<<"$response")"
  while [[ "$unprocessed" != "{}" ]]; do
    sleep 1
    response="$(aws dynamodb batch-write-item \
      --region "$AWS_REGION" \
      --request-items "$unprocessed" \
      --output json)"
    unprocessed="$(jq -c '.UnprocessedItems' <<<"$response")"
  done
}

start_key=""
deleted=0
while :; do
  if [[ -n "$start_key" ]]; then
    aws dynamodb scan \
      --table-name "$TABLE_NAME" \
      --region "$AWS_REGION" \
      --projection-expression "PK, SK" \
      --exclusive-start-key "$start_key" \
      --output json >"$response_file"
  else
    aws dynamodb scan \
      --table-name "$TABLE_NAME" \
      --region "$AWS_REGION" \
      --projection-expression "PK, SK" \
      --output json >"$response_file"
  fi

  while IFS= read -r items; do
    request="$(jq -cn --arg table "$TABLE_NAME" --argjson items "$items" \
      '{($table): [$items[] | {DeleteRequest: {Key: {PK: .PK, SK: .SK}}}]}')"
    delete_batch "$request"
    deleted=$((deleted + $(jq 'length' <<<"$items")))
  done < <(jq -c '[.Items | range(0; length; 25) as $start | .[$start:$start + 25]][]' "$response_file")

  start_key="$(jq -c '.LastEvaluatedKey // empty' "$response_file")"
  [[ -n "$start_key" ]] || break
done

echo "Deleted ${deleted} records from ${TABLE_NAME} in ${AWS_REGION}."

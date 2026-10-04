retry_policy_normalize() {
  local max_retry_attempts=10
  local max_retry_delay_seconds=922337203685477580
  local normalized_attempts
  local normalized_delay_seconds
  local attempts_exceed_max=0
  local delay_seconds_exceed_max=0

  RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-${LOCAL_VERIFIER_RETRY_ATTEMPTS:-3}}"
  RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-${LOCAL_VERIFIER_RETRY_DELAY_SECONDS:-2}}"

  if ! [[ "$RETRY_ATTEMPTS" =~ ^[0-9]+$ ]]; then
    echo "LOCAL_VERIFIER_RETRY_ATTEMPTS must be a positive decimal integer." >&2
    return 64
  fi
  normalized_attempts="${RETRY_ATTEMPTS#"${RETRY_ATTEMPTS%%[!0]*}"}"
  if [[ -z "$normalized_attempts" ]]; then
    normalized_attempts=0
  fi
  RETRY_ATTEMPTS="$normalized_attempts"
  if ! [[ "$RETRY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    echo "LOCAL_VERIFIER_RETRY_ATTEMPTS must be a positive decimal integer." >&2
    return 64
  fi

  if ! [[ "$RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "LOCAL_VERIFIER_RETRY_DELAY_SECONDS must be a non-negative decimal integer." >&2
    return 64
  fi
  normalized_delay_seconds="${RETRY_DELAY_SECONDS#"${RETRY_DELAY_SECONDS%%[!0]*}"}"
  if [[ -z "$normalized_delay_seconds" ]]; then
    normalized_delay_seconds=0
  fi
  RETRY_DELAY_SECONDS="$normalized_delay_seconds"

  if (( ${#RETRY_ATTEMPTS} > ${#max_retry_attempts} )); then
    attempts_exceed_max=1
  elif (( ${#RETRY_ATTEMPTS} == ${#max_retry_attempts} )) &&
    [[ "$RETRY_ATTEMPTS" > "$max_retry_attempts" ]]; then
    attempts_exceed_max=1
  fi
  if (( attempts_exceed_max )); then
    echo "LOCAL_VERIFIER_RETRY_ATTEMPTS must be between 1 and $max_retry_attempts." >&2
    return 64
  fi

  if (( ${#RETRY_DELAY_SECONDS} > ${#max_retry_delay_seconds} )); then
    delay_seconds_exceed_max=1
  elif (( ${#RETRY_DELAY_SECONDS} == ${#max_retry_delay_seconds} )) &&
    [[ "$RETRY_DELAY_SECONDS" > "$max_retry_delay_seconds" ]]; then
    delay_seconds_exceed_max=1
  fi
  if (( delay_seconds_exceed_max )); then
    echo "LOCAL_VERIFIER_RETRY_DELAY_SECONDS must be between 0 and $max_retry_delay_seconds." >&2
    return 64
  fi

  return 0
}

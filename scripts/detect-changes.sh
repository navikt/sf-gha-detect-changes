#!/usr/bin/env bash
set -euo pipefail

# Inputs
BASE="${BASE:-}"
EVENT_NAME="${EVENT_NAME:-}"
BEFORE="${BEFORE:-}"
SHA="${SHA:-HEAD}"
PR_BASE="${PR_BASE:-}"

CHANGED_FILE="${CHANGED_FILE:-/tmp/changed.txt}"
: > "$CHANGED_FILE"

# Resolve base commit
if [[ -n "${BASE}" ]]; then
  COMPARE_BASE="$BASE"
elif [[ "${EVENT_NAME}" == "pull_request" && -n "${PR_BASE}" ]]; then
  COMPARE_BASE="$PR_BASE"
else
  COMPARE_BASE="${BEFORE:-}"
  if [[ -z "${COMPARE_BASE}" || "${COMPARE_BASE}" == "0000000000000000000000000000000000000000" ]]; then
    PARENTS="$(git show -s --format=%P "${SHA}")"
    COMPARE_BASE="${PARENTS%% *}"
    if [[ -z "${COMPARE_BASE}" ]]; then
      COMPARE_BASE="$(git hash-object -t tree /dev/null)"
    fi
  fi
fi

echo "Comparing ${COMPARE_BASE:-<none>} → ${SHA}" >&2

# Get changed files
git diff --name-only "${COMPARE_BASE}" "${SHA}" > "$CHANGED_FILE"

echo "Changed files:" >&2
cat "$CHANGED_FILE" >&2

# Categorize
CODE=false
METADATA=false
OTHER=false

CHANGED_FILES=()
CODE_FILES=()
METADATA_FILES=()
OTHER_FILES=()

while IFS= read -r file || [[ -n "$file" ]]; do
  [[ -z "$file" ]] && continue
  CHANGED_FILES+=("$file")

  categorized=false

  # Code: LWC (non-md) + Apex/Trigger + their meta files
  if [[ "$file" == force-app/*/lwc/* && "$file" != *.md ]] || \
     [[ "$file" == *.cls || "$file" == *.trigger || "$file" == *.apex ]] || \
     [[ "$file" == *.cls-meta.xml || "$file" == *.trigger-meta.xml ]]; then
    CODE=true
    CODE_FILES+=("$file")
    categorized=true
  fi

  # Metadata: remaining *-meta.xml under force-app
  if [[ "$file" == force-app/* && "$file" == *-meta.xml && "$categorized" == false ]]; then
    METADATA=true
    METADATA_FILES+=("$file")
    categorized=true
  fi

  # Everything else
  if [[ "$categorized" == false ]]; then
    OTHER=true
    OTHER_FILES+=("$file")
  fi
done < "$CHANGED_FILE"

# Build summary
SUMMARY="### Change summary"$'\n'$'\n'

[[ "$CODE" == true ]] && SUMMARY+="- **Code** (LWC / Apex / Trigger) updated"$'\n'
[[ "$METADATA" == true ]] && SUMMARY+="- **Metadata** (Flows / other) updated"$'\n'
[[ "$OTHER" == true ]] && SUMMARY+="- **Other** files updated"$'\n'

if [[ "$CODE" == false && "$METADATA" == false && "$OTHER" == false ]]; then
  SUMMARY+="- No changes detected"$'\n'
fi

SUMMARY+=$'\n'"**Changed files:**"$'\n'"\`\`\`"$'\n'
SUMMARY+="$(cat "$CHANGED_FILE")"$'\n'
SUMMARY+="\`\`\`"$'\n'

# Helper to JSON-encode an array
json_array() {
  local arr=("$@")
  if [[ ${#arr[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  printf '%s\n' "${arr[@]}" | jq -R . | jq -s .
}

# Emit single JSON object to stdout
jq -n \
  --arg code "$CODE" \
  --arg metadata "$METADATA" \
  --arg other "$OTHER" \
  --arg summary "$SUMMARY" \
  --argjson changed "$(json_array "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}")" \
  --argjson code_files "$(json_array "${CODE_FILES[@]+"${CODE_FILES[@]}"}")" \
  --argjson metadata_files "$(json_array "${METADATA_FILES[@]+"${METADATA_FILES[@]}"}")" \
  --argjson other_files "$(json_array "${OTHER_FILES[@]+"${OTHER_FILES[@]}"}")" \
  '{
    code: $code,
    metadata: $metadata,
    other: $other,
    summary: $summary,
    changed_files: $changed,
    code_files: $code_files,
    metadata_files: $metadata_files,
    other_files: $other_files
  }'
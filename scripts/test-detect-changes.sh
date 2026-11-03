#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/detect-changes.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

git init -q "$TEST_DIR/repo"
cd "$TEST_DIR/repo"
git config user.name "Test"
git config user.email "test@example.invalid"
git config commit.gpgsign false
git config core.hooksPath /dev/null

mkdir -p force-app/main/default/flows
printf 'class Example {}\n' > Example.cls
git add .
git commit -qm initial
ROOT_SHA="$(git rev-parse HEAD)"
ZERO_SHA=0000000000000000000000000000000000000000

detect() {
  BASE="$1" EVENT_NAME="$2" BEFORE="$3" SHA="$4" PR_BASE="${5:-}" \
    CHANGED_FILE="$TEST_DIR/changed.txt" bash "$SCRIPT" \
    > "$TEST_DIR/result.json" 2> "$TEST_DIR/stderr"
}

assert_json() {
  jq -e "$1" "$TEST_DIR/result.json" > /dev/null
}

assert_failure() {
  if detect "$@"; then
    printf 'Expected detection to fail: %s\n' "$*" >&2
    exit 1
  fi
  test -s "$TEST_DIR/stderr"
  test ! -s "$TEST_DIR/result.json"
}

for before in "" "$ZERO_SHA"; do
  detect "" push "$before" "$ROOT_SHA"
  assert_json '.code == "true" and .metadata == "false" and .other == "false"
    and .changed_files == ["Example.cls"] and .code_files == ["Example.cls"]'
done

printf '<Flow/>\n' > force-app/main/default/flows/Example.flow-meta.xml
printf 'notes\n' > notes.txt
git add .
git commit -qm "add metadata and other files"
SECOND_SHA="$(git rev-parse HEAD)"

for before in "" "$ZERO_SHA" "$ROOT_SHA"; do
  detect "" push "$before" "$SECOND_SHA"
  assert_json '.code == "false" and .metadata == "true" and .other == "true"
    and .changed_files == ["force-app/main/default/flows/Example.flow-meta.xml", "notes.txt"]
    and .metadata_files == ["force-app/main/default/flows/Example.flow-meta.xml"]
    and .other_files == ["notes.txt"] and .code_files == []'
done

detect "$ROOT_SHA" push missing-ref "$SECOND_SHA"
assert_json '.metadata == "true" and .other == "true"'

detect "" pull_request missing-ref "$SECOND_SHA" "$ROOT_SHA"
assert_json '.metadata == "true" and .other == "true"'

detect HEAD push "" HEAD
assert_json '.code == "false" and .metadata == "false" and .other == "false"
  and .changed_files == [] and .code_files == [] and .metadata_files == []
  and .other_files == [] and (.summary | contains("No changes detected"))'

for before in "" "$ZERO_SHA"; do
  detect "" push "$before" "$ROOT_SHA"
  assert_json '.changed_files == ["Example.cls"] and .code == "true"'
done

git checkout -qb feature "$ROOT_SHA"
printf 'class Feature {}\n' > Feature.cls
git add Feature.cls
git commit -qm "add feature"
git checkout -q --detach "$SECOND_SHA"
git merge --no-ff -qm "merge feature" feature

for before in "" "$ZERO_SHA"; do
  detect "" push "$before" HEAD
  assert_json '.changed_files == ["Feature.cls"] and .code_files == ["Feature.cls"]
    and .code == "true" and .metadata == "false" and .other == "false"'
done

assert_failure missing-ref push "" HEAD
assert_failure "" push missing-ref HEAD
assert_failure HEAD push "" missing-ref
assert_failure "" push "" missing-ref
assert_failure "" push "$ZERO_SHA" missing-ref
assert_failure "" pull_request "" HEAD missing-ref

printf 'All detect-changes tests passed.\n'

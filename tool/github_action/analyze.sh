#!/usr/bin/env bash
# Runs hyena_dart for action.yml and writes the SARIF path and exit code to
# $GITHUB_OUTPUT. Report paths are rebased onto the repository root so code
# scanning can place findings from a package in a subdirectory.
set -uo pipefail

sarif="${HYENA_SARIF:-${RUNNER_TEMP:-/tmp}/hyena_dart.sarif}"
case "$sarif" in
  /* | [A-Za-z]:*) ;;
  *) sarif="$PWD/$sarif" ;;
esac

args=(analyze "${HYENA_PATH:-.}" --format=sarif "--output=$sarif")
[[ -n "${HYENA_CONFIG:-}" ]] && args+=("--config=$HYENA_CONFIG")
[[ -n "${HYENA_BASELINE:-}" ]] && args+=("--baseline=$HYENA_BASELINE")
[[ -n "${HYENA_FAIL_ON:-}" ]] && args+=("--fail-on=$HYENA_FAIL_ON")
read -r -a extra <<< "${HYENA_ARGS:-}"
args+=(${extra[@]+"${extra[@]}"})

dart pub global run hyena_dart "${args[@]}"
code=$?
echo "exit-code=$code" >> "$GITHUB_OUTPUT"
if [[ $code -ne 0 && $code -ne 1 ]]; then
  exit "$code"
fi

prefix="${HYENA_WORKDIR:-.}"
prefix="${prefix#./}"
prefix="${prefix%/}"
if [[ -n "$prefix" && "$prefix" != "." ]]; then
  escaped=$(printf '%s' "$prefix" | sed 's/[&#\\]/\\&/g')
  sed "s#\"uri\": \"#\"uri\": \"$escaped/#" "$sarif" > "$sarif.tmp" &&
    mv "$sarif.tmp" "$sarif"
fi
echo "sarif-file=$sarif" >> "$GITHUB_OUTPUT"

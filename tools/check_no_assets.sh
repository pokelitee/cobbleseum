#!/usr/bin/env bash
# Fails if any tracked or staged file looks like a third-party asset or download.
# Runs in CI and works as a pre-commit hook (see README).
set -euo pipefail

max_bytes="${MAX_FILE_BYTES:-1048576}"
max_fixture_bytes="${MAX_FIXTURE_BYTES:-65536}"
status=0

while IFS= read -r -d '' file; do
	reason=""
	case "$file" in
		cache/* | recordings/* | results/*)
			reason="is inside a git-ignored output folder" ;;
		*.jar | *.tgz | *.tar.gz | *.zip | *.apk | *.xapk | *.apks)
			reason="is a downloaded archive" ;;
		tests/fixtures/*)
			# Fixtures are original, hand-made files; keeping them small stops real models slipping in.
			if [ -f "$file" ] && [ "$(wc -c < "$file")" -gt "$max_fixture_bytes" ]; then
				reason="is a fixture larger than $max_fixture_bytes bytes"
			fi ;;
		*.geo.json | *.animation.json)
			reason="is a Bedrock model or animation outside tests/fixtures/" ;;
	esac
	if [ -z "$reason" ] && [ -f "$file" ] && [ "$(wc -c < "$file")" -gt "$max_bytes" ]; then
		reason="is larger than $max_bytes bytes"
	fi
	if [ -n "$reason" ]; then
		echo "error: $file $reason; third-party assets must stay in the local cache" >&2
		status=1
	fi
done < <(git ls-files -z --cached)

if [ "$status" -eq 0 ]; then
	echo "No third-party assets found."
fi
exit "$status"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./publish_report.sh [--channel <ui|mobile|api|cross|unified>] [--date YYYY-MM-DD] [--no-push] [--dry-run]

Examples:
  ./publish_report.sh
  ./publish_report.sh --channel mobile
  ./publish_report.sh --channel ui --date 2026-05-05
  ./publish_report.sh --channel api --no-push
EOF
}

channel="ui"
report_date="$(date +"%Y-%m-%d")"
push_changes=true
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      channel="${2:-}"
      shift 2
      ;;
    --date)
      report_date="${2:-}"
      shift 2
      ;;
    --no-push)
      push_changes=false
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! "$channel" =~ ^(ui|mobile|api|cross|unified)$ ]]; then
  echo "Invalid channel '$channel'. Expected one of: ui, mobile, api, cross, unified"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$script_dir/.git" ]]; then
  echo "This folder is not a git repository: $script_dir"
  exit 1
fi

latest_report="$(ls -td "$script_dir/allure-report/$report_date/${channel}_"* 2>/dev/null | head -n 1 || true)"
if [[ -z "$latest_report" ]]; then
  echo "No report folder found for channel '$channel' on date '$report_date'"
  echo "Expected pattern: allure-report/$report_date/${channel}_*"
  exit 1
fi

if [[ ! -f "$latest_report/index.html" ]]; then
  echo "Report folder found, but index.html is missing: $latest_report"
  exit 1
fi

echo "Selected report: $latest_report"
echo "Target folder: $script_dir/docs"

if [[ "$dry_run" == true ]]; then
  echo "Dry run enabled. No files changed."
  exit 0
fi

mkdir -p "$script_dir/docs"
rsync -av --delete "$latest_report/" "$script_dir/docs/" >/dev/null

git -C "$script_dir" add docs
if git -C "$script_dir" diff --cached --quiet; then
  echo "No report changes to commit."
  exit 0
fi

commit_message="Update ${channel} report (${report_date})"
git -C "$script_dir" commit -m "$commit_message" >/dev/null

echo "Committed: $commit_message"

if [[ "$push_changes" == true ]]; then
  git -C "$script_dir" push origin main
  remote_url="$(git -C "$script_dir" config --get remote.origin.url || true)"
  if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    echo "Report URL: https://${owner,,}.github.io/${repo}/"
  fi
else
  echo "Push skipped (--no-push)."
fi


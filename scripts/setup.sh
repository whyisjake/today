#!/usr/bin/env bash
# Adds the agentic workflow template to an existing repository.
#
# Usage (run from the root of your target repo):
#   bash <(curl -fsSL https://raw.githubusercontent.com/whyisjake/agentic-workflow-template/main/scripts/setup.sh)
#
# Or clone and run locally:
#   bash /path/to/agentic-workflow-template/scripts/setup.sh
#
# What this does:
#   - Adds .github/ISSUE_TEMPLATE/agent-ready.md       (alongside existing templates)
#   - Adds .github/PULL_REQUEST_TEMPLATE/agent-generated.md  (alongside existing templates)
#   - Adds .github/LABELS.yml  (or prints merge instructions if one already exists)
#   - Adds .github/workflows/  (all agent workflow files, skips any that already exist)
#   - Adds .github/agents/issue-screener.agent.md
#   - Creates docs/ if it doesn't exist
#   - Prints next steps
#
# Nothing is committed — you review and commit the changes yourself.
#
# EXISTING TEMPLATES:
#   Issue templates coexist — GitHub shows all files in ISSUE_TEMPLATE/ as choices.
#   PR templates coexist   — GitHub shows all files in PULL_REQUEST_TEMPLATE/ as choices.
#   If you use a single flat pull_request_template.md, this script adds a named
#   PULL_REQUEST_TEMPLATE/ directory alongside it (both work at the same time).

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/whyisjake/agentic-workflow-template/main"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || true

# ── Helpers ───────────────────────────────────────────────────────────────────

green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
dim()    { printf '\033[2m%s\033[0m\n' "$*"; }

# Download a file from the template repo, or copy from a local clone
fetch() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -n "$TEMPLATE_DIR" && -f "$TEMPLATE_DIR/$src" ]]; then
    cp "$TEMPLATE_DIR/$src" "$dest"
  else
    curl -fsSL "$REPO_URL/$src" -o "$dest"
  fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────

if [[ ! -d ".git" ]]; then
  red "Error: run this script from the root of a git repository."
  exit 1
fi

bold ""
bold "Agentic Workflow Template — Setup"
echo  "Adding agent-ready workflow files to: $(basename "$(pwd)")"
echo  ""

# ── Issue template ────────────────────────────────────────────────────────────
# GitHub shows every file in ISSUE_TEMPLATE/ as a separate choice when opening
# an issue, so agent-ready.md coexists with bug_report.md, feature_request.md, etc.

if [[ -d ".github/ISSUE_TEMPLATE" ]]; then
  dim "  .github/ISSUE_TEMPLATE/ already exists — adding agent-ready.md alongside your existing templates"
fi

if [[ -f ".github/ISSUE_TEMPLATE/agent-ready.md" ]]; then
  yellow "  skipped (already exists): .github/ISSUE_TEMPLATE/agent-ready.md"
else
  fetch ".github/ISSUE_TEMPLATE/agent-ready.md" ".github/ISSUE_TEMPLATE/agent-ready.md"
  green "  added: .github/ISSUE_TEMPLATE/agent-ready.md"
fi

# ── PR template ───────────────────────────────────────────────────────────────
# GitHub supports multiple named PR templates in PULL_REQUEST_TEMPLATE/.
# If you have a flat .github/pull_request_template.md, both approaches work
# simultaneously — GitHub uses the named directory when it exists.

if [[ -f ".github/pull_request_template.md" ]]; then
  dim "  Found .github/pull_request_template.md — adding named PULL_REQUEST_TEMPLATE/ alongside it"
  dim "  (GitHub uses named templates when PULL_REQUEST_TEMPLATE/ exists; your existing template is unaffected)"
fi

if [[ -f ".github/PULL_REQUEST_TEMPLATE/agent-generated.md" ]]; then
  yellow "  skipped (already exists): .github/PULL_REQUEST_TEMPLATE/agent-generated.md"
else
  fetch ".github/PULL_REQUEST_TEMPLATE/agent-generated.md" ".github/PULL_REQUEST_TEMPLATE/agent-generated.md"
  green "  added: .github/PULL_REQUEST_TEMPLATE/agent-generated.md"
fi

# ── LABELS.yml ────────────────────────────────────────────────────────────────

if [[ -f ".github/LABELS.yml" ]]; then
  yellow "  skipped (already exists): .github/LABELS.yml"
  echo   "  → To add agent labels, append these entries to your existing LABELS.yml:"
  echo   "    $REPO_URL/.github/LABELS.yml"
else
  fetch ".github/LABELS.yml" ".github/LABELS.yml"
  green "  added: .github/LABELS.yml"
fi

# ── Workflows ────────────────────────────────────────────────────────────────
# Each workflow file is independent — skipping an existing file leaves the
# rest unaffected.

WORKFLOW_FILES=(
  ".github/workflows/agent-ready-trigger.yml"
  ".github/workflows/plan-approval-gate.yml"
  ".github/workflows/setup-labels.yml"
  ".github/workflows/auto-label-agent-ready.yml"
  ".github/workflows/issue-screener.yml"
)

for file in "${WORKFLOW_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    yellow "  skipped (already exists): $file"
  else
    fetch "$file" "$file"
    green "  added: $file"
  fi
done

# ── Agent file ────────────────────────────────────────────────────────────────

if [[ -f ".github/agents/issue-screener.agent.md" ]]; then
  yellow "  skipped (already exists): .github/agents/issue-screener.agent.md"
else
  fetch ".github/agents/issue-screener.agent.md" ".github/agents/issue-screener.agent.md"
  green "  added: .github/agents/issue-screener.agent.md"
fi

# ── docs/ directory ───────────────────────────────────────────────────────────

if [[ ! -d "docs" ]]; then
  mkdir -p docs
  green "  created: docs/"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
bold "Done. Next steps:"
echo ""
echo "  1. Review added files:"
echo "     git status"
echo ""
echo "  2. Commit:"
echo "     git add .github/ docs/"
echo "     git commit -m 'chore: add agentic workflow template'"
echo "     git push"
echo ""
echo "  3. Sync labels (run once after pushing):"
echo "     Actions → Setup Labels → Run workflow"
echo ""
echo "  4. Configure your agent (optional, defaults to claude):"
echo "     Settings → Secrets and variables → Variables → AGENT_PROVIDER"
echo "     Settings → Secrets and variables → Secrets → CLAUDE_CODE_OAUTH_TOKEN"
echo ""
echo "  Full docs: https://github.com/whyisjake/agentic-workflow-template"
echo ""

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptsRoot = Join-Path $repoRoot "skills/auto-github-contributor/scripts"

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    $script:failures.Add($Message)
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Message
  )
  Assert-True ($Text.Contains($Needle)) $Message
}

function Read-File {
  param([string]$Path)
  Assert-True (Test-Path -LiteralPath $Path) "Missing file: $Path"
  if (Test-Path -LiteralPath $Path) {
    return Get-Content -LiteralPath $Path -Raw
  }
  return ""
}

Write-Host "[smoke] shell workflow regression checks"
Write-Host "[smoke] repo root: $repoRoot"

$scriptNames = @(
  "browser-verify.sh",
  "config.sh",
  "check-prereqs.sh",
  "dev-loop-check.sh",
  "setup-workspace.sh",
  "scan-quick-wins.sh",
  "fetch-issues.sh",
  "rank-candidates.sh",
  "create-pr.sh"
)

$scriptText = @{}
foreach ($name in $scriptNames) {
  $path = Join-Path $scriptsRoot $name
  $text = Read-File -Path $path
  $scriptText[$name] = $text
  Assert-Contains $text "#!/usr/bin/env bash" "$name must keep bash shebang."
}

# config.sh invariants
$config = $scriptText["config.sh"]
Assert-Contains $config "set -euo pipefail" "config.sh should enforce strict shell mode."
Assert-Contains $config ': "${AGC_BASE_BRANCH:=main}"' "config.sh should default AGC_BASE_BRANCH=main."
Assert-Contains $config "bug,bugfix,tests,testing,ci,security" "config.sh should discover substantive issue labels by default."
Assert-True (-not $config.Contains('AGC_LABELS:=good first issue,help wanted,documentation')) "config.sh should not default to documentation-first discovery."
Assert-Contains $config "agc::require_repo() {" "config.sh should define agc::require_repo."
Assert-Contains $config "TARGET_REPO must be in <owner>/<name> form" "config.sh should validate TARGET_REPO format."
Assert-Contains $config "agc::fork_repo() {" "config.sh should define fork repo helper."

# check-prereqs.sh invariants
$prereqs = $scriptText["check-prereqs.sh"]
Assert-Contains $prereqs "set -uo pipefail" "check-prereqs.sh should avoid immediate -e exit."
Assert-Contains $prereqs "check_bin gh" "check-prereqs.sh must verify gh."
Assert-Contains $prereqs "check_bin git" "check-prereqs.sh must verify git."
Assert-Contains $prereqs "check_bin jq" "check-prereqs.sh must verify jq."
Assert-Contains $prereqs "gh auth status" "check-prereqs.sh must check gh authentication."
Assert-Contains $prereqs "printf 'GH_USER=%s\n'" "check-prereqs.sh should emit GH_USER=..."
Assert-Contains $prereqs "printf 'READY=1\n'" "check-prereqs.sh should emit READY=1."

# browser-verify.sh invariants
$browserVerify = $scriptText["browser-verify.sh"]
Assert-Contains $browserVerify "playwright@latest screenshot" "browser-verify.sh should attempt Playwright first."
Assert-Contains $browserVerify "falling back to stub" "browser-verify.sh should log when it falls back to stub mode."
Assert-Contains $browserVerify ".stub.txt" "browser-verify.sh should preserve stub artifact output."

# dev-loop-check.sh invariants
$devLoop = $scriptText["dev-loop-check.sh"]
Assert-Contains $devLoop "set -euo pipefail" "dev-loop-check.sh should enforce strict shell mode."
Assert-Contains $devLoop "red|green|final" "dev-loop-check.sh should support red/green/final phases."
Assert-Contains $devLoop "is_docs_only_change()" "dev-loop-check.sh should include docs-only detection."
Assert-Contains $devLoop "git diff --check" "dev-loop-check.sh docs-only checks should include unstaged diff validation."
Assert-Contains $devLoop "git diff --cached --check" "dev-loop-check.sh docs-only checks should include staged diff validation."
Assert-Contains $devLoop "pnpm-lock.yaml" "dev-loop-check.sh should detect pnpm lockfile."
Assert-Contains $devLoop "package-lock.json" "dev-loop-check.sh should detect npm lockfile."
Assert-Contains $devLoop "AGC_INSTALL_CMD" "dev-loop-check.sh should keep install fallback override."

# setup-workspace.sh invariants
$setup = $scriptText["setup-workspace.sh"]
Assert-Contains $setup "agc::require_repo" "setup-workspace.sh must require TARGET_REPO."
Assert-Contains $setup "agc::require gh" "setup-workspace.sh must require gh."
Assert-Contains $setup "agc::require git" "setup-workspace.sh must require git."
Assert-Contains $setup "refusing to operate on path outside AGC_WORK_ROOT" "setup-workspace.sh must keep AGC_WORK_ROOT safety guard."
Assert-Contains $setup ".git/info/exclude" "setup-workspace.sh should write .git/info/exclude."
Assert-Contains $setup ".auto-pr/" "setup-workspace.sh should ignore .auto-pr metadata."

# scan-quick-wins.sh invariants
$scan = $scriptText["scan-quick-wins.sh"]
Assert-Contains $scan "set +e" "scan-quick-wins.sh should remain best-effort (set +e)."
Assert-Contains $scan 'kind: "typo"' "scan-quick-wins.sh should emit typo quick-wins."
Assert-Contains $scan 'kind: "missing-test"' "scan-quick-wins.sh should emit missing-test quick-wins."
Assert-Contains $scan 'kind: "i18n"' "scan-quick-wins.sh should emit i18n quick-wins."
Assert-Contains $scan 'kind: "todo"' "scan-quick-wins.sh should emit todo quick-wins."
Assert-Contains $scan "!.auto-pr" "scan-quick-wins.sh should continue excluding .auto-pr metadata."
Assert-Contains $scan 'candidate_type: "quick-win"' "scan-quick-wins.sh should tag normalized quick-win candidates."
Assert-Contains $scan "kind_rank" "scan-quick-wins.sh should rank substantive quick-wins before typo fallbacks."
Assert-Contains $scan "fallback_only: true" "scan-quick-wins.sh should tag typos as fallback-only candidates."
Assert-Contains $scan "if (`$substantive | length) > 0 then `$substantive else (`$fallbacks | .[0:2]) end" "scan-quick-wins.sh should cap typo fallbacks when no substantive quick-win exists."

# fetch-issues.sh invariants
$fetch = $scriptText["fetch-issues.sh"]
Assert-Contains $fetch "gh issue list" "fetch-issues.sh must use gh issue list."
Assert-Contains $fetch "unique_by(.number)" "fetch-issues.sh should de-dupe issues by number."
Assert-Contains $fetch "score:" "fetch-issues.sh should produce ranked scores."
Assert-Contains $fetch 'candidate_type: "issue"' "fetch-issues.sh should tag issue candidates."
Assert-Contains $fetch '. == "bug" or . == "bugfix" or . == "security" or . == "ci" then 4' "fetch-issues.sh should prioritize substantive maintenance labels."
Assert-Contains $fetch '. == "documentation" or . == "docs" or . == "typo" then 0' "fetch-issues.sh should demote docs/typo labels during discovery."

# rank-candidates.sh invariants
$rank = $scriptText["rank-candidates.sh"]
Assert-Contains $rank "--issues is required" "rank-candidates.sh must require an issues input path."
Assert-Contains $rank "--quickwins is required" "rank-candidates.sh must require a quickwins input path."
Assert-Contains $rank "merge_probability" "rank-candidates.sh should compute merge_probability."
Assert-Contains $rank "impact_potential" "rank-candidates.sh should compute impact_potential."
Assert-Contains $rank "signal_strength" "rank-candidates.sh should compute substantive signal strength."
Assert-Contains $rank "toy_risk" "rank-candidates.sh should compute toy-risk metadata."
Assert-Contains $rank "recommended_stage" "rank-candidates.sh should emit recommended_stage."
Assert-Contains $rank "tiny-pr-first" "rank-candidates.sh should preserve the tiny-first stage."
Assert-Contains $rank 'if $toy_risk == "high" then "fallback"' "rank-candidates.sh should prevent high toy-risk candidates from tiny-pr-first."
Assert-Contains $rank 'elif $toy_risk == "medium" then "manual-review"' "rank-candidates.sh should require manual review for medium toy-risk candidates."

# create-pr.sh invariants
$createPr = $scriptText["create-pr.sh"]
Assert-Contains $createPr "main|master|develop" "create-pr.sh must keep branch safety guard."
Assert-Contains $createPr "git reset --quiet -- .auto-pr" "create-pr.sh should avoid committing .auto-pr metadata."
Assert-Contains $createPr "gh pr create" "create-pr.sh should open PR via gh."
Assert-Contains $createPr "printf 'PR_URL=%s\n'" "create-pr.sh should emit PR_URL=..."
Assert-Contains $createPr "*.stub.txt" "create-pr.sh should surface browser stub artifacts."

# Ranking fixture regression checks. Run only when bash + jq are available.
$bashCommand = Get-Command bash -ErrorAction SilentlyContinue
$jqCommand = Get-Command jq -ErrorAction SilentlyContinue
if ($bashCommand -and $jqCommand) {
  $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agc-rank-fixture-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
  try {
    $issuesPath = Join-Path $fixtureRoot "issues.json"
    $quickwinsPath = Join-Path $fixtureRoot "quickwins.json"
    $issuesJson = @(
      '[',
      '  {"number": 1, "title": "Fix auth bug", "url": "https://example.test/1", "labels": ["bug"], "score": 4, "updatedAt": "2026-05-10T00:00:00Z", "body": "Real behavior bug."},',
      '  {"number": 2, "title": "Fix README typo", "url": "https://example.test/2", "labels": ["typo"], "score": 9, "updatedAt": "2026-05-10T00:00:00Z", "body": "Typo only."}',
      ']'
    ) -join "`n"
    $quickwinsJson = @(
      '[',
      '  {"kind": "typo", "title": "Typo fallback", "summary": "Fix typo.", "file": "README.md", "line": 1, "estimated_minutes": 5, "slug": "typo-readme"},',
      '  {"kind": "missing-test", "title": "Add missing test", "summary": "Cover module.", "file": "src/client.ts", "line": 1, "estimated_minutes": 30, "slug": "missing-test-client"}',
      ']'
    ) -join "`n"
    Set-Content -LiteralPath $issuesPath -Value $issuesJson -Encoding UTF8
    Set-Content -LiteralPath $quickwinsPath -Value $quickwinsJson -Encoding UTF8

    $rankScript = (Join-Path $scriptsRoot "rank-candidates.sh").Replace("\", "/")
    $issuesArg = $issuesPath.Replace("\", "/")
    $quickwinsArg = $quickwinsPath.Replace("\", "/")
    $rankOutput = & $bashCommand.Source $rankScript --issues $issuesArg --quickwins $quickwinsArg --max 4
    if ($LASTEXITCODE -ne 0) {
      $script:failures.Add("rank-candidates.sh fixture run failed with exit code $LASTEXITCODE.")
    } else {
      $ranked = $rankOutput | ConvertFrom-Json
      Assert-True ($ranked[0].title -eq "Add missing test" -or $ranked[0].title -eq "Fix auth bug") "Ranking fixture should put substantive bug/test candidates before typo fallbacks."
      $typoIssue = $ranked | Where-Object { $_.title -eq "Fix README typo" } | Select-Object -First 1
      Assert-True ($null -ne $typoIssue) "Ranking fixture should include the typo issue for fallback review."
      Assert-True ($typoIssue.recommended_stage -eq "fallback") "Ranking fixture should mark typo issue as fallback, not tiny-pr-first."
      $typoQuickWin = $ranked | Where-Object { $_.title -eq "Typo fallback" } | Select-Object -First 1
      Assert-True ($null -ne $typoQuickWin) "Ranking fixture should include the typo quick-win for fallback review."
      Assert-True ($typoQuickWin.recommended_stage -eq "fallback") "Ranking fixture should mark typo quick-win as fallback, not tiny-pr-first."
    }
  } finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
} else {
  $warnings.Add("Skipped runtime ranking fixture; bash and jq are required.")
}

# PR body template invariants
$prBodyTemplatePath = Join-Path $repoRoot "skills/auto-github-contributor/templates/PR-BODY.template.md"
$prBodyTemplate = Read-File -Path $prBodyTemplatePath
Assert-Contains $prBodyTemplate "Visual verification (screenshots / stubs)" "PR body template should mention both screenshots and stubs."
Assert-Contains $prBodyTemplate "visual artifacts" "PR body template should direct reviewers to visual artifacts."

# Keep this harness deterministic in constrained local environments.
$warnings.Add("Skipped runtime bash -n checks; this harness validates script workflow invariants only.")

if ($warnings.Count -gt 0) {
  foreach ($warning in $warnings) {
    Write-Warning $warning
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "[smoke] FAILED ($($failures.Count) checks)"
  foreach ($failure in $failures) {
    Write-Host " - $failure"
  }
  exit 1
}

Write-Host ""
Write-Host "[smoke] PASS ($($scriptNames.Count) scripts validated)"
exit 0

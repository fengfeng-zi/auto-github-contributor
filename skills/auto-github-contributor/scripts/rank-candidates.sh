#!/usr/bin/env bash
# Merge issue and quick-win discovery output into a single ranked candidate list.
# Emits a JSON array on stdout with normalized fields including:
#   { candidate_type, kind, merge_probability, impact_potential,
#     estimated_minutes, estimated_cost_usd, recommended_stage, ... }
#
# Usage:
#   rank-candidates.sh --issues /tmp/agc-issues.json --quickwins /tmp/agc-quickwins.json [--max <n>]

set -euo pipefail
source "$(dirname "$0")/config.sh"

agc::require jq

ISSUES_JSON=""
QUICKWINS_JSON=""
MAX="${AGC_ISSUE_LIMIT:-30}"

while (($#)); do
  case "$1" in
    --issues) ISSUES_JSON="$2"; shift 2 ;;
    --quickwins) QUICKWINS_JSON="$2"; shift 2 ;;
    --max) MAX="$2"; shift 2 ;;
    *) agc::die "unknown flag: $1" ;;
  esac
done

[[ -n "$ISSUES_JSON" ]] || agc::die "--issues is required"
[[ -n "$QUICKWINS_JSON" ]] || agc::die "--quickwins is required"
[[ -f "$ISSUES_JSON" ]] || agc::die "issues json not found: $ISSUES_JSON"
[[ -f "$QUICKWINS_JSON" ]] || agc::die "quickwins json not found: $QUICKWINS_JSON"

jq -n \
  --arg max "$MAX" \
  --slurpfile issues "$ISSUES_JSON" \
  --slurpfile quickwins "$QUICKWINS_JSON" '
  def rank_value($level):
    if $level == "high" then 3
    elif $level == "medium" then 2
    else 1
    end;

  def estimated_cost($minutes):
    if $minutes <= 10 then 0.30
    elif $minutes <= 30 then 1.50
    elif $minutes <= 45 then 3.00
    else 6.00
    end;

  def issue_minutes($labels):
    ($labels | map(ascii_downcase)) as $labels
    | if ($labels | index("documentation")) or ($labels | index("docs")) or ($labels | index("typo")) then 30
      elif ($labels | index("testing")) or ($labels | index("tests")) or ($labels | index("i18n")) or ($labels | index("l10n")) or ($labels | index("translation")) then 45
      else 90
      end;

  def issue_merge_probability($score; $labels):
    ($labels | map(ascii_downcase)) as $labels
    | if $score >= 7 then "high"
      elif $score >= 5 then "medium"
      elif ($labels | index("good first issue")) or ($labels | index("good-first-issue")) then "medium"
      else "low"
      end;

  def issue_impact($labels):
    ($labels | map(ascii_downcase)) as $labels
    | if ($labels | index("enhancement")) or ($labels | index("feature")) or ($labels | index("help wanted")) then "high"
      elif ($labels | index("testing")) or ($labels | index("tests")) or ($labels | index("documentation")) or ($labels | index("docs")) then "medium"
      else "medium"
      end;

  def quickwin_merge_probability($kind):
    if $kind == "typo" then "high"
    elif $kind == "missing-test" or $kind == "i18n" then "medium"
    else "low"
    end;

  def quickwin_impact($kind):
    if $kind == "todo" then "high"
    elif $kind == "missing-test" or $kind == "i18n" then "medium"
    else "low"
    end;

  def recommended_stage($merge_probability; $estimated_minutes):
    if $merge_probability == "high" and $estimated_minutes <= 30 then "tiny-pr-first"
    elif $merge_probability == "medium" and $estimated_minutes <= 45 then "tiny-pr-first"
    else "follow-up"
    end;

  def normalize_issue:
    . as $issue
    | (issue_minutes($issue.labels)) as $minutes
    | (issue_merge_probability($issue.score; $issue.labels)) as $merge_probability
    | (issue_impact($issue.labels)) as $impact_potential
    | $issue + {
        candidate_type: "issue",
        kind: "issue",
        estimated_minutes: $minutes,
        merge_probability: $merge_probability,
        impact_potential: $impact_potential,
        follow_up_potential: $impact_potential,
        estimated_cost_usd: estimated_cost($minutes),
        recommended_stage: recommended_stage($merge_probability; $minutes)
      };

  def normalize_quickwin:
    . as $quickwin
    | (quickwin_merge_probability($quickwin.kind)) as $merge_probability
    | (quickwin_impact($quickwin.kind)) as $impact_potential
    | $quickwin + {
        candidate_type: "quick-win",
        merge_probability: $merge_probability,
        impact_potential: $impact_potential,
        follow_up_potential: $impact_potential,
        estimated_cost_usd: estimated_cost($quickwin.estimated_minutes),
        recommended_stage: recommended_stage($merge_probability; $quickwin.estimated_minutes)
      };

  (($issues[0] // []) | map(normalize_issue))
  + (($quickwins[0] // []) | map(normalize_quickwin))
  | unique_by([.candidate_type, (.slug // (.number | tostring) // .title)])
  | sort_by(
      (if .recommended_stage == "tiny-pr-first" then 0 else 1 end),
      -rank_value(.merge_probability),
      .estimated_minutes,
      -rank_value(.impact_potential),
      .candidate_type,
      .title
    )
  | to_entries
  | map(.value + { rank: (.key + 1) })
  | .[0:($max | tonumber)]
'

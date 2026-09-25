#!/bin/bash
# =============================================================================
# metrics_utility_report_minimal.sh
# Bare-minimum usage report with metrics-utility on an RPM-based Red Hat Ansible
# Automation Platform 2.6 automation controller node:
#   Organization name, Job runs, managed nodes, Number of task runs
#
# Run on ONE automation controller node, as the awx user:
#   sudo -u awx bash metrics_utility_report_minimal.sh                        # this month so far
#   sudo -u awx bash metrics_utility_report_minimal.sh 2026-09-01 2026-09-30  # SINCE UNTIL (UTC, inclusive)
#
# Output: $SHIP_PATH/reports/YYYY/MM/CCSPv2-<since>--<until>.xlsx (+ .csv of the same sheet)
# Changes nothing on the controller. See ../full/ for the report with every sheet.
# =============================================================================
set -euo pipefail

SINCE=${1:-$(date -u +%Y-%m-01)}
UNTIL=${2:-$(date -u +%F)}
SHIP_PATH=${SHIP_PATH:-/var/lib/awx/metrics-utility-reports}

export METRICS_UTILITY_SHIP_TARGET=directory
export METRICS_UTILITY_SHIP_PATH="$SHIP_PATH"
export METRICS_UTILITY_REPORT_TYPE=CCSPv2                               # case sensitive
export METRICS_UTILITY_OPTIONAL_CCSP_REPORT_SHEETS=usage_by_organizations  # add ",jobs" for per-template rows
export METRICS_UTILITY_OPTIONAL_COLLECTORS=                             # none: only job host summaries are read
export METRICS_UTILITY_PRICE_PER_NODE=0                                 # required by metrics-utility, unused here
export METRICS_UTILITY_REPORT_SKU=N/A
export METRICS_UTILITY_REPORT_COMPANY_NAME="$(hostname -s)"
export METRICS_UTILITY_REPORT_EMAIL=admin@localhost
export METRICS_UTILITY_DISABLE_SAVE_LAST_GATHERED_ENTRIES=true          # leave the scheduling marker alone

[ -r /etc/tower/SECRET_KEY ] || { echo "Run as the awx user: sudo -u awx bash $0" >&2; exit 1; }
mkdir -p "$SHIP_PATH"

# gather --until is EXCLUSIVE (go one day past UNTIL); build_report --until is inclusive
metrics-utility gather_automation_controller_billing_data --ship --since="$SINCE" --until="$(date -u -d "$UNTIL +1 day" +%F)"
metrics-utility build_report --since="$SINCE" --until="$UNTIL" --force

REPORT=$(find "$SHIP_PATH/reports" -name "CCSPv2-${SINCE}--${UNTIL}.xlsx" | head -1)
echo "Report: $REPORT"

# Also save the sheet as CSV and print it (openpyxl ships in the AWX virtualenv)
/var/lib/awx/venv/awx/bin/python - "$REPORT" <<'PY' || echo "(CSV export skipped; open the .xlsx)"
import csv, sys, openpyxl
ws = openpyxl.load_workbook(sys.argv[1])['Usage by organizations']
rows = [['' if c is None else str(c).replace('\n', ' ') for c in r] for r in ws.iter_rows(values_only=True) if any(r)]
out = sys.argv[1][:-5] + '-usage_by_organizations.csv'
with open(out, 'w', newline='') as fh: csv.writer(fh).writerows(rows)
print('CSV:   ', out, '\n'); csv.writer(sys.stdout).writerows(rows)
PY

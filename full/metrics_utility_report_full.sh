#!/bin/bash
# =============================================================================
# metrics_utility_report_full.sh
# Build a full CCSPv2 usage report (per organization, per job template, per host,
# per collection / role / module) with metrics-utility on an RPM-based
# Red Hat Ansible Automation Platform 2.6 automation controller node.
#
# Run on ONE automation controller node, as the awx user (or root):
#   sudo -u awx bash metrics_utility_report_full.sh                        # this month so far
#   sudo -u awx bash metrics_utility_report_full.sh 2026-09-01 2026-09-30  # SINCE UNTIL (UTC, inclusive)
#
# Output (in $SHIP_PATH/reports/YYYY/MM/):
#   CCSPv2-<since>--<until>.xlsx                       full Excel report
#   CCSPv2-<since>--<until>-usage_by_organizations.csv organization, job runs, task runs
#   CCSPv2-<since>--<until>-jobs.csv                   per job template
#
# This is a one-off/on-demand run: it does NOT change controller settings, does NOT
# install anything, and does NOT move metrics-utility's "last gathered" marker.
# =============================================================================
set -euo pipefail

# ---- Settings ---------------------------------------------------------------
SINCE=${1:-$(date -u +%Y-%m-01)}          # first day (UTC), inclusive
UNTIL=${2:-$(date -u +%F)}                # last day (UTC), inclusive
SHIP_PATH=${SHIP_PATH:-/var/lib/awx/metrics-utility-reports}   # where data + reports go

export METRICS_UTILITY_SHIP_TARGET=directory
export METRICS_UTILITY_SHIP_PATH="$SHIP_PATH"
export METRICS_UTILITY_REPORT_TYPE=CCSPv2            # case sensitive
# Every CCSPv2 sheet. Remove names to get a smaller report.
export METRICS_UTILITY_OPTIONAL_CCSP_REPORT_SHEETS=ccsp_summary,jobs,managed_nodes,indirectly_managed_nodes,inventory_scope,infrastructure_summary,usage_by_organizations,usage_by_collections,usage_by_roles,usage_by_modules,data_collection_status,managed_nodes_by_organizations
# Extra data needed by the collection/role/module, inventory and indirect-node sheets
export METRICS_UTILITY_OPTIONAL_COLLECTORS=main_jobevent,main_host,main_host_daily,main_indirectmanagednodeaudit
# Required by the report's "Usage Reporting" (CCSP billing) sheet; not used otherwise
export METRICS_UTILITY_PRICE_PER_NODE=0
export METRICS_UTILITY_REPORT_SKU=${REPORT_SKU:-N/A}
export METRICS_UTILITY_REPORT_COMPANY_NAME=${REPORT_COMPANY_NAME:-"$(hostname -s)"}
export METRICS_UTILITY_REPORT_EMAIL=${REPORT_EMAIL:-"admin@$(hostname -d 2>/dev/null || echo localhost)"}
# On-demand run: leave the scheduled-gather marker (stored in the controller DB) untouched
export METRICS_UTILITY_DISABLE_SAVE_LAST_GATHERED_ENTRIES=true

# ---- Pre-flight checks ------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
command -v metrics-utility >/dev/null || die "metrics-utility not found. Run this on an automation controller node."
[ -r /etc/tower/SECRET_KEY ] || die "cannot read /etc/tower/SECRET_KEY. Run as the awx user: sudo -u awx bash $0"
date -u -d "$SINCE" >/dev/null 2>&1 || die "bad SINCE date: $SINCE (use YYYY-MM-DD)"
date -u -d "$UNTIL" >/dev/null 2>&1 || die "bad UNTIL date: $UNTIL (use YYYY-MM-DD)"
[[ "$SINCE" < "$UNTIL" || "$SINCE" == "$UNTIL" ]] || die "SINCE ($SINCE) is after UNTIL ($UNTIL)"
mkdir -p "$SHIP_PATH" || die "cannot create $SHIP_PATH"
[ -w "$SHIP_PATH" ] || die "$SHIP_PATH is not writable by $(id -un)"

echo "Report period : $SINCE .. $UNTIL (UTC, inclusive)"
echo "Output folder : $SHIP_PATH"
F='pkg_resources|iter_entry_points'   # hide a harmless Python deprecation warning

# ---- 1. Gather (reads the controller database directly, not the API) ---------
# --until is EXCLUSIVE for gather, so go one day past UNTIL
t0=$(date +%s)
metrics-utility gather_automation_controller_billing_data --ship \
  --since="$SINCE" --until="$(date -u -d "$UNTIL +1 day" +%F)" 2>&1 | grep -vE "$F" || true
t1=$(date +%s)

# ---- 2. Build the report (--until is inclusive here) -------------------------
metrics-utility build_report --since="$SINCE" --until="$UNTIL" --force 2>&1 | grep -vE "$F" || true
t2=$(date +%s)
echo "Timing        : gather $((t1-t0))s, report $((t2-t1))s"

REPORT=$(find "$SHIP_PATH/reports" -name "CCSPv2-${SINCE}--${UNTIL}.xlsx" 2>/dev/null | head -1)
[ -n "$REPORT" ] || die "no report produced; check the messages above (e.g. no jobs in the period)"
echo "Report        : $REPORT"

# ---- 3. Export the key sheets to CSV (openpyxl ships in the AWX virtualenv) ---
PY=/var/lib/awx/venv/awx/bin/python
if [ -x "$PY" ] && "$PY" -c 'import openpyxl' 2>/dev/null; then
  "$PY" - "$REPORT" <<'PYCODE'
import csv, sys, openpyxl
report = sys.argv[1]
wb = openpyxl.load_workbook(report)
print('Sheets        :', ', '.join(wb.sheetnames))
for sheet, suffix in (('Usage by organizations', 'usage_by_organizations'), ('Jobs', 'jobs')):
    if sheet not in wb.sheetnames:
        continue
    rows = [['' if c is None else str(c).replace('\n', ' ') for c in r]
            for r in wb[sheet].iter_rows(values_only=True) if any(c is not None for c in r)]
    out = report[:-5] + f'-{suffix}.csv'
    with open(out, 'w', newline='') as fh:
        csv.writer(fh).writerows(rows)
    print(f'CSV           : {out}')
    if suffix == 'usage_by_organizations':
        print()
        csv.writer(sys.stdout).writerows(rows)
PYCODE
else
  echo "(openpyxl not available: skipped CSV export; open the .xlsx instead)"
fi

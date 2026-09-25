# AAP usage reporting with metrics-utility (AAP 2.6, RPM install)

Get **job runs and task runs per organization** from Red Hat Ansible Automation Platform in
seconds, using `metrics-utility`, the reporting tool that is already installed on every
automation controller node. There are no API calls, nothing to install, and nothing changes
on the platform.

There are two versions. Both run the same way; they differ only in how much the report contains.

| | **Minimal** (`minimal/`) | **Full** (`full/`) |
|---|---|---|
| Answers | Job runs and task runs per organization | Everything metrics-utility can report |
| Report sheets | 1: *Usage by organizations* | 15: organizations, job templates, hosts, collections, roles, modules, inventories, … |
| Data read | Job host summaries only | Job host summaries + job events + host inventory |
| Load on the database | Lowest | Higher: job events are the biggest table |
| Output | `.xlsx` + `.csv` | `.xlsx` + 2 `.csv` (organizations, job templates) |
| Use it when | You only need the per-organization totals | You want the full picture, e.g. content usage or per-host detail |

**Not sure which one? Start with minimal.**

---

## What's in this repo

```
minimal/
  metrics_utility_report_minimal.sh                 <- the minimal script
  sample-min-CCSPv2-...xlsx / ...csv                <- example output
full/
  metrics_utility_report_full.sh                    <- the full script
  sample-full-CCSPv2-...xlsx / ...-usage_by_organizations.csv / ...-jobs.csv   <- example output
README.md
```

The samples come from a small lab and have been sanitized: `example.com`, `192.0.2.x` addresses,
and demo organizations Acme / Globex / Initech.

---

## Requirements

- An **RPM-based AAP 2.6** installation.
- Shell access to **one automation controller node** (not the gateway, hub or EDA node).
- `sudo` rights to run commands as the **`awx`** user. The tool must read `/etc/tower/SECRET_KEY`.

That's all. `metrics-utility` ships with automation controller. No installer re-run,
configuration change or restart is needed.

---

## How to run it

The steps are the same for both scripts; only the file name differs.

**1. Copy the script to one automation controller node**
```bash
scp minimal/metrics_utility_report_minimal.sh <controller-node>:/tmp/
# or
scp full/metrics_utility_report_full.sh       <controller-node>:/tmp/
```

**2. Log in to that node and confirm the tool is there**
```bash
command -v metrics-utility          # should print a path, e.g. /usr/bin/metrics-utility
```

**3. Run it as the `awx` user, giving the first and last day you want**
```bash
sudo -u awx bash /tmp/metrics_utility_report_minimal.sh 2026-09-01 2026-09-30
# or
sudo -u awx bash /tmp/metrics_utility_report_full.sh    2026-09-01 2026-09-30
```
- Dates are `YYYY-MM-DD`, in **UTC**, and **both days are included**.
- Without dates, it reports **the current month so far**.

**4. Get the results**

Files are written to `/var/lib/awx/metrics-utility-reports/reports/<YYYY>/<MM>/`:

| File | Minimal | Full |
|---|:-:|:-:|
| `CCSPv2-<first>--<last>.xlsx`: the Excel report | ✓ | ✓ |
| `CCSPv2-<first>--<last>-usage_by_organizations.csv` | ✓ | ✓ |
| `CCSPv2-<first>--<last>-jobs.csv`: one row per job template | | ✓ |

The organization table is also printed on screen at the end of the run.

To save the files somewhere else, pass `SHIP_PATH`. The folder must be writable by `awx`:
```bash
sudo -u awx env SHIP_PATH=/data/aap-usage bash /tmp/metrics_utility_report_minimal.sh 2026-09-01 2026-09-30
```

---

## What to expect

**Run time.** In our lab, a 25-day report took about **6 seconds to gather and 6 seconds to
build**. Larger installations take longer, but it's still a few direct database queries, not
thousands of API calls.

**Screen output.** Progress lines, then the result. Lines like
`Skipping ... because it is not enabled` are **normal**. They're optional data sources that
the report doesn't use.

```
Progress info: Now gathering job_host_summary
Analytics collected
Report generated into directory: /var/lib/awx/metrics-utility-reports/reports/2026/09/CCSPv2-2026-09-01--2026-09-25.xlsx
Report: /var/lib/awx/metrics-utility-reports/reports/2026/09/CCSPv2-2026-09-01--2026-09-25.xlsx
CSV:    /var/lib/awx/metrics-utility-reports/reports/2026/09/CCSPv2-2026-09-01--2026-09-25-usage_by_organizations.csv

Organization name,Job runs,Unique managed nodes automated,Non-unique managed nodes automated,Number of task runs
Acme Corp,92,4,181,2456
Globex Inc,106,4,210,2942
Initech LLC,26,4,36,551
Lab Operations,156,1,156,1737
```

**Sheets in the full report**

| Sheet | What it shows |
|---|---|
| **Usage by organizations** | Per organization: job runs, managed nodes, task runs. *This is also the minimal report* |
| **Jobs** | Per job template: organization, job runs, managed nodes, task runs, first and last run |
| Managed nodes | Per host: job runs, task runs, first and last automation |
| Usage by collections | Per Ansible collection: managed nodes, task runs, total task duration |
| Usage by roles | Per role. Tasks not in a role are grouped as "No role used" |
| Usage by modules | Per module, e.g. `ansible.builtin.copy`: managed nodes, task runs, duration |
| Inventory Scope | Every host in any inventory, with its organizations and inventories |
| One sheet per organization | The hosts each organization automated |
| Indirectly Managed nodes, Infrastructure Summary | Devices managed through a cloud or network API. Empty if you have none |
| Data collection status | What data was collected and for which time range |
| Usage Reporting | A billing form for Red Hat's CCSP partner program. **Ignore it**: it's mostly blank with $0 prices |

---

## How the numbers are counted

| Column | Meaning |
|---|---|
| **Job runs** | Number of jobs that ran against at least one reachable host |
| **Number of task runs** | One task result on one host, counting ok, failed, skipped, unreachable, ignored and rescued. **A playbook with 10 tasks run on 5 hosts counts 50** |
| **Unique managed nodes automated** | Distinct hosts automated |
| **Non-unique managed nodes automated** | Every host in every job; one host in 3 jobs counts 3 |

In the full report, the **collection, role and module** sheets count task activity in a
different way and show **higher** totals than the organization sheet. For "total tasks per
organization", use **Usage by organizations** or **Jobs**.

---

## Before you rely on the numbers

1. **Compare with your current method once.** If your existing scripts count a "task"
   differently, e.g. per playbook instead of per host, the totals won't match. Run both for
   the same month and compare before switching.
2. **Only job history still in the database is reported.** The *Cleanup Job Details*
   management job regularly deletes old job data. Jobs older than your retention period
   can't be reported.
3. **Run it on one controller node only.** All nodes share one database, so running on
   several nodes collects the same data more than once.
4. **The first run over a long period is the heaviest.** For several months of history on a
   large installation, run it outside business hours. The full script reads more data than the
   minimal one.
5. **The scripts don't affect scheduled reporting.** They set
   `METRICS_UTILITY_DISABLE_SAVE_LAST_GATHERED_ENTRIES=true`, so the marker that a scheduled
   setup relies on is left alone.
6. **One gather covers at most 28 days.** metrics-utility quietly cuts a longer range short and
   logs `End of the collection interval is greater than 28 days from start`. The scripts
   handle this by gathering in 28-day chunks. Keep it in mind if you run
   `metrics-utility` by hand.

---

## Why this is better than collecting the data through the API

- **Speed.** Seconds to minutes instead of hours.
- **Low impact.** It reads the database directly with a few bulk queries, so there's no API,
  web or authentication traffic competing with users and running jobs.
- **Consistent.** These are the same counts Red Hat uses for usage reporting. In our lab they
  matched the controller database exactly.
- **Supported.** It ships with automation controller and is maintained by Red Hat.

---

## Optional: run it automatically every month

Set this up after a successful test run. Red Hat's documented pattern is to gather data every
hour and build the report once a month.

1. Create `/var/lib/awx/metrics-utility.env`, owned by `awx`. This example uses the minimal
   set; for the full report, copy the two `OPTIONAL_*` lines from the full script instead:
   ```bash
   export METRICS_UTILITY_SHIP_TARGET=directory
   export METRICS_UTILITY_SHIP_PATH=/var/lib/awx/metrics-utility-scheduled
   export METRICS_UTILITY_REPORT_TYPE=CCSPv2
   export METRICS_UTILITY_OPTIONAL_CCSP_REPORT_SHEETS=usage_by_organizations,jobs
   export METRICS_UTILITY_OPTIONAL_COLLECTORS=
   export METRICS_UTILITY_PRICE_PER_NODE=0
   export METRICS_UTILITY_REPORT_SKU=N/A
   export METRICS_UTILITY_REPORT_COMPANY_NAME="Your Company"
   export METRICS_UTILITY_REPORT_EMAIL=you@example.com
   ```
   Don't add `METRICS_UTILITY_DISABLE_SAVE_LAST_GATHERED_ENTRIES` here. Scheduled gathering
   depends on that marker.
2. **Collect history once**, from the first day you want onward. This also sets the starting
   point for the hourly runs:
   ```bash
   sudo -u awx bash -c '. /var/lib/awx/metrics-utility.env && metrics-utility gather_automation_controller_billing_data --ship --since=2026-10-01 --until=10m'
   ```
   One gather covers at most 28 days. To go back further, run it once per 28 days, oldest first,
   e.g. `--since=2026-08-01 --until=2026-08-29`, then `--since=2026-08-29 --until=2026-09-26`,
   and so on, finishing with `--until=10m`.
3. **Add the schedule** with `sudo crontab -u awx -e`:
   ```
   5 * * * *  . /var/lib/awx/metrics-utility.env && metrics-utility gather_automation_controller_billing_data --ship --until=10m >/dev/null 2>&1
   0 4 2 * *  . /var/lib/awx/metrics-utility.env && metrics-utility build_report >/dev/null 2>&1
   ```
   - The first line collects new data every hour, continuing from where the last run stopped.
   - The second builds **last month's** report at 04:00 on the 2nd of each month, in
     `/var/lib/awx/metrics-utility-scheduled/reports/<YYYY>/<MM>/`.
   - Hourly collection keeps its own copy of the data, so reports still work after the
     controller's cleanup job has removed old job history.
4. Delete old reports from that folder from time to time.

**Use a separate folder for the schedule.** Don't reuse the test folder: its data would be
counted twice.

---

## Cleanup after testing

```bash
sudo rm -rf /var/lib/awx/metrics-utility-reports /tmp/metrics_utility_report_*.sh
```
Nothing else on the system was changed.

---

## Troubleshooting

| Message | What to do |
|---|---|
| `Run as the awx user` / `cannot read /etc/tower/SECRET_KEY` | Run with `sudo -u awx bash ...` |
| `metrics-utility: command not found` / `metrics-utility not found` | You're not on an automation controller node |
| `No billing data for input date range` | No jobs ran in that period, or they've already been cleaned up |
| `Invalid METRICS_UTILITY_REPORT_TYPE` | The value must be exactly `CCSPv2` (case-sensitive) |
| `Permission denied` on the output folder | Use a folder the `awx` user can write to (see `SHIP_PATH` above) |

---

## References (AAP 2.6)

- [Red Hat Ansible Automation Platform 2.6: metrics-utility](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/observe-assembly_metrics_utility)
- [Turning Automation into Insights: Ansible's metrics-utility (Red Hat article)](https://access.redhat.com/articles/7127789)

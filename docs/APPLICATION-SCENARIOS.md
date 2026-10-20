# Application scenarios

Read [Current lab setup](CURRENT-SETUP.md) for the baseline apps, dependencies and test commands.

Use local feature branches. All versions, credentials and addresses are fictional.
Check your branch and save existing work first. Start from the branch containing
these additions, feature/offline-dta-stg-prd; main/develop do not contain them until
explicitly promoted. Nothing here requires a network, live cluster or Git push.

## 1. Upgrade identity without losing data

Files: base/identity/values.yaml, the environment identity/values.yaml,
local-sources/DockerFiles/identity/Dockerfile, inventory/<ENV>/images.json.

- Compare DTA/STG image 2.1.0-lab with PRD image 2.0.0-lab.
- The image inventory records build_args.APP_VERSION; an output tag alone does not
  update the Dockerfile's upstream image. Preserve required customizations.
- The identity schema plan records currentVersion, requiredVersion, migration.enabled
  and migration.targetVersion. It is an exercise declaration, not observed DB state.
- Try disabling migration in DTA, which requires schema 2 but declares current schema 1.
  Run ruby scripts/lab.rb check DTA identity. Explain the diagnostic and restore the plan.
- For PRD upgrade planning, prepare the target image, image inventory/build args,
  schema requirement and migration plan together. The chart version is separate.
- Run the local data exercise below before describing recovery.

```sh
python3 scripts/migrate-demo.py init
python3 scripts/migrate-demo.py status
python3 scripts/migrate-demo.py upgrade --to 2
python3 scripts/migrate-demo.py status
python3 scripts/migrate-demo.py restore
```

Schema 1 has a demo account. Schema 2 adds its email while preserving the account.
Verify the original record survives. Restore returns to the pre-v2 schema/data.
Trying upgrade --to 1 after reaching version 2 fails deliberately: a version-number
revert is not a database rollback. These are local SQLite operations only. The
fictional Kubernetes Job neither runs SQLite nor proves production sequencing.

## 2. Upgrade releasehub's cache dependency

Files: local-sources/HelmCharts/service-stack/Chart.yaml, Chart.lock,
charts/demo-cache-1.0.0.tgz, and the sibling demo-cache source chart.

- In Chart.yaml find demo-cache, alias cache, condition cache.enabled, version 1.0.0.
- In the parent values inspect cache.enabled and cache.image.tag.
- releasehub enables and requires cache. Disable it and run the focused DTA check;
  restore it after explaining why the app needs its Service.
- Change a harmless label in the sibling demo-cache source chart. Render DTA
  releasehub. The bundled dependency remains unchanged until deliberately rebuilt.
- For an upgrade exercise, choose fictional dependency chart 1.1.0 and image 0.9.0.
  Update the child metadata/defaults, parent dependency version, parent cache image
  override and the DTA image inventory. Bump the parent chart to 2.1.0.
- Only for this explicit dependency exercise, rebuild this new parent:

```sh
helm dependency build local-sources/HelmCharts/service-stack --skip-refresh
ruby scripts/lab.rb check DTA releasehub
```

This uses file:// dependencies only. Do not rebuild the original charts/platform.
To practice STG promotion, package the new parent into offline-cache, append its
new chart inventory entry (retain versions still selected by other apps), update
releasehub STG's chart targetRevision, and inventory the selected cache image.
The existing 2.0.0 archive stays available to identity/searchbox and PRD.
Explain which changes affect DTA only, one STG app, or all consumers of shared values.

## 3. Change a scheduled task

Files: base/scheduler/values.yaml and clusters/<ENV>/lab/local/scheduler/values.yaml.

- STG runs every five minutes; PRD runs at the top of each hour.
- Change only STG to every ten minutes (*/10 * * * *).
- Check timeZone, concurrencyPolicy and suspend before rendering.
- Run ruby scripts/lab.rb check STG scheduler.
- Try an invalid schedule and explain the diagnostic. The checker verifies field
  count and concurrency values, not the full Kubernetes cron grammar.
- Prepare an image-only worker upgrade and matching image inventory change.

Runtime follow-up would examine actual Jobs, missed schedules, overlap and logs.
A successful CronJob render does not prove a task ran or completed.

## 4. Change searchbox storage or release settings

Files: searchbox Application, values, pv.yaml, pvc.yaml and service-stack templates.

- Identify the StatefulSet, its serviceName, the headless Service and PVC reference.
- Compare DTA/STG/PRD PV names, selectors and export paths.
- Break a PVC selector and use the focused check to locate the problem.
- Plan a storage migration to a newly named PV/PVC rather than assuming an existing
  PV's NFS server/path can be patched. Include data copy/consistency, downtime,
  validation and recovery in the plan. No actual NFS is available in this lab.
- Keep the workload reference and inventory aligned when preparing an image update.

StatefulSet identity is not backup, replication, application-level clustering or HA.

## 5. Combined incident: upgrade failed

Have a reviewer introduce one fault on a local branch: a wrong image tag, missing
inventory entry, mismatched Service reference, invalid scheduler policy, disabled
required cache or missing schema migration plan. You should:

1. Identify app, environment and declared source revision.
2. Reproduce with the focused check; inspect freshly rendered output.
3. Trace the owning file/field and distinguish cause from symptoms.
4. Make the smallest correction; inspect the complete diff.
5. State runtime validation that remains unavailable.

## Use agents economically

Give one agent one app and one symptom. Ask for inspection first and a focused diff.
Require AGENTS.md plus docs/OFFLINE-LAB.md as context. Do not ask it to review every
app or start cluster infrastructure for a single values change. A second reviewer
can check scope, inventory consistency and recovery assumptions without editing.

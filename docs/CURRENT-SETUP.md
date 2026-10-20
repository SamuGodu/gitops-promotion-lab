# Current lab setup

Snapshot: **16 October 2026**, from the working files on
`feature/offline-dta-stg-prd`. Recheck with `inventory` after making changes.

This guide covers the six fictional apps in **DTA, STG and PRD**. The older
development/production exercises are described separately below.

## 1. Start here

Open a terminal in the original repository:

```sh
cd /Users/samuelzambrano/DevOps-Lab/18-proyects/gitops-promotion-lab
ruby scripts/lab.rb check
ruby scripts/lab.rb inventory
```

`check` verifies all **18 app/environment combinations**. `inventory` shows the
chart, selected image, workload, branch declaration and sync policy for each one.
Both write YAML to the ignored `rendered/<ENV>/<app>.yaml` folder.

This is a local configuration lab. Its Git, registry, database, storage and route
addresses are fictional. The commands render files; they do not deploy apps,
download images, run Argo CD or contact a cluster. No real app is running as a
result of these commands.

## 2. The overall hierarchy

```text
clusters/<ENV>/lab/local/apps/<app>.yaml       Argo CD Application
  |
  +-- Helm chart                             How to build workload YAML
  |     +-- Chart.yaml                       Chart version and dependencies
  |     +-- templates/                       Deployment, Service, Job, etc.
  |     +-- values.yaml                      Chart defaults
  |           -> base/<app>/values.yaml       Shared app settings
  |           -> clusters/<ENV>/lab/local/<app>/values.yaml
  |                                          Environment overrides
  |
  +-- clusters/<ENV>/lab/local/<app>/kustomization.yaml
        +-- base/<app>/                      Shared ExternalSecret resource
        +-- patch                           Environment secret key
        +-- pv.yaml + pvc.yaml + route.yaml  Except scheduler
  |
  +-- Combined desired manifests             Written under rendered/
```

| Term | Meaning in this lab |
| --- | --- |
| Application | The instructions Argo CD would use: sources, versions, values and destination. |
| Base | Settings or resources shared by one app across environments. |
| Overlay | One environment's values, extra resources and patches. |
| Kustomization | A file listing which Kubernetes resources to combine and patch. |
| Helm chart | A package containing templates, defaults and chart metadata. |
| Template | A YAML pattern filled with values to produce a Kubernetes resource. |
| Dependency | Another chart or resource that an app needs, such as cache, storage or a Secret. |
| Render | Produce the final YAML locally, without applying it. |

The Helm and Kustomize paths are combined. Kustomize does **not** merge the Helm
values files here; Helm does that. Also, `base/<app>/kustomization.yaml` includes
the ExternalSecret, while `base/<app>/values.yaml` is read separately by Helm.

## 3. What differs between environments

| Setting | DTA | STG | PRD |
| --- | --- | --- | --- |
| Declared Git branch | `develop` | `develop` | `main` |
| Declared sync | Manual | Automated | Automated |
| Chart input | Editable local chart folder | Saved chart package | Saved chart package |
| Namespace example | `workboard-dta` | `workboard-stg` | `workboard-prd` |

STG/PRD declare `prune: true` and `selfHeal: true`: a real Argo CD controller
would remove managed resources deleted from Git and correct drift. There is no
controller behind this offline exercise. `CreateNamespace=true` is also only a
declaration here.

The local renderer **always reads your current checkout**, including uncommitted
edits. It does not fetch `develop` or `main`, switch branches or simulate sync.
The branch columns above describe the Application files, not separate Git views.

`lab/local` is just a folder grouping. DTA represents a separate pretend cluster;
STG/PRD represent a shared pretend cluster with different namespaces. PV names
must also differ because PVs are cluster scoped.

## 4. Where versions come from

| What you want | Where to look | Example |
| --- | --- | --- |
| Selected packaged chart | Application source containing `chart` and `targetRevision` | `service-stack`, `2.0.0` |
| Local chart version | The selected local chart's `Chart.yaml`, field `version` | `2.0.0` |
| Chart's app metadata | `Chart.yaml`, field `appVersion` | `2.1.0` |
| Selected application image | Final rendered workload's `image` | `registry.example.invalid/identity:2.1.0-lab` |
| Image preparation entry | `inventory/<ENV>/images.json`, `source_repo` and `tag` | Identity image and build arguments |
| Saved chart location | `inventory/<ENV>/charts.json`, `offline_package` | `offline-cache/service-stack-2.0.0.tgz` |
| Git branch | Application source containing the Git URL and `targetRevision` | `develop` or `main` |

Chart version and app version are separate numbers. These charts use `appVersion`
as an image-tag fallback when `image.tag` is empty; the app values currently set
explicit tags. The rendered image is therefore the best evidence of the selected
version. `appVersion` alone does not prove compatibility or a running version.
Inventory entries list prepared references; they do not prove an image exists.

**Values order: chart defaults → shared app values → environment values.**
For the same setting, the later file wins. A PRD override can therefore prevent a
shared base change from changing PRD.

Example: [workboard's shared tag](../base/workboard/values.yaml) is `1.4.2`, but
[PRD's values](../clusters/PRD/lab/local/workboard/values.yaml) set `1.4.1`.
PRD renders `1.4.1`. An STG-only change belongs in STG's values file.

## 5. Application and dependency catalog

All main images use `registry.example.invalid/<app>:<tag>`.

| App | Chart / chart version | Chart appVersion | DTA / STG image tag | PRD image tag |
| --- | --- | --- | --- | --- |
| workboard | demo-web / 1.0.0 | 1.4.2 | 1.4.2 | 1.4.1 |
| notebook | demo-web / 1.0.0 | 1.4.2 | 1.4.2 | 1.4.1 |
| releasehub | service-stack / 2.0.0 | 2.1.0 | 2.1.0 | 2.0.0 |
| identity | service-stack / 2.0.0 | 2.1.0 | 2.1.0-lab | 2.0.0-lab |
| scheduler | demo-worker / 1.0.0 | 3.2.0 | 3.2.0 | 3.1.0 |
| searchbox | service-stack / 2.0.0 | 2.1.0 | 2.1.0 | 2.0.0 |

| App | Workload | Replicas DTA / STG / PRD | Dependencies and extra resources |
| --- | --- | --- | --- |
| workboard | Deployment | 1 / 1 / 2 | Database reference, ExternalSecret, Service, HTTPRoute, PV/PVC. |
| notebook | Deployment | 1 / 1 / 2 | Same resources as workboard; useful for secret and storage tests. |
| releasehub | Deployment | 1 / 1 / 2 | Common web resources plus required cache Deployment and Service. |
| identity | Deployment | 1 / 1 / 2 | Common web resources, schema-plan ConfigMap, migration Job in DTA/STG. |
| scheduler | CronJob | Scheduled Jobs | ExternalSecret only; no Service, HTTPRoute or PV/PVC. |
| searchbox | StatefulSet | 1 / 1 / 1 | Database reference, ExternalSecret, headless Service, HTTPRoute, PV/PVC. |

### workboard and notebook

Both use [demo-web](../local-sources/HelmCharts/demo-web). A Deployment describes
the app Pods; a Service provides their stable internal endpoint. Use workboard
for image, memory and route changes; use notebook for secret and PVC exercises.
Neither chart installs a database.

### releasehub and its cache

[Shared releasehub values](../base/releasehub/values.yaml) set `cache.enabled: true`
and `cacheRequired: true`. Disabling cache makes Helm fail deliberately.
The app receives `CACHE_SERVICE=releasehub-cache`.

The dependency is **demo-cache chart 1.0.0**, aliased as `cache`, with image
`registry.example.invalid/demo-cache:0.8.0`. It renders one cache Pod replica and a
Service on port `6379` in every environment. It has no PVC or declared resource
requests/limits. The other service-stack apps leave cache disabled, even though
the dependency still appears in chart metadata and inventory summaries.

### identity and migration

[The Dockerfile](../local-sources/DockerFiles/identity/Dockerfile) uses
`APP_VERSION` to select a fictional upstream identity image. The image inventory
records that build input: `2.1.0` in DTA/STG, `2.0.0` in PRD. The output tags add
`-lab`. Changing the output tag does not automatically change the build input;
the lab does not build an image.

| Schema-plan setting | DTA / STG | PRD |
| --- | --- | --- |
| Declared current schema | 1 | 1 |
| Schema required by the app | 2 | 1 |
| Migration enabled | true | false |
| Migration target | 2 | 2, unused while disabled |

DTA/STG render Job `identity-migrate-v2`, using
`registry.example.invalid/schema-tool:1.0.0` and the database Secret. The schema
ConfigMap is a plan, not a database measurement. The ordinary Job has no hooks or
sync waves to guarantee it runs before the app; it has no declared resource limits.
The separate SQLite exercise below performs the actual local data migration.

### scheduler

[Environment values](../clusters/STG/lab/local/scheduler/values.yaml) control the
schedule, time zone, overlap policy and suspension. DTA/STG use `*/5 * * * *`
(every five minutes); PRD uses `0 * * * *` (at the start of every hour).
All use `Etc/UTC`, `concurrencyPolicy: Forbid` and `suspend: false`.

`Forbid` would prevent overlapping Jobs from this CronJob. Its sample command only
echoes a message. It references a database password Secret but has no database URL
or real task implementation. Offline rendering does not run the schedule.

### searchbox

[Shared values](../base/searchbox/values.yaml) select `workload.kind: StatefulSet`.
The headless Service and matching `serviceName` teach stable Pod identities.
The workload uses the existing `app-data` claim; there is no per-replica claim
template. Keep its single replica for the baseline. StatefulSet does not itself
provide application replication, high availability or a backup.

## 6. Shared supporting resources

### Database and secrets

The five web apps receive a fictional `DATABASE_URL` such as
`postgres://database-stg.example.invalid:5432/workboard`. No PostgreSQL chart,
database server or database data is created by their manifests.

All six apps follow this Secret chain:

```text
base/<app>/external-secret.yaml
  -> overlay patches remoteRef.key to <app>-<env>-password
  -> ExternalSecret would create Secret app-db, key password
  -> workload reads app-db/password as DATABASE_PASSWORD
```

The referenced `ClusterSecretStore` is `fictional-store`; it and the external
secret controller/provider are absent. No real password is included. Identical
Secret names are isolated by namespaces such as `notebook-dta` and `notebook-prd`.

### Storage

Every app except scheduler has a static **1Gi**, **ReadWriteMany** PV/PVC pair.
The PV is `<app>-<env>-pv`; the PVC is `app-data`. Labels `app` and `environment`
connect them, with an empty storage class. The workload mounts the claim at `/data`.
The NFS server is `storage-<env>.example.invalid`, export `/practice/<app>`.

`Retain` asks Kubernetes to retain storage after claim release; it is not a backup.
The lab checks references, not NFS availability or mount success. Backend migration
needs a data-copy and recovery plan, not just a different endpoint in YAML.

### Routing

Every app except scheduler has this route:

```text
<app>-<env>.example.invalid
  -> HTTPRoute app-route, parent lab-gateway in namespace lab-gateway
  -> listener https -> Service <app>:8080 -> container port http:8080
```

DNS, the Gateway, listener, TLS certificates and controllers are not supplied.
The checker verifies the route's Service name and port, not HTTPS reachability.
Searchbox's Service is headless (`clusterIP: None`).

### CPU and memory

| Main workload | CPU request / limit | Memory request DTA / STG / PRD | Memory limit |
| --- | --- | --- | --- |
| Five web apps | 25m / 200m | 32Mi / 64Mi / 96Mi | 128Mi |
| scheduler | 25m / 100m | 32Mi / 32Mi / 32Mi | 128Mi |

Requests describe scheduling needs; limits cap usage. These are small teaching
values, not measured sizing recommendations. The cache and migration Job are
outside this table and have no declared resource requests/limits.

## 7. Local charts versus saved packages

There are three distinct copies to recognize:

1. **Editable source:** `local-sources/HelmCharts/`. DTA reads the selected parent
   chart here, so edits can affect every DTA app using that chart.
2. **Bundled dependency:** `service-stack/charts/demo-cache-1.0.0.tgz` under that
   source directory. Editing the sibling demo-cache source does not update it.
3. **Saved parent release:** `offline-cache/service-stack-2.0.0.tgz` and the other
   parent archives. STG/PRD resolve these through their chart inventories.

Editing local templates does not update a saved parent release. Shared base or
environment values are still read from the working tree for every environment.
Changing a chart default also has no effect when a later values file overrides it.

For a deliberate dependency upgrade, update child and parent versions/values,
rebuild the new local dependency bundle, test DTA, then create a new parent package
and update only the chosen environment's Application and inventories. Retain old
packages still selected by other apps. Follow [scenario 2](APPLICATION-SCENARIOS.md)
for the commands; ordinary checks do not rebuild or download dependencies.

## 8. Run tests and read the result

Tools: Ruby standard library, Helm 3 and kubectl with Kustomize; Python 3 standard
library for SQLite tests. No Docker daemon, package installation or cluster is
needed. The renderer passes Kubernetes version `1.30.0` to Helm for templating;
this is not a detected server version or a full API compatibility check.

This snapshot was checked with Ruby 2.6.10, Helm 3.22.0, kubectl 1.36.1
(Kustomize 5.8.1) and Python 3.9.6. These are the tools used, not minimum versions.

| Command, from the repository root | Purpose |
| --- | --- |
| `ruby scripts/lab.rb check` | Render and check all 18 combinations. |
| `ruby scripts/lab.rb check STG identity` | Check just one app/environment. |
| `ruby scripts/lab.rb inventory STG releasehub` | Show selected versions and metadata; also checks and saves YAML. |
| `ruby scripts/lab.rb render PRD scheduler` | Produce YAML without running reference checks. |
| `ruby scripts/test-lab.rb` | Run behavioral tests that introduce faults in disposable copies. |
| `python3 scripts/test-migrations.py` | Test migration, data preservation, restore and failed-migration rollback in temporary databases. |

Snapshot results: all 18 app/environment checks, 14 behavioral checks and four
migration tests passed. The original two Kustomize renders, two Helm renders and
two Helm lint checks also passed. Helm's optional icon recommendation is informational.

Open `rendered/STG/identity.yaml` after a successful focused check. If a check fails,
an older rendered file may still exist. `render` can help inspect a broken
configuration, but it bypasses the checker and can itself fail on template errors.

The checker covers image inventory entries, namespaces, Secret references, route
and Service links, cache references, workload PVC references, PV label/class/mode
matching and schema plans. The full check also catches duplicate STG/PRD PV names.
Cron validation checks five fields and the concurrency enum, not full cron syntax.

A pass does not prove image availability, database connectivity, PVC capacity or
mounting, API admission, resource sizing, migration ordering or workload health.
The inventory shows the main image; inspect rendered YAML for cache and Job images.

### Try the real local data exercise

```sh
python3 scripts/migrate-demo.py status
python3 scripts/migrate-demo.py init
python3 scripts/migrate-demo.py upgrade --to 2
python3 scripts/migrate-demo.py status
python3 scripts/migrate-demo.py restore
```

Start from a new demo database or schema 1. Files stay under
`rendered/migrations/`: `identity.sqlite` and numbered backups. Version 1 creates
one demo account; version 2 adds its email without deleting the account. Each
migration is transactional. Before version 2, the script saves a backup; restore
uses the latest pre-v2 backup and also saves the current database first.

`init` selects schema 1 and refuses to downgrade an existing schema 2 database;
use restore after a completed upgrade. This script neither runs the Kubernetes
Job nor updates the schema-plan YAML. Changing an image tag cannot undo schema
changes. See [scenario 1](APPLICATION-SCENARIOS.md) for the full exercise.

## 9. Find the file for a change or failure

| Change or symptom | Start here |
| --- | --- |
| One environment's tag, replicas, memory or schedule | `clusters/<ENV>/lab/local/<app>/values.yaml` |
| Shared setting across environments | `base/<app>/values.yaml`; check later overrides. |
| Packaged chart version or wrong destination | `clusters/<ENV>/lab/local/apps/<app>.yaml` |
| Missing chart package | Same Application plus `inventory/<ENV>/charts.json` and `offline-cache/`. |
| Image missing from inventory | Effective image values plus `inventory/<ENV>/images.json`. |
| Identity custom image inputs | Its Dockerfile and the inventory's `build_args.APP_VERSION`. |
| Required cache disabled | Releasehub values and service-stack's dependency/condition. |
| Unresolved secret/database placeholder | Overlay `kustomization.yaml` patch or environment database URL. |
| Route points nowhere | Overlay `route.yaml`, then rendered Service and container ports. |
| PVC selector mismatch | Overlay `pvc.yaml` selectors and `pv.yaml` labels. |
| Schema requirement fails | Identity environment `schema` and `migration` values. |
| Template edit absent in STG/PRD | The selected saved package, not just editable source. |

Begin with a [small ticket](EXERCISES.md), then try the
[migration, dependency and StatefulSet scenarios](APPLICATION-SCENARIOS.md).
Predict the effect, edit one cause, run a focused check, inspect the diff, then run
the full check to catch effects on other apps/environments.

## 10. Original development/production exercises

These remain a separate part of the repository:

| Component | Location and purpose |
| --- | --- |
| Kustomize podinfo | `base/podinfo/` plus `clusters/development/podinfo/` and `clusters/production/podinfo/`; namespace `podinfo`, replicas 1 / 2. |
| Helm platform | `charts/platform/`, chart 0.3.0; namespace `podinfo-helm`, releases `platform-dev` / `platform-prod`. |
| Platform dependencies | podinfo-helm, storage-demo and resource-demo, each chart 0.1.0. Development enables all three; production enables podinfo only. |
| Workload images | Podinfo 6.14.1, storage-demo busybox 1.36.1, resource-demo python 3.13-alpine in the current renders. |
| Argo CD definitions | `clusters/development/apps/`, `clusters/production/apps/` and parents under `argocd/app-of-apps/`. |

The storage demo uses a 128Mi ReadWriteOnce claim with class `standard`. The
resource demo teaches CPU/memory scenarios. Its currently selected `idle` scenario
does not allocate its configured 96Mi workload amount. Platform uses packaged
child dependencies, which can differ from their editable sibling source charts.

Original parents declare auto-sync; their child apps omit it. This differs from
the new DTA/STG/PRD policies. The new apps are **not wired into those parents**.
See [the original overview](../README.md) and [agent guidance](../AGENTS.md).

## 11. Preserve the practice baseline

At the time of this snapshot, these additions are uncommitted on
`feature/offline-dta-stg-prd`; `develop` and `main` do not contain them yet.
Check `git status` and save the intended lab files on that branch before
branch-switching or promotion exercises. Stage only intended files, keeping
existing agent guidance and unrelated work.

Rendering uses the current checkout, so a local PRD preview is not evidence that
`main` contains the change. All exercises can stay local; none of the commands in
this guide push Git changes or synchronize a live application.

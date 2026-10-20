# Offline GitOps Practice Lab

For the full hierarchy, each app's dependencies and versions, and test instructions,
read [Current lab setup](CURRENT-SETUP.md).

Six fictional apps across **DTA, STG and PRD**: workboard, notebook, releasehub, identity, scheduler and searchbox.
Practice tracing configuration, recording versions, preparing upgrades, and finding
broken references. No corporate names, source code, hosts, credentials or screenshots
are used in this practice structure.

## Start

From this folder, run:

```sh
ruby scripts/lab.rb check
ruby scripts/lab.rb inventory
```

Requirements: Ruby with its standard library, Helm 3, and kubectl with Kustomize.
The optional SQLite migration exercise uses Python 3 standard library only.
They are available on the machine used to prepare this lab. No packages are downloaded.

`check` renders and checks all 18 app/environment combinations. `inventory` prints
the chart version, chart appVersion, selected image, replicas, source branch and sync policy.
Output manifests go under `rendered/`, which Git ignores.

This is an **offline manifest lab**, not a live cluster. Registry, Git, database,
storage and routing addresses use `.invalid` domains. ExternalSecrets and routes
are teaching resources: their controllers, providers and Gateways are not installed.
Image tags are fictional and cannot be pulled. Checks do not prove runtime health.

## Structure

```text
base/<app>/                         shared Helm values and ExternalSecret base
clusters/DTA/lab/local/apps/         DTA Argo CD Application definitions
clusters/DTA/lab/local/<app>/        DTA values + Kustomize overlay
clusters/STG/lab/local/...           STG definitions and overlays
clusters/PRD/lab/local/...           PRD definitions and overlays
local-sources/HelmCharts/           local web, service-stack, worker and cache charts
offline-cache/                     pinned chart packages for offline STG/PRD rendering
inventory/<ENV>/charts.json         selected chart packages and offline locations
inventory/<ENV>/images.json         fictional image references
scripts/lab.rb                      offline render, inventory and reference checks
docs/EXERCISES.md                    small hands-on tickets, hints and agent prompts
AGENTS.md                           instructions for future agent-assisted practice
```

`lab/local` is a fictional subscription/cluster grouping, not a Kubernetes context.
For discussion, DTA represents a separate cluster; STG/PRD share a pretend cluster
and use different namespaces and PV names. Nothing is deployed.

## The three environments

| Setting | DTA | STG | PRD |
| --- | --- | --- | --- |
| Chart | editable local source | pinned offline package | pinned offline package |
| Declared Git revision | develop | develop | main |
| Declared auto-sync | off | on | on |

Image tags, replica counts and schedules differ by application. See the
[application and dependency catalog](CURRENT-SETUP.md#5-application-and-dependency-catalog)
for the exact baseline; searchbox stays at one replica and scheduler uses a CronJob.

The Applications use realistic multi-source declarations. The offline renderer maps
the fictional registry source to the saved package; it does not contact a registry.
**It always reads your current working-tree files.** It does not fetch Git branches,
simulate auto-sync, or apply resources. To compare revisions, switch branches or
use Git diff/show yourself. Rendering PRD while on develop previews those files,
not an independent view of main.

## Trace one app

Start at `clusters/DTA/lab/local/apps/workboard.yaml`:

```text
Application
  + local chart templates
      + chart defaults -> base values -> DTA values
  + DTA Kustomization
      + shared ExternalSecret -> DTA key patch
      + PV + PVC + HTTPRoute
  = desired Kubernetes manifests
```

For STG/PRD, substitute the saved chart package for the editable local chart.
Do not repackage the archive during ordinary checks: it represents a separate
published chart release. A deliberate chart-release exercise should use a new
chart version and archive name, then update the selected inventories/Applications.

Start with [the small exercises](EXERCISES.md), then [the application scenarios](APPLICATION-SCENARIOS.md).


## Focus on one application

```sh
ruby scripts/lab.rb check STG identity
ruby scripts/lab.rb inventory STG releasehub
ruby scripts/lab.rb render PRD scheduler
```

The inventory reports the primary workload and its image, plus declared chart dependencies.
A dependency being listed in Chart.yaml does not mean its condition enables it.
Inspect rendered resources to see active dependencies.

## Added applications

| App | Workload | Practice |
| --- | --- | --- |
| workboard | Deployment | values precedence, image upgrades, routes |
| notebook | Deployment | secret mapping, storage selectors |
| releasehub | Deployment + optional cache Deployment | chart dependencies and packaged-source differences |
| identity | Deployment + optional migration Job | custom image build inputs, schema compatibility, backup/restore |
| scheduler | CronJob | schedules, time zones, concurrency, job images |
| searchbox | StatefulSet + headless Service | stable workload identity, PVC references, upgrade constraints |

All six have separate DTA/STG/PRD Application definitions, values and image inventories.
Chart versions and image versions remain separate. service-stack bundles a local
demo-cache dependency, and STG/PRD read saved parent packages. The original charts/
platform dependencies are untouched.

## Actual local data migration practice

```sh
python3 scripts/migrate-demo.py init
python3 scripts/migrate-demo.py upgrade --to 2
python3 scripts/migrate-demo.py status
python3 scripts/migrate-demo.py restore
```

This uses only a disposable SQLite database under rendered/migrations/. Each SQL
migration is transactional. A pre-upgrade backup is made before version 2; restore
recovers it and also saves the current database first. No external database is used.
The Kubernetes migration Job is a fictional rendering example; the SQLite exercise
is run separately, not by that Job. Its completion does not deploy an application.

Validation commands:

```sh
ruby scripts/test-lab.rb
python3 scripts/test-migrations.py
```

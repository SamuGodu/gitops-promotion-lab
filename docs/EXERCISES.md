# Small offline tickets

Use [Current lab setup](CURRENT-SETUP.md) as the reference for current versions and dependencies.

Start each ticket on a local feature branch. Read the referenced files, predict the
result, make a focused change, then run `ruby scripts/lab.rb check`.
Use `git diff` to explain the result. The initial lab files may still be uncommitted. Save them on the lab branch before
branch-switching exercises; inspect git status and stage only your intended files.
Do not discard unrelated changes.
All sample versions and infrastructure are fictional.

## 1. Record current versions (no changes)

For workboard in each environment, record:

| Environment | Chart source/version | Chart appVersion | Effective image/tag | Evidence |
| --- | --- | --- | --- | --- |
| DTA | | | | |
| STG | | | | |
| PRD | | | | |

Start with `clusters/<ENV>/lab/local/apps/workboard.yaml`. Follow valueFiles.
Then compare your findings with `ruby scripts/lab.rb inventory`.
The image inventory lists preparation inputs; the rendered Deployment shows what
the configuration selects. Neither tells you what is currently running.

## 2. Raise only STG's memory request

Requirement: workboard STG needs 80Mi instead of 64Mi. Preserve its limits.

- Edit `clusters/STG/lab/local/workboard/values.yaml`.
- Run the check and inspect `rendered/STG/workboard.yaml`.
- Verify DTA and PRD requests did not change.
- Explain why this edit belongs in the environment overlay rather than shared base.

## 3. Upgrade an image and update inventory

Requirement: prepare workboard STG for fictional image 1.4.3.

- Set `image.tag: "1.4.3"` in STG workboard values. It overrides the inherited tag.
- Update only workboard's tag in `inventory/STG/images.json`.
- Run the check; inspect the rendered image reference.
- Chart version remains 1.0.0 because this ticket changes only the selected image.
- No actual image is built or published. In a live workflow, availability, compatibility,
  tests and recovery would be additional requirements.
- STG declares auto-sync; this local edit/render does not simulate or trigger it.

Try the check before updating the image inventory. Which missing-artifact message appears?

## 4. Find a broken route

On a fresh branch, deliberately change the backend Service name in
`clusters/STG/lab/local/workboard/route.yaml` to `workboard-old`.

- Run the check and read its error.
- Trace route backend -> rendered Service metadata.name -> chart template.
- Repair the incorrect reference and rerun the check.
- Explain why increasing replicas would not fix this problem.

## 5. Find an unresolved secret mapping

On a fresh branch, replace the remote key patch's value with `REPLACE_BY_OVERLAY`
in `clusters/DTA/lab/local/notebook/kustomization.yaml`.

- Run the check.
- Trace patch -> ExternalSecret remoteRef.key -> target Secret -> Deployment reference.
- Repair with the fictional notebook DTA key from the surrounding convention.
- Explain why successful rendering alone cannot prove a provider has the credential.

## 6. Find a storage selector mismatch

On a fresh branch, change PRD workboard PVC's environment selector to `stg`.

- Run the check. Compare its selector to PRD PV labels.
- Repair the selector without changing NFS endpoints.
- Explain why namespaces do not isolate PV object names and why Retain is not backup.
- The checker verifies label/class/mode references, not backend capacity, permission,
  availability, actual binding or mount success.

## 7. Prove local and packaged charts are independent

On a fresh branch, add a harmless fixed label under the local Deployment template's
`spec.template.metadata.labels`, for example `practice: local-change`.

```sh
ruby scripts/lab.rb check
```

Inspect the DTA and STG workboard renders. Only DTA should include the new label.
Do not run helm package: STG/PRD deliberately keep their separate saved package.
Explain what extra artifact-release steps a real STG chart upgrade would need.

## Git branch practice

Use the branch containing this lab as your starting point. Until it is promoted,
main/develop do not include these additions. Before a new exercise:

```sh
git status
git switch feature/offline-dta-stg-prd
git switch -c feature/your-exercise-name
```

Choose a unique branch name. Save/commit existing work before switching if Git reports
conflicts. Merge a completed feature into develop to practice a reviewed change.
Promote a tested commit to main as a separate exercise after comparing the complete diff.
Your existing remote is preserved. These exercises stay local; no push is necessary.

The renderer reads the current checkout. For branch-isolation evidence, inspect
`git show main:<path>` and `git show develop:<path>`, or render after switching branches.
It does not impersonate an Argo CD controller.

## Optional agent practice

No agent needs to read corporate files. Give it one small fictional ticket at a time:

> Review this offline lab's AGENTS.md. Diagnose the workboard STG route error.
> Explain the dependency chain before editing. Make the smallest fix and run the
> offline check. Do not contact a cluster, network service, or registry.

For a separate review:

> Review my feature-branch diff for environment scope and reference mistakes.
> Do not edit files. Distinguish rendered checks from pending runtime validation.

## Ticket handover

```text
Symptom or requested outcome:
Application/environment:
Cause or selected change:
Files/fields changed:
Other environments affected and why:
Validation performed:
Runtime checks unavailable in this offline lab:
Recovery considerations:
```

For migrations, dependency upgrades, CronJobs and StatefulSets, continue with
[application scenarios](APPLICATION-SCENARIOS.md).

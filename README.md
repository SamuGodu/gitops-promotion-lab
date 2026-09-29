# GitOps Promotion Lab

## Purpose

This lab simulates a simplified version of the structure and GitOps promotion workflow used by the application migration team. Its purpose is to understand how a shared Kustomize base, environment-specific overlays, Git branches, and Argo CD work together to promote tested application changes from development to production.

## Learning objectives

- Explain the relationship between a Kustomize base and an overlay.
- Render and compare separate development and production configurations.
- Configure development to track the `develop` branch.
- Configure production to track the `main` branch.
- Observe and explain Argo CD OutOfSync behavior.
- Promote a tested Git change from development to production.
- Use App of Apps without allowing the parent to discover itself.
- Verify Kubernetes resources with both `kubectl` and OpenLens.

## Architecture

```text
develop branch
      |
      v
Development Argo CD
      |
      v
Development cluster

main branch
      |
      v
Production Argo CD
      |
      v
Production cluster
```

## Repository structure

```text
base/podinfo/
    Shared Deployment and Service.

clusters/development/podinfo/
    Development Kustomize overlay.

clusters/production/podinfo/
    Production Kustomize overlay.

clusters/development/apps/
    Argo CD child Application definitions for development.

clusters/production/apps/
    Argo CD child Application definitions for production.

argocd/app-of-apps/
    Parent Application definitions, kept outside the folders they watch.

evidence/
    Sanitized command output, screenshots, and test results.
```

## Relationship to the team structure

The team repository uses a shared `base` and environment-specific paths under `clusters`. The real repository contains additional subscription and cluster-name levels, while this lab intentionally uses one cluster per environment.

The `clusters` directories act as Kustomize overlays. Each environment also contains an `apps` directory for its Argo CD child Application definitions. The parent App-of-Apps definitions are kept in a separate directory so that a parent cannot discover and recreate itself.

## Environment differences

| Setting | Development | Production |
|---|---|---|
| Git branch | `develop` | `main` |
| Cluster | `gitops-dev` | `gitops-prod` |
| Namespace | `podinfo` | `podinfo` |
| Replicas | 1 | 2 |
| Environment label | `development` | `production` |
| UI message | Development | Production |

## Promotion workflow

1. Create an application change on a feature branch.
2. Merge the feature branch into `develop`.
3. Confirm that only the development Application becomes OutOfSync.
4. Review the Argo CD development diff.
5. Sync and validate the change in development.
6. Merge the tested change from `develop` into `main`.
7. Confirm that the production Application becomes OutOfSync.
8. Review the production diff, sync it, and validate the result.

## Success criteria

The experiment is successful when:

- both Kustomize overlays render without errors;
- the development and production Applications initially report Synced and Healthy;
- a change pushed to `develop` makes only development OutOfSync;
- production remains unchanged while the change exists only on `develop`;
- the development diff is reviewed, synced, and verified;
- the tested change is promoted to `main`;
- production then becomes OutOfSync;
- the production diff is reviewed, synced, and verified;
- both environments finish Synced and Healthy;
- the observed results are confirmed with `kubectl` and OpenLens.

## Scope

The core lab covers Kustomize, Git branches, two Kubernetes clusters, Argo CD Applications, App of Apps, OutOfSync behavior, `kubectl`, and OpenLens.

The monitoring Helm chart is an optional extension after the core promotion simulation has been completed.
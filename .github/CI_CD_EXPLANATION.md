# CI/CD Explanation For This Demo Project

## 1. What this project is

This repository is a small Node.js + TypeScript API demo, but the main value is the delivery setup around it:

- CI checks code quality and security before merge.
- CD builds a Docker image, publishes it, verifies supply-chain metadata, and simulates deployment.
- Release automation manages version bumps, changelog entries, tags, and GitHub releases.

The application itself is intentionally simple:

- [`src/app.ts`](/home/ducnhan/Documents/works/CI-CD/src/app.ts) defines `GET /health` and `GET /ready`.
- [`src/server.ts`](/home/ducnhan/Documents/works/CI-CD/src/server.ts) starts the Fastify server.
- [`src/app.test.ts`](/home/ducnhan/Documents/works/CI-CD/src/app.test.ts) tests those endpoints.

That simplicity helps the repository focus on pipeline design.

---

## 2. CI vs CD in this repository

### CI: Continuous Integration

CI means every change is automatically validated when developers push code or open a pull request.

In this project, CI answers:

- Does the code install correctly?
- Does it pass linting and formatting rules?
- Does TypeScript type-check?
- Do tests pass?
- Are there obvious security issues in code, dependencies, or filesystem contents?
- Does the PR follow the release naming convention?

CI here is mainly implemented by:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)
- [`reusable-node-ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-node-ci.yml)

### CD: Continuous Delivery / Deployment

CD means code that passed CI is prepared and pushed toward release and deployment automatically.

In this project, CD answers:

- Can we build a production Docker image?
- Can we push it to GHCR?
- Can we attach provenance, SBOM, and signatures?
- Can we verify the image before deployment?
- Can we move the artifact through staging and production environments?

CD here is mainly implemented by:

- [`cd.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/cd.yml)
- [`reusable-docker.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-docker.yml)

### Release Automation

This repository also has a release-management pipeline between CI and CD:

- [`release.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/release.yml)
- [`release-please-config.json`](/home/ducnhan/Documents/works/CI-CD/release-please-config.json)
- [`.release-please-manifest.json`](/home/ducnhan/Documents/works/CI-CD/.release-please-manifest.json)

This part controls versioning and changelog generation.

---

## 3. High-level pipeline map

```text
Developer push / Pull Request
        |
        v
   CI workflow
   - install
   - lint
   - format check
   - typecheck
   - test + coverage
   - PR title lint
   - CodeQL
   - dependency review
   - Trivy filesystem scan
        |
        v
   Merge into main
        |
        +------------------------------+
        |                              |
        v                              v
   Release workflow               CD workflow
   - release-please               - quality gate
   - create/update release PR     - docker build
   - create tag/release           - push image to GHCR
                                   - attach SBOM/provenance
                                   - sign image with cosign
                                   - verify signature
                                   - deploy staging
                                   - deploy production
```

Important detail:

- `ci.yml` does not run on pushes to `main`.
- After merge to `main`, `cd.yml` and `release.yml` run.
- `release.yml` may create a semver tag like `v1.2.3`.
- `cd.yml` also runs on tags matching `v*`.

So the repository has:

- a validation pipeline for development,
- a release/version pipeline for main,
- a delivery pipeline for container publishing and deployment.

---

## 4. File-by-file explanation

## 4.1 Workflow files

### [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)

Purpose:

- Main CI entrypoint for pull requests and non-main branch pushes.

Trigger:

```yaml
on:
  pull_request:
  push:
    branches-ignore: [main]
```

Meaning:

- Every PR runs CI.
- Every branch push except `main` runs CI.
- This avoids duplicate quality runs on `main`, because `cd.yml` runs its own quality gate there.

Main jobs:

- `quality`: calls the reusable Node CI workflow.
- `pr-title`: ensures PR title follows Conventional Commits.
- `codeql`: static code analysis by GitHub.
- `dependency-review`: checks risky dependency changes in PRs.
- `trivy-fs`: scans repository filesystem for vulnerabilities/misconfigurations.

Other important settings:

- `concurrency` cancels older runs on the same branch/PR, reducing waste.
- minimal `permissions` follow least-privilege principles.

### [`reusable-node-ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-node-ci.yml)

Purpose:

- Shared quality pipeline reused by both CI and CD.

Why reusable workflows matter:

- no duplicated YAML,
- one place to change Node versions or quality rules,
- CI and CD both enforce the same baseline.

Trigger type:

```yaml
on:
  workflow_call:
```

This means it is not triggered directly by GitHub events. Other workflows call it.

Its job:

- creates a matrix for Node `22` and `24`,
- installs dependencies with `npm ci`,
- runs:
  - `npm run lint`
  - `npm run format:check`
  - `npm run typecheck`
  - `npm test`
- uploads coverage artifacts,
- comments coverage on PRs for Node 22 only.

Why `npm ci` and not `npm install`:

- `npm ci` is deterministic,
- it uses `package-lock.json`,
- it is preferred in CI because builds are more reproducible.

Why matrix testing matters:

- the project declares `node >=22` in [`package.json`](/home/ducnhan/Documents/works/CI-CD/package.json),
- testing on 22 and 24 catches version-specific behavior early.

### [`cd.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/cd.yml)

Purpose:

- Main delivery pipeline for `main`, version tags, and manual runs.

Trigger:

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch:
```

Meaning:

- run after code lands on `main`,
- run when a semver tag like `v1.1.0` is pushed,
- allow manual triggering from GitHub UI.

Jobs:

1. `quality`
2. `build-push`
3. `deploy-staging`
4. `deploy-production`

Execution order:

```text
quality
  -> build-push
      -> deploy-staging
          -> deploy-production
```

This ensures:

- deployment never happens if quality checks fail,
- production never happens before staging,
- image verification happens before each deploy stage.

### [`reusable-docker.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-docker.yml)

Purpose:

- Shared container build/publish/sign workflow.

This workflow:

- checks out code,
- enables QEMU for multi-architecture builds,
- enables Buildx,
- logs into GitHub Container Registry,
- generates tags and OCI labels,
- builds and pushes the image,
- emits SBOM and provenance,
- creates GitHub build attestation,
- scans the pushed image with Trivy,
- signs the image using keyless cosign.

It outputs:

- pushed image reference by digest.

That output is consumed by deployment jobs so they deploy an exact immutable artifact.

### [`release.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/release.yml)

Purpose:

- Automates semantic releases from merged commits on `main`.

Trigger:

```yaml
on:
  push:
    branches: [main]
```

Main jobs:

- `release-please`
- `publish-image`

Behavior:

1. When commits land on `main`, `release-please` analyzes commit history.
2. It creates or updates a release PR if needed.
3. When that release PR is merged, it creates:
   - a version bump,
   - changelog update,
   - GitHub release,
   - Git tag like `v1.1.0`.
4. If a new release was created in that run, `publish-image` calls the reusable Docker workflow with the release version.

Important condition:

```yaml
if: needs.release-please.outputs.release_created == 'true'
```

So the image publishing part only happens when there is an actual new release.

---

## 4.2 Project configuration files used by the pipeline

### [`package.json`](/home/ducnhan/Documents/works/CI-CD/package.json)

This file is central to CI because the workflows directly call these scripts:

- `build`: compile TypeScript for production
- `lint`: ESLint checks code style/problems
- `format:check`: Prettier verifies formatting
- `typecheck`: `tsc --noEmit` validates types
- `test`: Vitest runs tests and coverage

If any of these scripts is missing or failing, the quality gate fails.

Other CI/CD-relevant fields:

- `engines.node: >=22`
  - documents supported Node version floor.
- `main: dist/server.js`
  - matches the Docker/runtime build output expectation.
- dependency and devDependency versions
  - used by Dependabot and security tooling.

### [`Dockerfile`](/home/ducnhan/Documents/works/CI-CD/Dockerfile)

Purpose:

- defines how the production container image is built.

Stages:

1. `deps`
   - copies package manifests
   - runs `npm ci`
2. `build`
   - copies source and TypeScript configs
   - runs `npm run build`
3. `prod-deps`
   - installs only production dependencies with `npm ci --omit=dev`
4. `runtime`
   - copies production dependencies and compiled `dist`
   - runs as non-root user `node`
   - exposes port `3000`
   - defines health check

Why multi-stage build is good here:

- final image is smaller,
- build tools do not stay in production image,
- attack surface is reduced.

Why the health check matters:

- it checks `/health`,
- that endpoint is defined in [`src/app.ts`](/home/ducnhan/Documents/works/CI-CD/src/app.ts),
- container platforms can use it to detect unhealthy containers.

### [`release-please-config.json`](/home/ducnhan/Documents/works/CI-CD/release-please-config.json)

Purpose:

- tells release-please how to version and write the changelog.

Important settings:

- `"release-type": "node"`
- `"package-name": "ci-cd"`
- `"include-v-in-tag": true`
- custom changelog sections for:
  - `feat`
  - `fix`
  - `perf`
  - `docs`
  - `chore` hidden from changelog

Meaning:

- tags will look like `v1.1.0`,
- release-please interprets commits using Node package conventions,
- changelog is grouped into readable sections.

### [`.release-please-manifest.json`](/home/ducnhan/Documents/works/CI-CD/.release-please-manifest.json)

Purpose:

- stores the current released version for each managed package.

Current content:

```json
{
  ".": "1.1.0"
}
```

Meaning:

- the root package is currently at version `1.1.0`.

Release-please uses this to understand what the next version should be.

### [`vitest.config.ts`](/home/ducnhan/Documents/works/CI-CD/vitest.config.ts)

Purpose:

- configures test execution and coverage behavior used by `npm test`.

This file matters because CI is not only running tests; it is also producing coverage artifacts used for reporting.

### [`tsconfig.json`](/home/ducnhan/Documents/works/CI-CD/tsconfig.json) and [`tsconfig.build.json`](/home/ducnhan/Documents/works/CI-CD/tsconfig.build.json)

Purpose:

- define TypeScript compiler behavior.

These files affect:

- `npm run typecheck`
- `npm run build`

So they are part of the CI contract even though they are not workflow files.

### [`eslint.config.js`](/home/ducnhan/Documents/works/CI-CD/eslint.config.js)

Purpose:

- defines lint rules used by the `lint` step.

Any rule violation here breaks the quality gate.

---

## 4.3 Governance and maintenance files around the pipeline

### [`.github/rulesets/main-branch-protection.json`](/home/ducnhan/Documents/works/CI-CD/.github/rulesets/main-branch-protection.json)

Purpose:

- defines protection rules for the default branch.

This is not a workflow, but it is critical to CI/CD governance.

It enforces:

- no branch deletion,
- no force-push (`non_fast_forward`),
- linear history,
- PR-based integration,
- required status checks.

Required status checks listed:

- `Quality gate / Node 22`
- `Quality gate / Node 24`
- `CodeQL`
- `Dependency review`
- `Trivy filesystem scan`
- `Lint PR title`

Meaning:

- even if a workflow exists, it only becomes policy when branch protection requires it.
- this file turns CI into a merge gate.

### [`.github/dependabot.yml`](/home/ducnhan/Documents/works/CI-CD/.github/dependabot.yml)

Purpose:

- automates dependency update PRs.

It watches:

- `npm`
- `github-actions`
- `docker`

Schedule:

- weekly

Why it matters to CI/CD:

- keeps dependencies and action versions current,
- update PRs flow through the same CI quality gate,
- commit prefixes are aligned with release/repo conventions.

### [`.github/CODEOWNERS`](/home/ducnhan/Documents/works/CI-CD/.github/CODEOWNERS)

Purpose:

- declares who owns files in the repository.

Current content:

- `* @taovietducofficial`

This becomes more useful when branch protection requires code-owner review.

### [`CONTRIBUTING.md`](/home/ducnhan/Documents/works/CI-CD/CONTRIBUTING.md)

Purpose:

- documents the expected developer workflow.

Important CI/CD links:

- branch from `main`,
- keep quality gate green locally,
- open PR,
- pass CI,
- merge with squash,
- use Conventional Commit titles.

This matters because release-please depends on commit/PR naming quality.

### [`SECURITY.md`](/home/ducnhan/Documents/works/CI-CD/SECURITY.md)

Purpose:

- documents vulnerability handling and supply-chain guarantees.

It explicitly states published images include:

- SBOM,
- SLSA provenance,
- GitHub build provenance attestation,
- cosign signature.

That matches the behavior in the Docker publishing workflow.

---

## 5. Detailed explanation of the CI pipeline

## 5.1 CI trigger conditions

The CI workflow runs when:

- a pull request is opened, synchronized, or updated,
- a branch push happens on any branch except `main`.

This is a common design:

- feature branches get feedback quickly,
- PRs are fully validated before merge,
- `main` is reserved for release/delivery flows.

## 5.2 CI jobs and why each one exists

### Job: `quality`

Source:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)
- [`reusable-node-ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-node-ci.yml)

This is the core build validation job.

Steps:

1. `actions/checkout@v4`
   - downloads repository contents into the runner.
   - without this, the runner has no source code to test.

2. `actions/setup-node@v4`
   - installs the requested Node version.
   - enables npm dependency caching.

3. `npm ci`
   - installs exact locked dependencies from `package-lock.json`.

4. `npm run lint`
   - enforces ESLint rules.

5. `npm run format:check`
   - fails if formatting differs from Prettier rules.

6. `npm run typecheck`
   - validates TypeScript types without generating output.

7. `npm test`
   - runs Vitest with coverage.

8. `Upload coverage`
   - stores coverage results as artifacts even if earlier checks fail because of `if: always()`.

9. `Report coverage on PR`
   - comments coverage report on PRs for Node 22 only.
   - this avoids duplicate PR comments from both Node versions.

Why this sequence is sensible:

- install first,
- then static checks,
- then tests,
- then reporting.

### Job: `pr-title`

Source:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)

Tool:

- `amannn/action-semantic-pull-request@v5`

Purpose:

- validates PR title follows Conventional Commit format.

Allowed types in this repo:

- `feat`
- `fix`
- `docs`
- `perf`
- `refactor`
- `test`
- `build`
- `ci`
- `chore`
- `revert`

Why this matters:

- `release-please` depends on commit semantics to infer version bumps and changelog sections.
- enforcing semantic PR titles reduces messy release history.

### Job: `codeql`

Source:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)

Steps:

1. checkout source
2. initialize CodeQL for `javascript-typescript`
3. analyze code

Purpose:

- static application security testing,
- detects code-level vulnerabilities or risky patterns.

### Job: `dependency-review`

Source:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)

Runs only on PRs.

Purpose:

- examines dependency changes introduced by the PR,
- can fail on high-severity issues.

Configured behavior:

- `fail-on-severity: high`

Meaning:

- if a PR brings in a dependency with known high-severity risk, CI blocks it.

### Job: `trivy-fs`

Source:

- [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)

Purpose:

- scans the repository filesystem directly.

Configured behavior:

- scan type: `fs`
- target: repository root
- severities: `HIGH,CRITICAL`
- exit code `1` on findings
- ignore unfixed issues

Meaning:

- high/critical findings fail CI,
- known issues without fixes are tolerated to reduce noise.

## 5.3 CI result

If all jobs pass:

- PR can satisfy branch protection checks,
- code is considered acceptable to merge.

If any required check fails:

- merge to `main` should be blocked by the ruleset.

---

## 6. Detailed explanation of the CD pipeline

## 6.1 CD trigger conditions

The CD workflow runs on:

- push to `main`,
- push of tags matching `v*`,
- manual dispatch.

Why both branch and tag triggers exist:

- push to `main` supports continuous delivery after merge,
- tag trigger supports versioned release builds,
- manual dispatch helps testing or reruns.

## 6.2 CD jobs and dependencies

### Job: `quality`

This reuses the same Node quality workflow as CI.

Why this is valuable:

- it prevents “passed in PR but skipped in deploy” drift,
- it ensures artifacts are only built from code that still passes current checks on `main`.

### Job: `build-push`

Source:

- [`cd.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/cd.yml)
- [`reusable-docker.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-docker.yml)

This is the heart of the delivery pipeline.

Step-by-step:

1. `actions/checkout@v4`
   - fetch code for Docker build context.

2. `docker/setup-qemu-action@v3`
   - enables emulation so the runner can build for multiple CPU architectures.

3. `docker/setup-buildx-action@v3`
   - enables Docker Buildx features.

4. `docker/login-action@v3`
   - logs into `ghcr.io` using `GITHUB_TOKEN`.

5. `docker/metadata-action@v5`
   - generates image tags and labels.

6. `docker/build-push-action@v6`
   - builds and pushes the image.
   - target platforms:
     - `linux/amd64`
     - `linux/arm64`
   - enables GitHub Actions cache
   - generates SBOM
   - generates provenance

7. `Compute image refs (lowercase)`
   - normalizes repository name to lowercase because container registry names must be lowercase.
   - constructs immutable image digest reference.

8. `actions/attest-build-provenance@v2`
   - creates registry-linked provenance attestation.

9. `Trivy image scan`
   - scans the built image for vulnerabilities.
   - `continue-on-error: true` means it is advisory, not blocking.

10. `sigstore/cosign-installer@v3`
    - installs cosign.

11. `cosign sign --yes`
    - signs the image by digest using keyless signing with GitHub OIDC identity.

Why digest-based references matter:

- tags can move,
- digests are immutable,
- deployment should target exact content, not a mutable label.

### How image tags are generated

The metadata action may produce tags from:

- branch name,
- git SHA,
- semver version,
- `latest` if on default branch,
- explicit version passed from release workflow.

Examples:

- `ghcr.io/owner/repo:main`
- `ghcr.io/owner/repo:sha-abc123...`
- `ghcr.io/owner/repo:latest`
- `ghcr.io/owner/repo:1.1.0`

This gives both human-friendly and immutable references.

### Job: `deploy-staging`

Purpose:

- deploy the pushed image to staging after verifying its signature.

Current implementation:

- login to GHCR,
- install cosign,
- verify the image signature,
- print a placeholder deploy command.

Verification command meaning:

- ensure the image was signed by a GitHub Actions workflow from this repository,
- ensure the OIDC issuer is GitHub,
- reject artifacts that do not match expected identity.

The current deploy step is:

```sh
echo "Deploying $IMAGE to staging"
```

So this demo shows deployment structure, not a real staging rollout command yet.

### Job: `deploy-production`

Purpose:

- deploy to production only after:
  - build completed,
  - staging deployment completed.

It repeats signature verification before deployment.

That duplication is intentional:

- each environment should verify what it is about to deploy,
- trust is re-established at the boundary.

Current production deploy is also a placeholder `echo`.

## 6.3 GitHub Environments

`cd.yml` uses:

- `environment: staging`
- `environment: production`

This matters because GitHub Environments can provide:

- approval gates,
- environment-scoped secrets,
- deployment history.

The README instructs creating both environments and adding required reviewers to `production`.

That means in a real setup:

- staging can auto-deploy,
- production can pause for human approval.

---

## 7. Detailed explanation of the release pipeline

## 7.1 Why release automation exists here

Without release automation, a team often has to manually:

- decide next version,
- edit `package.json`,
- update changelog,
- create tag,
- publish release.

This repo automates that through release-please.

## 7.2 How release-please works in this project

Input:

- merged commit history on `main`
- Conventional Commit style titles/messages

Rules:

- `feat` usually means minor bump
- `fix` usually means patch bump
- `feat!` or `BREAKING CHANGE` means major bump

Flow:

1. Developer opens PR with semantic title.
2. CI checks the title format.
3. PR is squash-merged.
4. `release.yml` runs on `main`.
5. release-please creates or updates a Release PR.
6. When that PR is merged, release-please creates:
   - version bump
   - changelog update
   - GitHub release
   - Git tag
7. Docker publishing can apply the released semver tag to the image.

This connects source control history to release artifacts in a repeatable way.

## 7.3 Why squash merge is mentioned in `CONTRIBUTING.md`

Because release-please reads commit history. With squash merge:

- the final commit can match the PR title,
- history stays cleaner,
- version inference is easier and more reliable.

---

## 8. How the demo app supports the pipeline

Even though the app is small, it is designed to support the pipeline demonstration.

### [`src/app.ts`](/home/ducnhan/Documents/works/CI-CD/src/app.ts)

Defines:

- `/health`
- `/ready`

These endpoints support:

- automated tests,
- Docker health checks,
- future deployment readiness checks.

### [`src/app.test.ts`](/home/ducnhan/Documents/works/CI-CD/src/app.test.ts)

Verifies:

- `/health` returns 200 and `{ status: 'ok' }`
- `/ready` returns 200 and `{ status: 'ready' }`

That gives the CI pipeline something concrete to validate.

### [`src/server.ts`](/home/ducnhan/Documents/works/CI-CD/src/server.ts)

Handles:

- host/port binding,
- graceful shutdown on `SIGINT` and `SIGTERM`.

That matters in deployment contexts because containers are expected to stop cleanly.

---

## 9. Security and supply-chain design in this repository

This project intentionally adds several layers beyond basic “run tests and build image”.

## 9.1 Source-level security

Handled by:

- CodeQL
- dependency review
- Trivy filesystem scan

These protect before artifact creation.

## 9.2 Artifact-level security

Handled by:

- image vulnerability scan
- SBOM generation
- provenance generation
- GitHub attestation
- cosign signing

These protect after artifact creation.

## 9.3 Deployment-time verification

Handled by:

- `cosign verify` in staging and production jobs

This is important because:

- signing alone is not enough,
- deploy systems must verify the signature before trusting the artifact.

This is one of the strongest educational points in the repo.

---

## 10. End-to-end scenarios

## 10.1 Scenario A: feature branch and pull request

```text
1. Developer pushes branch
2. ci.yml runs
3. quality checks run on Node 22 and 24
4. PR title is checked
5. security scans run
6. if all required checks pass, PR can be merged
```

## 10.2 Scenario B: merge to main

```text
1. PR is merged into main
2. release.yml runs
3. cd.yml runs
4. cd quality gate reruns
5. image is built and pushed
6. image is signed and attested
7. staging deploy step runs
8. production deploy step runs, usually behind approval
```

## 10.3 Scenario C: release creation

```text
1. main contains new feat/fix commits
2. release-please creates or updates Release PR
3. Release PR is merged
4. tag vX.Y.Z is created
5. release image can be published with version tag
```

---

## 11. Why this repository is a good CI/CD learning example

It includes several maturity levels in one place:

### Basic level

- lint
- format check
- typecheck
- test

### Intermediate level

- matrix testing
- reusable workflows
- branch protection
- dependency update automation

### Advanced level

- release automation
- multi-arch Docker builds
- SBOM and provenance
- signed container images
- signature verification before deployment

That makes it useful for a beginner because you can learn the pipeline in layers.

---

## 12. Limits of this demo

This is still a demo template, not a full production platform.

Current limitations:

- deployment steps are placeholders using `echo`
- no real cluster, server, or cloud target is configured
- no environment secrets are shown for real deployment
- observability and rollback workflows are not included
- database migrations are not part of the pipeline

So the CD structure is real, but the final deployment commands are intentionally left for adaptation.

---

## 13. Short summary by file

| File                                                                                                                               | Role in CI/CD                                                |
| ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| [`ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/ci.yml)                                                           | Main CI workflow for PRs and non-main branches               |
| [`reusable-node-ci.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-node-ci.yml)                               | Shared Node quality gate                                     |
| [`cd.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/cd.yml)                                                           | Main delivery/deployment workflow                            |
| [`reusable-docker.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/reusable-docker.yml)                                 | Shared container build, publish, scan, attest, sign workflow |
| [`release.yml`](/home/ducnhan/Documents/works/CI-CD/.github/workflows/release.yml)                                                 | Release automation workflow                                  |
| [`Dockerfile`](/home/ducnhan/Documents/works/CI-CD/Dockerfile)                                                                     | Production image build definition                            |
| [`package.json`](/home/ducnhan/Documents/works/CI-CD/package.json)                                                                 | Source of scripts called by workflows                        |
| [`release-please-config.json`](/home/ducnhan/Documents/works/CI-CD/release-please-config.json)                                     | Release strategy and changelog mapping                       |
| [`.release-please-manifest.json`](/home/ducnhan/Documents/works/CI-CD/.release-please-manifest.json)                               | Current managed release version                              |
| [`.github/rulesets/main-branch-protection.json`](/home/ducnhan/Documents/works/CI-CD/.github/rulesets/main-branch-protection.json) | Turns CI into enforced branch policy                         |
| [`.github/dependabot.yml`](/home/ducnhan/Documents/works/CI-CD/.github/dependabot.yml)                                             | Automated maintenance PRs                                    |
| [`.github/CODEOWNERS`](/home/ducnhan/Documents/works/CI-CD/.github/CODEOWNERS)                                                     | Ownership policy for reviews                                 |
| [`CONTRIBUTING.md`](/home/ducnhan/Documents/works/CI-CD/CONTRIBUTING.md)                                                           | Human workflow aligned with automation                       |
| [`SECURITY.md`](/home/ducnhan/Documents/works/CI-CD/SECURITY.md)                                                                   | Security and supply-chain expectations                       |

---

## 14. Final takeaway

The CI pipeline in this project is the protection layer:

- it validates code quality,
- checks formatting and types,
- runs tests,
- enforces PR naming,
- scans for security issues.

The CD pipeline is the delivery layer:

- it rebuilds validated code,
- creates a production container,
- pushes it to GHCR,
- signs and attests the artifact,
- verifies trust before deployment,
- promotes the artifact through environments.

The release pipeline sits between them:

- it translates commit history into versions, tags, changelog entries, and GitHub releases.

So this repository is not only “run tests on push”. It demonstrates a full path:

```text
code change
-> validation
-> merge policy
-> versioning
-> artifact build
-> supply-chain proof
-> deployment gate
```

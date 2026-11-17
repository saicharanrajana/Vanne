# Release pipeline

How CI, CD and releases work in this repo, and why the pieces look the way
they do. High-level overview lives in the README (`## Releases`); this is the
operational detail.

## The flow

```
feature branch ──merge-commit PR──▶ dev ──merge-commit PR──▶ main
                                                 │
                                    release-please opens a release PR
                                    ("chore(main): release X.Y.Z")
                                                 │
                                    merge release PR ──▶ tag vX.Y.Z
                                                 │
                                    Release workflow builds signed APKs
                                                 │
                                    APKs + SHA256SUMS.txt + download table
                                    attached to the GitHub Release
```

- Direct pushes to `main` and `dev` are rejected (branch protection); all
  changes go through PRs. Feature branches are deleted on merge
  automatically.
- Merging anything into `main` is the release trigger: release-please decides
  whether a release is needed, opens its PR, and merging that PR ships.

## Merge methods

| Hop | Method | Why |
|---|---|---|
| feature → `dev` | **merge commit** | each curated commit on the branch survives, so every `feat:`/`fix:` commit becomes its own changelog entry. Squash is still allowed for branches whose commit history you don't want to expose — that collapses them into one entry named by the PR title. |
| `dev` → `main` | **merge commit** | keeps every commit that accumulated on dev, so release-please emits one changelog entry per commit. The sync PR title is irrelevant to the release; still use a conventional title (e.g. `chore: sync dev into main`) because the PR-title check runs on every PR. |
| release PR → `main` | squash | release-please's branch is a single commit |

Squash collapses history. Squashing at either hop merges commits into one
umbrella commit and therefore one umbrella changelog entry — that is why both
feature and promotion hops use merge commits.

## Versioning

release-please derives the next version from the Conventional Commits that
reach `main`. With merge commits on both hops those are your feature-branch
commits, so keep them curated and conventional — the `commit-msg` hook
enforces the format. The promotion merge commit itself is ignored:

| Commit prefix | Version bump | Example |
|---|---|---|
| `fix:` | patch | 0.1.0 → 0.1.1 |
| `feat:` | minor | 0.1.0 → 0.2.0 |
| `feat!:` / `fix!:` / `BREAKING CHANGE:` footer | major | 0.1.0 → 1.0.0 |
| `docs:`, `chore:`, `ci:`, `test:`, `refactor:`, `style:`, `perf:` | none | no release PR |

Pre-1.0, `bump-minor-pre-major` is on, so breaking changes bump minor instead
of major.

Files updated by a release PR: `CHANGELOG.md` and `version:` in
`pubspec.yaml` (`X.Y.Z+N` build number comes from release-please's dart
release type). The manifest of the current released version is
`.github/release-please-manifest.json` — do not edit it by hand unless
recovering from a mistake.

## Workflow inventory

| File | Trigger | What it does |
|---|---|---|
| `.github/workflows/ci.yml` | PR to `main`/`dev`, pushes to both | `flutter analyze`, `flutter test`, unsigned release APK build (debug-keystore fallback). Job/check name: **"Analyze, test and build APK"** — this exact name is a required check on both protected branches. |
| `.github/workflows/pr-title.yml` | every PR | Validates the PR title as a Conventional Commit (≤72 chars, no trailing period). Matters because the squash-merge title becomes the commit release-please parses. |
| `.github/workflows/release-please.yml` | push to `main` | Runs release-please; when it cut a release, chains the APK build (see gotcha 1). Workflow name: **Release PR**. |
| `.github/workflows/release.yml` | `v*` tag push, `workflow_dispatch` (input: tag), `workflow_call` | Builds signed per-ABI + universal APKs, generates `SHA256SUMS.txt`, writes the "Which APK do I download?" table, attaches everything to the release. Workflow name: **Release**. |
| `.github/release-please-config.json` | — | `release-type: dart`, `initial-version: 0.1.0`, tag format `vX.Y.Z` (`include-component-in-tag: false`). |

Signing: `release.yml` decodes the `KEYSTORE_BASE64` secret to
`android/app/vanne-upload.jks` and writes `android/key.properties` from the
`KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` secrets, then
`flutter build apk --release` signs with them. Secrets are wiped in an
`if: always()` cleanup step.

## What a release run does, step by step

1. `dev` is promoted into `main` with a merge-commit PR → push to `main`.
   Every commit that accumulated on `dev` (each a real feature commit) lands
   on `main` individually, so the changelog names each change.
2. **Release PR** workflow runs release-please:
   - No unreleased conventional commits → no-op.
   - Otherwise → opens/updates the release PR with changelog + version bump.
   - If a release was cut in this push (i.e. the release PR itself was merged):
     the same run's second job (`apks`) calls `release.yml` as a reusable
     workflow with `tag: vX.Y.Z`.
3. `release.yml` builds on that tag, attaches `vanne-<ver>-arm64-v8a.apk`,
   `vanne-<ver>-armeabi-v7a.apk`, `vanne-<ver>-universal.apk`,
   `SHA256SUMS.txt`, and appends the download table to the release notes.

## Gotchas (why the code is shaped this way)

1. **Tags created by release-please don't trigger workflows.** GitHub refuses
   to run workflows for events caused by the default `GITHUB_TOKEN`
   (anti-recursion). release-please always tags with `GITHUB_TOKEN`, so a
   plain `push: tags` trigger would never fire. Fix: `release-please.yml`
   chains `release.yml` as a reusable-workflow *job* in the same run — jobs
   in the same run are exempt. Do not "simplify" this back to a tag trigger.

2. **GITHUB_TOKEN can't edit releases whose commit touches `.github/workflows/`.**
   Updating a release is rejected with
   `403 Resource not accessible by integration` when the release's target
   commit adds/modifies workflow files, because `GITHUB_TOKEN` can never hold
   the workflows permission. Any cycle containing a `ci:` commit hits this.
   Fix: `release.yml` uses the `gh` CLI (`gh release upload` / `gh release
   edit`), which only sends changed fields — softprops/action-gh-release was
   removed for this reason (it always sends `target_commitish`).

3. **release-please outputs.** Use `release_created` and `tag_name`. The
   `releases_created` output is unreliable (known action issue).

4. **Bot PR workflow runs need approval.** release-please PRs are authored by
   `github-actions[bot]`; their CI runs sit in `action_required` until
   approved. The repo setting Actions → General → "Allow GitHub Actions to
   create and approve pull requests" is enabled, which auto-approves these
   runs. If release-PR checks get stuck in `action_required`, re-check that
   setting.

5. **Reruns use the commit the run started on.** A re-run of an old failed run
   does not pick up newer workflow code. To run current `release.yml` against
   an existing tag use a dispatch instead:

   ```
   gh workflow run release.yml --ref main -f tag=v0.1.0
   ```

   The dispatch rebuilds, re-attaches (`--clobber`) and is idempotent about
   the download table.

## Branch protection

- `main`: requires the "Analyze, test and build APK" check, admins included
  (no bypass). Linear history is off and merge commits are allowed, because
  promotions from `dev` are merge commits; squash stays available for feature
  hotfix PRs and the release PR.
- `dev`: requires the same check. Merge commits and squash are both allowed
  (linear history off) so feature commits are preserved unless you choose to
  squash; this is where feature work lands first.
- CI also runs unsigned APK builds on `dev`, so breakage is caught before it
  ever reaches a release.

## Local checks before pushing

```sh
flutter analyze && flutter test   # what CI runs
actionlint                        # workflow syntax
git commit …                      # githooks/commit-msg validates the message
                                  # (activate once: git config core.hooksPath githooks)
```

## Emergency recovery

- **Release exists but assets missing / table missing** → dispatch the
  Release workflow for that tag (gotcha 5). It is safe to re-run.
- **Version bump went wrong** → fix `pubspec.yaml` + the manifest
  (`.github/release-please-manifest.json`) in a `chore:` PR, or
  `gh release delete <tag> --yes && git push origin :refs/tags/<tag>` to redo
  a release entirely (then merge the release PR again).
- **Signing identity** — upload keystore + passwords live outside the repo
  (`android/key.properties` is gitignored); back them up off-machine. CI uses
  the `KEYSTORE_*` secrets, not local files.

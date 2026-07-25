# Releasing errorAlerts

How to cut a release and publish it to ForgeBox and GitHub. The whole flow is one guarded
command (`box run-script publish:release`) plus a couple of deliberate manual steps. The build
tooling lives in [build/](build/) — see [build/README.md](build/README.md) if you want the
details of how each piece works.

## One-time setup

- **CommandBox** installed (`box version`).
- **GitHub CLI** installed and logged in: `gh auth login`. The release refuses to start if `gh`
  is not ready, so it can never publish to ForgeBox and then fail to tag GitHub.
- A **test server** you can start on port 60310, e.g. `box run-script start:2023`.

## The version + changelog model

Two rules keep the version in one place and the release notes honest:

1. **`box.json` holds the version you are releasing next.** Nothing else hardcodes it — the build
   and release tasks read it from `box.json`.
2. **You write notes as you work under `## [Unreleased]` in [changelog.md](changelog.md).** At
   release time those notes become a dated section and the GitHub Release body.

You do not edit the version or move the changelog notes by hand — `bump` does both (next section).

## Cutting a release

1. **Finish and commit your work**, with the release notes written under `## [Unreleased]` in
   `changelog.md`.

2. **Run the full cross-engine sweep** (optional but recommended; it is slow, 15-30+ min):
   ```
   box run-script test:release
   ```
   This runs the whole test suite on every engine in turn (Adobe 2023, BoxLang, Adobe 2025,
   Lucee 5, Lucee 6). It is separate from `publish:release` on purpose: a flaky engine boot
   should never abort a publish, and the publish already runs the suite on one engine as a gate.

3. **Bump the version and date the changelog** with one command. Pick the SemVer level:
   ```
   box run-script bump:patch     # 1.0.0 -> 1.0.1  (bug fixes)
   box run-script bump:minor     # 1.0.0 -> 1.1.0  (new, backward-compatible features)
   box run-script bump:major     # 1.0.0 -> 2.0.0  (breaking changes)
   ```
   `bump` updates `box.json`, moves the `## [Unreleased]` notes into a new
   `## [<new version>] - <today>` section, and leaves a fresh empty `[Unreleased]`. It does not
   commit, tag, or publish — you review the diff first.

   **First release only:** `box.json` is already `1.0.0` and you want to ship `1.0.0`, not
   `1.0.1`. So do not bump — date the current version instead:
   ```
   box task run taskFile=build/Bump.cfc :level=none
   ```

4. **Review and commit** the two changed files:
   ```
   git diff box.json changelog.md
   git commit -am "Release <version>"
   git push origin main
   ```

5. **Start a test server** on port 60310 (the build runs the suite against it):
   ```
   box run-script start:2023
   ```

6. **Publish** — the one guarded command:
   ```
   box run-script publish:release
   ```

## What `publish:release` does

It runs [build/release.boxr](build/release.boxr), which stops on the first failure, in order:

1. **Preflight** ([build/Release.cfc](build/Release.cfc) `target=preflight`). Aborts unless the
   working tree is clean, you are on `main`, tag `v<version>` does not already exist,
   `changelog.md` has a `## [<version>]` section, and `gh` is logged in.
2. **`git checkout -f main` + `git pull`** — release only what the remote has.
3. **Build** (`build:module`). Runs the test suite and aborts on any failure, then stages a slim
   module tree to `.tmp/erroralerts/`, zips it to `.artifacts/erroralerts/<version>/`, and
   verifies the zip holds every staged file.
4. **Publish from the built tree** (`cd .tmp/erroralerts` then `publish`), never the repo root —
   a bare `box publish` packages using `.gitignore`, and one stray ignore pattern can silently
   drop source folders from the published module.
5. **The GitHub half** (`target=github`): tag `v<version>`, push `main` and the tag, then
   `gh release create` with the changelog section as notes and the built zip + `.sha512`
   attached (`--prerelease` is added automatically when the version has a `-` suffix).

If a step **after** the ForgeBox publish fails (a push or the GitHub Release), the task prints the
exact commands to finish by hand — don't re-run the recipe, because preflight will now refuse
(the version is already on ForgeBox).

## Verifying without publishing

Safe checks that touch nothing:

- **List the scripts:** `box package show scripts` — confirm `publish:release`, `test:release`,
  and the `bump:*` entries are there.
- **Preview the release notes:**
  ```
  box task run taskFile=build/Release.cfc target=github :version=<version> :notesOnly=true
  ```
  Prints the changelog section that would become the GitHub Release body, then stops before any
  tag, push, or release.
- **Build only** (needs a running server): `box run-script build:module` — runs the suite, stages
  the tree, and writes the zip + checksums under `.artifacts/`, without publishing.

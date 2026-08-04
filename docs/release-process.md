# Release process

Run releases with `box run-script release`. Do not run `box publish` from the
repository root.

CommandBox reads `.gitignore` while packaging a repository. An unanchored
ignore pattern can remove a source directory with a matching name. A
caffeinecms release used such a pattern and shipped without required source
files. The release publishes the staged copy in `.tmp/erroralerts/` instead of
the repository root, so packaging never depends on `.gitignore`.

The release build requires the TestBox server on port 60310. It runs the full
test suite before packaging, stages the module in `.tmp/erroralerts/`, writes
the zip and checksums under `.artifacts/erroralerts/<version>/`, and publishes
the staged module.

After creating the zip, the build compares its file count with the staged
directory. This detects ignore rules, exclude expressions, or zip behavior
that removes source files.

## Settings

Everything this project changes lives in [build/build.json](../build/build.json).
The task files in `build/` are the shared build kit and are not edited here.

Exclusions apply only to top-level entries. Each value is a regular expression
passed to `reFindNoCase()`, which accepts partial matches. Anchor an expression
when its text could also match an entry that must ship. Add project-specific
exclusions to `excludesAdd`, which appends to the defaults; `excludes` replaces
the whole default list.

## Commands

| Command | What it does |
| --- | --- |
| `box run-script release:check` | Reports whether the project is ready to release. Changes nothing. |
| `box run-script release:dryrun` | Full rehearsal. Publishes, tags, and pushes nothing. |
| `box run-script release` | The release: check, sync, test, build, publish, tag, GitHub Release. |
| `box run-script release:skip-tests` | The release, skipping the test suite. |
| `box run-script release:hotfix` | The same as `release:skip-tests`, kept as an alias. |
| `box run-script release:existing-tag` | Publishes a version whose tag already exists at HEAD, instead of creating the tag. |
| `box run-script test:engines` | Runs the suite on every engine in turn. It runs every engine even after one fails, then prints a pass or fail line for each and exits non-zero if any failed. |
| `box run-script bump:patch` | Raises the version and dates the changelog. Also `bump:minor`, `bump:major`. |
| `box run-script bump:beta` | Starts a prerelease of the next minor version. Also `bump:alpha`. |
| `box run-script bump:prerelease` | Steps an existing prerelease forward, `beta.3` to `beta.4`. |
| `box run-script build:package` | Builds and checks the zip without publishing. |

A bump refuses when the changelog's `[Unreleased]` section is empty, and changes nothing when it
refuses. The dated section becomes the release notes on GitHub, so it must say something.

[RELEASE.md](../RELEASE.md) covers the routine step by step, including every bump level.

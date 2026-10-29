# Release process

Releases use [commandbox-release](https://github.com/homestar9/commandbox-release), which adds
`box release` commands to CommandBox. Its settings live in `release.json` in the repository root.
Do not run `box publish` from the repository root.

The package contents come from the `ignore` list in `box.json`, never from `.gitignore`. A
caffeinecms release once shipped without required source files because an unanchored ignore
pattern matched a source directory, so anchor directory patterns with a leading `/`.

This repository uses Gitflow. Stable releases run through `box release gitflow <level>` on
`develop` or a `release/*` branch. `branch` in `release.json` is the production branch, `main`.

## Commands

| Command | What it does |
| --- | --- |
| `box release check` | Reports whether the project is ready to release. Changes nothing. |
| `box release test` | Runs the suite on every engine in `release.json`, one after another. A release itself tests only the server that is already running. |
| `box release package` | Builds and checks the zip without publishing. |
| `box release publish --dryRun` | Full rehearsal from the current branch. Publishes, tags, and pushes nothing. |
| `box release gitflow minor` | On `develop`, creates the release branch, merges it into `develop` and `main`, and publishes. Also `patch`, `major`. |
| `box release bump <level>` | Raises the version and dates the changelog without committing. |

A release refuses when the changelog's `[Unreleased]` section is empty. The dated section becomes
the release notes on GitHub, so it must say something.

The integration specs read the harness's in-memory mailbox. Make sure `ERRORALERTS_MAILER` in
`.env` selects the `default` mailer before `box release test` starts the engines, or those specs
fail.

[RELEASE.md](../RELEASE.md) covers the routine step by step.

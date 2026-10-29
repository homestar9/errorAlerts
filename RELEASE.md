# Releasing errorAlerts

Releases use [commandbox-release](https://github.com/homestar9/commandbox-release), configured in
`release.json`. This repo uses Gitflow: work lands on `develop`, and `main` holds published versions.

## Set up once

```bash
box install commandbox-release
gh auth login
box forgebox login
```

## Release

1. On `develop`, describe the release under `## [Unreleased]` in `CHANGELOG.md`, then commit.
2. Set `ERRORALERTS_MAILER=default` in `.env`. The integration specs read the in-memory mailbox.
3. Test every engine in `release.json`. This starts and stops each server in turn:

   ```bash
   box release test
   ```

4. Start one engine (`box run-script start:lucee5`) for the release's own test run, then rehearse and release:

   ```bash
   box release gitflow minor --dryRun
   box release gitflow minor          # or patch / major
   ```

   This creates `release/x.y.z`, bumps the version, dates the changelog, runs the tests, merges
   into `main` and `develop`, publishes to ForgeBox and GitHub, pushes both branches, and deletes
   the release branch.

For a hotfix, branch `hotfix/x.y.z` from `main`, commit the fix and its changelog note, and run
`box release gitflow` on that branch.

## If something goes wrong

- `box release check` lists anything that would stop a release, without changing anything.
- If the release stopped after publishing, run `box release resume`. Do not run the release again.
- If the release stopped before publishing, fix the problem on the release branch, commit, and
  run `box release gitflow` again without a level.

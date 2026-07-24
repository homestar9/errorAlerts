# Release process

Run releases through `build/release.boxr`. Do not run `box publish` from the
repository root.

CommandBox reads `.gitignore` while packaging a repository. An unanchored
ignore pattern can remove a source directory with a matching name. A
caffeinecms release used such a pattern and shipped without required source
files.

The release build requires the TestBox server on port 60310. It runs the full
test suite before packaging, stages the module in `.tmp/erroralerts/`, writes
the zip and checksums under `.artifacts/erroralerts/<version>/`, and publishes
the staged module.

`Build.cfc` applies `variables.excludes` only to top-level entries. Each value
is a regular expression passed to `reFindNoCase()`, which accepts partial
matches. Anchor an expression when its text could also match an entry that
must ship.

After creating the zip, the build compares its file count with the staged
directory. This detects ignore rules, exclude expressions, or zip behavior
that removes source files.

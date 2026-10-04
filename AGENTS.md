# Verification

Gate: `powershell -NoProfile -ExecutionPolicy Bypass -File sweatshop/scripts/check.ps1`

The gate uses disposable local repositories and fake CLIs. Keep its full output
and exit status outside this repository; inspect the saved log for counts and
failures. Skill instructions and agent cards are production changes.

# Attempts

One folder per attempt, opened by a PR:

```
attempts/
  R07/
    R07-Vera-01/
      report.md          required (start from _template/report.md)
      aggregates.csv         optional: aggregate numbers only, < 512 KiB
      extract_metrics.py    optional: your own script
```

Raw logs, captures, `dumpbin` or Ghidra output, and binaries do not go here. That data stays in the local `REA-COORD\evidence\...` folder, and the report cites its path relative to the workspace.

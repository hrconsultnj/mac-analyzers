## What & why

## Checklist

- [ ] `bash -n` passes on every changed script
- [ ] Dry-run output of the changed script attached (redacted)
- [ ] Interactive menu still works (`FORCE_INTERACTIVE=1`)
- [ ] No personal data in tracked files (`git grep -iE "$(whoami)|$(hostname)"` is clean)
- [ ] Safety invariants intact (CONTRIBUTING.md) — analyzers read-only,
      cleaners dry-run-default, protect list wins, live-AI-session exemption kept
- [ ] New knobs documented in `config.example.sh`
- [ ] I agree my contribution is licensed per CONTRIBUTING.md

# Security policy

## Reporting

Please report vulnerabilities privately via GitHub's **Security Advisories**
("Report a vulnerability" on the repo's Security tab) rather than public
issues. Expect an acknowledgment within a few days.

## Scope & threat model

These are shell scripts that run with **your user's privileges**:

- Analyzers are read-only; cleaners delete only regenerable artifacts and are
  dry-run by default.
- The guard and reapers send `SIGTERM`/`SIGKILL` to processes matched by
  allowlist/protect-list regexes — a regex weakness that could match an
  unintended process **is** a valid report.
- The only privileged surface is the optional sudoers rule, deliberately
  scoped to one exact command
  (`/usr/bin/tmutil thinlocalsnapshots / 999999999999 4`). Anything that
  widens that surface, or any way to make the installers hydrate a template
  into something unexpected, is a valid report.
- launchd agents execute from the cloned repo path; treat the repo directory's
  write permissions accordingly.

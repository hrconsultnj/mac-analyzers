## What changed for people who use the app

<!-- Plain words, as if to someone who has never seen the code. For a change only a developer would notice, say so. -->

## Release notes

<!-- A change people would notice needs one bullet under "## Next" at the top of CHANGELOG.md, ending with its tag. -->

- [ ] I added a bullet under `## Next` in `CHANGELOG.md`, ending with its `<!-- wn: open=… icon=… -->` tag
- [ ] No user-visible change (a maintainer adds the `no-changelog` label)

## Checks

- [ ] `scripts/check.sh` passes on my Mac
- [ ] For a script change: the dry-run output is pasted below (redacted), and it also runs under `/bin/bash` (macOS 3.2)
- [ ] For an app change: renders of the affected screens, light and dark, are attached

## Never destroy user data

- [ ] Analyzers stay read-only, and cleaners stay dry-run unless `--apply` / `--execute` is passed
- [ ] The protect list still wins, and processes of a live AI session are still never touched
- [ ] Nothing deletes volumes, Time Machine backups, documents or recordings by itself
- [ ] No usernames, hostnames, project names or personal app lists in tracked files; new settings are documented in `config.example.sh`

## Licence

- [ ] I agree my contribution is licensed as described in `CONTRIBUTING.md`

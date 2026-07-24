# Contributing

Keep Hey Codex small, local, and understandable.

Before opening a pull request:

```bash
swift test
swift build -c release
for script in scripts/*.sh; do zsh -n "$script"; done
./scripts/test-install.sh
./scripts/test-install-latest.sh
./scripts/test-uninstall.sh
./scripts/test-release.sh
```

Keep changes focused and include a regression test when behavior changes. Install and uninstall tests must use disposable paths; never reset a contributor's live permissions or Codex data.

Please do not add analytics, accounts, a hosted backend, or a third-party runtime without first discussing why the native path is insufficient.

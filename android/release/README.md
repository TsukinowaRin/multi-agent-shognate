Fork APKs are no longer committed into this directory.

Use this repository's GitHub Releases page and download these assets as needed:

- `multi-agent-shognate-android-<version>.apk`
  - Android app package
  - SSH client / dashboard / host-side update UI
- `multi-agent-shognate-package.tar.gz`
  - canonical Shogunate runtime package for cURL bootstrap
- `multi-agent-shognate-package.zip`
  - archive package for manual extraction
- `multi-agent-shognate-package-<version>.tar.gz`
  - version-labeled copy of the same tag-fixed package
- `multi-agent-shognate-package-<version>.zip`
  - version-labeled copy of the same tag-fixed package

Recommended install / update:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

Pinned install / update:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash -s -- --version v4.6.0.12
```

Optional npm / npx wrapper:

```bash
npx @tsukinowarin/shogunate install -- --version v4.6.0.12
```

Packages:
  - expand into `$SHOGUNATE_HOME` or `~/.shogunate/shogunate` by default
  - never pull moving `main` when installed from a Release asset
  - preserve local state such as `config/settings.yaml`, `queue/`, `logs/`, and `.shogunate/`
  - run `first_setup.sh`
  - do not publish OS-specific installer assets

Release versions follow upstream plus a fork revision: `v<upstream-version>.<fork-revision>`.
With the current upstream baseline, aligned examples are `v4.6.0.0` and `v4.6.0.12`.

This avoids confusion with the upstream `multi-agent-shogun.apk`.

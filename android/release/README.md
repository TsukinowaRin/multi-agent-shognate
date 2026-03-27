Fork APKs are no longer committed into this directory.

Use this repository's GitHub Releases page and download these assets as needed:

- `multi-agent-shognate-android-<tag>.apk`
  - Android app package
  - SSH client / dashboard / host-side update UI
- `multi-agent-shognate-installer-<version>.bat`
  - Windows first-time installer
  - expands the matching Release snapshot into the folder where you place it
  - runs `first_setup.sh`
- `multi-agent-shognate-updater-<version>.bat`
  - Windows updater for an existing portable install
  - updates that installed copy to the latest Release
  - can also enable or disable startup auto-update for Release installs

Portable installs created by the installer also contain `Shogunate-Uninstaller.bat` inside the installed folder. The uninstaller lets you either preserve personal data outside the install folder or delete everything and prepare for a clean reinstall into the same folder.

Release tags are versioned as `android-v4.2.0.x`.

This avoids confusion with the upstream `multi-agent-shogun.apk`.

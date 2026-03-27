Fork APKs are no longer committed into this directory.

Use this repository's GitHub Releases page and download these assets as needed:

- `multi-agent-shognate-android-<tag>.apk`
  - Android app package
  - SSH client / dashboard / host-side update UI
- `multi-agent-shognate-installer-<version>.bat`
  - Windows installer and in-place updater for portable installs
  - expands the matching Release snapshot into the folder where you place it
  - if that folder already contains an older portable Release install, it updates that copy while preserving personal data
  - runs `first_setup.sh`

Portable installs created by the installer also contain `Shogunate-Uninstaller.bat` inside the installed folder. The uninstaller lets you either preserve personal data outside the install folder or delete everything and prepare for a clean reinstall into the same folder.

Release tags are versioned as `android-v4.2.0.x`.

This avoids confusion with the upstream `multi-agent-shogun.apk`.

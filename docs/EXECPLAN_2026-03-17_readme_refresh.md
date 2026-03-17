# ExecPlan: README Refresh

## Context
- Root README files have accumulated upstream text plus incremental fork notes.
- The current README mentions some fork specifics, but the overall story is still upstream-shaped and underspecified for this repository's actual distribution and runtime model.
- The user requested a full rewrite in both English and Japanese that clearly explains installation, multi-CLI coverage, APK distribution, and the concrete differences from upstream.

## Scope
- Rewrite `README.md` and `README_ja.md` as mirrored documents.
- Document this fork's supported CLI/vendor matrix, Android APK distribution, portable installer behavior, and upstream differences.
- Update docs metadata so the rewrite intent is traceable.

## Acceptance Criteria
- `README.md` and `README_ja.md` both describe:
  - recommended Windows install via Release installer
  - manual install via clone/ZIP
  - multi-CLI support including Gemini CLI, OpenCode, Kilo, localapi, Ollama, LM Studio
  - fork APK distribution and Android connection model
  - concrete differences from upstream
- The docs index and requirements mention this rewrite.
- `git diff --check` passes.

## Work Breakdown
1. Normalize requirements for the README rewrite.
2. Add this ExecPlan to the docs index.
3. Rewrite `README.md`.
4. Rewrite `README_ja.md`.
5. Run validation and publish the checkpoint.

## Progress
- 2026-03-17: Started. Current README content, docs policy, and related implementation points were reviewed.
- 2026-03-17: Rewrote `README.md` and `README_ja.md` around fork-specific install, runtime, CLI coverage, Android APK distribution, and upstream differences.

## Surprises & Discoveries
- The current root README already contains many fork notes, but they are scattered through an upstream-length document and understate newer additions such as portable release installers and broader CLI coverage.

## Decision Log
- Rewrite the root README pair rather than append more fork notes.
- Keep the documents shorter and more operational than upstream, focusing on what this repository actually ships and supports.

## Outcomes & Retrospective
- Root README files were rewritten as mirrored documents focused on this fork's actual runtime and release story.
- Installation, Android APK distribution, multi-CLI coverage, and upstream differences are now first-class sections instead of scattered notes.

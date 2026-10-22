# GitHub Pages Offline Demo Implementation Plan

> **For agentic workers:** Implement each checked task in order, following test-first steps and preserving commits as reviewable units.

**Goal:** Publish the current visual demo at the Pages root in a clearly labeled offline mode while keeping online publication gated by the existing strict production probe.

**Architecture:** Keep the existing `visual_demo` export and `web_playtest` local browser tests. Add an explicit Pages mode to the release policy; the offline artifact contains a dedicated offline landing and `/demo/` only. Online mode keeps the previous landing/playtest layout and executes the existing exact-SHA plus protocol/snapshot probe.

**Tech Stack:** Godot 4.4.1, GitHub Actions/Pages, Python 3 policy and artifact checks, Node/Playwright Chromium.

**Spec:** User-provided “SUSPEITOS — PUBLICAR VERSÃO WEB OFFLINE NO GITHUB PAGES” request (2026-10-22).

## Global Constraints

- Railway remains on protocol 11 and is not accessed, updated, restarted, or modified.
- The offline demo must not make a multiplayer connection or publish online links.
- Online Pages publication still requires a full exact main SHA and the existing live protocol/snapshot probe.
- Existing gameplay and multiplayer tests remain enabled.
- Publish only the Web Demo export and offline landing in offline mode.
- Run on Godot 4.4.1; verify the final deployed commit and Pages deployment status.

## Review Focus

- Missing/incorrect mode or SHA must not publish Pages: policy tests reject it.
- Offline mode must not call the online endpoint or include the playtest path: policy, artifact scan, and browser smoke test.
- Online release must still require exact SHA and matching live snapshots: retain policy and probe tests.
- Base-path links must work at `/ossuspeitos/`: browser test opens the actual repository base path.
- GLB/model/animation/render failures must be visible in Chromium: demo browser smoke checks readiness, canvas, assets, and console errors.

---

### Task 1: Explicit offline and online publication policy

**Files:** Modify `scripts/pages_release_policy.py` and `tests/pages_release_policy_test.py`.

- [ ] Add first a test for explicit offline and online dispatch, exact SHA, and rejection of missing/invalid modes, push/PR events, wrong ref, and wrong SHA.
- [ ] Verify the new cases fail against the existing single-mode policy.
- [ ] Add a separate online mode with the same exact-SHA eligibility. Preserve strict probe validation unchanged.
- [ ] Run the policy suite; both modes should be eligible only on manual main dispatch with exact SHA.

### Task 2: Offline landing and artifact isolation

**Files:** Preserve the current online landing as `web/site/online-index.html`; replace `web/site/index.html` with the Portuguese offline presentation. Add `scripts/verify_offline_site.py` and `tests/offline_site_artifact_test.py`.

- [ ] Write tests for an offline site containing its landing, Web Demo files, and `/demo/`, while rejecting `/playtest/`, online labels/endpoints, absent assets, and Web entry files.
- [ ] Verify tests fail before the checker exists.
- [ ] Implement the checker against a directory tree; inspect all public text and packed bytes for the production WebSocket URL and prohibited online paths.
- [ ] Build test fixture directories for valid and invalid offline artifacts and run the checker tests.

### Task 3: Mode-specific Pages assembly and browser validation

**Files:** Modify `.github/workflows/godot-web-build.yml`; add `tests/web_demo_browser.mjs`; document the demo in `web/site/index.html` and `docs/decisions.md`.

- [ ] Keep both existing exports and the full local Web Playtest tests on the workflow head.
- [ ] Offline assembly includes the offline landing plus `build/web` at `/demo/` only and runs the artifact checker.
- [ ] Online assembly uses the preserved online landing and both existing export paths.
- [ ] The offline release deploy job checks current main SHA but skips online protocol probing. Online mode retains the existing full-SHA, matching protocol, joined room, and live snapshot probe.
- [ ] Chromium opens the offline root, follows its demo link, observes `DEMO_READY network=disabled`, confirms a rendered canvas/models, exercises camera/movement inputs, watches briefly for stability, and fails on any WebSocket or engine/page error.
- [ ] Run the demo test, full browser tests, export verification, and all workflow-required checks.

### Task 4: Publish and confirm Pages

**Files:** No further implementation files.

- [ ] Review the branch diff and ensure no Railway or production configuration changed.
- [ ] Wait for all PR checks, then merge the validated exact head.
- [ ] Wait for post-merge checks and dispatch offline mode with the full main SHA.
- [ ] Confirm the Pages deployment SHA, completed status, live landing content, `/demo/` entry, and that `/playtest/` is absent.


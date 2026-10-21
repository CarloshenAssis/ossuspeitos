# Independent menu cleanup review

Verdict: PASS. No findings.

Reviewed AGENTS.md, immutable menu-cleanup-review.patch, commit f639d83 (base 0d9bc69), and the complete tests/menu_flow_test.sh lifecycle. The only source change adds exec to server(). All five callers (retry, shutdown, full, name and rooms) run in the background, so exec replaces their function subshell with Godot and makes captured $! the process that explicit kill/wait and EXIT cleanup must own. menu() has foreground callers, so applying the same change there would be unsafe.

The patch preserves all arguments, flags, redirections, assertions, timeouts, status handling and gameplay. No production source changes. Scope and project guidance are satisfied.

Validation evidence reviewed: menu-cleanup-report.md, menu-cleanup-console.log ending MENU_FLOW_TEST_OK scenes=10, menu-cleanup-pid-repro.json showing the old child survives and exec process does not, and menu-cleanup-process-audit.json showing owned_servers_left=0 after normal EXIT by current UID, exact executable, server mode and ports 39800–39809. The report records suite status 0 under pinned Godot 4.4.1 without group or manual suite cleanup. Independent bash -n passed. No redundant suite was run for this review.

Known bounded limitation: asynchronous menu() wrappers can retain timeout/Godot descendants after unexpected harness exit until their existing 120-second timeout. This is unchanged and outside this persistent-server fix.

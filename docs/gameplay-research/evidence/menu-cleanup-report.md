# Menu harness server lifecycle cleanup

Baseline: root previously verified four detached Godot menu_flow servers on ports 33072/33075/33076/33077 by UID, executable and logs under `/workspace/.ossuspeitos-state/spec00-tests/menu_flow`, then terminated only those individual processes. This observation is also recorded in repository mission-progress.md. No old full suite was repeated.

Cause: `server()` launched Godot as a child of its background Bash function subshell; `$!` stored the subshell PID. Explicit scenario termination and EXIT cleanup signalled that Bash process, allowing Godot to remain. The only implementation change adds `exec` in `server()`, replacing that subshell with Godot while preserving the captured PID and all arguments, log redirections, assertions, timeouts and exit handling.

All five calls are backgrounded: retry-server, shutdown-server, full-server, name-server and rooms-server (the latter spans two lines). `menu()` has foreground callers and was intentionally left unchanged.

Focused reproduction: `menu-cleanup-pid-repro.json` records the same background function structure using sleep. Before exec captured PID 68088 had child 68089, which survived termination of 68088. With exec captured PID 68093 was the process itself and no process survived its termination. Only exact owned reproduction processes were terminated. An initial reproduction attempt could not read proc children; its exact known sleep/function PIDs 67688/67687 were subsequently cleaned, and the successful reproduction uses ps instead.

Verification: sourced `/workspace/.ossuspeitos-state/mission-sdd/env.sh`, pinned Godot 4.4.1, GAME_PATH=/workspace/ossuspeitos, TEST_PORT=39800, TEST_LOG_DIR=/workspace/.ossuspeitos-state/mission-sdd/menu-cleanup. Actual tests/menu_flow_test.sh exited 0 and printed `MENU_FLOW_TEST_OK scenes=10`; complete console is `menu-cleanup-console.log`, scenario logs in `menu-cleanup/`. `bash -n` and `git diff --check` also pass.

After normal harness EXIT, `menu-cleanup-process-audit.json` records zero owned Godot servers by exact executable argv[0], current UID, --mode=server and unique ports 39800–39809. No process group kill or manual cleanup of the real suite was used. The initial proc scan was replaced with this explicit ps audit because proc child metadata is unavailable in this sandbox.

Remaining bounded caveat: menu() remains a background function wrapping timeout 120 when invoked asynchronously. Unexpected early harness exit can leave its timeout/Godot descendants until their existing 120-second bound; this narrow fix covers persistent server processes and does not redesign menu cancellation. Normal tested completion leaves no servers. No production, gameplay, common profile, workflow or root ledger edits.

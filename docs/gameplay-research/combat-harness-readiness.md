# Combat harness prediction readiness

The coordinator could acknowledge INITIAL after receiving reliable private state
and public pickups, before the first world snapshot initialized prediction.
CONTEST then called `queue_test_action`, which previously accepted an action even
though `_commands_enabled()` prevented command building. First-state or new-epoch
`PlayerPrediction.reconcile` correctly clears queued actions. The coordinator saw
success and therefore did not retain its retry. The action disappeared before it
could reach the authoritative server.

`queue_test_action` now uses the existing command eligibility barrier. INITIAL
also waits on that barrier. The existing coordinator retry retains refused
actions until prediction has state and epoch synchronization completes. Prediction
clearing and raw `send_test_packet` rejection probes remain unchanged. No damage,
round, protocol, timing, timeout, or gameplay assertion changed.

The regression in `combat_network_coordinator_test.gd` instantiates the actual
NetworkApp and its PlayerPrediction. It covers refusal before the first snapshot,
clearing old actions at reconciliation, retry after release, exactly one intended
pickup in the built command, a new epoch, and disconnected/shutdown/dead gates.
Against the old enqueue implementation it exits 1 with readiness and gate
assertion failures; with the fix it passes 37 total coordinator checks.

Pinned Godot 4.4.1 validation logs are stored outside the repository under
`/workspace/.ossuspeitos-state/mission-sdd/combat-flake/`. Netcode passes 266 checks,
combat authority passes 86, and the unchanged four-client combat harness passes.
The unchanged eight-client extended harness also passes, including spectator,
post-end rejection, next-round reset, and complete eight-peer shutdown checks.

The historical SPEC04 CONTEST log (ACKs before movement authorization, no
pickup results or rejection) is consistent with this race. Source and the
regression establish the action-loss mechanism; the historical clients did not
log enough enqueue/epoch detail to prove the exact interleaving. The initial CI
eight-client failure has no available step log and cannot be assigned this cause.
No visual suites or remote environment were retested for this focused change.

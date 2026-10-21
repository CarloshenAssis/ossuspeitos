# SPEC 02 — prediction and reconciliation

Implemented on SPEC01 (`669b109`), protocol 11 and WebSocket/TCP unchanged. No Quake/GPL source incorporated; the existing shared deterministic integrator, replay and interpolation remain in place.

Accepted epoch changes now discard pending commands, queued actions, raw/split mouse input, its timestamp and presentation offsets/ages. An older epoch ACK is rejected before official/predicted state changes, including equal or higher cumulative sequences. A new epoch may retain the same cumulative ACK. `reset_all()` remains the session boundary; sequence/telemetry policy was not changed.

Tests cover queued fire across reset, stale epoch snapshots without mutation, 91 builds triggering exactly one recovery, <=90 pending, <=32 server commands, <=32 remote samples, bounded six-tick extrapolation, one movement/action application for duplicate commands, old epoch action refusal and late application commands arriving after a cumulative ACK. Omission/reordering/duplication here are application-adversarial injections, **not physical TCP loss**.

The combat test fixture retained itself through `Loop -> action_runner -> Loop`. Capturing a `WeakRef` breaks this cycle. Before: ObjectDB leak warning and nine resources still in use; after: neither diagnostic. Existing six CharacterModel owner warnings remain visible.

`NetStats` now emits six decimal places, separate bounded yaw/pitch error samples, and bounded pending-age percentiles. The deterministic loop reports queue/pending high water. Existing combined look and snapshot metrics remain compatible.

## Verification and reproduction

Pinned engine: Godot 4.4.1 `49a5bc7b6`. Logs: `/workspace/.ossuspeitos-state/mission-sdd/spec02/` (outside checkout).

```bash
export GODOT_BIN=/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config
export XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache
export XDG_DATA_HOME=/workspace/.ossuspeitos-state/data
for test in movement_config movement_rules netcode arena_layout vertical_aim; do
  "$GODOT_BIN" --headless --path . --script "tests/${test}_test.gd"
done
TEST_LOG_DIR=/tmp/spec02-smoke bash tests/network_smoke_test.sh
for profile in local rtt50 rtt100 rtt200 rtt150j; do
  PROFILE=$profile SEED=1 TEST_LOG_DIR=/tmp/spec02-$profile bash tests/sync_network_test.sh
done
PROFILE=rtt150j SEED=1 STALL=true TEST_LOG_DIR=/tmp/spec02-stall bash tests/sync_network_test.sh
```

All commands passed exit 0 and their success markers, with real server + four clients and the deliberately incompatible fifth client rejected exit 1. Invalid PROFILE exits 2 before spawning. Final netcode has 266 checks. `red.log` records eight meaningful failures before production fixes; initial weakref type-inference parse failure is recorded in the report and is not red evidence.

Baseline deterministic replay (local/jitter) had worst ACK position error 0.000000 m. The final deterministic replay remains 0.000000 m, yaw/pitch differences below 1e-6 rad. A separate convergence case intentionally displaces the server by 0.2 m: its max correction error is 0.200000 m and must not be mistaken for a failed exact-replay gate. Its yaw/pitch p50/p95/max are all 0.000000 rad.

A controlled copy with final instrumentation/profiles but only the two epoch fixes reverted reproduces seven gameplay assertion failures. Its convergence, position percentiles and queue/pending high-water results match final results exactly; this is a regression fix, no throughput or latency improvement is claimed.

| Profile | Tick-loop base delay up/down ms | Convergence before/after s | Peak pending | Peak server queue |
|---|---:|---:|---:|---:|
| local | 0 / 0 | .100 / .100 | 4 | 2 |
| rtt50 | 33.333 / 33.333 | .133 / .133 | 8 | 2 |
| rtt80 | 33.333 / 50 | .133 / .133 | 9 | 2 |
| rtt100 | 50 / 50 | .150 / .150 | 10 | 2 |
| rtt200 | 100 / 100 | .233 / .233 | 16 | 2 |
| rtt150j | 66.667 / 66.667 plus 0–2 ticks jitter | .200 / .200 | 16 | 4 |

The tick-loop rtt50 rounds 25 ms to two ticks/side, hence effective base RTT 66.667 ms. These are simulated deadlines, not measured physical RTT. The real application-delay wrapper uses configured 25/50/100 ms each way and measures time actually held, including poll quantization. Existing local/rtt80/rtt150j/rtt150j_stall profiles remain available.

Representative real-process applied delays (last actor report, seed 1, first complete run):

| Profile | Configured up/down ms | Measured up p50/p95/max ms | Measured down p50/p95/max ms |
|---|---:|---:|---:|
| rtt50 | 25 / 25 | 27.4 / 27.7 / 29.4 | 27.5 / 27.8 / 31.9 |
| rtt100 | 50 / 50 | 55.0 / 55.3 / 62.5 | 55.3 / 55.6 / 59.1 |
| rtt200 | 100 / 100 | 103.4 / 103.6 / 104.8 | 103.5 / 103.7 / 105.2 |
| rtt150j | 65 / 65 + 0–20 jitter | 82.2 / 89.5 / 89.8 | 76.3 / 89.8 / 90.3 |
| rtt150j + stall | same + 400 ms interruption | 75.8 / 89.6 / 387.7 | 76.2 / 89.9 / 374.2 |

MOVE reports: max pending local/50/100/200/jitter/stall = 6/9/12/18/16/34; max pending age = 83/131/187/283/249/552 ms. Position and combined look ACK p50/p95/max were zero to six decimals for all six MOVE reports. Stall snapshot interval max was 339.900 ms. For rtt200 pending age p50/p95/max = 248.460/269.209/282.938 ms; snapshots =128, interval p50/p95/max =48.336/55.173/55.327 ms. Stall pending age =317.469/517.652/551.967 ms. All MOVE small/large corrections and recoveries =0. Deterministic forced-displacement scenarios each record one small correction, zero large.

Historical SPEC01 local MOVE vs first SPEC02 local MOVE: snapshot interval p50/p95/max 48.3/55.5/56.6 ->48.301/55.464/56.010 ms; snapshots127->128, peak pending5->6, age70->83 ms. These small scheduling differences are not a performance regression/improvement claim; old ACK metrics had insufficient precision.

Limitations: one deterministic seed7 and real-process seed1, loopback headless only; no physical TCP impairment/retransmission measurements, WAN, browser/mobile exports or new visual acceptance. No full network campaign suite claimed. New profiles have no historical real-process pre-fix comparison; controlled before/after comparison is in-process. Final local/50/100 reruns also capture the newly added per-axis and age instrumentation.

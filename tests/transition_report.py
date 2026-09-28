#!/usr/bin/env python3
"""Fase 10: relatório das linhas `TRANSITION` (medição de transições).

Uso: tests/transition_report.py [--max-network-ms N] log1 [log2 ...]

Lê as linhas `TRANSITION kind=... ms=... class=... round=... session=...`
dos logs de cliente/servidor e imprime, por medida, a classe e n/min/p50/p95/
max em ms. Com `--max-network-ms`, sai com 1 se alguma medida de rede ou de
servidor passar do limite (atraso anormal numa transição de sala).
"""

import re
import sys

LINE = re.compile(r"TRANSITION kind=(\S+) ms=([0-9.]+) class=(\S+) round=(\d+) session=(\S+)")
# Classes medidas contra o limite: pedido/resposta e trabalho do servidor.
# `ux` (contagem, resultado) e `render` têm leitura própria no relatório.
BOUNDED = {"network", "server"}


def percentile(values, fraction):
    return values[int((len(values) - 1) * fraction)]


def main(argv):
    limit = None
    paths = []
    args = iter(argv)
    for arg in args:
        if arg == "--max-network-ms":
            limit = float(next(args))
        else:
            paths.append(arg)
    kinds = {}
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for text in handle:
                match = LINE.search(text)
                if match:
                    kind, ms, cls = match.group(1), float(match.group(2)), match.group(3)
                    kinds.setdefault(kind, (cls, []))[1].append(ms)
    if not kinds:
        print("TRANSITION_REPORT_EMPTY")
        return 1
    print("TRANSITION_REPORT %-26s %-8s %4s %9s %9s %9s %9s" % ("kind", "class", "n", "min", "p50", "p95", "max"))
    over = []
    for kind in sorted(kinds):
        cls, values = kinds[kind]
        values.sort()
        print("TRANSITION_REPORT %-26s %-8s %4d %9.1f %9.1f %9.1f %9.1f" % (
            kind, cls, len(values), values[0], percentile(values, 0.5), percentile(values, 0.95), values[-1]))
        if limit is not None and cls in BOUNDED and values[-1] > limit:
            over.append("%s=%.1f" % (kind, values[-1]))
    if over:
        print("TRANSITION_REPORT_SLOW limit_ms=%.0f %s" % (limit, " ".join(over)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

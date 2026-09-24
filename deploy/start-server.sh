#!/bin/sh
# Start do servidor dedicado no container (fase 8).
#
# O Godot 4.4.1 não trata SIGTERM: o processo morre na hora (143) sem avisar
# os jogadores. Este wrapper fica como PID 1, repassa o pedido de parada ao
# jogo por um arquivo que o servidor verifica a cada ~0,25 s e espera o
# encerramento coordenado (aviso aos clientes, fechamento dos peers, saída 0).
# Se o jogo não sair em ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS, envia SIGKILL.
#
# Sem loop de restart, sem sleep infinito: o container vive exatamente
# enquanto o processo do jogo vive e sai com o código dele.
set -u

SERVER_BIN="${ARMED_MYSTERY_SERVER_BIN:-/app/armed-mystery-server.x86_64}"
STOP_FILE="${ARMED_MYSTERY_SHUTDOWN_FILE:-/tmp/armed-mystery.stop}"
GRACE="${ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS:-8}"

case "$GRACE" in
  ''|*[!0-9]*) echo "WRAPPER_CONFIG_ERROR ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS inválida: '$GRACE'" >&2; exit 2 ;;
esac

rm -f "$STOP_FILE"
"$SERVER_BIN" --headless -- --mode=dedicated --shutdown-file="$STOP_FILE" "$@" &
child=$!
killer=""

request_stop() {
  if [ -n "$killer" ]; then return; fi
  echo "WRAPPER_SIGNAL stop_requested grace_s=$GRACE"
  : > "$STOP_FILE"
  ( sleep "$GRACE"; if kill -0 "$child" 2>/dev/null; then echo "WRAPPER_GRACE_EXPIRED sending=SIGKILL"; kill -KILL "$child" 2>/dev/null; fi ) &
  killer=$!
}
trap request_stop TERM INT

# `wait` volta antes da hora quando um sinal com trap chega: repete até o
# processo do jogo terminar de fato.
status=0
while :; do
  wait "$child"
  status=$?
  if ! kill -0 "$child" 2>/dev/null; then break; fi
done
if [ -n "$killer" ]; then kill "$killer" 2>/dev/null; fi
rm -f "$STOP_FILE"
echo "WRAPPER_EXIT code=$status"
exit "$status"

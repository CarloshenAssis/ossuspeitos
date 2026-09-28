class_name TransitionMetrics
extends RefCounted

## Fase 10: medição leve das transições que o jogador sente (criar/entrar em
## sala, PRONTO -> contagem, contagem -> partida, eliminação, resultado, volta
## ao lobby, erros). Desligada por padrão: liga com `--transition-metrics=true`
## (ou `?transition-metrics=true` na página Web).
##
## Cada medida vira uma linha `TRANSITION` com a duração em ms e uma classe:
##   ux       espera que faz parte do jogo (contagem, tela de resultado);
##   network  pedido do cliente -> resposta do servidor (inclui ida e volta);
##   server   trabalho do servidor dentro do processo;
##   render   quadro lento do cliente depois de trocar de tela;
##   unknown  medida sem origem determinada.
## Sem papel, código de sala, nome, IP, inventário ou payload: só um id de
## sessão aleatório, o número da rodada e a duração.

const CLASS_UX := "ux"
const CLASS_NETWORK := "network"
const CLASS_SERVER := "server"
const CLASS_RENDER := "render"
const CLASS_UNKNOWN := "unknown"

## Nome da medida -> classe. Medidas fora da lista viram `unknown`.
const KINDS := {
	"room_create": CLASS_NETWORK,        # CRIAR SALA -> estado da sala recebido
	"room_join": CLASS_NETWORK,          # ENTRAR EM SALA -> estado da sala recebido
	"ready_ack": CLASS_NETWORK,          # PRONTO -> estado da sala com o PRONTO
	"countdown": CLASS_UX,               # contagem vista pelo cliente (esperada ~10 s)
	"countdown_to_play": CLASS_NETWORK,  # fim previsto da contagem -> tela da partida
	"play_first_snapshot": CLASS_NETWORK,  # partida -> primeiro snapshot da época nova
	"elimination_to_body": CLASS_NETWORK,  # aviso de eliminação -> corpo na tela
	"ended_to_reveal": CLASS_NETWORK,    # ENDED -> revelação dos papéis
	"results_to_lobby": CLASS_UX,        # resultado -> lobby da sala (esperado ~8 s)
	"connect": CLASS_NETWORK,            # conectar -> boas-vindas do servidor
	"error": CLASS_NETWORK,              # pedido -> erro do servidor
	"server_tick": CLASS_SERVER,         # tick mais lento do servidor (janela)
	"server_ready_to_countdown": CLASS_SERVER,  # último PRONTO -> contagem publicada
	"render_hitch": CLASS_RENDER,        # quadro mais lento após trocar de tela
}

var enabled := false
var session := ""
var round_id := 0
var records: Array = []
var _marks: Dictionary = {}
var _clock: Callable

func _init(on: bool = false, clock: Callable = Callable(), session_id: String = "") -> void:
	enabled = on
	_clock = clock
	session = session_id if not session_id.is_empty() else "%06x" % (randi() & 0xffffff)

static func from_arguments(arguments: Dictionary) -> TransitionMetrics:
	return TransitionMetrics.new(NetworkConfig.bool_argument(arguments, "transition-metrics"))

func now_usec() -> int:
	return int(_clock.call()) if _clock.is_valid() else Time.get_ticks_usec()

## Marca o começo de uma medida. Uma nova marca com o mesmo nome substitui a
## anterior (só a tentativa mais recente conta).
func begin(kind: String, at_usec: int = -1) -> void:
	if not enabled:
		return
	_marks[kind] = at_usec if at_usec >= 0 else now_usec()

func has(kind: String) -> bool:
	return _marks.has(kind)

func cancel(kind: String) -> void:
	_marks.erase(kind)

## Fecha a medida aberta com `begin`. Devolve a duração em ms (ou -1).
## `record_as` registra com outro nome (pedido que terminou em erro).
func end(kind: String, at_usec: int = -1, record_as: String = "") -> float:
	if not enabled or not _marks.has(kind):
		return -1.0
	var started := int(_marks[kind])
	_marks.erase(kind)
	return record(record_as if not record_as.is_empty() else kind,
		float((at_usec if at_usec >= 0 else now_usec()) - started) / 1000.0)

## Registra uma duração medida por outro caminho (tick lento, quadro lento).
func record(kind: String, ms: float) -> float:
	if not enabled:
		return -1.0
	var value := maxf(0.0, ms)
	var entry := {"kind": kind, "ms": value, "class": classify(kind), "round": round_id}
	records.append(entry)
	print(line(entry, session))
	return value

static func classify(kind: String) -> String:
	return str(KINDS.get(kind, CLASS_UNKNOWN))

static func line(entry: Dictionary, session_id: String) -> String:
	return "TRANSITION kind=%s ms=%.1f class=%s round=%d session=%s" % [
		str(entry["kind"]), float(entry["ms"]), str(entry["class"]), int(entry["round"]), session_id]

## Resumo por medida: n, mínimo, mediana, p95 e máximo (ms).
static func summarize(entries: Array) -> Dictionary:
	var by_kind: Dictionary = {}
	for entry in entries:
		var kind := str(entry["kind"])
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(float(entry["ms"]))
	var result: Dictionary = {}
	for kind in by_kind.keys():
		var values: Array = by_kind[kind]
		values.sort()
		result[kind] = {
			"class": classify(kind),
			"n": values.size(),
			"min": float(values[0]),
			"p50": float(values[int(floor((values.size() - 1) * 0.5))]),
			"p95": float(values[int(floor((values.size() - 1) * 0.95))]),
			"max": float(values[-1]),
		}
	return result

## Uma linha `TRANSITION ...` de volta em entrada (para o relatório).
static func parse_line(text: String) -> Dictionary:
	var at := text.find("TRANSITION ")
	if at < 0:
		return {}
	var fields := {}
	for token in text.substr(at + 11).strip_edges().split(" ", false):
		var parts := token.split("=", true, 1)
		if parts.size() == 2:
			fields[parts[0]] = parts[1]
	if not fields.has("kind") or not fields.has("ms") or not str(fields["ms"]).is_valid_float():
		return {}
	return {"kind": str(fields["kind"]), "ms": str(fields["ms"]).to_float(),
		"class": str(fields.get("class", CLASS_UNKNOWN)), "round": str(fields.get("round", "0")).to_int()}

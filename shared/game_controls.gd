class_name GameControls
extends RefCounted

## Fonte única dos controles do jogo (fase 7). Registra as ações no InputMap
## (idempotente) e descreve cada uma para a tela "Como jogar", que lê as
## teclas do próprio InputMap: o que aparece no menu é o que o jogo usa.
##
## O olhar com o mouse não é ação do InputMap (é movimento relativo com o mouse
## capturado); aparece na lista como entrada fixa do grupo "Câmera".

const GROUPS := ["Movimento", "Câmera", "Interação e coleta", "Disparo", "Recarga", "Espectador", "Mouse", "Sair"]

## Ação -> grupo, descrição e tecla padrão (tecla física ou botão do mouse).
const ACTIONS := [
	{"action": "move_forward", "group": "Movimento", "text": "Andar para frente", "key": KEY_W},
	{"action": "move_backward", "group": "Movimento", "text": "Andar para trás", "key": KEY_S},
	{"action": "move_left", "group": "Movimento", "text": "Andar para a esquerda", "key": KEY_A},
	{"action": "move_right", "group": "Movimento", "text": "Andar para a direita", "key": KEY_D},
	{"action": "interact", "group": "Interação e coleta", "text": "Pegar arma ou munição próxima", "key": KEY_E},
	{"action": "fire", "group": "Disparo", "text": "Atirar (com arma na mão)", "mouse": MOUSE_BUTTON_LEFT},
	{"action": "reload", "group": "Recarga", "text": "Recarregar", "key": KEY_R},
	{"action": "spectate_previous", "group": "Espectador", "text": "Observar o jogador anterior (eliminado)", "key": KEY_Q},
	{"action": "spectate_next", "group": "Espectador", "text": "Observar o próximo jogador (eliminado)", "key": KEY_E},
	{"action": "release_mouse", "group": "Mouse", "text": "Soltar o mouse (clique na janela para capturar de novo)", "key": KEY_ESCAPE},
	{"action": "leave_match", "group": "Sair", "text": "Sair da partida e voltar ao menu", "key": KEY_F10},
]

## Entradas que não são ações do InputMap.
const FIXED := [
	{"group": "Câmera", "text": "Olhar ao redor (mouse capturado)", "input": "Mouse"},
	{"group": "Mouse", "text": "Capturar o mouse para jogar", "input": "Clique na janela"},
]

## Registra as ações que ainda não existem. Chamar várias vezes não duplica
## eventos (antes, cada `ArenaView` nova somava outra tecla igual).
static func ensure() -> void:
	for entry in ACTIONS:
		var action := str(entry["action"])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if not InputMap.action_get_events(action).is_empty():
			continue
		if entry.has("key"):
			var key := InputEventKey.new()
			key.physical_keycode = int(entry["key"])
			InputMap.action_add_event(action, key)
		else:
			var button := InputEventMouseButton.new()
			button.button_index = int(entry["mouse"])
			InputMap.action_add_event(action, button)

## Texto de uma entrada do InputMap, em português.
static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = (event as InputEventKey).physical_keycode
		if code == 0:
			code = (event as InputEventKey).keycode
		var text := OS.get_keycode_string(code)
		return {"Escape": "Esc"}.get(text, text)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Botão esquerdo do mouse"
			MOUSE_BUTTON_RIGHT: return "Botão direito do mouse"
			MOUSE_BUTTON_MIDDLE: return "Botão do meio do mouse"
	return event.as_text()

## Teclas atuais de uma ação, lidas do InputMap.
static func action_text(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	var parts: Array = []
	for event in InputMap.action_get_events(action):
		parts.append(event_text(event))
	return " / ".join(PackedStringArray(parts))

## Linhas da tela "Como jogar", por grupo, na ordem de `GROUPS`.
static func help_rows() -> Array:
	ensure()
	var rows: Array = []
	for group in GROUPS:
		for entry in FIXED:
			if str(entry["group"]) == group:
				rows.append({"group": group, "input": str(entry["input"]), "text": str(entry["text"]), "action": ""})
		for entry in ACTIONS:
			if str(entry["group"]) == group:
				rows.append({"group": group, "input": action_text(str(entry["action"])), "text": str(entry["text"]), "action": str(entry["action"])})
	return rows

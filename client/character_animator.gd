class_name CharacterAnimator
extends RefCounted

## Repouso e locomoção procedurais de um personagem remoto (fase 3). Camada só
## de apresentação: lê a posição e o yaw já apresentados pela `ArenaView`
## (interpolados do estado oficial) e escreve apenas nos pivôs criados por
## `CharacterRig` e na altura do nó visual `CharacterModel`. Não toca na raiz do
## avatar (posição e yaw oficiais), no pivô da cabeça (pitch), na câmera, na
## colisão ou em qualquer dado enviado ao servidor.
##
## A fase do ciclo avança com a distância horizontal efetivamente apresentada,
## não com a tecla nem com o tempo de quadro: a cadência acompanha a velocidade
## e é a mesma a 20 ou a 144 quadros por segundo. Contra uma parede a posição
## apresentada não muda, então não há caminhada no lugar. Saltos maiores que
## `TELEPORT_DISTANCE` (reposicionamento, reset, nova rodada) reiniciam a
## referência sem avançar o ciclo.
##
## Eixos do modelo: frente +Z, cima +Y. Quadril girando em X negativo leva o pé
## para frente; joelho em X positivo dobra a canela para trás; o tornozelo
## devolve a sola para perto da horizontal.

## Ciclo lateral (dois passos de lado), em metros. O ciclo para frente/trás
## sai da perna medida no rig (`cycle_length`), para o pé de apoio não deslizar.
const SIDE_CYCLE_LENGTH := 1.0
## Amplitudes máximas (radianos) com velocidade plena.
const HIP_SWING := 0.5
const KNEE_BEND := 0.85
const ARM_SWING := 0.36
const ELBOW_WALK := 0.32
const SIDE_ABDUCT := 0.24
const SIDE_KNEE := 0.35
## Fração da inclinação da canela que o tornozelo desfaz (1 = sola paralela).
const FOOT_LEVEL := 0.9
const TORSO_TWIST := 0.06
const TORSO_LEAN := 0.05
## Velocidade apresentada (m/s) em que a amplitude chega ao máximo, e abaixo da
## qual o personagem é considerado parado.
const FULL_AMPLITUDE_SPEED := 2.2
const IDLE_SPEED := 0.3
## Suavização exponencial (1/s): independente da taxa de quadros.
const SPEED_SMOOTHING := 10.0
const AMPLITUDE_RISE := 7.0
const AMPLITUDE_FALL := 5.0
const DIRECTION_SMOOTHING := 9.0
## Filtros contra ruído e saltos de rede.
const TELEPORT_DISTANCE := 1.5
const MAX_PRESENTED_SPEED := MovementRules.MAX_SPEED * 1.5
const MIN_STEP := 0.0005
## Repouso: respiração discreta do tronco e leve balanço dos braços.
const BREATH_PERIOD := 3.8
const BREATH_ANGLE := 0.014
const IDLE_ARM := 0.03
## Fase 11: pose armada (só apresentação). O braço da arma sobe para a frente
## e acompanha parte do pitch oficial, com limite; nada muda posição, colisão
## ou hitbox (o nó raiz continua na posição oficial).
const ARMED_SHOULDER := -1.42
const ARMED_ELBOW := -0.12
const ARMED_PITCH_SHARE := 0.6
const ARMED_PITCH_LIMIT := 0.5
const ARMED_BLEND_RATE := 14.0
const ARMED_SWING_SHARE := 0.15
const RECOIL_ANGLE := 0.22
const RECOIL_DECAY := 18.0
## Passo: pé de apoio chega ao chão (fase 0 ou meia volta) com amplitude real.
const FOOTSTEP_MIN_AMPLITUDE := 0.35
## Pistola na mão (m, relativo ao centro da mão).
const HELD_WEAPON_SCALE := 1.0
const HELD_GRIP_OFFSET := Vector3(0.0, -0.08, 0.07)

var rig: Dictionary
var model: Node3D
var base_y := 0.0
var phase := 0.0
var speed := 0.0
var amplitude := 0.0
## Direção suavizada do deslocamento no espaço do modelo: x lateral, y frente.
var direction := Vector2(0.0, 1.0)
var teleports := 0
var _last_position := Vector3.INF
var _time := 0.0
var _breath_offset := 0.0
var _pivots: Dictionary
var _torso: Node3D
var _hips: Array = []
var _knees: Array = []
var _shoulders: Array = []
var _elbows: Array = []
var _ankles: Array = []
var _thigh := 0.0
var _shin := 0.0
var _leg_length := 0.9
var _outward: Array = []
## Cantos das caixas dos sapatos (espaço do sapato) e a cadeia até o modelo,
## para manter o ponto mais baixo dos pés na altura de repouso.
var _visual: Node3D
var _shoes: Array = []
var _shoe_corners: Array = []
var _rest_floor := 0.0
## Fase 11: estado apresentado vindo do snapshot oficial (`armed`, pitch).
var armed := false
var aim_pitch := 0.0
var armed_blend := 0.0
var recoil := 0.0
var footsteps := 0
var _pending_footsteps := 0
## Índice (0 = _L, 1 = _R) do braço do lado direito real do personagem (a
## nomeação das malhas não segue o lado de quem veste).
var gun_side := 1
var held_weapon: Node3D
var _held_muzzle: Node3D
static var _mutation := ""
static var _mutation_read := false

## `model` é o nó `CharacterModel` (já com os pivôs de `CharacterRig`).
## `seed_offset` só desencontra a respiração entre personagens (cosmético).
func _init(character_model: Node3D, seed_offset: float = 0.0) -> void:
	model = character_model
	base_y = model.position.y
	rig = CharacterRig.build(model)
	_breath_offset = seed_offset
	if rig.is_empty():
		return
	_pivots = rig["pivots"]
	_torso = _pivots[CharacterRig.TORSO]
	for side in ["L", "R"]:
		_hips.append(_pivots["Hip_" + side])
		_knees.append(_pivots["Knee_" + side])
		_shoulders.append(_pivots["Shoulder_" + side])
		_elbows.append(_pivots["Elbow_" + side])
		_ankles.append(_pivots["Ankle_" + side])
		var joint: Vector3 = rig["joints"]["Hip_" + side]
		# Para fora: o lado da perna no espaço do modelo.
		_outward.append(signf(joint.x) if absf(joint.x) > 0.001 else (-1.0 if side == "L" else 1.0))
	_thigh = (float(rig["legs"]["L"]["thigh"]) + float(rig["legs"]["R"]["thigh"])) * 0.5
	_shin = (float(rig["legs"]["L"]["shin"]) + float(rig["legs"]["R"]["shin"])) * 0.5
	_visual = (_hips[0] as Node3D).get_parent() as Node3D
	for index in 2:
		var shoe := (_ankles[index] as Node).find_child("Shoe_" + ["L", "R"][index], false, false) as MeshInstance3D
		_shoes.append(shoe)
		var corners := PackedVector3Array()
		var box := shoe.get_aabb()
		for corner in 8:
			corners.append(box.get_endpoint(corner))
		_shoe_corners.append(corners)
	_rest_floor = _lowest_foot()
	_setup_held_weapon()
	# Perna efetiva: do quadril ao piso, medida no próprio modelo.
	var hip: Vector3 = rig["joints"]["Hip_L"]
	_leg_length = (_visual.transform * hip).y - _rest_floor

func is_valid() -> bool:
	return not rig.is_empty()

## Esquece a posição anterior (entrada, reset, reaparição): o próximo quadro
## não conta deslocamento.
func reset(position: Vector3 = Vector3.INF) -> void:
	_last_position = position
	# Teleporte (época nova, reset de rodada): o salto nunca vira passo.
	_pending_footsteps = 0
	if _test_mutation() == "step_on_reset":
		_pending_footsteps += 1
		footsteps += 1

## Volta à pose de repouso na hora (corpo oculto, eliminado).
func rest() -> void:
	speed = 0.0
	amplitude = 0.0
	_last_position = Vector3.INF
	armed = false
	armed_blend = 0.0
	recoil = 0.0
	_pending_footsteps = 0
	_apply(0.0, 0.0)
	_sync_held_weapon()

## Avança a animação com a posição e o yaw apresentados neste quadro.
func update(position: Vector3, yaw: float, delta: float) -> void:
	if rig.is_empty() or delta <= 0.0:
		return
	_time += delta
	var moved := Vector3.ZERO
	if _last_position != Vector3.INF:
		moved = position - _last_position
		moved.y = 0.0
	_last_position = position
	if moved.length() > TELEPORT_DISTANCE:
		teleports += 1
		moved = Vector3.ZERO
	var step := minf(moved.length(), MAX_PRESENTED_SPEED * delta)
	if step < MIN_STEP:
		step = 0.0
	speed = lerpf(speed, step / delta, 1.0 - exp(-SPEED_SMOOTHING * delta))
	if step > 0.0:
		# Mundo → espaço do modelo (yaw do avatar + meia volta do GLB).
		var local := moved.rotated(Vector3.UP, -(yaw + ArenaModels.CHARACTER_YAW))
		var wanted := Vector2(local.x, local.z).normalized()
		# Sem normalizar: numa inversão (frente → trás) o vetor passa por perto de
		# zero e troca de sinal em vez de ficar preso na direção antiga.
		direction = direction.lerp(wanted, 1.0 - exp(-DIRECTION_SMOOTHING * delta))
	var target := clampf(speed / FULL_AMPLITUDE_SPEED, 0.0, 1.0) if speed > IDLE_SPEED else 0.0
	var rate := AMPLITUDE_RISE if target > amplitude else AMPLITUDE_FALL
	amplitude = lerpf(amplitude, target, 1.0 - exp(-rate * delta))
	if amplitude < 0.002 and target == 0.0:
		amplitude = 0.0
	var forward_weight := absf(direction.y) / maxf(absf(direction.x) + absf(direction.y), 0.0001) if direction.length() > 0.0001 else 1.0
	var previous_phase := phase
	phase = fposmod(phase + step / cycle_length(forward_weight) * TAU, TAU)
	# Passo: a fase cruzou 0 ou PI (um pé toca o chão) andando de verdade.
	if step > 0.0 and amplitude >= FOOTSTEP_MIN_AMPLITUDE and _crossed_contact(previous_phase, phase):
		footsteps += 1
		_pending_footsteps += 1
	armed_blend = lerpf(armed_blend, 1.0 if armed else 0.0, 1.0 - exp(-ARMED_BLEND_RATE * delta))
	if absf(armed_blend - (1.0 if armed else 0.0)) < 0.002:
		armed_blend = 1.0 if armed else 0.0
	recoil = recoil * exp(-RECOIL_DECAY * delta)
	if recoil < 0.001:
		recoil = 0.0
	_apply(amplitude, forward_weight)
	_sync_held_weapon()

static func _crossed_contact(before: float, after: float) -> bool:
	if after < before:
		return true
	return before < PI and after >= PI

## Passos acumulados desde a última leitura (a ArenaView toca um som por passo).
func take_footsteps() -> int:
	var count := _pending_footsteps
	_pending_footsteps = 0
	return count

## Recuo curto do braço armado (evento de tiro oficial desse jogador).
func kick() -> void:
	if held_weapon != null and held_weapon.visible:
		recoil = RECOIL_ANGLE

## Ângulo do ombro armado para um pitch oficial: parte do pitch, limitada.
static func armed_shoulder_angle(pitch: float) -> float:
	return ARMED_SHOULDER - clampf(pitch * ARMED_PITCH_SHARE, -ARMED_PITCH_LIMIT, ARMED_PITCH_LIMIT)

func held_weapon_visible() -> bool:
	return held_weapon != null and held_weapon.visible

## Boca da pistola na mão (global), para o clarão do disparo alheio.
func muzzle_position() -> Vector3:
	if _held_muzzle != null and _held_muzzle.is_inside_tree():
		return _held_muzzle.global_position
	return Vector3.INF

func _setup_held_weapon() -> void:
	# Braço do lado direito real: o ombro com X positivo no espaço do avatar
	# (frente em -Z) depois da meia volta do GLB.
	var right_in_avatar := [0.0, 0.0]
	for index in 2:
		var joint: Vector3 = rig["joints"]["Shoulder_" + ["L", "R"][index]]
		right_in_avatar[index] = (model.transform * _to_model(_visual) * joint).x
	gun_side = 0 if float(right_in_avatar[0]) > float(right_in_avatar[1]) else 1
	var elbow := _elbows[gun_side] as Node3D
	var hand := elbow.find_child("Hand_" + ["L", "R"][gun_side], false, false) as MeshInstance3D
	var hand_center := Vector3(0.0, -0.2, 0.0)
	if hand != null:
		hand_center = hand.transform * hand.get_aabb().get_center()
	held_weapon = ArenaModels.build_pistol()
	held_weapon.name = "HeldPistol"
	# Cano ao longo do antebraço (-Y do pivô), topo para a frente do braço
	# (+Z do pivô vira o "para cima" com o braço erguido).
	var basis := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)).scaled(Vector3.ONE * HELD_WEAPON_SCALE)
	held_weapon.transform = Transform3D(basis, hand_center - basis * HELD_GRIP_OFFSET)
	held_weapon.visible = false
	elbow.add_child(held_weapon)
	_held_muzzle = held_weapon.find_child("Muzzle", true, false) as Node3D

## Transformação de um nó descendente para o espaço do modelo.
func _to_model(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != model:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _sync_held_weapon() -> void:
	if held_weapon != null:
		held_weapon.visible = armed and armed_blend > 0.5

static func _test_mutation() -> String:
	if not _mutation_read:
		_mutation_read = true
		_mutation = NetworkConfig.test_mutation(NetworkConfig.user_arguments())
	return _mutation

## Onda de uma perna na fase `leg_phase`: devolve (posição do pé para frente,
## em fração de sen(amplitude), e dobra do joelho em 0..1). Metade do ciclo é
## apoio, com o pé recuando em velocidade constante (casa com o corpo e não
## desliza); a outra metade é o balanço, que volta o pé à frente com o joelho
## dobrando no começo e estendendo antes do contato.
## Andando de costas o balanço começa com a coxa à frente; o joelho dobra no
## fim do balanço (espelho no tempo), senão a canela ficaria vertical e o pé
## tocaria o chão antes da hora.
static func leg_wave(leg_phase: float, backward: bool = false) -> Vector2:
	var psi := fposmod(leg_phase, TAU)
	if psi < PI:
		return Vector2(1.0 - 2.0 * psi / PI, 0.0)
	var u := (psi - PI) / PI
	var knee_u := 1.0 - u if backward else u
	return Vector2(-cos(PI * u), sin(PI * minf(knee_u * 1.25, 1.0)))

## Pose a partir da fase, amplitude e mistura frente/lado. Só grava rotações
## dos pivôs e a altura do modelo.
func _apply(weight: float, forward_weight: float) -> void:
	var s := sin(phase)
	var forward_sign := 1.0 if direction.y >= 0.0 else -1.0
	var side_sign := 1.0 if direction.x >= 0.0 else -1.0
	var fw := weight * forward_weight
	var sw := weight * (1.0 - forward_weight)
	var reach := sin(HIP_SWING)
	for index in 2:
		var leg_sign := 1.0 if index == 0 else -1.0
		# Frente/trás: pernas defasadas de meio ciclo. Andando de costas, o apoio
		# empurra o pé para frente (sinal invertido).
		var wave := leg_wave(phase + (0.0 if index == 0 else PI), forward_sign < 0.0)
		var swing := asin(clampf(wave.x * reach, -1.0, 1.0)) * forward_sign * fw
		var bend := KNEE_BEND * fw * wave.y
		# Lado: a perna do lado do movimento abre primeiro, a outra acompanha;
		# nenhuma cruza a linha do corpo.
		var leads: bool = float(_outward[index]) == side_sign
		var open := maxf(0.0, s) if leads else maxf(0.0, -s) * 0.7
		var abduct := SIDE_ABDUCT * sw * open
		bend += SIDE_KNEE * sw * open
		(_hips[index] as Node3D).rotation = Vector3(-swing, 0.0, abduct * float(_outward[index]))
		(_knees[index] as Node3D).rotation = Vector3(bend, 0.0, 0.0)
		# Tornozelo mantém a sola quase paralela ao piso (sem bico enterrado).
		(_ankles[index] as Node3D).rotation = Vector3((swing - bend) * FOOT_LEVEL, 0.0, -abduct * float(_outward[index]))
		# Braço para frente quando a perna do mesmo lado vai para trás
		# (rotação X negativa leva a mão para frente).
		var arm := ARM_SWING * fw * wave.x * forward_sign
		var idle_arm := IDLE_ARM * (1.0 - weight) * sin(_time * TAU / BREATH_PERIOD + _breath_offset + index)
		var shoulder_x := arm + idle_arm
		var elbow_x := -ELBOW_WALK * weight
		if index == gun_side and armed_blend > 0.0:
			# Braço armado: sobe para a frente, balança pouco e segue parte do
			# pitch; o recuo levanta o cano um instante.
			var aimed := armed_shoulder_angle(aim_pitch) - recoil
			shoulder_x = lerpf(shoulder_x, aimed + arm * ARMED_SWING_SHARE, armed_blend)
			elbow_x = lerpf(elbow_x, ARMED_ELBOW, armed_blend)
		(_shoulders[index] as Node3D).rotation = Vector3(shoulder_x, 0.0, 0.08 * sw * float(_outward[index]) * (1.0 - armed_blend if index == gun_side else 1.0))
		(_elbows[index] as Node3D).rotation = Vector3(elbow_x, 0.0, 0.0)
	# Pé de apoio no piso: o ponto mais baixo dos sapatos (calcanhar ou bico,
	# conforme a inclinação) volta à altura de repouso.
	model.position.y = base_y + (_rest_floor - _lowest_foot())
	var breath := BREATH_ANGLE * (1.0 - weight) * sin(_time * TAU / BREATH_PERIOD + _breath_offset)
	_torso.rotation = Vector3(breath + TORSO_LEAN * fw * forward_sign, TORSO_TWIST * fw * s * forward_sign, 0.0)

## Comprimento de um ciclo (dois passos) casado com a passada plena: no apoio o
## pé percorre 2·perna·sen(HIP_SWING) enquanto o corpo anda meio ciclo. A fase
## é função só da distância; a amplitude apenas abre e fecha a passada no
## início e na parada (a velocidade do jogo é praticamente 0 ou 5 m/s).
func cycle_length(forward_weight: float = 1.0) -> float:
	var forward_cycle := 4.0 * _leg_length * sin(HIP_SWING)
	return lerpf(SIDE_CYCLE_LENGTH, forward_cycle, forward_weight)

## Menor altura dos cantos dos sapatos no espaço do modelo (só Y interessa; a
## meia volta do modelo não altera a altura).
func _lowest_foot() -> float:
	var lowest := INF
	for index in 2:
		var chain := _visual.transform * (_hips[index] as Node3D).transform * (_knees[index] as Node3D).transform * (_ankles[index] as Node3D).transform * (_shoes[index] as Node3D).transform
		for corner in (_shoe_corners[index] as PackedVector3Array):
			lowest = minf(lowest, (chain * corner).y)
	return lowest

class_name CharacterRig
extends RefCounted

## Pivôs procedurais dos oito personagens (fase 3). Os GLBs não têm ossos,
## skinning nem animação: cada peça é uma malha irmã com transformação
## identidade e vértices já no lugar. As articulações que a geometria realmente
## separa são quadril (coxa), joelho (canela), tornozelo (sapato), ombro
## (braço) e cotovelo (antebraço + mão); não há pulso nem dedos separados, e
## nenhuma peça é dobrada no meio.
##
## `build(model)` reorganiza as malhas sob pivôs posicionados pela geometria
## inspecionada (topo da coxa, junção coxa/canela, topo do braço, sobreposição
## braço/antebraço), compensando cada malha para que a pose de repouso fique
## idêntica ao GLB. Peças extras de cada variante (bolsos, faixas, punhos,
## joelheiras, painéis) vão para o segmento cuja caixa as contém. O pivô da
## cabeça (`ArenaModels.HEAD_PIVOT`) passa a ser filho do tronco; seu pitch
## continua escrito só pela `ArenaView`.
##
## Hierarquia criada sob o pai das malhas (`CharacterVisual`):
##   Torso ─ tronco, pescoço, HeadPivot, Shoulder_L/R ─ Elbow_L/R
##   Hip_L/R ─ coxa, bolso ─ Knee_L/R ─ canela ─ Ankle_L/R ─ sapato

const TORSO := "Torso"
const SEGMENTS := {
	"Hip_L": "Thigh_L", "Hip_R": "Thigh_R", "Knee_L": "Shin_L", "Knee_R": "Shin_R",
	"Shoulder_L": "UpperArm_L", "Shoulder_R": "UpperArm_R", "Elbow_L": "Forearm_L", "Elbow_R": "Forearm_R",
}
## Peças base de cada segmento (as demais são atribuídas pela geometria).
const BASE_PARTS := {
	"Ankle_L": ["Shoe_L"], "Ankle_R": ["Shoe_R"], "Elbow_L": ["Hand_L"], "Elbow_R": ["Hand_R"],
}
const ASSIGN_MARGIN := 0.04

## Constrói (uma única vez) os pivôs e devolve as referências usadas pelo
## animador. Chamar de novo no mesmo modelo não duplica nada.
static func build(model: Node3D) -> Dictionary:
	if model.has_meta("character_rig"):
		return model.get_meta("character_rig")
	var meshes := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		meshes[str(node.name)] = node
	for required in SEGMENTS.values() + ["Shoe_L", "Shoe_R", "Hand_L", "Hand_R", "Jacket"]:
		if not meshes.has(required):
			return {}
	var parent := (meshes["Jacket"] as Node).get_parent() as Node3D
	var boxes := {}
	for key in meshes:
		var mesh_node := meshes[key] as MeshInstance3D
		boxes[key] = _box_in(parent, mesh_node)
	# Articulações medidas na geometria (espaço do pai das malhas).
	var joints := {}
	for side in ["L", "R"]:
		var thigh: AABB = boxes["Thigh_" + side]
		var shin: AABB = boxes["Shin_" + side]
		var upper: AABB = boxes["UpperArm_" + side]
		var fore: AABB = boxes["Forearm_" + side]
		joints["Hip_" + side] = Vector3(thigh.get_center().x, thigh.end.y, thigh.get_center().z)
		joints["Knee_" + side] = Vector3(shin.get_center().x, (thigh.position.y + shin.end.y) * 0.5, shin.get_center().z)
		joints["Shoulder_" + side] = Vector3(upper.get_center().x, upper.end.y - upper.size.x * 0.4, upper.get_center().z)
		# Cotovelo: meio da sobreposição entre braço e antebraço.
		joints["Elbow_" + side] = Vector3(fore.get_center().x, (upper.position.y + fore.end.y) * 0.5, fore.get_center().z)
		# Tornozelo: onde a canela encontra o sapato, alinhado à canela.
		var shoe: AABB = boxes["Shoe_" + side]
		joints["Ankle_" + side] = Vector3(shin.get_center().x, (shin.position.y + shoe.end.y) * 0.5, shin.get_center().z)
	var torso_origin := Vector3(0.0, (joints["Hip_L"] as Vector3).y, 0.0)
	var torso := _pivot(parent, TORSO, torso_origin, parent)
	var pivots := {TORSO: torso}
	for name in ["Hip_L", "Hip_R"]:
		pivots[name] = _pivot(parent, name, joints[name], parent)
	for side in ["L", "R"]:
		pivots["Knee_" + side] = _pivot(pivots["Hip_" + side], "Knee_" + side, joints["Knee_" + side], parent)
		pivots["Ankle_" + side] = _pivot(pivots["Knee_" + side], "Ankle_" + side, joints["Ankle_" + side], parent)
		pivots["Shoulder_" + side] = _pivot(torso, "Shoulder_" + side, joints["Shoulder_" + side], parent)
		pivots["Elbow_" + side] = _pivot(pivots["Shoulder_" + side], "Elbow_" + side, joints["Elbow_" + side], parent)
	# Peças base.
	for pivot_name in SEGMENTS:
		_adopt(pivots[pivot_name], meshes[SEGMENTS[pivot_name]])
	for pivot_name in BASE_PARTS:
		for part in BASE_PARTS[pivot_name]:
			_adopt(pivots[pivot_name], meshes[part])
	# Demais peças: o menor segmento cuja caixa (com margem) contém o centro;
	# sem segmento, o tronco. O pivô da cabeça vai inteiro para o tronco.
	var taken := {}
	for value in SEGMENTS.values():
		taken[value] = true
	for list in BASE_PARTS.values():
		for part in list:
			taken[part] = true
	var assigned := {}
	for key in meshes:
		if taken.has(key):
			continue
		var mesh_node := meshes[key] as MeshInstance3D
		if mesh_node.get_parent() != parent:
			continue
		var center: Vector3 = (boxes[key] as AABB).get_center()
		var best := TORSO
		var best_volume := INF
		for pivot_name in SEGMENTS:
			var segment_box: AABB = (boxes[SEGMENTS[pivot_name]] as AABB).grow(ASSIGN_MARGIN)
			if segment_box.has_point(center) and segment_box.get_volume() < best_volume:
				best = pivot_name
				best_volume = segment_box.get_volume()
		_adopt(pivots[best], mesh_node)
		assigned[key] = best
	var head := parent.get_node_or_null(ArenaModels.HEAD_PIVOT) as Node3D
	if head != null:
		_adopt(torso, head)
	var legs := {}
	for side in ["L", "R"]:
		var hip: Vector3 = joints["Hip_" + side]
		var knee: Vector3 = joints["Knee_" + side]
		var shoe: AABB = boxes["Shoe_" + side]
		legs[side] = {"thigh": hip.y - knee.y, "shin": knee.y - shoe.position.y}
	var rig := {"pivots": pivots, "joints": joints, "legs": legs, "assigned": assigned, "head": head}
	model.set_meta("character_rig", rig)
	return rig

## Cria um pivô filho de `pivot_parent` na posição `point` do espaço `visual`
## (o pai original das malhas), sem rotação em repouso.
static func _pivot(pivot_parent: Node3D, pivot_name: String, point: Vector3, visual: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot_parent.add_child(pivot)
	pivot.transform = _global_of(pivot_parent).affine_inverse() * _global_of(visual) * Transform3D(Basis(), point)
	return pivot

## Move `node` para `pivot` mantendo a transformação global (pose de repouso).
static func _adopt(pivot: Node3D, node: Node3D) -> void:
	var global := _global_of(node)
	node.get_parent().remove_child(node)
	pivot.add_child(node)
	node.transform = _global_of(pivot).affine_inverse() * global

static func _box_in(parent: Node3D, mesh_node: MeshInstance3D) -> AABB:
	return (_global_of(parent).affine_inverse() * _global_of(mesh_node)) * mesh_node.get_aabb()

## Transformação acumulada até a raiz, válida também fora da árvore de cena.
static func _global_of(node: Node3D) -> Transform3D:
	var result := node.transform
	var current := node.get_parent() as Node3D
	while current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

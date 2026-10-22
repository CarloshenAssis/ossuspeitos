class_name EnvironmentView
extends Node3D

## Presentation of server-owned objects only. No CollisionShape or local
## simulation can change the official world. Open door leaves park in wall.
var snapshot: Dictionary={}
var nodes: Dictionary={}
func apply_state(value: Dictionary) -> void:
 snapshot=value.duplicate(true)
 var present: Dictionary={}
 for item in snapshot.get("objects",[]):
  var id := str(item.id)
  present[id]=true
  var def := EnvironmentRules.definition(id)
  if not nodes.has(id):
   var mesh := MeshInstance3D.new()
   var shape := BoxMesh.new()
   shape.size=def.size
   mesh.mesh=shape
   var material := StandardMaterial3D.new()
   material.albedo_color=Color(0.28,0.16,0.08) if def.kind=="door" else Color(0.55,0.37,0.16)
   material.roughness=0.9
   mesh.material_override=material
   add_child(mesh)
   nodes[id]=mesh
  var node: MeshInstance3D=nodes[id]
  node.position=item.position
  node.rotation=Vector3.ZERO
  if def.kind=="door" and item.open:
   if def.size.x>def.size.z: node.position.x+=def.size.x+0.15
   else: node.position.z+=def.size.z+0.15
 for id in nodes.keys():
  if not present.has(id):
   nodes[id].queue_free()
   nodes.erase(id)

func nearest(position: Vector3, own_peer: int, verb: String="") -> Dictionary:
 var result: Dictionary={}
 var closest := EnvironmentRules.REACH
 for item in snapshot.get("objects",[]):
  var def := EnvironmentRules.definition(str(item.id))
  if verb=="drop" and int(item.holder)==own_peer: return item.duplicate(true)
  if verb=="drop": continue
  if int(item.holder)>0: continue
  if verb=="toggle" and def.kind!="door": continue
  if verb in ["take","push"] and def.kind!="prop": continue
  if verb=="take" and float(def.mass)>EnvironmentRules.MAX_CARRY_MASS: continue
  var distance := position.distance_to(item.position)
  if distance<closest:
   result=item
   closest=distance
 return result.duplicate(true)

func hint_for(id: String, holder: int, own_peer: int) -> String:
 var def := EnvironmentRules.definition(id)
 if def.is_empty(): return ""
 if holder>0: return "Q — Soltar objeto" if holder==own_peer else "Objeto em uso por outro jogador"
 if def.kind=="door":
  for item in snapshot.get("objects",[]):
   if item.id==id: return "E — Fechar porta" if item.open else "E — Abrir porta"
 if float(def.mass)>EnvironmentRules.MAX_CARRY_MASS: return "G — Empurrar (objeto pesado)"
 return "F — Pegar objeto   G — Empurrar"

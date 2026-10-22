class_name EnvironmentRules
extends RefCounted

## Bounded build-distributed geometry. Same AABBs feed movement, bullets and
## meshes; never a mutable static room state. No native physics dependency.
const MAX_OBJECTS := 24
const REACH := 2.5
const MAX_CARRY_MASS := 4.0
const MAX_HORIZONTAL_SPEED := 1.5
const MAX_FALL_SPEED := 6.0
const OBJECT_KEYS := ["id", "position", "velocity", "open", "holder"]
const VERBS := ["toggle", "push", "take", "drop", "inspect"]

static var _definitions: Array = _build_definitions()
static var _by_id: Dictionary = _build_index()

static func definitions() -> Array:
 return _definitions.duplicate(true)

static func _build_index() -> Dictionary:
 var result: Dictionary={}
 for item in _definitions:
  item.make_read_only()
  result[item.id]=item
 result.make_read_only()
 return result

static func _build_definitions() -> Array:
 var result: Array=[]
 for door in MansionMap.DOORS:
  var lo: Vector2=door.min
  var hi: Vector2=door.max
  result.append({"id":door.id,"kind":"door","position":Vector3((lo.x+hi.x)*0.5,MansionMap.DOOR_HEIGHT*0.5,(lo.y+hi.y)*0.5),"size":Vector3(hi.x-lo.x,MansionMap.DOOR_HEIGHT,hi.y-lo.y),"mass":0.0})
 result.append({"id":"prop_escritorio","kind":"prop","position":Vector3(3,0.3,3.5),"size":Vector3(0.6,0.6,0.6),"mass":2.0})
 result.append({"id":"prop_salao","kind":"prop","position":Vector3(12,0.3,10),"size":Vector3(0.6,0.6,0.6),"mass":3.0})
 result.append({"id":"prop_cozinha","kind":"prop","position":Vector3(24,0.35,11.5),"size":Vector3(0.7,0.7,0.7),"mass":10.0})
 return result

static func definition(id: String) -> Dictionary:
 return _by_id.get(id,{})

static func initial_objects() -> Array:
 var result: Array=[]
 for item in definitions():
  result.append({"id":item.id,"position":item.position,"velocity":Vector3.ZERO,"open":item.kind=="door","holder":0})
 return result

static func sanitize(raw: Variant) -> Dictionary:
 if typeof(raw)!=TYPE_DICTIONARY: return {}
 var value: Dictionary=raw
 if value.size()!=3 or not value.has("round_id") or not value.has("revision") or not value.has("objects"): return {}
 if typeof(value.round_id)!=TYPE_INT or typeof(value.revision)!=TYPE_INT or typeof(value.objects)!=TYPE_ARRAY: return {}
 if value.round_id<0 or value.revision<0 or value.objects.size()>MAX_OBJECTS: return {}
 var seen: Dictionary={}
 for raw_item in value.objects:
  if typeof(raw_item)!=TYPE_DICTIONARY: return {}
  var item: Dictionary=raw_item
  if item.size()!=OBJECT_KEYS.size(): return {}
  for key in OBJECT_KEYS:
   if not item.has(key): return {}
  if typeof(item.id)!=TYPE_STRING or typeof(item.position)!=TYPE_VECTOR3 or typeof(item.velocity)!=TYPE_VECTOR3 or typeof(item.open)!=TYPE_BOOL or typeof(item.holder)!=TYPE_INT: return {}
  var def := definition(item.id)
  if def.is_empty() or seen.has(item.id): return {}
  seen[item.id]=true
  var p: Vector3=item.position
  var v: Vector3=item.velocity
  if not p.is_finite() or not v.is_finite() or p.x<MovementRules.MAP_MIN_X or p.x>MovementRules.MAP_MAX_X or p.z<MovementRules.MAP_MIN_Z or p.z>MovementRules.MAP_MAX_Z or p.y<0 or p.y>4: return {}
  if Vector2(v.x,v.z).length()>MAX_HORIZONTAL_SPEED+0.001 or absf(v.y)>MAX_FALL_SPEED+0.001 or item.holder<0: return {}
  if def.kind=="door" and (p!=def.position or v!=Vector3.ZERO or item.holder!=0): return {}
 return value.duplicate(true)

static func blockers(snapshot: Dictionary) -> Array:
 var result: Array=[]
 for item in snapshot.get("objects",[]):
  var def := definition(str(item.id))
  if def.is_empty() or int(item.holder)>0 or (def.kind=="door" and bool(item.open)): continue
  result.append({"center":item.position,"size":def.size})
 return result

static func overlaps(position: Vector3, radius: float, boxes: Array) -> bool:
 for box in boxes:
  if ArenaRules.blocks_movement(box) and ArenaRules._circle_hits_box(position,radius,box.center,box.size): return true
 return false

static func first_hit(origin: Vector3, direction: Vector3, distance: float, boxes: Array) -> float:
 var closest := -1.0
 for box in boxes:
  var hit := ArenaRules.ray_aabb(origin,direction,distance,box.center,box.size)
  if hit>=0 and (closest<0 or hit<closest): closest=hit
 return closest

## Protocol12 wire codec. Geometry is bundled, never sent as mutable client
## definitions: twenty closed-door bits + three bounded dynamic prop states.
static func encode_wire(snapshot: Dictionary) -> Array:
 var clean := sanitize(snapshot)
 if clean.is_empty() or clean.objects.size()!=_definitions.size(): return []
 var by_id: Dictionary={}
 for item in clean.objects: by_id[item.id]=item
 var mask := 0
 var door_index := 0
 var props: Array=[]
 for def in _definitions:
  if not by_id.has(def.id): return []
  var item: Dictionary=by_id[def.id]
  if def.kind=="door":
   if not item.open: mask|=1<<door_index
   door_index+=1
  else:
   if item.open: return []
   props.append([item.position,item.velocity,item.holder])
 return [clean.round_id,clean.revision,mask,props]

static func decode_wire(raw: Variant) -> Dictionary:
 if typeof(raw)!=TYPE_ARRAY or raw.size()!=4: return {}
 var wire: Array=raw
 for index in 3:
  if typeof(wire[index])!=TYPE_INT or int(wire[index])<0: return {}
 if int(wire[2])>=(1<<MansionMap.DOORS.size()) or typeof(wire[3])!=TYPE_ARRAY: return {}
 var count := _definitions.size()-MansionMap.DOORS.size()
 var props: Array=wire[3]
 if props.size()!=count: return {}
 var objects := initial_objects()
 var prop_index := 0
 var door_index := 0
 for item in objects:
  var def := definition(str(item.id))
  if def.kind=="door":
   item.open=(int(wire[2])&(1<<door_index))==0
   door_index+=1
  else:
   var value: Variant=props[prop_index]
   prop_index+=1
   if typeof(value)!=TYPE_ARRAY or value.size()!=3: return {}
   var row: Array=value
   if typeof(row[0])!=TYPE_VECTOR3 or typeof(row[1])!=TYPE_VECTOR3 or typeof(row[2])!=TYPE_INT: return {}
   item.position=row[0]
   item.velocity=row[1]
   item.holder=row[2]
 return sanitize({"round_id":wire[0],"revision":wire[1],"objects":objects})

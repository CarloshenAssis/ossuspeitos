class_name InventoryAuthority
extends RefCounted

const PICKUP_RANGE_METERS := 2.0
const MAX_ITEMS_PER_SESSION := 512

var definitions: Dictionary = {}
var inventories: Dictionary = {}
var ground_items: Dictionary = {}

func _init(weapon_definitions: Dictionary = {}) -> void:
	for weapon_id in weapon_definitions:
		var definition: Variant = weapon_definitions[weapon_id]
		if definition is WeaponDefinition and WeaponRules.validate_definition(definition).is_empty() and definition.id == weapon_id:
			definitions[weapon_id] = definition

func register_player(peer_id: int) -> bool:
	if peer_id <= 0 or inventories.has(peer_id):
		return false
	inventories[peer_id] = _empty_inventory()
	return true

func add_ground_weapon(item_id: String, weapon_id: String, position: Vector3, magazine: int = -1, reserve: int = 0) -> bool:
	if item_id.is_empty() or ground_items.has(item_id) or ground_items.size() >= MAX_ITEMS_PER_SESSION:
		return false
	if not definitions.has(weapon_id) or not WeaponRules.is_finite_vector3(position):
		return false
	var definition: WeaponDefinition = definitions[weapon_id]
	ground_items[item_id] = {
		"weapon_id": weapon_id,
		"position": position,
		"available": true,
		"magazine": int(definition.magazine_capacity) if magazine < 0 else WeaponRules.clamp_ammo(magazine, int(definition.magazine_capacity)),
		"reserve": WeaponRules.clamp_ammo(reserve, int(definition.max_reserve_ammo)),
	}
	return true

func pickup_weapon(peer_id: int, item_id: Variant, player_alive: bool, round_active: bool, official_position: Variant) -> String:
	if not inventories.has(peer_id):
		return "unknown_peer"
	if not player_alive:
		return "player_dead"
	if not round_active:
		return "round_not_active"
	if typeof(item_id) != TYPE_STRING or not ground_items.has(item_id):
		return "item_not_found"
	var item: Dictionary = ground_items[item_id]
	if not bool(item["available"]):
		return "item_unavailable"
	if typeof(official_position) != TYPE_VECTOR3 or not WeaponRules.is_finite_vector3(official_position):
		return "invalid_position"
	if official_position.distance_to(item["position"]) > PICKUP_RANGE_METERS:
		return "out_of_range"
	var inventory: Dictionary = inventories[peer_id]
	if not str(inventory["weapon_id"]).is_empty():
		return "inventory_full"
	inventory["weapon_id"] = item["weapon_id"]
	inventory["equipped"] = true
	inventory["magazine"] = item["magazine"]
	inventory["reserve"] = item["reserve"]
	item["available"] = false
	return ""

func start_reload(peer_id: int, now_msec: int, player_alive: bool = true, round_active: bool = true) -> String:
	if now_msec < 0:
		return "invalid_time"
	if not inventories.has(peer_id):
		return "unknown_peer"
	if not player_alive:
		return "player_dead"
	if not round_active:
		return "round_not_active"
	var inventory: Dictionary = inventories[peer_id]
	if bool(inventory["reloading"]):
		return "already_reloading"
	var definition := get_equipped_definition(peer_id)
	if definition == null:
		return "no_equipped_weapon"
	if int(inventory["magazine"]) >= int(definition.magazine_capacity):
		return "magazine_full"
	if int(inventory["reserve"]) <= 0:
		return "reserve_empty"
	inventory["reloading"] = true
	inventory["reload_deadline_msec"] = now_msec + int(definition.reload_time_msec)
	return ""

func complete_reload(peer_id: int, now_msec: int) -> String:
	if now_msec < 0:
		return "invalid_time"
	if not inventories.has(peer_id):
		return "unknown_peer"
	var inventory: Dictionary = inventories[peer_id]
	if not bool(inventory["reloading"]):
		return "not_reloading"
	if now_msec < int(inventory["reload_deadline_msec"]):
		return "reload_pending"
	var definition := get_equipped_definition(peer_id)
	if definition == null:
		_cancel_reload(inventory)
		return "no_equipped_weapon"
	var transfer := WeaponRules.reload_transfer(inventory["magazine"], inventory["reserve"], int(definition.magazine_capacity))
	inventory["magazine"] = int(inventory["magazine"]) + transfer
	inventory["reserve"] = int(inventory["reserve"]) - transfer
	_cancel_reload(inventory)
	return ""

func get_inventory(peer_id: int) -> Dictionary:
	return (inventories.get(peer_id, {}) as Dictionary).duplicate(true)

func get_equipped_definition(peer_id: int) -> WeaponDefinition:
	if not inventories.has(peer_id):
		return null
	var inventory: Dictionary = inventories[peer_id]
	if not bool(inventory["equipped"]):
		return null
	return definitions.get(inventory["weapon_id"])

func consume_round(peer_id: int) -> bool:
	if not inventories.has(peer_id):
		return false
	var inventory: Dictionary = inventories[peer_id]
	if int(inventory["magazine"]) <= 0:
		return false
	inventory["magazine"] = int(inventory["magazine"]) - 1
	return true

func clear_player(peer_id: int) -> void:
	inventories.erase(peer_id)

func clear_session() -> void:
	inventories.clear()
	ground_items.clear()

func _empty_inventory() -> Dictionary:
	return {"weapon_id": "", "equipped": false, "magazine": 0, "reserve": 0, "reloading": false, "reload_deadline_msec": 0, "last_sequence": -1, "last_shot_msec": -1}

func _cancel_reload(inventory: Dictionary) -> void:
	inventory["reloading"] = false
	inventory["reload_deadline_msec"] = 0

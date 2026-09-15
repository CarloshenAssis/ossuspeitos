class_name WeaponDefinition
extends RefCounted

## Immutable-by-convention server catalogue entry. Clients may refer to `id`, but
## every gameplay value is read from the server-owned instance.
var id: Variant
var damage: Variant
var magazine_capacity: Variant
var max_reserve_ammo: Variant
var fire_interval_msec: Variant
var range_meters: Variant
var reload_time_msec: Variant
var spread_radians: Variant

func _init(
	weapon_id: Variant = "",
	weapon_damage: Variant = 0.0,
	capacity: Variant = 0,
	max_reserve: Variant = 0,
	interval_msec: Variant = 0,
	weapon_range: Variant = 0.0,
	reload_msec: Variant = 0,
	spread: Variant = 0.0
) -> void:
	id = weapon_id
	damage = weapon_damage
	magazine_capacity = capacity
	max_reserve_ammo = max_reserve
	fire_interval_msec = interval_msec
	range_meters = weapon_range
	reload_time_msec = reload_msec
	spread_radians = spread

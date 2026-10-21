class_name WeaponCatalog
extends RefCounted

## Trusted server configuration. Each call owns its dictionary and definitions.
static func defaults() -> Dictionary:
	return {"common_pistol": WeaponDefinition.new("common_pistol", 34, 6, 18,
		WeaponRules.COMMON_FIRE_INTERVAL_MSEC, 20.0, 1200, 0.0)}

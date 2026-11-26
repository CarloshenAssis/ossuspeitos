class_name WeaponCatalog
extends RefCounted

## Trusted server configuration. Each call owns its dictionary and definitions.
static func defaults() -> Dictionary:
	return {"common_pistol": WeaponDefinition.new("common_pistol", 34, 6, 18,
		WeaponRules.COMMON_FIRE_INTERVAL_MSEC, 20.0, 1200, 0.0)}

## Armas extra da Nocturna. O catálogo padrão da planta aprovada não muda.
static func nocturna() -> Dictionary:
	return {
		"hunting_rifle": WeaponDefinition.new("hunting_rifle", 50, 4, 12, 550, 35.0, 1600, 0.01),
		"coach_gun": WeaponDefinition.new("coach_gun", 62, 2, 8, 700, 12.0, 1800, 0.08),
	}


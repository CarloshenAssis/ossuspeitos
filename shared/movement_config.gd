class_name MovementConfig
extends Resource
## Build-time planar movement tuning, shared by authority and prediction.
## Supported values are finite and strictly positive: speed <= 5 m/s,
## acceleration/deceleration <= 60 m/s². No client or RPC selects this Resource.

@export_range(0.001, 5.0) var walk_speed: float = 5.0
@export_range(0.001, 60.0) var ground_acceleration: float = 18.0
@export_range(0.001, 60.0) var ground_deceleration: float = 18.0

func validate() -> String:
	for field in ["walk_speed", "ground_acceleration", "ground_deceleration"]:
		var value: float = get(field)
		var maximum := 5.0 if field == "walk_speed" else 60.0
		if not is_finite(value) or value <= 0.0 or value > maximum:
			return "movement_config_" + field
	return ""

## Snapshot validated scalars; never retain the mutable Resource in simulation.
func validated_parameters() -> Dictionary:
	var reason := validate()
	var result := {"rejection": reason}
	if reason.is_empty():
		result["walk_speed"] = walk_speed
		result["ground_acceleration"] = ground_acceleration
		result["ground_deceleration"] = ground_deceleration
	result.make_read_only()
	return result

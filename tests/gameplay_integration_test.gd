extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture := load("res://tests/scenes/gameplay_integration.tscn") as PackedScene
	if fixture == null:
		quit(1)
		return
	root.add_child(fixture.instantiate())

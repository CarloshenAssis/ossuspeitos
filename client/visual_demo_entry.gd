extends Node

## Ponto de entrada exclusivo do preset `Web Demo`: não instancia NetworkApp,
## menu online, cliente de rede ou autoridade de servidor.
func _ready() -> void:
	GameControls.ensure()
	add_child(VisualDemo.new())

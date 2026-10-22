extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("ENVIRONMENT_PRESENTATION_ASSERT "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var view:=EnvironmentView.new()
	root.add_child(view)
	var state={"round_id":1,"revision":1,"objects":EnvironmentRules.initial_objects()}
	view.apply_state(state)
	check(view.nodes.size()==MansionMap.DOORS.size()+3,"official mansion catalog rendered without extra blockers")
	var nearest:=view.nearest(Vector3(3,1,3.5),1,"toggle")
	check(not nearest.is_empty() and EnvironmentRules.definition(nearest.id).kind=="door","E selects door instead of closer non-toggle prop")
	var heavy:=view.nearest(Vector3(23.2,1,11.5),1,"take")
	check(heavy.is_empty(),"take hint never promises carrying heavy crate")
	check(view.has_method("hint_for"),"context-sensitive public interaction hints exist")
	if not view.has_method("hint_for"):
		view.free()
		quit(1)
		return
	check(view.hint_for("prop_cozinha",0,1).contains("pesado"),"heavy crate described as push-only")
	check(view.hint_for("prop_escritorio",0,1).contains("F"),"light prop offers take")
	check(view.hint_for("prop_escritorio",1,1).contains("Soltar"),"own held prop offers drop")
	check(view.hint_for("prop_escritorio",2,1).contains("uso"),"occupied prop has explicit feedback")
	for item in state.objects:
		var def:=EnvironmentRules.definition(item.id)
		var mesh: MeshInstance3D=view.nodes[item.id]
		check((mesh.mesh as BoxMesh).size==def.size,"visible dimensions match authoritative definition")
		if def.kind=="door":
			var visible:=AABB(mesh.position-def.size*0.5,def.size)
			var passage:=AABB(def.position-def.size*0.5,def.size)
			check(not visible.intersects(passage),"open leaf parked outside shared passage")
			item.open=false
	view.apply_state(state)
	for item in state.objects:
		var def:=EnvironmentRules.definition(item.id)
		if def.kind=="door": check((view.nodes[item.id] as Node3D).position==def.position,"closed leaf exactly matches shared blocker center")
	check(RoundHud.rejection_notice("interact","object_too_heavy").contains("pesado"),"human-readable mass rejection")
	check(RoundHud.rejection_notice("interact","interaction_blocked").contains("caminho"),"human-readable obstruction rejection")
	var pristine:=state.duplicate(true)
	view.apply_state({"round_id":2,"revision":2,"objects":EnvironmentRules.initial_objects()})
	check(state==pristine,"presentation never mutates server snapshot")
	view.free()
	print("ENVIRONMENT_PRESENTATION_TEST_%s checks=%d failures=%d"%["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)

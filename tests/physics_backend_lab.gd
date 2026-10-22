extends SceneTree
## Isolated backend experiment, never the production authoritative integrator.
var lab_root: Node3D
func _initialize() -> void:
 lab_root=Node3D.new()
 get_root().add_child(lab_root)
 var floor := StaticBody3D.new()
 var floor_shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size=Vector3(10,0.2,10)
 floor_shape.shape=box
 floor.position.y=-0.1
 floor.add_child(floor_shape)
 lab_root.add_child(floor)
 var body := RigidBody3D.new()
 var shape := CollisionShape3D.new()
 var small := BoxShape3D.new()
 small.size=Vector3(0.5,0.5,0.5)
 shape.shape=small
 body.add_child(shape)
 body.position=Vector3(0,2,0)
 lab_root.add_child(body)
 call_deferred("measure",body)
func measure(body: RigidBody3D) -> void:
 var start := Time.get_ticks_usec()
 for index in 180: await physics_frame
 var elapsed := Time.get_ticks_usec()-start
 var good := is_finite(body.position.y) and absf(body.position.y-0.25)<0.04 and body.linear_velocity.length()<0.1
 print("PHYSICS_BACKEND_LAB engine=%s ticks=180 elapsed_usec=%d final_y=%.6f speed=%.6f result=%s" % [ProjectSettings.get_setting("physics/3d/physics_engine"),elapsed,body.position.y,body.linear_velocity.length(),"OK" if good else "FAILED"])
 lab_root.queue_free()
 await process_frame
 quit(0 if good else 1)

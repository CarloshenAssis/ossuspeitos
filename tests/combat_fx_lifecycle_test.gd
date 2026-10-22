extends SceneTree

## Regression: a SceneTreeTimer can outlive an effect cleared by the arena or
## its parent. The strict suite runner rejects engine errors from callbacks,
## including errors raised before the callback body itself starts executing.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("COMBAT_FX_LIFECYCLE_ASSERT " + label)

func _make_fx() -> CombatFx:
	var fx := CombatFx.new()
	root.add_child(fx)
	# Exercise the production visuals without audio-driver shutdown warnings.
	fx.set_category_volume(0.0)
	return fx

func _emit_all(fx: CombatFx) -> Array:
	fx.muzzle_flash(Vector3(2, 1, 2), Vector3.FORWARD)
	fx.impact(Vector3(2, 1, 1), false)
	fx.pickup_vanish(Vector3(2, 1, 3), Color.GOLD)
	fx.elimination(Vector3(3, 1, 2))
	var refs: Array = []
	for child in fx.get_children():
		if child is MeshInstance3D:
			refs.append(weakref(child))
	_expect(refs.size() == 8, "all public effect types created their eight visual nodes")
	return refs

func _expect_released(refs: Array, label: String) -> void:
	for ref in refs:
		_expect((ref as WeakRef).get_ref() == null, label)

func run() -> void:
	# Positive control: the timer must still expire live visuals normally.
	var fx := _make_fx()
	var refs := _emit_all(fx)
	await create_timer(CombatFx.ELIMINATION_SECONDS + 0.15).timeout
	await process_frame
	_expect_released(refs, "live effect expires at its normal lifetime")
	_expect(fx.get_child_count() == 10, "normal expiry preserves the ten audio players")
	fx.free()
	fx = null

	# Arena reset/clear: visual nodes die while their scene-tree timers remain.
	fx = _make_fx()
	refs = _emit_all(fx)
	fx.clear()
	await process_frame
	await process_frame
	_expect_released(refs, "clear really frees visuals before timer deadlines")
	await create_timer(CombatFx.ELIMINATION_SECONDS + 0.15).timeout
	_expect(fx.get_child_count() == 10, "expired callbacks do not touch persistent audio players")
	fx.free()
	fx = null

	# Leaving the arena: the entire FX owner can disappear before the timers.
	fx = _make_fx()
	refs = _emit_all(fx)
	fx.queue_free()
	fx = null
	await process_frame
	await process_frame
	_expect_released(refs, "owner deletion really frees every visual")
	await create_timer(CombatFx.ELIMINATION_SECONDS + 0.15).timeout
	print("COMBAT_FX_LIFECYCLE_TEST_%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)

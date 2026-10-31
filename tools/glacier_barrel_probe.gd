extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog: Catalog = Catalog.new()
	var world: MatchWorld = MatchWorld.new()
	root.add_child(world)
	world.configure(catalog,"glacier_peak",catalog.starter_loadouts()[0],1,2410,true)
	for frame: int in 600:
		if world.ready_for_play:break
		await physics_frame
	world.set_physics_process(false)
	world.clock = 10.0
	var barrels: Array[Destructible] = []
	for prop: Destructible in world.destructibles:
		if prop.kind == Destructible.Kind.BARREL:barrels.append(prop)
	var shooter: Combatant = world.actors[0]
	for actor: Combatant in world.actors:
		actor.alive = false
		actor.collision_layer = 0
		actor.head.collision_layer = 0
		actor.torso.collision_layer = 0
	var scaled: int = 0
	var visible: int = 0
	var ray_hits: int = 0
	var punctured: int = 0
	var exploded: int = 0
	var hidden: int = 0
	var runtime: WeaponRuntime = WeaponRuntime.new()
	runtime.configure(catalog.weapons.ar_a4,[])
	for barrel: Destructible in barrels:
		var shape: CylinderShape3D = (barrel.body.get_child(0) as CollisionShape3D).shape as CylinderShape3D
		if shape != null and absf(shape.height-1.24)<0.01:scaled+=1
		if not barrel.visuals.is_empty():
			var box: AABB = barrel.visuals[0].global_transform * barrel.visuals[0].mesh.get_aabb()
			if box.size.y>1.15 and box.size.y<1.3:visible+=1
		var hit: Dictionary = world.ray(barrel.center+Vector3(0,0,-0.9),barrel.center,shooter)
		if hit.get("collider")==barrel.body:ray_hits+=1
		shooter.global_position = barrel.center+Vector3(0,-0.62,-2.5)
		shooter.yaw = PI
		shooter.pitch = atan2(barrel.center.y-shooter.eye().y,2.5)
		shooter.ads = true
		world.fire(shooter,runtime)
		if barrel.state==Destructible.State.LEAKING:punctured+=1
		for shot: int in 6:world.fire(shooter,runtime)
		world.clock+=0.02
		world.step_destructibles()
		if barrel.state==Destructible.State.DONE and barrel.body.collision_layer==0:exploded+=1
		if not barrel.visuals.is_empty() and barrel.visuals.all(func(mesh:MeshInstance3D)->bool:return not mesh.visible):hidden+=1
	var checks: Dictionary = {"nine_registered_explosive_barrels":barrels.size()==9,"full_size_colliders":scaled==9,"full_size_visible_drums":visible==9,"bullet_ray_hits_barrels":ray_hits==9,"actual_rifle_shot_punctures":punctured==9,"seven_a4_rifle_shots_detonate":exploded==9,"detonation_hides_drum":hidden==9}
	var failed: int = 0
	for label: String in checks:
		print("PASS " if checks[label] else "FAIL ",label)
		if not checks[label]:failed+=1
	var report: Dictionary = {"passed":checks.size()-failed,"failed":failed,"checks":checks,"registered":barrels.size(),"scaled":scaled,"visible":visible,"rays":ray_hits,"punctured":punctured,"exploded":exploded,"hidden":hidden}
	DirAccess.make_dir_recursive_absolute("res://.artifacts/glacier_overhaul")
	var output: FileAccess = FileAccess.open("res://.artifacts/glacier_overhaul/barrels.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"));output.close()
	world.free()
	await process_frame
	quit(1 if failed>0 else 0)

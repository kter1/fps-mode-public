extends SceneTree

var results:Array[Dictionary]=[]

func _initialize() -> void:call_deferred("run")

func verify(condition:bool,name:String) -> void:
	results.append({"name":name,"passed":condition});print("PASS " if condition else "FAIL ",name)

func run() -> void:
	var app:Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	await app.start_match()
	app.screen="inspection";paused=true
	app.set_process(false);app.hands.shown=false;app.hands.hide();app.hud.hide()
	var world:MatchWorld=app.match_world
	var target:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(1,1,.1);target.mesh=box
	var red:=StandardMaterial3D.new();red.albedo_color=Color(1,.015,.01);red.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;target.material_override=red
	world.add_child(target);target.position=Vector3(0,2,-3)
	var grenade:=GameGrenade.new();world.add_child(grenade);grenade.kind=1;grenade.global_position=Vector3(0,.3,0);world.detonate(grenade);grenade.queue_free()
	var smoke:Node3D=world.smoke_clouds[0].node
	verify(not smoke.can_process(),"smoke_visual_pauses_with_match")
	verify(not smoke.get_node("Smoke").can_process(),"smoke_particles_pause_with_match")
	# This inspection freezes gameplay while advancing the cosmetic cloud.
	# Normal play inherits MatchWorld's pausable process mode.
	smoke.process_mode=Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/graphics")
	for quality in 3:
		app.profile.settings.quality=quality;app.apply_settings()
		verify(app.world_view.size==app.get_window().size and absi(RenderScale.internal_size(app.world_view).y-RenderScale.HEIGHTS[quality])<=1,"resolution_"+str(quality))
		verify(app.get_node_or_null("FirstPersonRender")==null and app.hands.get_parent()==app.camera,"single_world_render_"+str(quality))
		verify(app.world_view.use_taa,"temporal_aa_"+str(quality))
		verify(not app.world_view.use_occlusion_culling,"conservative_visibility_"+str(quality))
		verify(app.world_view.msaa_3d==Viewport.MSAA_4X,"msaa_"+str(quality))
		verify(app.world_view.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED,"screen_aa_"+str(quality))
		verify(world.effects.effect_budget==[48,96,144][quality],"cosmetic_pool_"+str(quality))
		verify(world.arena.get_node("Sun").directional_shadow_max_distance==[35,45,120][quality],"shadow_distance_"+str(quality))
		verify(not world.visible_between(Vector3(-5,2,0),Vector3(5,2,0),true),"smoke_core_"+str(quality))
		var cloud:Node3D=world.smoke_clouds[0].node
		cloud.hide();app.camera.position=Vector3(0,2,0);app.camera.rotation=Vector3.ZERO
		var clear:Color=await center_pixel()
		verify(clear.r>clear.g*2 and clear.r>.5,"smoke_pixel_control_"+str(quality))
		cloud.show()
		var inside:Color=await center_pixel()
		verify(inside.r<inside.g*1.3,"smoke_inside_occludes_"+str(quality))
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/graphics/"+str(quality)+"-inside.png")
		app.camera.position=Vector3(0,2,8);app.camera.look_at(Vector3(0,2,0))
		var outside:Color=await center_pixel()
		verify(outside.r<outside.g*1.3,"smoke_outside_occludes_"+str(quality))
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/graphics/"+str(quality)+"-outside.png")
	var actor:Combatant=world.actors[0]
	var arms:Node3D=app.hands.arms
	var primary_rig:Node3D=app.hands.rig
	app.hands.refresh(actor)
	verify(app.hands.arms==arms,"viewmodel_refresh_reuses_skinned_arms")
	verify(app.hands.rig==primary_rig,"viewmodel_refresh_reuses_weapon_rig")
	actor.switch_to(1,world.clock);app.hands.refresh(actor)
	verify(app.hands.arms==arms and app.hands.rig!=primary_rig,"viewmodel_switch_keeps_shared_arms")
	actor.switch_to(0,world.clock);app.hands.refresh(actor)
	verify(app.hands.rig==primary_rig,"viewmodel_return_restores_cached_rig")
	var failed:=results.filter(func(row:Dictionary):return not row.passed).size()
	var file:=FileAccess.open("res://.artifacts/reports/graphics.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":results.size()-failed,"failed":failed,"tests":results},"\t"));file.close()
	if failed>0:push_error("Graphics preset regression failed")
	print("GRAPHICS CHECK ",results.size()-failed," passed / ",failed," failed")
	paused=false
	await app.safe_quit()

func center_pixel() -> Color:
	# CPU emitters publish their interpolated render data during node processing,
	# after SceneTree.process_frame. Allow that update before a forced QA draw.
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	return image.get_pixel(image.get_width()/2,image.get_height()/2)

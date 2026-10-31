extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	RenderingServer.render_loop_enabled=true
	var catalog:=Catalog.new()
	var camera:=Camera3D.new();camera.fov=70;camera.near=.025;root.add_child(camera);camera.current=true
	var environment:=WorldEnvironment.new();var sky:=Environment.new();sky.background_mode=Environment.BG_COLOR;sky.background_color=Color("647585");sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;sky.ambient_light_energy=.8;sky.ambient_light_color=Color("cad8e1");environment.environment=sky;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=1.6;root.add_child(sun)
	var actor:=Combatant.new();root.add_child(actor);var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();actor.setup(slot,catalog)
	var hands:=ViewModel.new();root.add_child(hands)
	var title:=Label.new();title.position=Vector2(28,28);title.add_theme_font_size_override("font_size",25);root.add_child(title)
	var reticle:=Label.new();reticle.text="+";reticle.position=Vector2(632,343);reticle.add_theme_font_size_override("font_size",26);root.add_child(reticle)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/arsenal")
	for id in catalog.weapon_ids:
		slot.loadout.primary=StringName(id);slot.loadout.primary_attachments=[];actor.set_loadout(catalog);actor.ads=false
		hands.refresh(actor);hands.tick(1,0,0);title.text=catalog.weapons[id].display_name+" / GRIP INSPECTION"
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/arsenal/"+id+"-hip.png")
		actor.ads=true;hands.tick(1,0,0);title.text=catalog.weapons[id].display_name+" / AIM INSPECTION"
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/arsenal/"+id+".png")
		# Side views of the aimed rig: grip hand (right) and support hand (left).
		for view in [["right",Vector3(.75,-.12,-.3)],["left",Vector3(-.75,-.12,-.3)]]:
			camera.position=view[1];camera.look_at(Vector3(0,-.12,-.3));title.text=catalog.weapons[id].display_name+" / "+str(view[0]).to_upper()+" SIDE"
			reticle.visible=false
			await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://.artifacts/screenshots/arsenal/"+id+"-"+str(view[0])+".png")
		camera.transform=Transform3D.IDENTITY;reticle.visible=true
		# A shot from the hip (flash, recoil, cycling) and the magazine change.
		var runtime:=actor.weapon();actor.ads=false;hands.blend=0
		runtime.last_shot_at=0;hands.previous_ammo=runtime.ammo+1;hands.tick(1.0/60,0.01,1)
		title.text=catalog.weapons[id].display_name+" / FIRING"
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/arsenal/"+id+"-fire.png")
		runtime.last_shot_at=-100;runtime.ammo=3;hands.previous_ammo=3;runtime.start_reload(0)
		for phase in [[.3,"reload-out"],[.8,"reload-in"]]:
			hands.tick(1,runtime.reload_time*float(phase[0]),0);title.text=catalog.weapons[id].display_name+" / "+str(phase[1]).to_upper()
			await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://.artifacts/screenshots/arsenal/"+id+"-"+str(phase[1])+".png")
		runtime.cancel_reload()
	hands.free();actor.free();ModelFactory.sources.clear()
	await process_frame
	print("ARSENAL INSPECTION CAPTURE PASS / 15 WEAPONS");quit()

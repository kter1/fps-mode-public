extends SceneTree

# Walks a real player body (Combatant movement, sprinting, then crouched and jumping) straight
# into every wall-shaped surface of each map and reports any it ends up behind.
#   godot --headless --script res://tools/walkthrough_probe.gd -- [--map=village]

class Stub extends RefCounted:
	var clock := 0.0
	var actors: Array[Combatant] = []
	var effects := self
	func sound(_kind, _position, _volume := 1.0, _priority := false) -> void: pass

func _initialize() -> void:call_deferred("probe")

func probe() -> void:
	var ids:=MapCatalog.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):ids=[arg.trim_prefix("--map=")]
	var catalog:=Catalog.new();var stub:=Stub.new()
	var total:=0
	for id in ids:
		var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
		var actor:=Combatant.new();arena.add_child(actor)
		var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=catalog.starter_loadouts()[0];actor.setup(slot,catalog)
		stub.actors=[actor]
		for frame in 3:await physics_frame
		var space:=arena.get_world_3d().direct_space_state
		var extent:Vector2=arena.definition.extent
		var leaks:=[];var tried:=0
		for node in arena.find_children("*","MeshInstance3D",true,false):
			var mesh:MeshInstance3D=node
			if mesh.mesh==null or not mesh.is_visible_in_tree() or mesh.is_ancestor_of(actor) or actor.is_ancestor_of(mesh):continue
			var box:=mesh.global_transform*mesh.mesh.get_aabb()
			var long:=maxf(box.size.x,box.size.z);var thin:=minf(box.size.x,box.size.z)
			if box.size.y<1.8 or long<1.2 or thin>1.0 or box.position.y>.4:continue
			if absf(box.get_center().x)>extent.x*.5-1 or absf(box.get_center().z)>extent.y*.5-1:continue
			var faces:=mesh.mesh.get_faces();var to_world:=mesh.global_transform
			var across:=Vector3(0,0,1) if box.size.x>=box.size.z else Vector3(1,0,0)
			for k in 4:
				var t:=(k+.5)/4.0
				var p:=box.position+Vector3(box.size.x*(t if box.size.x>=box.size.z else .5),1.0-box.position.y,box.size.z*(t if box.size.z>box.size.x else .5))
				var surfaced:=false
				for f in range(0,faces.size(),3):
					if Geometry3D.ray_intersects_triangle(p-across*(thin+.5),across,to_world*faces[f],to_world*faces[f+1],to_world*faces[f+2])!=null:surfaced=true;break
				if not surfaced:continue
				for side:float in [-1.0,1.0]:
					var direction:Vector3=across*-side
					var start:Vector3=p+across*side*(thin*.5+.7);start.y=box.position.y+2.0
					var down:=space.intersect_ray(PhysicsRayQueryParameters3D.create(start,start+Vector3.DOWN*3,1))
					if down.is_empty():continue
					start=Vector3(down.position)+Vector3.UP*.05
					# Start position must be free.
					var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.36;capsule.height=1.8
					query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.92);query.collision_mask=3;query.exclude=actor.excluded()
					if not space.intersect_shape(query,1).is_empty():continue
					for style in ["sprint","crouch_jump"]:
						tried+=1
						actor.respawn(start,0.0,catalog);actor.global_position=start;actor.velocity=Vector3.ZERO;actor.protected_until=0
						var command:=ActorCommand.new();command.aim_yaw=atan2(-direction.x,-direction.z);command.movement=Vector2(0,-1)
						command.sprint=style=="sprint";command.crouch=style=="crouch_jump"
						for step in 75:
							command.jump_pressed=style=="crouch_jump" and step%20==5
							actor.command=command;actor.simulate_movement(1.0/60,stub);stub.clock+=1.0/60
						var past:=(actor.global_position-p).dot(direction)
						if past>thin*.5+.2 and absf(actor.global_position.y-start.y)<1.5:
							leaks.append("%s (%s) wall at %s from %s %s ended %s"%[mesh.name,mesh.get_parent().name,str(p.snapped(Vector3.ONE*.1)),str(start.snapped(Vector3.ONE*.1)),style,str(actor.global_position.snapped(Vector3.ONE*.1))])
		print("== ",id," walked into walls ",tried," times; went through ",leaks.size())
		for line in leaks.slice(0,30):print("  ",line)
		total+=leaks.size()
		arena.queue_free();await process_frame;await process_frame
	print("WALKTHROUGH PROBE ",total)
	quit(1 if total>0 else 0)

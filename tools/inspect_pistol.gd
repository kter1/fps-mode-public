extends SceneTree

# Renders the first-person pistol hold (hip and aimed) for every sidearm, plus one rifle for
# reference, through the real ViewModel as 1280x720 frames. Writes <out>/<tag>_<weapon>_<hip|ads>.png
# and the arm chains (camera-space joints) to <out>/<tag>_chains.json.
# Args: --tag=NAME --out=DIR (default .artifacts/screenshots/pistol)
# Usage: godot --script res://tools/inspect_pistol.gd -- --tag=after

const WEAPONS := ["pistol_p9","pistol_p45","pistol_r357","ar_a4"]
var tag := "after"
var out := "res://.artifacts/screenshots/pistol"

func _initialize() -> void:call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):tag=argument.trim_prefix("--tag=")
		if argument.begins_with("--out="):out=argument.trim_prefix("--out=")
	root.size=Vector2i(1280,720)
	RenderingServer.render_loop_enabled=true
	var catalog:=Catalog.new()
	var camera:=Camera3D.new();camera.fov=75;camera.near=.025;root.add_child(camera);camera.current=true;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment:=WorldEnvironment.new();var sky:=Environment.new();sky.background_mode=Environment.BG_COLOR;sky.background_color=Color("647585");sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;sky.ambient_light_energy=.8;sky.ambient_light_color=Color("b8c4d0")
	environment.environment=sky;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-32,0);sun.light_energy=1.6;root.add_child(sun)
	DirAccess.make_dir_recursive_absolute(out)
	var player:=Combatant.new();root.add_child(player);var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();player.setup(slot,catalog)
	var hands:=ViewModel.new();camera.add_child(hands);hands.shown=true
	await render_set(tag,WEAPONS,player,slot,catalog,camera,hands)
	print("PISTOL INSPECTION PASS");quit()

func render_set(label:String,weapons:Array,player:Combatant,slot:ActorSlot,catalog:Catalog,camera:Camera3D,hands:ViewModel) -> void:
	var chains:={}
	for weapon in weapons:
		if str(weapon).begins_with("pistol"):slot.loadout.sidearm=StringName(weapon);player.set_loadout(catalog);player.switch_to(1,0.0)
		else:slot.loadout.primary=StringName(weapon);player.set_loadout(catalog);player.switch_to(0,0.0)
		for state in ["hip","ads"]:
			player.ads=state=="ads"
			hands.refresh(player);hands.shown=true;hands.blend=1.0 if player.ads else 0.0
			for i in 20:hands.tick(1.0/60,1.0+float(i)/60,0.0)
			var name:String=label+"_"+str(weapon)+"_"+state
			print("BEND ",name," L=%.1f R=%.1f"%[hands.wrist_bend("L"),hands.wrist_bend("R")])
			await process_frame;RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(out+"/"+name+".png")
			chains[name]=chain(hands,camera)
	var file:=FileAccess.open(out+"/"+label+"_chains.json",FileAccess.WRITE);file.store_string(JSON.stringify(chains,"\t"));file.close()

# Shoulder, elbow, wrist and middle knuckle of each arm in camera space.
func chain(hands:ViewModel,camera:Camera3D) -> Dictionary:
	var result:={}
	var to_camera:=camera.global_transform.affine_inverse()
	for side in ["L","R"]:
		var joints:={}
		for part in ["Arm","ForeArm","Hand","HandMiddle1"]:
			var point:Vector3=to_camera*(hands.skeleton.global_transform*hands.skeleton.get_bone_global_pose(hands.bone(side,part)).origin)
			joints[part]=[point.x,point.y,point.z]
		result[side]=joints
	return result

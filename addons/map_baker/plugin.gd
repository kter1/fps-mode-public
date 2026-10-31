@tool
extends EditorPlugin

func _enter_tree() -> void:
	if "--bake-maps" in OS.get_cmdline_user_args():call_deferred("bake_maps")
	for argument in OS.get_cmdline_user_args():
		# --bake-scene=res://path.tscn bakes one scene (diagnostics and partial rebakes).
		if argument.begins_with("--bake-scene="):call_deferred("bake_maps",[argument.trim_prefix("--bake-scene=")])

func find_bake(node: Node) -> Button:
	if node is Button and "Bake Lightmaps" in node.text:return node
	for child in node.get_children():
		var found:=find_bake(child)
		if found!=null:return found
	return null

# Every registered map (content/manifest/map_list/<id>.json; see MapCatalog).
func registered_scenes() -> Array:
	var scenes:=[]
	for file in DirAccess.get_files_at("res://content/manifest/map_list/"):
		if file.ends_with(".json"):scenes.append("res://game/maps/generated/"+file.get_basename()+".tscn")
	scenes.sort()
	return scenes

func bake_maps(paths:Array=[]) -> void:
	if paths.is_empty():paths=registered_scenes()
	await get_tree().create_timer(2).timeout
	for path in paths:
		var id:String=path.get_file().get_basename()
		var data_path:String=path.get_basename()+"_lightmap.lmbake"
		var started:=Time.get_ticks_msec()
		EditorInterface.open_scene_from_path(path)
		await get_tree().create_timer(1).timeout
		var map:=EditorInterface.get_edited_scene_root()
		var gi:LightmapGI=map.get_node("BakedLight")
		if gi.light_data==null:
			var data:=LightmapGIData.new()
			ResourceSaver.save(data,data_path)
			gi.light_data=data
		gi.light_data.take_over_path(data_path)
		EditorInterface.edit_node(gi)
		await get_tree().create_timer(1).timeout
		var button:=find_bake(EditorInterface.get_base_control())
		if button==null:
			push_error("Editor lightmap bake command was not found")
			get_tree().quit(1);return
		print("EDITOR BAKE BEGIN ",id)
		button.pressed.emit()
		await get_tree().create_timer(2).timeout
		for dialog in EditorInterface.get_base_control().find_children("*","EditorFileDialog",true,false):
			if dialog.visible:dialog.file_selected.emit(data_path);dialog.hide()
		print_dialogs(EditorInterface.get_base_control())
		EditorInterface.save_scene()
		print("EDITOR BAKE END ",id," seconds=",(Time.get_ticks_msec()-started)/1000.0)
	print("LIGHTMAP BAKE PASS")
	get_tree().quit(0)

func print_dialogs(node: Node) -> void:
	if node is AcceptDialog and node.visible:print("BAKE DIALOG: ",node.dialog_text)
	for child in node.get_children():print_dialogs(child)

extends SceneTree

func _initialize() -> void:
	call_deferred("prepare")

func prepare() -> void:
	var id:="dead_current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):id=arg.trim_prefix("--map=")
	var builder:=ZombiesMapBuilder.new();var arena:=builder.build(id)
	var packed:=PackedScene.new();packed.pack(arena)
	var result:=ResourceSaver.save(packed,MapCatalog.scene_path(id))
	arena.free()
	print("ZOMBIES PREPARE ",id," ",result)
	quit(0 if result==OK else 1)

extends SceneTree

var errors := 0

func scan(path: String) -> void:
	var directory:=DirAccess.open(path)
	for file in directory.get_files():
		if not file.ends_with(".gd"):continue
		var script:Script=load(path.path_join(file))
		if script==null or not script.can_instantiate():
			errors+=1;print("INVALID SCRIPT ",path.path_join(file))
	for child in directory.get_directories():scan(path.path_join(child))

func _initialize() -> void:
	scan("res://game")
	scan("res://tests")
	scan("res://tools")
	print("SCRIPT_CHECK ",errors," failures")
	quit(0 if errors==0 else 1)

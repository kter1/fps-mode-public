extends SceneTree

func _initialize() -> void:
	var index:Array[Dictionary]=[]
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/review")
	var groups:Array[String]=["arsenal","operators","optics"]
	groups.append_array(MapCatalog.ids());groups.append_array(["controls","replay","overviews"])
	for group in groups:
		var directory:String="res://.artifacts/screenshots/"+group
		if not DirAccess.dir_exists_absolute(directory):continue
		var files:=DirAccess.get_files_at(directory);var names:Array[String]=[]
		for file in files:
			if file.ends_with(".png") and (group!="arsenal" or "-" not in file or file.ends_with("-hip.png")):names.append(file)
		for offset in range(0,names.size(),4):
			var sheet:=Image.create_empty(1280,720,false,Image.FORMAT_RGB8);sheet.fill(Color("18232e"))
			var sources:Array[String]=[]
			for tile in mini(4,names.size()-offset):
				var name:=names[offset+tile];var source:=Image.load_from_file(directory+"/"+name);source.convert(Image.FORMAT_RGB8);source.resize(640,360,Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(source,Rect2i(0,0,640,360),Vector2i((tile%2)*640,(tile/2)*360));sources.append(group+"/"+name)
			var output:String="res://.artifacts/screenshots/review/"+group+"-"+str(offset/4)+".png";sheet.save_png(output)
			index.append({"sheet":output,"sources":sources})
	var file:=FileAccess.open("res://.artifacts/screenshots/review/index.json",FileAccess.WRITE);file.store_string(JSON.stringify(index,"\t"));file.close()
	print("REVIEW SHEETS ",index.size());quit()

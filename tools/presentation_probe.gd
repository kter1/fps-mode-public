extends SceneTree

func _initialize() -> void:call_deferred("inspect_presentation")

func inspect_presentation() -> void:
	root.size=Vector2i(640,400)
	var swatch:=ColorRect.new();swatch.color=Color(.15,.25,.35);swatch.size=Vector2(640,400);root.add_child(swatch)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var usable:=DisplayServer.screen_get_usable_rect()
	var screen_size:=DisplayServer.screen_get_size()
	var values:=[]
	for phase in ["visible","outside_display","visible_again"]:
		root.position=usable.position+Vector2i(50,80) if phase!="outside_display" else Vector2i(screen_size.x-100,screen_size.y+40)
		for frame in 20:await process_frame
		var began:=Time.get_ticks_usec();var frames:=0
		while Time.get_ticks_usec()-began<3000000:
			await process_frame;frames+=1
		var elapsed:float=(Time.get_ticks_usec()-began)/1000000.0
		values.append({"phase":phase,"frames":frames,"seconds":elapsed,"fps":frames/elapsed,"vsync":DisplayServer.window_get_vsync_mode(),"position":str(root.position)})
	root.position=usable.position+Vector2i(50,80)
	var result:={"engine":Engine.get_version_info().string,"driver":RenderingServer.get_current_rendering_driver_name(),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"results":values,"purpose":"Empty-scene presentation diagnostic only; not a game benchmark"}
	var path:String="res://.artifacts/probes/presentation-"+str(result.driver)+".json"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PRESENTATION_PROBE ",JSON.stringify(result));quit()

extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var passed:=true
	for id in MapCatalog.ids_for_mode("zombies"):
		var world:=ZombiesWorld.new();root.add_child(world);world.configure(Catalog.new(),id,LoadoutDefinition.new(),1,2601)
		for i in 8:await physics_frame
		world.qa_protect_player=true;world.mode.intermission=10000
		for station in world.stations:
			if station.kind=="door":station.open(world)
		for i in 3:await physics_frame
		for fixture in [{"crawl":false,"start":Vector3(22,0,-10)},{"crawl":true,"start":Vector3(22,0,-10)},{"crawl":false,"start":Vector3(-16,0,-24)},{"crawl":true,"start":Vector3(-16,0,-24)}]:
			var crawling: bool=fixture.crawl
			var enemy:=world.actors[1] as ZombieActor
			enemy.activate(fixture.start,world.clock,500,2,null);enemy.state="PURSUE"
			if crawling:enemy.become_crawler()
			for i in (9000 if crawling else 3000):
				world.actors[0].global_position=Vector3(-6+sin(i*.015)*6,0,6) if i<1800 else Vector3(-6,0,6)
				await physics_frame
			var reached:=enemy.global_position.distance_to(world.actors[0].global_position)<3
			print("PATH ",id," start=",fixture.start," crawler=",crawling," ","PASS" if reached else "FAIL"," at=",enemy.global_position)
			passed=passed and reached;enemy.deactivate()
		world.free()
	print("ZOMBIES PATH ","PASS" if passed else "FAIL");quit(0 if passed else 1)

class_name MapDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export var extent := Vector2(220, 180)
@export var scene_path := ""
@export var spawns_blue: Array[Vector3] = []
@export var spawns_red: Array[Vector3] = []
@export var routes: Array[Vector3] = []
@export var cover_points: Array[Vector3] = []
@export var cover_peeks: Array[Vector3] = []
@export var ammo_caches: Array[Vector3] = []
@export var domination: Array[Vector3] = []
@export var hardpoints: Array[Vector3] = []
@export var qa_route: Array[Vector3] = []

@export var zombies: Dictionary = {}

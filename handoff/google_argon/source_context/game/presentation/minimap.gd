class_name Minimap
extends Control

# Top-left radar (CoD-style). The map's pre-rendered top-down texture (content/minimaps/<id>.png,
# bounds in the registry "minimap" entry) turns under a fixed player arrow: the shader rotates
# and masks the texture every frame, and markers are drawn on an overlay at 30 Hz. Allies show
# with facing; enemies appear only as a ping for PING_TIME after an unsuppressed shot.

const RANGE_M := 40.0
const DESIGN_PX := 200.0          # diameter at 1080p, scaled with the viewport height
const MARGIN := Vector2(18,16)    # the HUD's left gutter and top edge
const PING_TIME := 2.0
const MARK_INTERVAL := 1.0/30.0
const SHOT_WINDOW := .2           # a shot counts as new only if it happened this recently
const ALLY := Color("70c9ed")
const ENEMY := Color("f0604f")
const RIM := Color(.62,.74,.82,.7)
const PLAYER := Color("edf2f6")
const SHADER := """
shader_type canvas_item;
uniform vec2 centre_uv;
uniform vec2 forward;
uniform vec2 right_axis;
uniform float radius_m;
uniform float span_m;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Screen up is the player's facing; each disc point maps to metres on the map plane.
	vec2 q = vec2(p.x, -p.y) * radius_m;
	vec2 uv = centre_uv + (q.x * right_axis + q.y * forward) / span_m;
	vec3 colour = texture(TEXTURE, uv).rgb;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) colour = vec3(0.03, 0.05, 0.07);
	COLOR = vec4(colour, 0.94 * (1.0 - smoothstep(0.96, 1.0, r)));
}
"""

var world: MatchWorld
var replaying := false            # kill replay hides the radar; the HUD sets this
var bounds := Rect2()             # world XZ rectangle the square texture covers

var _map := TextureRect.new()
var _marks := Control.new()
var _material := ShaderMaterial.new()
var _diameter := 0.0
var _mark_clock := 0.0
var _origin := Vector2.ZERO      # player XZ at the last overlay sample
var _forward := Vector2(0,-1)    # player facing on the map plane at the last sample
var _right := Vector2(1,0)
var _shots := PackedFloat64Array()  # last_shot_at seen per actor, to spot new shots
var _pings := PackedVector3Array()  # enemy shots as x, z and world clock

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode=TextureRect.STRETCH_SCALE
	_map.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shader:=Shader.new();shader.code=SHADER;_material.shader=shader;_map.material=_material
	_marks.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_map);add_child(_marks)

# Square side of the radar in pixels for the current viewport; the HUD places its match panel below.
func diameter() -> float:
	return roundf(DESIGN_PX*get_viewport_rect().size.y/1080.0)

func bind(source: MatchWorld) -> void:
	world=source
	var definition:=source.arena.definition
	var registry:Dictionary=MapCatalog.entry(definition.id).get("minimap",{})
	var box:Array=registry.get("bounds",[])
	if box.size()!=4 or not registry.has("texture"):
		push_error("Missing minimap registry entry for "+definition.id);visible=false;return
	bounds=Rect2(float(box[0]),float(box[1]),float(box[2])-float(box[0]),float(box[3])-float(box[1]))
	_map.texture=load(str(registry.texture))
	_shots.resize(source.actors.size())
	for i in source.actors.size():_shots[i]=source.actors[i].weapon().last_shot_at

# World XZ to texture UV, for a box [x0, z0, x1, z1]. The top edge is -Z (north), the right edge +X.
static func uv_of(box: Array, point: Vector3) -> Vector2:
	return Vector2((point.x-float(box[0]))/(float(box[2])-float(box[0])),(point.z-float(box[1]))/(float(box[3])-float(box[1])))

func _process(delta: float) -> void:
	# Match teardown can free or detach actors before the HUD stops updating.
	if world==null or world.actors.is_empty() or bounds.size.x<=0 or not world.actors[0].is_inside_tree():
		visible=false;return
	var player:=world.actors[0]
	var runtime:=player.weapon()
	visible=not replaying and not (player.ads and runtime.magnification>=3.0)
	if not visible:return
	var diameter_px:=diameter()
	if diameter_px!=_diameter:
		_diameter=diameter_px;position=MARGIN;size=Vector2.ONE*diameter_px;_map.size=size;_marks.size=size
	var forward:=Vector2(-sin(player.yaw),-cos(player.yaw))
	var player_xz:=Vector2(player.global_position.x,player.global_position.z)
	_material.set_shader_parameter("centre_uv",(player_xz-bounds.position)/bounds.size.x)
	_material.set_shader_parameter("forward",forward)
	_material.set_shader_parameter("right_axis",Vector2(-forward.y,forward.x))
	_material.set_shader_parameter("radius_m",RANGE_M)
	_material.set_shader_parameter("span_m",bounds.size.x)
	_mark_clock-=delta
	if _mark_clock<=0:
		_mark_clock=MARK_INTERVAL
		_sample()
		_marks.queue_redraw()

# Overlay state at 30 Hz: player frame, enemy shots (new, unsuppressed, just fired) and ping expiry.
func _sample() -> void:
	var player:=world.actors[0]
	_origin=Vector2(player.global_position.x,player.global_position.z)
	_forward=Vector2(-sin(player.yaw),-cos(player.yaw));_right=Vector2(-_forward.y,_forward.x)
	var clock:=world.clock
	if _shots.size()!=world.actors.size():
		_shots.resize(world.actors.size())
		for i in world.actors.size():_shots[i]=world.actors[i].weapon().last_shot_at
	for i in world.actors.size():
		var actor:=world.actors[i]
		var runtime:=actor.weapon()
		if runtime.last_shot_at==_shots[i]:continue
		_shots[i]=runtime.last_shot_at
		# A weapon switch can change last_shot_at without a shot; only a fresh one pings.
		if actor.slot.team==player.slot.team or clock-runtime.last_shot_at>SHOT_WINDOW:continue
		if runtime.attachments.has("suppressor"):continue
		_pings.append(Vector3(actor.global_position.x,actor.global_position.z,clock))
	for i in range(_pings.size()-1,-1,-1):
		if clock-_pings[i].z>PING_TIME:_pings.remove_at(i)

# World XZ offset to overlay pixels relative to the centre, in metres: up is the player's facing.
func _to_screen(offset: Vector2) -> Vector2:
	return Vector2(offset.dot(_right),-offset.dot(_forward))

func _draw_marks() -> void:
	if world==null or world.actors.is_empty():return
	var centre:=_marks.size*.5
	var radius:=centre.x-3.0
	var scale:=radius/RANGE_M
	_marks.draw_arc(centre,radius,0,TAU,96,RIM,1.5,true)
	var north:=_to_screen(Vector2(0,-1)).normalized()
	_marks.draw_line(centre+north*(radius-7),centre+north*radius,RIM,2.0,true)
	_marks.draw_string(ThemeDB.fallback_font,centre+north*(radius-13)+Vector2(-4,4),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,11,RIM)
	var player:=world.actors[0]
	for i in range(1,world.actors.size()):
		var actor:=world.actors[i]
		if not actor.alive or actor.slot.team!=player.slot.team:continue
		var relative:=Vector2(actor.global_position.x,actor.global_position.z)-_origin
		if relative.length()>RANGE_M:continue
		var at:=centre+_to_screen(relative)*scale
		var facing:=_to_screen(Vector2(-sin(actor.yaw),-cos(actor.yaw)))
		_marks.draw_line(at,at+facing*7.0,ALLY,1.6,true)
		_marks.draw_circle(at,3.2,ALLY)
	for ping in _pings:
		var alpha:=clampf(1.0-(world.clock-ping.z)/PING_TIME,0,1)
		if alpha<=0:continue
		var relative:=Vector2(ping.x,ping.y)-_origin
		# Shots beyond the radar range are pinned to the rim so they still show a bearing.
		if relative.length()>RANGE_M:relative=relative.normalized()*RANGE_M*.92
		var at:=centre+_to_screen(relative)*scale
		_marks.draw_circle(at,4.0,Color(ENEMY,alpha*.9))
		_marks.draw_arc(at,8.0,0,TAU,24,Color(ENEMY,alpha*.5),1.5,true)
	if player.alive:
		_marks.draw_colored_polygon(PackedVector2Array([centre+Vector2(0,-10),centre+Vector2(7,7),centre+Vector2(0,3),centre+Vector2(-7,7)]),PLAYER)

class_name CampaignDialogue
extends Node3D

signal cue_started(id: String)
signal completed

const MANIFEST := "res://content/data/campaign/dead_circuit_dialogue.json"
const RADIO_BUS := "Campaign radio"
var world: Object
var cues: Array[Dictionary] = []
var streams: Array[AudioStream] = []
var spatial: AudioStreamPlayer3D
var radio: AudioStreamPlayer
var active := false
var intro_started := false
var current_index := -1
var remaining := 0.0
var subtitle := ""
var lead_seconds := 1.8

func configure(source: Object) -> void:
	world=source
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or not data.get("cues") is Array:
		push_error("Campaign dialogue manifest is missing or invalid");return
	lead_seconds=float(data.get("lead_seconds",1.8))
	for cue in data.cues:
		var stream:=load(str(cue.audio)) as AudioStream
		if stream==null or stream.get_length()<=0:
			push_error("Campaign dialogue audio is missing: "+str(cue.audio));return
		cues.append(cue);streams.append(stream)
	spatial=AudioStreamPlayer3D.new();spatial.name="SquadVoice"
	spatial.unit_size=10;spatial.max_distance=90;spatial.max_db=6
	spatial.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(spatial)
	if AudioServer.get_bus_index(RADIO_BUS)<0:
		AudioServer.add_bus();var index:=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,RADIO_BUS);AudioServer.set_bus_send(index,"Master")
		var high:=AudioEffectHighPassFilter.new();high.cutoff_hz=280
		var low:=AudioEffectLowPassFilter.new();low.cutoff_hz=4300
		AudioServer.add_bus_effect(index,high);AudioServer.add_bus_effect(index,low)
	radio=AudioStreamPlayer.new();radio.name="ControlRadio";radio.bus=RADIO_BUS;add_child(radio)

func start_intro() -> void:
	if intro_started or cues.size()!=10 or world.mode.stage!=0:return
	intro_started=true;active=true;current_index=-1;remaining=lead_seconds;subtitle=""

func _process(delta:float) -> void:
	if world==null:return
	if world.mode.finished or not world.actors[0].alive:
		stop();return
	if spatial!=null and current_index>=0 and current_index<cues.size():
		var speaker:String=cues[current_index].speaker
		var slot:=1 if speaker=="rook" else 2
		if speaker!="control" and not world.actors[slot].alive:
			stop();return
		spatial.global_position=world.actors[slot].eye()
	advance(delta)

func advance(delta:float) -> void:
	if not active:return
	remaining-=delta
	if current_index>=0 and remaining<=float(cues[current_index].gap):subtitle=""
	while active and remaining<=0:
		var carry:=remaining
		play_next()
		remaining+=carry

func play_next() -> void:
	spatial.stop();radio.stop();current_index+=1
	if current_index>=cues.size():
		active=false;subtitle="";remaining=0;completed.emit();return
	var cue:Dictionary=cues[current_index]
	subtitle=str(cue.speaker).to_upper()+"\n"+str(cue.text)
	if cue.speaker=="control":
		radio.stream=streams[current_index];radio.volume_db=float(cue.gain_db)+1.5;radio.play()
	else:
		var slot:=1 if cue.speaker=="rook" else 2
		if not world.actors[slot].alive:
			stop();return
		spatial.global_position=world.actors[slot].eye()
		spatial.stream=streams[current_index];spatial.volume_db=float(cue.gain_db);spatial.play()
	remaining=streams[current_index].get_length()+float(cue.gap)
	cue_started.emit(str(cue.id))

func stop() -> void:
	active=false;subtitle="";remaining=0
	if spatial!=null:spatial.stop()
	if radio!=null:radio.stop()

func _exit_tree() -> void:
	stop()

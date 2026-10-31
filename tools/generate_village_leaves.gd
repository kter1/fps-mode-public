extends SceneTree

# Leaf sprays for Village's trees and bushes. Each 1024 px card is composed from
# the individual photographed leaves of two CC0 ambientCG leaf sets (LeafSet004,
# LeafSet024), rescaled to real leaf size (about 7-8 cm on a 1.1 m card) and
# stamped along twigs with random angle and shade, carrying the sets' own
# normal maps. Output: colour, opacity (alpha test) and OpenGL normal maps in
# content/materials/village_leaf/. Run with:
#   python3 tools/dev.py ingest --domain maps --map village

const SIZE := 1024
const OUT := "res://content/materials/village_leaf/"
const SETS := {
	"linden": {"source": "res://content/models/props/LeafSet004/LeafSet004_1K-JPG_", "seed": 41, "length": 64.0, "fill": 220},
	"beech": {"source": "res://content/models/props/LeafSet024/LeafSet024_1K-JPG_", "seed": 87, "length": 58.0, "fill": 200},
}

var rgb: PackedByteArray
var alp: PackedByteArray
var nrm: PackedByteArray

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in SETS:spray(id,SETS[id])
	print("VILLAGE LEAVES PASS")
	quit()

# Splits a leaf sheet into one entry per leaf: RGBA crop (colour + opacity), RGB
# normal crop and the stem tip (the point a leaf attaches at).
@warning_ignore("integer_division")
func leaves_of(base: String) -> Array:
	var color:=Image.load_from_file(ProjectSettings.globalize_path(base)+"Color.jpg");color.convert(Image.FORMAT_RGBA8)
	var opacity:=Image.load_from_file(ProjectSettings.globalize_path(base)+"Opacity.jpg");opacity.convert(Image.FORMAT_L8)
	var normal:=Image.load_from_file(ProjectSettings.globalize_path(base)+"NormalGL.jpg");normal.convert(Image.FORMAT_RGB8)
	var w:=color.get_width();var h:=color.get_height()
	var alpha:=opacity.get_data()
	var label:=PackedInt32Array();label.resize(w*h)
	var found:Array=[];var next:=1
	for y0 in range(0,h,3):
		for x0 in range(0,w,3):
			if label[y0*w+x0]!=0 or alpha[y0*w+x0]<128:continue
			var stack:=PackedInt32Array([y0*w+x0]);label[y0*w+x0]=next
			var lo:=Vector2i(x0,y0);var hi:=Vector2i(x0,y0);var count:=0
			while stack.size()>0:
				var i:=stack[stack.size()-1];stack.resize(stack.size()-1)
				var x:=i%w;var y:=i/w
				count+=1;lo=Vector2i(mini(lo.x,x),mini(lo.y,y));hi=Vector2i(maxi(hi.x,x),maxi(hi.y,y))
				if x>0 and label[i-1]==0 and alpha[i-1]>=128:label[i-1]=next;stack.append(i-1)
				if x<w-1 and label[i+1]==0 and alpha[i+1]>=128:label[i+1]=next;stack.append(i+1)
				if y>0 and label[i-w]==0 and alpha[i-w]>=128:label[i-w]=next;stack.append(i-w)
				if y<h-1 and label[i+w]==0 and alpha[i+w]>=128:label[i+w]=next;stack.append(i+w)
			if count>2500:found.append({"id":next,"lo":lo,"hi":hi})
			next+=1
	var result:Array=[]
	for item in found:
		var lo:Vector2i=item.lo;var hi:Vector2i=item.hi
		var cw:=hi.x-lo.x+1;var ch:=hi.y-lo.y+1
		var crop:=Image.create(cw,ch,false,Image.FORMAT_RGBA8)
		var mean:=Color(0,0,0,0);var n:=0
		var stem:=Vector2i(0,0)
		for y in ch:
			for x in cw:
				var i:=(y+lo.y)*w+x+lo.x
				var who:=label[i]
				var a:=float(alpha[i])/255.0
				if who!=0 and who!=item.id:a=0.0
				var c:=color.get_pixel(x+lo.x,y+lo.y)
				if a>.5:
					mean+=c;n+=1
					if y>stem.y:stem=Vector2i(x,y)
				crop.set_pixel(x,y,Color(c.r,c.g,c.b,a))
		mean=mean/float(maxi(n,1))
		# Colour under the transparent border becomes the leaf's mean, so scaling
		# does not pull black fringes into the edge.
		for y in ch:
			for x in cw:
				var c:=crop.get_pixel(x,y)
				if c.a<.5:crop.set_pixel(x,y,Color(mean.r,mean.g,mean.b,c.a))
		result.append({"color":crop,"normal":normal.get_region(Rect2i(lo,Vector2i(cw,ch))),"w":cw,"h":ch,"ax":float(stem.x),"ay":float(stem.y),"mean":mean})
	return result

func spray(id: String, spec: Dictionary) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=int(spec.seed)
	var leaves:=leaves_of(spec.source)
	print(id," leaves found: ",leaves.size())
	var mean:=Color(0,0,0,0)
	for leaf in leaves:mean+=leaf.mean
	mean=mean/float(leaves.size())
	rgb=PackedByteArray();alp=PackedByteArray();nrm=PackedByteArray()
	rgb.resize(SIZE*SIZE*3);alp.resize(SIZE*SIZE);nrm.resize(SIZE*SIZE*3)
	for i in SIZE*SIZE:
		rgb[i*3]=int(mean.r*255.0*.8);rgb[i*3+1]=int(mean.g*255.0*.8);rgb[i*3+2]=int(mean.b*255.0*.8)
		nrm[i*3]=128;nrm[i*3+1]=128;nrm[i*3+2]=255
	var length:float=spec.length
	# Twigs: a curved main stem and side stems; leaves attach along them.
	var stems:Array=[]
	var main:Array=[]
	for k in 21:
		var t:=k/20.0
		main.append(Vector2(512.0+sin(t*3.1)*60.0+(t-.5)*70.0,1000.0-t*930.0))
	stems.append(main)
	for k in range(2,19,2):
		var from:Vector2=main[k];var side:=1.0 if k%4==0 else -1.0
		var branch:Array=[]
		for j in 8:
			var t:=j/7.0
			branch.append(from+Vector2(side*(t*230.0+t*t*60.0),-t*(120.0+rng.randf()*40.0)+t*t*50.0))
		stems.append(branch)
	var placed:Array=[]
	for stem in stems:
		for k in stem.size()-1:
			var a:Vector2=stem[k];var c:Vector2=stem[k+1]
			var steps:=int(a.distance_to(c)/2.5)
			for s in steps:stamp_disc(a.lerp(c,float(s)/steps),2.6-float(k)/stem.size()*1.2)
			var dir:=(c-a).normalized();var heading:=atan2(dir.x,-dir.y)
			for e in 2:
				var side:=1.0 if e==0 else -1.0
				placed.append([a.lerp(c,rng.randf()),heading+side*rng.randf_range(.6,1.3),rng.randf_range(.8,1.1)])
	# Fill leaves in a blob around the twigs so the card reads as foliage.
	for i in int(spec.fill):
		var angle:=rng.randf()*TAU;var radius:=pow(rng.randf(),.6)
		var p:=Vector2(512.0+cos(angle)*radius*380.0,470.0+sin(angle)*radius*440.0)
		placed.append([p,rng.randf_range(-PI,PI),rng.randf_range(.75,1.1)])
	# Painter's order: lower leaves first so the tip leaves overlap them.
	placed.sort_custom(func(a,b):return a[0].y>b[0].y)
	for item in placed:
		var leaf:Dictionary=leaves[rng.randi()%leaves.size()]
		var p:Vector2=item[0]
		var depth:=clampf(1.0-p.y/float(SIZE),0,1)
		var tone:=rng.randf_range(.78,1.12)*lerpf(.86,1.1,depth)
		var warm:=rng.randf_range(-.06,.06)
		stamp(leaf,p,float(item[1]),length*float(item[2]),Vector3(tone*(1.0+warm),tone,tone*(1.0-warm)))
	var color_png:=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGB8,rgb)
	var opacity_png:=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_L8,alp)
	var normal_png:=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGB8,nrm)
	var folder:=ProjectSettings.globalize_path(OUT)
	color_png.save_png(folder+id+"_color.png");opacity_png.save_png(folder+id+"_opacity.png");normal_png.save_png(folder+id+"_normal.png")

func stamp_disc(p: Vector2, radius: float) -> void:
	for y in range(int(p.y-radius),int(p.y+radius)+1):
		for x in range(int(p.x-radius),int(p.x+radius)+1):
			if x<0 or y<0 or x>=SIZE or y>=SIZE or Vector2(x,y).distance_to(p)>radius:continue
			var i:=y*SIZE+x
			rgb[i*3]=70;rgb[i*3+1]=52;rgb[i*3+2]=34;alp[i]=255
			nrm[i*3]=128;nrm[i*3+1]=128;nrm[i*3+2]=255

# Stamps one leaf with its stem tip at pos, rotated clockwise by angle (0 = tip up).
func stamp(leaf: Dictionary, pos: Vector2, angle: float, length: float, tone: Vector3) -> void:
	var scale:=length/float(leaf.h)
	var nw:=maxi(2,roundi(leaf.w*scale));var nh:=maxi(2,roundi(leaf.h*scale))
	var color:Image=leaf.color.duplicate();color.resize(nw,nh,Image.INTERPOLATE_LANCZOS)
	var normal:Image=leaf.normal.duplicate();normal.resize(nw,nh,Image.INTERPOLATE_BILINEAR)
	var cd:=color.get_data();var nd:=normal.get_data()
	var ax:=float(leaf.ax)*scale;var ay:=float(leaf.ay)*scale
	var c:=cos(angle);var s:=sin(angle)
	var r:=maxi(nw,nh)+2
	for py in range(maxi(0,int(pos.y)-r),mini(SIZE,int(pos.y)+r+1)):
		for px in range(maxi(0,int(pos.x)-r),mini(SIZE,int(pos.x)+r+1)):
			var dx:=float(px)-pos.x;var dy:=float(py)-pos.y
			var sx:=int(ax+dx*c+dy*s);var sy:=int(ay-dx*s+dy*c)
			if sx<0 or sy<0 or sx>=nw or sy>=nh:continue
			var si:=sy*nw+sx
			if cd[si*4+3]<115:continue
			var i:=py*SIZE+px
			rgb[i*3]=mini(255,int(cd[si*4]*tone.x));rgb[i*3+1]=mini(255,int(cd[si*4+1]*tone.y));rgb[i*3+2]=mini(255,int(cd[si*4+2]*tone.z))
			alp[i]=255
			# Tangent-space normal turned with the leaf (OpenGL convention, +Y up).
			var nx:=float(nd[si*3])/127.5-1.0;var ny:=float(nd[si*3+1])/127.5-1.0
			nrm[i*3]=clampi(int((nx*c+ny*s)*127.5+127.5),0,255)
			nrm[i*3+1]=clampi(int((-nx*s+ny*c)*127.5+127.5),0,255)
			nrm[i*3+2]=nd[si*3+2]

extends SceneTree

# Grass clump cards for Ridgeline and Village (MapNature.grass_*). The
# individually photographed blades of the CC0 ambientCG sheet Foliage001 are cut
# out, narrowed to meadow-grass width, bent, and stamped in dense fans of 40 to
# 60 overlapping blades, so one card reads as a soft tuft instead of nine lone
# spikes. The atlas is 2 x 2 clumps of 512 px; each clump is 0.5 m wide and
# stands on the bottom edge of its cell, centred. The sheet's own normal map
# travels with every blade. Output: colour, opacity (alpha test) and OpenGL
# normal maps in content/materials/grass_clump/. Run with:
#   python3 tools/dev.py ingest --domain maps --map village

const CELL := 512
const SIZE := 1024
const OUT := "res://content/materials/grass_clump/"
const SOURCE := "res://content/models/props/Foliage001/Foliage001_1K-JPG_"

var rgb: PackedByteArray
var alp: PackedByteArray
var nrm: PackedByteArray

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var blades:=blades_of(SOURCE)
	print("grass blades found: ",blades.size())
	var mean:=Color(0,0,0,0)
	for blade in blades:mean+=blade.mean
	mean=mean/float(blades.size())
	rgb=PackedByteArray();alp=PackedByteArray();nrm=PackedByteArray()
	rgb.resize(SIZE*SIZE*3);alp.resize(SIZE*SIZE);nrm.resize(SIZE*SIZE*3)
	# Transparent texels carry the mean blade colour so mip levels never pull in black fringes.
	for i in SIZE*SIZE:
		rgb[i*3]=int(mean.r*255.0*.7);rgb[i*3+1]=int(mean.g*255.0*.7);rgb[i*3+2]=int(mean.b*255.0*.7)
		nrm[i*3]=128;nrm[i*3+1]=128;nrm[i*3+2]=255
	for variant in 4:clump(blades,variant)
	var folder:=ProjectSettings.globalize_path(OUT)
	Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGB8,rgb).save_png(folder+"color.png")
	Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_L8,alp).save_png(folder+"opacity.png")
	Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGB8,nrm).save_png(folder+"normal.png")
	print("GRASS CLUMPS PASS")
	quit()

# One entry per blade on the sheet: RGBA crop, normal crop, root point (lowest pixel).
@warning_ignore("integer_division")
func blades_of(base: String) -> Array:
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
				for step in [-1,1,-w,w]:
					var j:int=i+step
					if j<0 or j>=w*h or (step==-1 and x==0) or (step==1 and x==w-1):continue
					if label[j]==0 and alpha[j]>=128:label[j]=next;stack.append(j)
			if count>2500:found.append({"id":next,"lo":lo,"hi":hi})
			next+=1
	var result:Array=[]
	for item in found:
		var lo:Vector2i=item.lo;var hi:Vector2i=item.hi
		var cw:=hi.x-lo.x+1;var ch:=hi.y-lo.y+1
		var crop:=Image.create(cw,ch,false,Image.FORMAT_RGBA8)
		var mean:=Color(0,0,0,0);var n:=0
		var root:=Vector2i(0,0)
		for y in ch:
			for x in cw:
				var i:=(y+lo.y)*w+x+lo.x
				var a:=float(alpha[i])/255.0
				if label[i]!=0 and label[i]!=item.id:a=0.0
				var c:=color.get_pixel(x+lo.x,y+lo.y)
				if a>.5:
					mean+=c;n+=1
					if y>root.y:root=Vector2i(x,y)
				crop.set_pixel(x,y,Color(c.r,c.g,c.b,a))
		mean=mean/float(maxi(n,1))
		for y in ch:
			for x in cw:
				var c:=crop.get_pixel(x,y)
				if c.a<.5:crop.set_pixel(x,y,Color(mean.r,mean.g,mean.b,c.a))
		result.append({"color":crop,"normal":normal.get_region(Rect2i(lo,Vector2i(cw,ch))),"w":cw,"h":ch,"ax":float(root.x),"ay":float(root.y),"mean":mean})
	return result

# A fan of blades rooted along the cell's bottom edge. Outer blades lean out,
# the centre stands tall, every blade bends a little toward its tip.
func clump(blades: Array, variant: int) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=1301+variant*97
	var origin:=Vector2((variant%2)*CELL+CELL*.5,(variant/2)*CELL+CELL-6.0)
	var count:=46+variant*6
	var placed:Array=[]
	for i in count:
		var offset:=rng.randfn()*.5
		offset=clampf(offset,-1.0,1.0)
		var tall:=lerpf(250.0,455.0,rng.randf())*lerpf(1.0,.62,absf(offset))
		var lean:=offset*.32+rng.randf_range(-.12,.12)
		placed.append({"x":offset*84.0+rng.randf_range(-8,8),"lean":lean,"tall":tall,"bend":rng.randf_range(-1.0,1.0)*(40.0+tall*.12)*(1.0 if rng.randf()<.7 else 1.8)})
	# A few short blades low in the middle fill the heart of the tuft.
	for i in 14:placed.append({"x":rng.randf_range(-40,40),"lean":rng.randf_range(-.4,.4),"tall":rng.randf_range(110.0,200.0),"bend":rng.randf_range(-30,30)})
	placed.sort_custom(func(a,b):return a.tall<b.tall)
	for item in placed:
		var blade:Dictionary=blades[rng.randi()%blades.size()]
		var tone:=rng.randf_range(.78,1.14)
		var warm:=rng.randf_range(-.07,.09)
		# One blade in nine is straw-coloured, like real rough grass.
		var dry:=.0 if rng.randf()>.11 else rng.randf_range(.35,.7)
		var shade:=Vector3(tone*(1.0+warm+dry*.55),tone*(1.0-dry*.18),tone*(1.0-warm-dry*.65))
		stamp(blade,origin,origin+Vector2(item.x,0),float(item.lean),float(item.tall),float(item.bend),shade,origin.x-CELL*.5,origin.y-CELL+6.0)

# Stamps one blade rooted at root, tilted by lean (radians, + right), length tall
# px, narrowed to .55 of its photographed width and curved by bend px at the tip.
func stamp(blade: Dictionary, _origin: Vector2, root: Vector2, lean: float, tall: float, bend: float, shade: Vector3, cell_x: float, cell_y: float) -> void:
	var sy:=tall/float(blade.ay+1.0)
	var sx:=sy*.55
	var cd:=(blade.color as Image).get_data();var nd:=(blade.normal as Image).get_data()
	var bw:int=blade.w;var bh:int=blade.h
	var c:=cos(lean);var s:=sin(lean)
	var reach:=int(tall*1.25)+24
	for py in range(maxi(int(cell_y),int(root.y)-reach),mini(int(cell_y)+CELL,int(root.y)+3)):
		for px in range(maxi(int(cell_x),int(root.x)-reach),mini(int(cell_x)+CELL,int(root.x)+reach)):
			# Pixel relative to the root, un-rotated into blade space (v up along the blade).
			var dx:=float(px)-root.x;var dy:=root.y-float(py)
			var u:=dx*c-dy*s;var v:=dx*s+dy*c
			if v<0.0:continue
			var t:=v/tall
			u-=bend*t*t
			var src_x:=int(float(blade.ax)+u/sx);var src_y:=int(float(blade.ay)-v/sy)
			if src_x<0 or src_y<0 or src_x>=bw or src_y>=bh:continue
			var si:=src_y*bw+src_x
			if cd[si*4+3]<115:continue
			var i:=py*SIZE+px
			# Darker toward the root (ambient occlusion in the sward).
			var ao:=lerpf(.42,1.0,smoothstep(0.0,.45,t))
			rgb[i*3]=mini(255,int(cd[si*4]*shade.x*ao));rgb[i*3+1]=mini(255,int(cd[si*4+1]*shade.y*ao));rgb[i*3+2]=mini(255,int(cd[si*4+2]*shade.z*ao))
			alp[i]=255
			var nx:=float(nd[si*3])/127.5-1.0;var ny:=float(nd[si*3+1])/127.5-1.0
			nrm[i*3]=clampi(int((nx*c+ny*s)*127.5+127.5),0,255)
			nrm[i*3+1]=clampi(int((-nx*s+ny*c)*127.5+127.5),0,255)
			nrm[i*3+2]=nd[si*3+2]

class_name MapMeshes
extends RefCounted

# Mesh generation for map architecture. Every mesh carries metric UVs (1 unit =
# 1 m, so MapSurfaces scans tile at true scale), tangents for normal maps and a
# vertex-colour mask read by surface.gdshader: R = cleanliness (grime gathers at
# the foot of walls and under top edges), G = 0 on bevelled edges (edge wear).
# Lightmap UV2 is added by the caller once the final mesh is assembled.

static func _vertex(st:SurfaceTool, p:Vector3, n:Vector3, face:float, h:Vector3, grime_height:float) -> void:
	var a:=n.abs()
	var uv:Vector2
	if a.y>=a.x and a.y>=a.z:uv=Vector2(p.x,p.z)
	elif a.x>=a.z:uv=Vector2(p.z*(1.0 if n.x>=0 else -1.0),h.y-p.y)
	else:uv=Vector2(-p.x*(1.0 if n.z>=0 else -1.0),h.y-p.y)
	var clean:=1.0
	if n.y>.6:clean=.82
	elif n.y>-.6:
		if grime_height>0:clean=lerpf(.08,1.0,smoothstep(0.0,grime_height,p.y+h.y))
		if h.y>1.2:clean*=1.0-.3*(1.0-smoothstep(0.0,.45,h.y-p.y))
	st.set_color(Color(clean,face,1.0))
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)

# Adds a planar polygon (3 or 4 corners) facing n, fixing the winding so the
# front face (clockwise in Godot) points along n.
static func _polygon(st:SurfaceTool, corners:Array, n:Vector3, face:float, h:Vector3, grime_height:float) -> void:
	var triangles:=[[0,1,2]] if corners.size()==3 else [[0,1,2],[0,2,3]]
	for tri in triangles:
		var a:Vector3=corners[tri[0]];var b:Vector3=corners[tri[1]];var c:Vector3=corners[tri[2]]
		if (b-a).cross(c-a).dot(n)>0:var swap:=b;b=c;c=swap
		for p in [a,b,c]:_vertex(st,p,n,face,h,grime_height)

# A box with 45-degree chamfered edges. grime_height is how far dirt climbs the
# sides from the base (0 for things that do not touch the ground); split_top puts
# the upper face in a second surface so walkable tops can take another material.
static func block(size:Vector3, bevel:=.03, grime_height:=.9, split_top:=false) -> ArrayMesh:
	var h:=size*.5
	var b:=clampf(bevel,0.0,minf(size.x,minf(size.y,size.z))*.24)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lid:=st
	if split_top:lid=SurfaceTool.new();lid.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Horizontal loop cuts give the grime gradient vertices to blend across.
	var ys:Array[float]=[-h.y+b]
	for cut in [.12,.4,grime_height,size.y-.55]:
		var y:float=-h.y+cut
		if y>ys.back()+.05 and y<h.y-b-.05:ys.append(y)
	ys.append(h.y-b)
	for i in ys.size()-1:
		var y0:=ys[i];var y1:=ys[i+1]
		for s in [-1.0,1.0]:
			_polygon(st,[Vector3(s*h.x,y0,-h.z+b),Vector3(s*h.x,y0,h.z-b),Vector3(s*h.x,y1,h.z-b),Vector3(s*h.x,y1,-h.z+b)],Vector3(s,0,0),1.0,h,grime_height)
			_polygon(st,[Vector3(-h.x+b,y0,s*h.z),Vector3(h.x-b,y0,s*h.z),Vector3(h.x-b,y1,s*h.z),Vector3(-h.x+b,y1,s*h.z)],Vector3(0,0,s),1.0,h,grime_height)
		if b>0:
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					_polygon(st,[Vector3(sx*h.x,y0,sz*(h.z-b)),Vector3(sx*(h.x-b),y0,sz*h.z),Vector3(sx*(h.x-b),y1,sz*h.z),Vector3(sx*h.x,y1,sz*(h.z-b))],Vector3(sx,0,sz).normalized(),0.0,h,grime_height)
	for sy in [-1.0,1.0]:
		var target:=lid if sy>0 else st
		_polygon(target,[Vector3(-h.x+b,sy*h.y,-h.z+b),Vector3(h.x-b,sy*h.y,-h.z+b),Vector3(h.x-b,sy*h.y,h.z-b),Vector3(-h.x+b,sy*h.y,h.z-b)],Vector3(0,sy,0),1.0,h,grime_height)
		if b<=0:continue
		for s in [-1.0,1.0]:
			_polygon(st,[Vector3(-h.x+b,sy*h.y,s*(h.z-b)),Vector3(h.x-b,sy*h.y,s*(h.z-b)),Vector3(h.x-b,sy*(h.y-b),s*h.z),Vector3(-h.x+b,sy*(h.y-b),s*h.z)],Vector3(0,sy,s).normalized(),0.0,h,grime_height)
			_polygon(st,[Vector3(s*(h.x-b),sy*h.y,-h.z+b),Vector3(s*(h.x-b),sy*h.y,h.z-b),Vector3(s*h.x,sy*(h.y-b),h.z-b),Vector3(s*h.x,sy*(h.y-b),-h.z+b)],Vector3(s,sy,0).normalized(),0.0,h,grime_height)
			for s2 in [-1.0,1.0]:
				_polygon(st,[Vector3(s*h.x,sy*(h.y-b),s2*(h.z-b)),Vector3(s*(h.x-b),sy*h.y,s2*(h.z-b)),Vector3(s*(h.x-b),sy*(h.y-b),s2*h.z)],Vector3(s,sy,s2).normalized(),0.0,h,grime_height)
	var mesh:=ArrayMesh.new()
	for tool in ([st,lid] if split_top else [st]):
		tool.index();tool.generate_tangents();tool.commit(mesh)
	return mesh

# A wall slab (long axis X, thickness Z) pierced by rectangular openings.
# openings are Rect2(x from the left end, y from the base, width, height); each
# gets full-depth reveals (sill, head, jambs) so glazing can sit inside it.
static func wall(size:Vector3, openings:Array, grime_height:=1.0) -> ArrayMesh:
	var h:=size*.5
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs:Array[float]=[-h.x,h.x];var ys:Array[float]=[-h.y,h.y]
	for cut in [.12,.4,grime_height,size.y-.55]:
		if cut>0 and cut<size.y:ys.append(-h.y+cut)
	var holes:Array[Rect2]=[]
	for rect in openings:
		var hole:=Rect2(rect.position.x-h.x,rect.position.y-h.y,rect.size.x,rect.size.y)
		holes.append(hole)
		xs.append_array([hole.position.x,hole.end.x]);ys.append_array([hole.position.y,hole.end.y])
	xs.sort();ys.sort()
	for i in xs.size()-1:
		for j in ys.size()-1:
			var x0:=xs[i];var x1:=xs[i+1];var y0:=ys[j];var y1:=ys[j+1]
			if x1-x0<.001 or y1-y0<.001:continue
			var mid:=Vector2((x0+x1)*.5,(y0+y1)*.5)
			if holes.any(func(hole:Rect2):return hole.has_point(mid)):continue
			for s in [-1.0,1.0]:
				_polygon(st,[Vector3(x0,y0,s*h.z),Vector3(x1,y0,s*h.z),Vector3(x1,y1,s*h.z),Vector3(x0,y1,s*h.z)],Vector3(0,0,s),1.0,h,grime_height)
	for j in ys.size()-1:
		if ys[j+1]-ys[j]<.001:continue
		for s in [-1.0,1.0]:
			var mid:=Vector2(s*h.x,(ys[j]+ys[j+1])*.5)
			if holes.any(func(hole:Rect2):return mid.x>=hole.position.x and mid.x<=hole.end.x and mid.y>=hole.position.y and mid.y<=hole.end.y):continue
			_polygon(st,[Vector3(s*h.x,ys[j],-h.z),Vector3(s*h.x,ys[j],h.z),Vector3(s*h.x,ys[j+1],h.z),Vector3(s*h.x,ys[j+1],-h.z)],Vector3(s,0,0),1.0,h,grime_height)
	# Boundary caps follow the same openings as the wall faces. A floor-level
	# doorway has no threshold polygon competing with the ground below it.
	for i in xs.size()-1:
		if xs[i+1]-xs[i]<.001:continue
		for s in [-1.0,1.0]:
			var mid:=Vector2((xs[i]+xs[i+1])*.5,s*h.y)
			if holes.any(func(hole:Rect2):return mid.x>=hole.position.x and mid.x<=hole.end.x and mid.y>=hole.position.y and mid.y<=hole.end.y):continue
			_polygon(st,[Vector3(xs[i],s*h.y,-h.z),Vector3(xs[i+1],s*h.y,-h.z),Vector3(xs[i+1],s*h.y,h.z),Vector3(xs[i],s*h.y,h.z)],Vector3(0,s,0),1.0,h,grime_height)
	for hole in holes:
		var a:=hole.position;var b:=hole.end
		if a.y>-h.y+.001:_polygon(st,[Vector3(a.x,a.y,-h.z),Vector3(b.x,a.y,-h.z),Vector3(b.x,a.y,h.z),Vector3(a.x,a.y,h.z)],Vector3.UP,0.0,h,grime_height)
		if b.y<h.y-.001:_polygon(st,[Vector3(a.x,b.y,-h.z),Vector3(b.x,b.y,-h.z),Vector3(b.x,b.y,h.z),Vector3(a.x,b.y,h.z)],Vector3.DOWN,0.0,h,grime_height)
		if a.x>-h.x+.001:_polygon(st,[Vector3(a.x,a.y,-h.z),Vector3(a.x,b.y,-h.z),Vector3(a.x,b.y,h.z),Vector3(a.x,a.y,h.z)],Vector3.RIGHT,0.0,h,grime_height)
		if b.x<h.x-.001:_polygon(st,[Vector3(b.x,a.y,-h.z),Vector3(b.x,b.y,-h.z),Vector3(b.x,b.y,h.z),Vector3(b.x,a.y,h.z)],Vector3.LEFT,0.0,h,grime_height)
	st.index();st.generate_tangents()
	return st.commit()

# Appends a single-sided quad (front along normal) to st; used to batch
# glazing for a whole building into one mesh.
static func add_quad(st:SurfaceTool, center:Vector3, right:Vector3, up:Vector3, size:Vector2) -> void:
	var normal:=right.cross(up).normalized()
	var r:=right.normalized()*size.x*.5;var u:=up.normalized()*size.y*.5
	_polygon(st,[center-r-u,center+r-u,center+r+u,center-r+u],normal,1.0,Vector3(size.x,size.y,0)*.5,0.0)

# A capped cylinder along Y with metric UVs (u runs around the circumference).
static func cylinder(radius:float, height:float, segments:=20, grime_height:=0.0) -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h:=Vector3(radius,height*.5,radius)
	var circumference:=TAU*radius
	for i in segments:
		var a0:=TAU*i/segments;var a1:=TAU*(i+1)/segments
		var n0:=Vector3(cos(a0),0,sin(a0));var n1:=Vector3(cos(a1),0,sin(a1))
		var quad:=[[n0,-h.y,circumference*i/segments],[n1,-h.y,circumference*(i+1)/segments],[n1,h.y,circumference*(i+1)/segments],[n0,h.y,circumference*i/segments]]
		for tri in [[0,1,2],[0,2,3]]:
			for k in tri:
				var n:Vector3=quad[k][0];var y:float=quad[k][1]
				var clean:=lerpf(.1,1.0,smoothstep(0.0,grime_height,y+h.y)) if grime_height>0 else 1.0
				st.set_color(Color(clean,1,1));st.set_normal(n);st.set_uv(Vector2(quad[k][2],h.y-y));st.add_vertex(n*radius+Vector3(0,y,0))
		for cap in [-1.0,1.0]:
			var tri:=[Vector3(0,cap*h.y,0),n0*radius+Vector3(0,cap*h.y,0),n1*radius+Vector3(0,cap*h.y,0)]
			if cap<0:tri=[tri[0],tri[2],tri[1]]
			for p in tri:
				st.set_color(Color(1,1,1));st.set_normal(Vector3(0,cap,0));st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	st.index();st.generate_tangents()
	return st.commit()

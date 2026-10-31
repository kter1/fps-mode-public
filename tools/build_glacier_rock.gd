extends SceneTree
# CC0 Poly Haven boulder_01, simplified in Blender by build_glacier_rock.py.
func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.artifacts/glacier_overhaul/moraine_scan.json"))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Blender triangles are counter-clockwise; Godot's front faces are clockwise.
	for triangle: int in rows.size() / 3:
		for corner: int in [0, 2, 1]:
			var row: Array = rows[triangle * 3 + corner]
			st.set_normal(Vector3(row[3], row[4], row[5]))
			st.set_uv(Vector2(row[6], row[7]))
			st.add_vertex(Vector3(row[0], row[1], row[2]))
	st.index()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	mesh.lightmap_unwrap(Transform3D.IDENTITY, 0.35)
	DirAccess.make_dir_recursive_absolute("res://content/models/glacier")
	ResourceSaver.save(mesh, "res://content/models/glacier/moraine_rock.res")
	print("GLACIER ROCK PASS: ", rows.size() / 3, " triangles")
	quit()

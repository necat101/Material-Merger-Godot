# MaterialCombiner.gd by necat101 (netcat7 discord)
# Merges descendant MeshInstance3D nodes, atlassing Albedo textures AND Albedo colors
# from BaseMaterial3D/StandardMaterial3D.
# Attempts to preserve skinning data. Manual Skeleton3D assignment now supported.
# Distortion may occur if source mesh arrays do not directly provide bone/weight data
# or if skinning is complex.
#
# Attach to an empty MeshInstance3D (recommended for clarity) or directly to the target MeshInstance3D.
# If attaching to a parent, make the character model (containing the target mesh) a child of this node.
#
# *** IMPORTANT FOR SKINNED MESHES (Characters, etc.) ***
# This script attempts to copy vertex bone/weight data. However, if the source mesh
# (as returned by surface_get_arrays()) does not contain explicit ARRAY_BONES and
# ARRAY_WEIGHTS, or if the skinning is complex, the resulting merged mesh may be
# distorted or lose its rigging if not properly linked to a Skeleton3D.
# Use the "Manual Skeleton Node Path" property for explicit linking.

@tool
extends MeshInstance3D
class_name TextureAtlasCombinerStd

@export_group("Target Mesh")
@export var target_mesh_name: String = "body"

@export_group("Atlas Settings")
@export var atlas_target_size: int = 2048
@export var color_block_size: int = 4 # Size of the square image created for solid colors
@export var regenerate_normals_and_tangents: bool = true 
@export var atlas_material_cull_mode: BaseMaterial3D.CullMode = BaseMaterial3D.CULL_BACK # New export for Cull Mode

var result_mesh: ArrayMesh = null # Holds the combined ArrayMesh resource
var generated_material: StandardMaterial3D = null # Holds the generated atlas material resource
var generated_texture: ImageTexture = null # Holds the generated atlas texture resource

@export_group("Collision Settings")
@export var collision_parent_path: NodePath = NodePath("") # Optional: Node to parent copied collision shapes under
var collision_parent: Node = null

@export_group("Skeleton Linking")
@export var manual_skeleton_node_path: NodePath = NodePath("") # Optional: Explicit path to Skeleton3D

@export_group("Actions")
@export var btn_combine_and_atlas: bool = false: set = combine_and_atlas
@export var btn_clean_result: bool = false: set = clean_result

@export_group("Child Handling")
@export var toggle_children_visibility: bool = true: set = set_toggle_children_visibility
@export var delete_child_meshes_on_play: bool = false: set = set_delete_child_meshes_on_play

# Internal class to hold texture/color data and its position in the atlas
class TextureData:
	var image: Image
	var original_key # Can be Texture2D resource or Color, used for uniqueness
	var atlas_rect: Rect2i # Position and size in the final atlas image
	func _init(p_image: Image, p_key):
		image = p_image
		original_key = p_key
		atlas_rect = Rect2i()

# Helper to get ArrayMesh, especially from ImporterMesh (robust against parser issues)
func _get_actual_array_mesh(mesh_resource: Mesh) -> ArrayMesh:
	if mesh_resource == null:
		print(" _get_actual_array_mesh: input mesh_resource is null.")
		return null

	if mesh_resource is ArrayMesh:
		return mesh_resource

	if mesh_resource.has_method("get_mesh"):
		var path_info_str = ""
		if mesh_resource.has_method("get_path") and mesh_resource.get_path() != "":
			path_info_str = mesh_resource.get_path()
		elif mesh_resource.resource_path and not mesh_resource.resource_path.is_empty():
			path_info_str = mesh_resource.resource_path
		else:
			path_info_str = "N/A (or not saved)"
		var generated_mesh_variant = mesh_resource.call("get_mesh")
		if generated_mesh_variant == null:
			print(" mesh_resource.call(\"get_mesh\") returned null.")
			return null
		if not generated_mesh_variant is Mesh:
			print(" mesh_resource.call(\"get_mesh\") did not return a Mesh. Type: %s" % typeof(generated_mesh_variant))
			return null
		var generated_mesh: Mesh = generated_mesh_variant as Mesh
		if generated_mesh is ArrayMesh:
			return generated_mesh as ArrayMesh
		else:
			# Recursive call to handle nested non-ArrayMesh types
			return _get_actual_array_mesh(generated_mesh)
	else:
		print(" Mesh resource is not ArrayMesh and does not have get_mesh() method. Type: %s." % typeof(mesh_resource))
		return null


func _enter_tree():
	if Engine.is_editor_hint() and collision_parent_path != NodePath(""):
		collision_parent = get_node_or_null(collision_parent_path)
		if not collision_parent:
			push_warning("Warning: Collision parent path set to '%s' but node not found." % str(collision_parent_path))


func combine_and_atlas(value: bool):
	print("DEBUG: combine_and_atlas setter CALLED. Value: %s, Editor Hint: %s" % [str(value), str(Engine.is_editor_hint())])

	if not Engine.is_editor_hint():
		print("DEBUG: combine_and_atlas RETURNING because not Engine.is_editor_hint()")
		return

	if value == true: 
		print("DEBUG: combine_and_atlas value is TRUE. Proceeding.")
		set_block_signals(true)
		btn_combine_and_atlas = false 
		set_block_signals(false)
		
		print("DEBUG: target_mesh_name is '%s'" % target_mesh_name) 
		if target_mesh_name.is_empty():
			printerr("Error: 'Target Mesh Name' cannot be empty. Please specify the name of the MeshInstance3D to process.")
			print("DEBUG: combine_and_atlas RETURNING because target_mesh_name is empty.")
			return

		print("DEBUG: All initial checks passed. Starting main logic...") 
		print("\n---- Starting Combine & Atlas for target mesh '%s' (Colors & Textures) ----" % target_mesh_name)

		var script_res = self.get_script()
		if not script_res or not script_res is Script:
			printerr("Error: Cannot get script resource. Type: %s" % typeof(script_res)); return
		var script_dir = script_res.resource_path.get_base_dir()
		var base_filename_prefix = target_mesh_name if not target_mesh_name.is_empty() else self.name
		if base_filename_prefix.is_empty() or base_filename_prefix == "MeshInstance3D": 
			base_filename_prefix = "AtlasedNode_%s" % str(self.get_instance_id())

		var auto_atlas_texture_path = script_dir.path_join(base_filename_prefix + "_atlas.png")
		var auto_atlas_material_path = script_dir.path_join(base_filename_prefix + "_atlas_mat.tres")
		var auto_atlas_debug_image_path = script_dir.path_join(base_filename_prefix + "_atlas_debug_direct.png")
		print("Generated resources will be saved to:\n  Texture: %s\n  Material: %s\n  Debug Image: %s" % [auto_atlas_texture_path, auto_atlas_material_path, auto_atlas_debug_image_path])

		var target_node = find_target_mesh_recursive(self, target_mesh_name)
		
		if not target_node and get_parent():
			print("Target mesh '%s' not found as a descendant of this node ('%s'). Attempting to find from parent node ('%s')." % [target_mesh_name, self.name, get_parent().name])
			target_node = find_target_mesh_recursive(get_parent(), target_mesh_name)
			
		if not target_node:
			var search_scope_message = "as a descendant of this node ('%s')" % self.name
			if get_parent():
				search_scope_message += " or its parent ('%s')" % get_parent().name
			else:
				search_scope_message += " (this node has no parent to search from)"
			printerr("---- Target MeshInstance3D named '%s' not found %s. Stopping. ----" % [target_mesh_name, search_scope_message])
			set_toggle_children_visibility(toggle_children_visibility); return

		var source_array_mesh_for_processing: ArrayMesh = null
		if target_node == self: 
			if self.mesh:
				source_array_mesh_for_processing = _get_actual_array_mesh(self.mesh)
				if source_array_mesh_for_processing:
					print(" Script is on target node ('%s'). Using its direct ArrayMesh for processing. Mesh: %s" % [self.name, str(source_array_mesh_for_processing)])
				else:
					printerr("[Error] Script is on target ('%s'), but failed to get/resolve its ArrayMesh for processing." % self.name)
					set_toggle_children_visibility(true); return
			else:
				printerr("[Error] Script is on target ('%s'), but its mesh property is null." % self.name)
				set_toggle_children_visibility(true); return

		print("---- Phase 1: Collecting textures/colors and surface data for '%s' ----" % target_mesh_name)
		var item_map: Dictionary = {}
		var surfaces_to_process: Array = []
		
		var mesh_for_material_collection: ArrayMesh
		if target_node == self:
			mesh_for_material_collection = source_array_mesh_for_processing 
			print("[MaterialCollect] Using direct ArrayMesh resource for materials as target is self. Mesh: %s" % str(mesh_for_material_collection))
		else: 
			if not target_node.mesh: 
				printerr("Error: Target child node '%s' has no mesh assigned. Stopping." % target_node.name)
				set_toggle_children_visibility(true); return
			mesh_for_material_collection = _get_actual_array_mesh(target_node.mesh)
			print("[MaterialCollect] Using target_node's ('%s') resolved ArrayMesh for materials. Mesh: %s" % [target_node.name, str(mesh_for_material_collection)])

		if not mesh_for_material_collection:
			printerr("Error: Actual ArrayMesh for material collection (from target '%s') is null. Stopping." % target_node.name)
			set_toggle_children_visibility(true); return
			
		var collection_success = collect_data_for_target(target_node, mesh_for_material_collection, item_map, surfaces_to_process)

		if not collection_success or item_map.is_empty():
			printerr("---- No processable Albedo textures or colors found on '%s'. Stopping. ----" % target_mesh_name)
			print("Suggestion: Check if materials are assigned, if albedo textures/colors are set, or if GLB materials need to be extracted (Advanced Import Settings).")
			set_toggle_children_visibility(true); return

		print("Found %d unique Albedo items (textures/colors) from '%s'." % [item_map.size(), target_mesh_name])
		if item_map.size() == 0: print("No items collected. Aborting."); set_toggle_children_visibility(true); return

		print("---- Phase 2: Packing items into atlas layout ----")
		var unique_item_data: Array = item_map.values()
		var initial_atlas_dimensions = Vector2i(atlas_target_size, atlas_target_size)
		var packer_result: Dictionary = basic_grid_packer(unique_item_data, initial_atlas_dimensions)
		if packer_result.is_empty() or not packer_result.has("rects") or not packer_result.has("final_size"):
			printerr("Error: Failed to pack items or packer returned invalid data."); set_toggle_children_visibility(true); return
		var packed_rects_list: Array = packer_result.rects
		var final_calculated_atlas_size: Vector2i = packer_result.final_size
		if packed_rects_list.size() != unique_item_data.size():
			printerr("Error: Packer returned incorrect number of rects."); set_toggle_children_visibility(true); return
		for i in range(unique_item_data.size()): unique_item_data[i].atlas_rect = packed_rects_list[i]
		print("Final Atlas Size (from packer): %dx%d" % [final_calculated_atlas_size.x, final_calculated_atlas_size.y])

		print("---- Phase 3: Creating atlas image ----")
		var atlas_image := Image.create(final_calculated_atlas_size.x, final_calculated_atlas_size.y, false, Image.FORMAT_RGBA8)
		if not atlas_image: 
			printerr("Error: Could not create atlas image."); 
			set_toggle_children_visibility(true); 
			return

		for data_item_idx in range(unique_item_data.size()): 
			var data_item: TextureData = unique_item_data[data_item_idx]
			
			if not data_item or not data_item.image: 
				printerr("Error: Invalid TextureData or null image at index %d during atlas image creation for original key: %s." % [data_item_idx, str(data_item.original_key if data_item else "N/A")])
				continue

			if data_item.image.is_empty():
				printerr("Error: TextureData image is empty at index %d for original key: %s. Size: %s, Format: %s. Skipping blit." % [data_item_idx, str(data_item.original_key), str(data_item.image.get_size()), data_item.image.get_format()])
				continue
			
			var image_to_blit := data_item.image.duplicate() 

			print("DEBUG: [AtlasBlit Index %d] Preparing to blit image (size %dx%d, format: %s, original key: %s) to atlas at %s" % [data_item_idx, image_to_blit.get_width(), image_to_blit.get_height(), image_to_blit.get_format(), str(data_item.original_key), str(data_item.atlas_rect.position)])

			if image_to_blit.is_compressed():
				print("DEBUG: [AtlasBlit Index %d] Image for key %s is compressed (format: %s). Decompressing." % [data_item_idx, str(data_item.original_key), image_to_blit.get_format()])
				var decompress_err = image_to_blit.decompress() 
				if decompress_err != OK:
					printerr("ERROR: [AtlasBlit Index %d] Failed to decompress image for key %s. Error: %s. Skipping blit." % [data_item_idx, str(data_item.original_key), error_string(decompress_err)])
					continue
				print("DEBUG: [AtlasBlit Index %d] Decompressed. New format: %s" % [data_item_idx, image_to_blit.get_format()])

			if image_to_blit.get_format() != atlas_image.get_format():
				print("DEBUG: [AtlasBlit Index %d] Converting image for key %s from format %s to %s" % [data_item_idx, str(data_item.original_key), image_to_blit.get_format(), atlas_image.get_format()])
				image_to_blit.convert(atlas_image.get_format()) 
				print("DEBUG: [AtlasBlit Index %d] Conversion attempted. New format after convert: %s" % [data_item_idx, image_to_blit.get_format()])

			atlas_image.blit_rect(image_to_blit, Rect2i(Vector2i.ZERO, image_to_blit.get_size()), data_item.atlas_rect.position)
			print("DEBUG: [AtlasBlit Index %d] Successfully attempted blit for image with key %s" % [data_item_idx, str(data_item.original_key)])
		
		print("Atlas image creation loop finished.")

		print("DEBUG: Atlas Image dimensions: %dx%d, Format: %s" % [atlas_image.get_width(), atlas_image.get_height(), atlas_image.get_format()]) 
		if atlas_image.get_width() > 0 and atlas_image.get_height() > 0:
			print("DEBUG: Atlas Image pixel at (0,0): %s" % str(atlas_image.get_pixel(0,0)))
			if atlas_image.get_width() > color_block_size and atlas_image.get_height() > 0: 
				print("DEBUG: Atlas Image pixel at (%d,0): %s" % [color_block_size, str(atlas_image.get_pixel(color_block_size,0))])
		
		var save_debug_img_err = atlas_image.save_png(auto_atlas_debug_image_path)
		if save_debug_img_err == OK: 
			print("DEBUG: Saved raw atlas Image to: %s. PLEASE INSPECT THIS FILE." % auto_atlas_debug_image_path)
		else: 
			printerr("DEBUG: Error saving raw atlas Image: %s" % error_string(save_debug_img_err))

		print("---- Phase 4: Creating atlas texture resource ----")
		var current_run_texture = ImageTexture.create_from_image(atlas_image) 
		if not current_run_texture: 
			printerr("Error: Could not create ImageTexture from atlas_image."); 
			set_toggle_children_visibility(true); return
		var save_tex_err = ResourceSaver.save(current_run_texture, auto_atlas_texture_path)
		if save_tex_err == OK: 
			print("Saved Atlas Texture to: ", auto_atlas_texture_path)
		else: 
			printerr("Error saving Atlas Texture: %s" % error_string(save_tex_err))

		print("---- Phase 5: Creating atlas material (StandardMaterial3D Output) ----")
		var current_run_material = StandardMaterial3D.new() 
		
		current_run_material.albedo_color = Color.WHITE 
		print("DEBUG: Set current_run_material.albedo_color to WHITE.")
		
		current_run_material.albedo_texture = current_run_texture 
		current_run_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		
		current_run_material.cull_mode = atlas_material_cull_mode # Use the exported variable
		print("DEBUG: Set material cull_mode to: %s (0=BACK, 1=FRONT, 2=DISABLED)" % atlas_material_cull_mode)


		var save_mat_err = ResourceSaver.save(current_run_material, auto_atlas_material_path)
		if save_mat_err == OK: 
			print("Saved Atlas Material to: ", auto_atlas_material_path)
		else: 
			printerr("Error saving Atlas Material: %s" % error_string(save_mat_err))

		print("---- Phase 6: Processing geometry and remapping UVs for '%s' ----" % target_mesh_name)
		var final_surface_tool = SurfaceTool.new()
		final_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var total_verts = 0
		
		for surface_info_idx in range(surfaces_to_process.size()):
			var surface_info = surfaces_to_process[surface_info_idx]
			var mesh_node_instance: MeshInstance3D = surface_info.mesh_node 
			var surface_idx: int = surface_info.surface_idx
			var relative_transform: Transform3D = surface_info.transform
			var data_item: TextureData = surface_info.item_data
			if not mesh_node_instance or not data_item or not data_item.image: printerr("Error: Invalid surface_info during geometry processing."); continue
			
			var array_mesh_for_geometry: ArrayMesh = mesh_for_material_collection 
			
			if not array_mesh_for_geometry:
				printerr("Error: Actual ArrayMesh for reading geometry arrays is null for %s, surf %d." % [mesh_node_instance.name, surface_idx]); continue
			var mesh_path_for_log = array_mesh_for_geometry.resource_path if array_mesh_for_geometry.resource_path and not array_mesh_for_geometry.resource_path.is_empty() else "RuntimeMesh (ID: %s)" % str(array_mesh_for_geometry)
			var surface_format = array_mesh_for_geometry.surface_get_format(surface_idx)
			print(" Surface %d format flags: %d (Mesh.ARRAY_FORMAT_VERTEX = %d, Mesh.ARRAY_FORMAT_TEX_UV = %d)" % [surface_idx, surface_format, Mesh.ARRAY_FORMAT_VERTEX, Mesh.ARRAY_FORMAT_TEX_UV])
			if (surface_format & Mesh.ARRAY_FORMAT_VERTEX) == 0:
				printerr("Error: Surface %d for mesh %s is missing ARRAY_FORMAT_VERTEX flag." % [surface_idx, mesh_path_for_log]); continue
			if (surface_format & Mesh.ARRAY_FORMAT_TEX_UV) == 0:
				printerr("Error: Surface %d for mesh %s is missing ARRAY_FORMAT_TEX_UV flag." % [surface_idx, mesh_path_for_log]); continue
			var arrays = array_mesh_for_geometry.surface_get_arrays(surface_idx)
			if arrays == null: printerr("Error: surface_get_arrays() returned null for %s, surf %d." % [mesh_path_for_log, surface_idx]); continue
			if arrays.is_empty(): printerr("Error: surface_get_arrays() returned empty array for %s, surf %d." % [mesh_path_for_log, surface_idx]); continue
			if arrays.size() <= ArrayMesh.ARRAY_VERTEX or not arrays[ArrayMesh.ARRAY_VERTEX]:
				printerr("Error: ARRAY_VERTEX missing or null in arrays for %s, surf %d. Array size: %d" % [mesh_path_for_log, surface_idx, arrays.size()]); continue
			if arrays.size() <= ArrayMesh.ARRAY_TEX_UV or not arrays[ArrayMesh.ARRAY_TEX_UV]:
				printerr("Error: ARRAY_TEX_UV missing or null in arrays for %s, surf %d. Array size: %d" % [mesh_path_for_log, surface_idx, arrays.size()]); continue

			var vertices: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[ArrayMesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[ArrayMesh.ARRAY_INDEX] if arrays.size() > ArrayMesh.ARRAY_INDEX and arrays[ArrayMesh.ARRAY_INDEX] else PackedInt32Array()
			var bones: PackedInt32Array = arrays[ArrayMesh.ARRAY_BONES] if arrays.size() > ArrayMesh.ARRAY_BONES and arrays[ArrayMesh.ARRAY_BONES] else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[ArrayMesh.ARRAY_WEIGHTS] if arrays.size() > ArrayMesh.ARRAY_WEIGHTS and arrays[ArrayMesh.ARRAY_WEIGHTS] else PackedFloat32Array()
			
			var vertex_count = vertices.size(); if vertex_count == 0: push_warning("Warning: Vert count 0 for %s, surf %d." % [mesh_node_instance.name, surface_idx]); continue
			var has_bones = bones.size() > 0 and bones.size() == vertex_count * 4
			var has_weights = weights.size() > 0 and weights.size() == vertex_count * 4
			
			print("DEBUG: [SkinCheck] Surface %d of %s - Vertex Count: %d, Has Bones: %s, Has Weights: %s" % [surface_idx, mesh_node_instance.name, vertex_count, str(has_bones), str(has_weights)])
			if has_bones: print("DEBUG: [SkinCheck] Bones array size: %d (vertex_count*4 = %d)" % [bones.size(), vertex_count*4])
			if has_weights: print("DEBUG: [SkinCheck] Weights array size: %d (vertex_count*4 = %d)" % [weights.size(), vertex_count*4])

			var atlas_rect_norm = Rect2( float(data_item.atlas_rect.position.x)/final_calculated_atlas_size.x, \
										 float(data_item.atlas_rect.position.y)/final_calculated_atlas_size.y, \
										 float(data_item.atlas_rect.size.x)/final_calculated_atlas_size.x, \
										 float(data_item.atlas_rect.size.y)/final_calculated_atlas_size.y )
			
			if not indices.is_empty():
				print("DEBUG: Surface %d is INDEXED. Processing %d indices." % [surface_idx, indices.size()])
				for k in range(indices.size()):
					var i = indices[k] 
					if i >= vertex_count: 
						printerr("ERROR: Index %d out of bounds for vertex_count %d on surface %d" % [i, vertex_count, surface_idx])
						continue

					var original_uv = uvs[i]
					var new_uv: Vector2
					if data_item.original_key is Color: 
						new_uv = atlas_rect_norm.position + atlas_rect_norm.size * 0.5 
					else: 
						new_uv = Vector2(atlas_rect_norm.position.x + original_uv.x * atlas_rect_norm.size.x,
										 atlas_rect_norm.position.y + original_uv.y * atlas_rect_norm.size.y)
					final_surface_tool.set_uv(new_uv)
					if arrays.size() > ArrayMesh.ARRAY_NORMAL and arrays[ArrayMesh.ARRAY_NORMAL] != null and i < (arrays[ArrayMesh.ARRAY_NORMAL] as PackedVector3Array).size():
						final_surface_tool.set_normal( (arrays[ArrayMesh.ARRAY_NORMAL] as PackedVector3Array)[i] )
					if arrays.size() > ArrayMesh.ARRAY_TANGENT and arrays[ArrayMesh.ARRAY_TANGENT] != null and i * 4 + 3 < (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array).size():
						var tangent_plane := Plane( (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+0], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+1], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+2], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+3] )
						final_surface_tool.set_tangent(tangent_plane)
					if arrays.size() > ArrayMesh.ARRAY_COLOR and arrays[ArrayMesh.ARRAY_COLOR] != null and i < (arrays[ArrayMesh.ARRAY_COLOR] as PackedColorArray).size():
						final_surface_tool.set_color( (arrays[ArrayMesh.ARRAY_COLOR] as PackedColorArray)[i] )
					if arrays.size() > ArrayMesh.ARRAY_TEX_UV2 and arrays[ArrayMesh.ARRAY_TEX_UV2] != null and i < (arrays[ArrayMesh.ARRAY_TEX_UV2] as PackedVector2Array).size():
						final_surface_tool.set_uv2( (arrays[ArrayMesh.ARRAY_TEX_UV2] as PackedVector2Array)[i] )
					if has_bones and i * 4 + 3 < bones.size(): 
						final_surface_tool.set_bones(PackedInt32Array([bones[i*4], bones[i*4+1], bones[i*4+2], bones[i*4+3]]))
					if has_weights and i * 4 + 3 < weights.size(): 
						final_surface_tool.set_weights(PackedFloat32Array([weights[i*4], weights[i*4+1], weights[i*4+2], weights[i*4+3]]))
					final_surface_tool.add_vertex(relative_transform * vertices[i])
			else: 
				print("DEBUG: Surface %d is NOT INDEXED. Processing %d vertices sequentially." % [surface_idx, vertex_count])
				for i in range(vertex_count):
					var original_uv = uvs[i]
					var new_uv: Vector2
					if data_item.original_key is Color: 
						new_uv = atlas_rect_norm.position + atlas_rect_norm.size * 0.5 
					else: 
						new_uv = Vector2(atlas_rect_norm.position.x + original_uv.x * atlas_rect_norm.size.x,
										 atlas_rect_norm.position.y + original_uv.y * atlas_rect_norm.size.y)
					final_surface_tool.set_uv(new_uv)
					if arrays.size() > ArrayMesh.ARRAY_NORMAL and arrays[ArrayMesh.ARRAY_NORMAL] != null and i < (arrays[ArrayMesh.ARRAY_NORMAL] as PackedVector3Array).size():
						final_surface_tool.set_normal( (arrays[ArrayMesh.ARRAY_NORMAL] as PackedVector3Array)[i] )
					if arrays.size() > ArrayMesh.ARRAY_TANGENT and arrays[ArrayMesh.ARRAY_TANGENT] != null and i * 4 + 3 < (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array).size():
						var tangent_plane := Plane( (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+0], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+1], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+2], \
													 (arrays[ArrayMesh.ARRAY_TANGENT] as PackedFloat32Array)[i*4+3] )
						final_surface_tool.set_tangent(tangent_plane)
					if arrays.size() > ArrayMesh.ARRAY_COLOR and arrays[ArrayMesh.ARRAY_COLOR] != null and i < (arrays[ArrayMesh.ARRAY_COLOR] as PackedColorArray).size():
						final_surface_tool.set_color( (arrays[ArrayMesh.ARRAY_COLOR] as PackedColorArray)[i] )
					if arrays.size() > ArrayMesh.ARRAY_TEX_UV2 and arrays[ArrayMesh.ARRAY_TEX_UV2] != null and i < (arrays[ArrayMesh.ARRAY_TEX_UV2] as PackedVector2Array).size():
						final_surface_tool.set_uv2( (arrays[ArrayMesh.ARRAY_TEX_UV2] as PackedVector2Array)[i] )
					if has_bones and i * 4 + 3 < bones.size(): 
						final_surface_tool.set_bones(PackedInt32Array([bones[i*4], bones[i*4+1], bones[i*4+2], bones[i*4+3]]))
					if has_weights and i * 4 + 3 < weights.size(): 
						final_surface_tool.set_weights(PackedFloat32Array([weights[i*4], weights[i*4+1], weights[i*4+2], weights[i*4+3]]))
					final_surface_tool.add_vertex(relative_transform * vertices[i])
			
			total_verts += vertex_count 

		print("---- Phase 7: Committing final mesh ----")
		if total_verts == 0:
			printerr("Error: No vertices processed. Combined mesh will not be created."); 
			clean_result(false); set_toggle_children_visibility(true); return
		
		if total_verts > 0: 
			print("DEBUG: Calling final_surface_tool.index() to build index buffer for %d added vertices." % total_verts)
			final_surface_tool.index() 
		else:
			print("DEBUG: No vertices added to SurfaceTool, skipping index().")

		if regenerate_normals_and_tangents:
			print("Generating normals for the combined mesh...")
			final_surface_tool.generate_normals() 
			if total_verts > 0: 
				print("Generating tangents for the combined mesh...")
				final_surface_tool.generate_tangents()
			else:
				print("Skipping tangent generation: no vertices in SurfaceTool.")
		else:
			print("Skipping normal and tangent regeneration as per export setting.")

		var final_arrays = final_surface_tool.commit_to_arrays()
		if final_arrays.is_empty():
			printerr("Error: Failed to commit final arrays. Combined mesh will not be created.")
			clean_result(false); set_toggle_children_visibility(true); return
		
		print(" Calling clean_result (deferred) to clear previous state before assigning new mesh to self.")
		clean_result(false) 
		
		self.generated_texture = current_run_texture
		self.generated_material = current_run_material 
		
		var new_result_mesh = ArrayMesh.new() 
		new_result_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final_arrays)
		new_result_mesh.surface_set_material(0, self.generated_material) 
		print("DEBUG: Set surface 0 material of new_result_mesh to: %s (Albedo Color: %s, Texture: %s)" % [str(self.generated_material), str(self.generated_material.albedo_color), str(self.generated_material.albedo_texture)])
		
		self.result_mesh = new_result_mesh 
		self.mesh = self.result_mesh 		
		self.material_override = null 
		print("DEBUG: Set self.material_override to null. self.mesh is now: %s (ID: %s)." % [str(self.mesh), str(self.mesh.get_instance_id() if self.mesh else "null")])
		if self.mesh:
			print("DEBUG: self.mesh surface count after assignment: %d" % self.mesh.get_surface_count())
			if self.mesh.get_surface_count() > 0:
				print("DEBUG: self.mesh surface 0 material after assignment: %s" % str(self.mesh.surface_get_material(0)))
				if self.mesh.surface_get_material(0) == self.generated_material:
					print("DEBUG: CONFIRMED: self.mesh surface 0 material IS the generated_material.")
				else:
					print("DEBUG: WARNING: self.mesh surface 0 material IS NOT the generated_material. It is: %s" % str(self.mesh.surface_get_material(0)))
			else:
				print("DEBUG: WARNING: self.mesh has 0 surfaces after assignment.")
		else:
			print("DEBUG: WARNING: self.mesh is null after assignment.")


		var skeleton_assigned_successfully = false
		print("DEBUG: [Skeleton] Starting skeleton assignment process.")
		print("DEBUG: [Skeleton] Manual path provided: '%s'" % str(manual_skeleton_node_path))

		if manual_skeleton_node_path != NodePath(""):
			var skeleton_node: Node = get_node_or_null(manual_skeleton_node_path)
			if is_instance_valid(skeleton_node) and skeleton_node is Skeleton3D:
				var path_to_skeleton = get_path_to(skeleton_node)
				print("DEBUG: [Skeleton] Assigning MANUALLY specified Skeleton3D. Resolved path from self ('%s') to skeleton ('%s'): %s" % [self.name, skeleton_node.name, str(path_to_skeleton)])
				self.set_deferred("skeleton_path", path_to_skeleton) 
				skeleton_assigned_successfully = true
			elif is_instance_valid(skeleton_node) and not skeleton_node is Skeleton3D:
				printerr("ERROR: [Skeleton] Manual Skeleton path '", manual_skeleton_node_path, "' points to a node ('", skeleton_node.name, "') that is NOT a Skeleton3D. Type is: ", typeof(skeleton_node))
			else:
				printerr("ERROR: [Skeleton] Manual Skeleton path '", manual_skeleton_node_path, "' is invalid or node does not exist.")
		else:
			print("DEBUG: [Skeleton] Manual skeleton path is empty. Attempting fallback.")

		if not skeleton_assigned_successfully: 
			var found_skel_path_fallback: NodePath = NodePath("")
			print("DEBUG: [Skeleton] Manual assignment failed or skipped. Entering fallback logic.")
			
			var original_node_skeleton_path_property = NodePath("")
			if is_instance_valid(target_node) and target_node is MeshInstance3D:
				original_node_skeleton_path_property = target_node.get_skeleton_path() 
				print("DEBUG: [Skeleton] Fallback: Target node ('%s') current get_skeleton_path() is: '%s'" % [target_node.name, str(original_node_skeleton_path_property)])

			if original_node_skeleton_path_property != NodePath(""):
				var skeleton_node_from_property = target_node.get_node_or_null(original_node_skeleton_path_property)
				if is_instance_valid(skeleton_node_from_property) and skeleton_node_from_property is Skeleton3D:
					found_skel_path_fallback = self.get_path_to(skeleton_node_from_property)
					print("DEBUG: [Skeleton] Fallback (from target's existing property): Assigning skeleton path. Resolved path from self to '%s': %s" % [skeleton_node_from_property.name, str(found_skel_path_fallback)])
				else:
					print("DEBUG: [Skeleton] Fallback: Target node's skeleton_path ('%s') did not point to a valid Skeleton3D." % str(original_node_skeleton_path_property))
			else:
				print("DEBUG: [Skeleton] Fallback: Target node's skeleton_path property was empty.")
			
			if found_skel_path_fallback.is_empty() and target_node == self:
				print("DEBUG: [Skeleton] Fallback: Target is self. Searching for common Skeleton3D patterns (sibling or parent).")
				var parent_of_self = self.get_parent()
				if is_instance_valid(parent_of_self):
					if parent_of_self is Skeleton3D:
						found_skel_path_fallback = self.get_path_to(parent_of_self)
						print("DEBUG: [Skeleton] Fallback: Parent node ('%s') is a Skeleton3D. Path: %s" % [parent_of_self.name, str(found_skel_path_fallback)])
					else:
						var sibling_skel: Skeleton3D = null
						var skel_node_check = parent_of_self.get_node_or_null("Skeleton3D")
						if is_instance_valid(skel_node_check) and skel_node_check is Skeleton3D:
							sibling_skel = skel_node_check
						else:
							skel_node_check = parent_of_self.get_node_or_null("skeleton3d")
							if is_instance_valid(skel_node_check) and skel_node_check is Skeleton3D:
								sibling_skel = skel_node_check
						
						if not is_instance_valid(sibling_skel): 
							for child_of_parent in parent_of_self.get_children():
								if child_of_parent is Skeleton3D:
									sibling_skel = child_of_parent
									break
						
						if is_instance_valid(sibling_skel) and sibling_skel is Skeleton3D:
							found_skel_path_fallback = self.get_path_to(sibling_skel)
							print("DEBUG: [Skeleton] Fallback: Found sibling/cousin Skeleton3D ('%s') under parent '%s'. Path: %s" % [sibling_skel.name, parent_of_self.name, str(found_skel_path_fallback)])
						else:
							print("DEBUG: [Skeleton] Fallback: No common Skeleton3D (sibling/parent) found for self.")
				else:
					print("DEBUG: [Skeleton] Fallback: Self has no parent to search for common Skeleton3D patterns.")

			if not found_skel_path_fallback.is_empty():
				self.set_deferred("skeleton_path", found_skel_path_fallback) 
				skeleton_assigned_successfully = true
				print("DEBUG: [Skeleton] Successfully assigned a fallback skeleton path: %s" % str(found_skel_path_fallback))
			else:
				print("DEBUG: [Skeleton] Fallback mechanism did not find any valid skeleton path.")
						
		if not skeleton_assigned_successfully:
			var mesh_is_likely_skinned = false
			for surf_info in surfaces_to_process: 
				var arrays_check = mesh_for_material_collection.surface_get_arrays(surf_info.surface_idx)
				if arrays_check and arrays_check.size() > ArrayMesh.ARRAY_BONES and arrays_check[ArrayMesh.ARRAY_BONES] and \
				   arrays_check.size() > ArrayMesh.ARRAY_WEIGHTS and arrays_check[ArrayMesh.ARRAY_WEIGHTS]:
					if (arrays_check[ArrayMesh.ARRAY_BONES] as PackedInt32Array).size() > 0:
						mesh_is_likely_skinned = true
						break
			if mesh_is_likely_skinned:
				push_warning("[Skeleton] WARNING: No valid Skeleton3D path was assigned to the combined mesh, and the mesh appears to have skinning data. Mesh will likely deform incorrectly (e.g., to bind pose). Final skeleton_path will be empty.")
			else:
				print("DEBUG: [Skeleton] No valid Skeleton3D path was assigned, but mesh does not appear to have skinning data on processed surfaces. Setting empty skeleton_path.")

			self.set_deferred("skeleton_path", NodePath("")) 
		else:
			print("DEBUG: [Skeleton] A skeleton path was determined and scheduled for deferred assignment.")

		print("DEBUG: [Skeleton] Finished skeleton assignment process.")

		print(" Process finished.")
		if target_node != self: 
			set_toggle_children_visibility(false) 
		if collision_parent_path != NodePath("") and get_node_or_null(collision_parent_path):
			collision_parent = get_node_or_null(collision_parent_path) 
			if collision_parent:
				clean_collisions(); copy_collisions_recursive(target_node) 
			else:
				push_warning("Skipping collision copy: collision_parent node not found at path '%s'." % str(collision_parent_path))
		else: print("Skipping collision copy: collision_parent_path not set.")
		print("---- Combine & Atlas process complete. Final mesh has %d vertices. ----" % total_verts)
	else: 
		print("DEBUG: combine_and_atlas value is FALSE. Not processing (this is normal if not a button press).")
		return


func find_target_mesh_recursive(node: Node, name_to_find: String) -> MeshInstance3D:
	if not node: return null
	if node is MeshInstance3D and node.name == name_to_find:
		return node
	for child in node.get_children():
		var found = find_target_mesh_recursive(child, name_to_find)
		if found:
			return found
	return null

func collect_data_for_target(target_mesh_instance_node: MeshInstance3D, p_mesh_for_materials: ArrayMesh, item_map: Dictionary, r_surfaces_to_process: Array) -> bool:
	var collected_something = false
	if not target_mesh_instance_node:
		printerr("CollectData: Target MeshInstance3D node is null."); return false
	var mi_node: MeshInstance3D = target_mesh_instance_node 
	print("CollectData: Processing target MeshInstance3D: ", mi_node.name)
	if not p_mesh_for_materials: 
		printerr("CollectData: ArrayMesh resource for material collection (p_mesh_for_materials) is null for %s." % mi_node.name); return false
	print("CollectData: ArrayMesh for materials '%s' has %d surfaces." % [mi_node.name, p_mesh_for_materials.get_surface_count()])
	var current_node_relative_transform: Transform3D
	if mi_node == self: 
		current_node_relative_transform = Transform3D.IDENTITY
		print("CollectData: Target is self. Using IDENTITY transform for mesh data.")
	else: 
		current_node_relative_transform = self.global_transform.affine_inverse() * mi_node.global_transform
		print("CollectData: Target is '%s' (not self). Calculated relative transform for mesh data." % mi_node.name)

	for surface_idx in range(p_mesh_for_materials.get_surface_count()):
		print("CollectData:    Processing surface_idx: ", surface_idx, " for mesh: ", mi_node.name)
		var material_to_check: Material = target_mesh_instance_node.get_active_material(surface_idx)
		print("CollectData:      Using material from target_mesh_instance_node.get_active_material(surface_idx).") 
		if material_to_check:
			print("CollectData:        Material Being Checked: %s (Type: %s, Path: %s)" % [str(material_to_check), typeof(material_to_check), material_to_check.resource_path if material_to_check.resource_path else "Embedded/Runtime"])
		else:
			print("CollectData:        Material Being Checked is NULL for surface %d." % surface_idx)

		var albedo_item_key 
		var item_image: Image = null
		var item_is_texture = false 

		if material_to_check is BaseMaterial3D:
			var base_mat: BaseMaterial3D = material_to_check
			print("DEBUG: Surface %d, BaseMaterial3D Path: %s" % [surface_idx, base_mat.resource_path if base_mat.resource_path else "Embedded/Runtime"])

			if base_mat.albedo_texture != null:
				var albedo_tex_resource: Texture2D = base_mat.albedo_texture
				print("CollectData:        Albedo texture resource IS PRESENT: %s (Type: %s, Path: %s)" % [str(albedo_tex_resource), typeof(albedo_tex_resource), albedo_tex_resource.resource_path if albedo_tex_resource.resource_path else "Embedded/Runtime"])
				if albedo_tex_resource.has_method("get_image"): 
					item_image = albedo_tex_resource.get_image() 
					if item_image and not item_image.is_empty(): 
						albedo_item_key = albedo_tex_resource 
						item_is_texture = true
						print("CollectData:          Surface %d: Successfully got Image from texture. Size: %dx%d, Format: %s." % [surface_idx, item_image.get_width(), item_image.get_height(), item_image.get_format()])
					elif item_image: 
						push_warning("CollectData:          Surface %d: Warning: Albedo Texture '%s'.get_image() returned an EMPTY Image." % [surface_idx, str(albedo_tex_resource)])
						item_image = null 
					else: 
						push_warning("CollectData:          Surface %d: Warning: Albedo Texture '%s'.get_image() returned null." % [surface_idx, str(albedo_tex_resource)])
				else:
					push_warning("CollectData:          Surface %d: Warning: Albedo item '%s' (Type: %s) does not have get_image() method." % [surface_idx, str(albedo_tex_resource), typeof(albedo_tex_resource)])
			else:
				print("CollectData:        Surface %d: Albedo texture property IS NULL on the material." % surface_idx)

			if not item_image:
				albedo_item_key = base_mat.albedo_color 
				print("DEBUG: Surface %d: Fallback to albedo_color: %s" % [surface_idx, str(albedo_item_key)]) 
				item_image = Image.create(color_block_size, color_block_size, false, Image.FORMAT_RGBA8) 
				if item_image:
					item_image.fill(albedo_item_key) 
					print("DEBUG: Surface %d: Filled image block with color: %s. Pixel (0,0) of block: %s. Format: %s" % [surface_idx, str(albedo_item_key), str(item_image.get_pixel(0,0)), item_image.get_format()])
				else: 
					printerr("CollectData: Failed to create image block for color %s" % str(albedo_item_key))
				item_is_texture = false 
				print("CollectData:          Surface %d: No valid Albedo Texture. Using Albedo Color: %s. Created %dx%d image block." % [surface_idx, str(albedo_item_key), color_block_size, color_block_size])
		else: 
			if material_to_check: push_warning("CollectData:        Surface %d: Material type '%s' not BaseMaterial3D compatible. Skipping." % [surface_idx, typeof(material_to_check)])
			else: push_warning("CollectData:        Surface %d: Material to check is null. Skipping." % surface_idx)
			continue 
		
		if item_image: 
			var data_item: TextureData
			if item_map.has(albedo_item_key): 
				data_item = item_map[albedo_item_key]
			else: 
				data_item = TextureData.new(item_image, albedo_item_key)
				item_map[albedo_item_key] = data_item
			r_surfaces_to_process.append({
				"mesh_node": mi_node, "surface_idx": surface_idx, 
				"transform": current_node_relative_transform, "item_data": data_item })
			collected_something = true
		else:
			push_warning("CollectData:          Surface %d: Warning: Could not get/create image for albedo item: %s. Skipping this surface." % [surface_idx, str(albedo_item_key if albedo_item_key else "Unknown")])
	return collected_something

func basic_grid_packer(item_data_list: Array, initial_atlas_size: Vector2i) -> Dictionary:
	if item_data_list.is_empty():
		push_warning("Packer: No item data provided."); 
		return {"rects": [], "final_size": initial_atlas_size} 
	var packed_rects: Array = []
	packed_rects.resize(item_data_list.size()) 
	var current_atlas_size = initial_atlas_size 
	var current_x = 0; var current_y = 0; var max_row_height = 0
	item_data_list.sort_custom(func(a,b):
		if not a or not a.image or not b or not b.image: return false 
		if a.image.get_height() == b.image.get_height():
			return a.image.get_width() > b.image.get_width() 
		return a.image.get_height() > b.image.get_height()
	)
	for i in range(item_data_list.size()):
		var data_item: TextureData = item_data_list[i]
		if not data_item or not data_item.image:
			printerr("Packer Error: Invalid TextureData (or no image) at index %d" % i)
			return {"rects": [], "final_size": current_atlas_size} 
		var img_size = data_item.image.get_size()
		if img_size.x == 0 or img_size.y == 0:
			printerr("Packer Error: TextureData at index %d has zero dimension image (%dx%d)." % [i, img_size.x, img_size.y])
			return {"rects": [], "final_size": current_atlas_size} 

		if img_size.x > current_atlas_size.x :
			push_warning("Packer Warning: Item %d (%dx%d) wider than current atlas width %d. Increasing atlas width." % [i,img_size.x,img_size.y,current_atlas_size.x])
			current_atlas_size.x = next_power_of_2(img_size.x) 
			print("Packer: New atlas width: %d." % current_atlas_size.x)
			current_x = 0 

		if current_x + img_size.x > current_atlas_size.x:
			current_x = 0
			current_y += max_row_height
			max_row_height = 0

		if current_y + img_size.y > current_atlas_size.y:
			push_warning("Packer Warning: Item %d (%dx%d) at (%d,%d) would exceed atlas height %d. Increasing atlas height." % [i, img_size.x, img_size.y, current_x, current_y, current_atlas_size.y])
			current_atlas_size.y = next_power_of_2(current_y + img_size.y) 
			if current_atlas_size.y > 8192: 
				printerr("Packer Error: Atlas height limit 8192 exceeded. Cannot pack item %d." % i)
				return {"rects": [], "final_size": current_atlas_size} 
			print("Packer: New atlas height: %d" % current_atlas_size.y)
		
		if current_x + img_size.x > current_atlas_size.x or current_y + img_size.y > current_atlas_size.y :
			printerr("Packer Error: Item %d (%dx%d) still doesn't fit in atlas %s at position (%d,%d) even after adjustments. This might indicate a packing logic issue or extremely large texture." % [i, img_size.x, img_size.y, str(current_atlas_size), current_x, current_y])
			if i == 0 or (current_x == 0 and current_y == 0) : 
				current_atlas_size.x = next_power_of_2(img_size.x)
				current_atlas_size.y = next_power_of_2(img_size.y)
				print("Packer Last Resort: Resizing atlas to fit first problematic item: %s" % str(current_atlas_size))
				if img_size.x <= current_atlas_size.x and img_size.y <= current_atlas_size.y:
					packed_rects[i] = Rect2i(0, 0, img_size.x, img_size.y)
					current_x = img_size.x
					max_row_height = img_size.y
				else:
					return {"rects": [], "final_size": current_atlas_size} 
			else: 
				return {"rects": [], "final_size": current_atlas_size} 


		packed_rects[i] = Rect2i(current_x, current_y, img_size.x, img_size.y)
		current_x += img_size.x
		max_row_height = max(max_row_height, img_size.y)
	
	var final_packed_height = current_y + max_row_height
	current_atlas_size.y = next_power_of_2(final_packed_height)
	if current_atlas_size.y > 8192: current_atlas_size.y = 8192 

	return { "rects": packed_rects, "final_size": current_atlas_size }


func next_power_of_2(n: int) -> int:
	if n <= 0: return 1 
	var p = 1
	while p < n: p <<= 1 
	return p

func clean_result(value): 
	if not Engine.is_editor_hint() and value: return 
	if value: 
		set_block_signals(true)
		btn_clean_result = false
		set_block_signals(false)
	print("Cleaning combined result...");
	self.mesh = null; 
	if result_mesh: 
		result_mesh = null 
	if generated_material: 
		generated_material = null
	if generated_texture: 
		generated_texture = null
	clean_collisions() 
	
	var actual_target_node = find_target_mesh_recursive(self, target_mesh_name)
	if not actual_target_node and get_parent():
		actual_target_node = find_target_mesh_recursive(get_parent(), target_mesh_name)

	if actual_target_node != self: 
		set_toggle_children_visibility(true) 
	print("Clean complete.")

func copy_collisions_recursive(node_to_copy_from: Node):
	if not collision_parent or not is_instance_valid(collision_parent):
		push_warning("Collision copy: No valid collision_parent. Skipping."); return
	if not collision_parent.is_inside_tree(): 
		push_warning("Collision copy WARNING: Collision parent not inside tree. Skipping."); return

	for child_of_source_node in node_to_copy_from.get_children():
		if child_of_source_node is StaticBody3D: 
			var sb: StaticBody3D = child_of_source_node
			for cs_node_original in sb.get_children():
				if cs_node_original is CollisionShape3D:
					var original_col_shape: CollisionShape3D = cs_node_original
					if not original_col_shape.shape: 
						push_warning("Collision copy: Skipping null collision shape from: %s" % original_col_shape.get_path()); 
						continue
					print("Collision copy: Copying collision shape from: ", original_col_shape.get_path())
					var new_col_shape_node := CollisionShape3D.new()
					new_col_shape_node.global_transform = original_col_shape.global_transform 
					
					new_col_shape_node.shape = original_col_shape.shape.duplicate(true) 
					collision_parent.add_child(new_col_shape_node)
					if Engine.is_editor_hint(): 
						var editor_scene_root = get_tree().edited_scene_root
						if editor_scene_root: new_col_shape_node.owner = editor_scene_root
						else: push_warning("Collision copy Warning: Could not set owner for new collision shape (edited_scene_root is null).")
		if child_of_source_node.get_child_count() > 0:
			copy_collisions_recursive(child_of_source_node)


func clean_collisions():
	if not collision_parent or not is_instance_valid(collision_parent): return
	if collision_parent.get_child_count() > 0:
		print("Cleaning collisions from: ", collision_parent.name)
		for i in range(collision_parent.get_child_count() - 1, -1, -1): 
			var child = collision_parent.get_child(i)
			if is_instance_valid(child) and child is CollisionShape3D: 
				print("Removing collision child: ", child.name)
				collision_parent.remove_child(child); child.queue_free()

func set_toggle_children_visibility(value: bool):
	toggle_children_visibility = value
	if not is_inside_tree(): 
		push_warning("Cannot toggle children visibility, node not in tree: %s" % self.name); return

	var actual_target_node = find_target_mesh_recursive(self, target_mesh_name)
	var search_root_for_visibility = self 
	
	if not actual_target_node and get_parent(): 
		actual_target_node = find_target_mesh_recursive(get_parent(), target_mesh_name)
		if actual_target_node: 
			search_root_for_visibility = get_parent() 

	if actual_target_node == self: 
		print("Toggle visibility: Script is on the target node ('%s'). Visibility of its own children is not toggled by this logic." % self.name)
		return 
	
	for node_child in search_root_for_visibility.get_children(): 
		if node_child is Node3D and node_child != collision_parent and node_child != self: 
			var is_container_of_target_or_target_itself = false
			if actual_target_node != null:
				if node_child == actual_target_node:
					is_container_of_target_or_target_itself = true
				elif node_child.is_ancestor_of(actual_target_node):
					is_container_of_target_or_target_itself = true
			
			if is_container_of_target_or_target_itself:
				print("Toggle visibility: Setting visibility of '%s' to %s" % [node_child.name, str(value)])
				node_child.visible = value


func set_delete_child_meshes_on_play(value: bool): delete_child_meshes_on_play = value

func _ready():
	if delete_child_meshes_on_play and not Engine.is_editor_hint():
		print("Runtime: Deleting original child meshes (if applicable)...")
		var target_node_found = find_target_mesh_recursive(self, target_mesh_name)
		var search_root_for_deletion = self

		if not target_node_found and get_parent(): 
			target_node_found = find_target_mesh_recursive(get_parent(), target_mesh_name)
			if target_node_found:
				search_root_for_deletion = get_parent()
		
		if target_node_found != null and target_node_found != self: 
			var child_to_delete: Node = null
			if search_root_for_deletion.is_ancestor_of(target_node_found):
				var current_node = target_node_found
				while is_instance_valid(current_node.get_parent()):
					if current_node.get_parent() == search_root_for_deletion:
						child_to_delete = current_node
						break
					current_node = current_node.get_parent()
					if not is_instance_valid(current_node): break 
			
			if is_instance_valid(child_to_delete) and child_to_delete != collision_parent and child_to_delete != self : 
				print("Runtime: Queueing free for node: '%s' (child of '%s')" % [child_to_delete.name, search_root_for_deletion.name])
				child_to_delete.queue_free()
			elif not is_instance_valid(child_to_delete):
				push_warning("Runtime: Could not determine the direct child (of '%s') that contains the target '%s' for deletion." % [search_root_for_deletion.name, target_mesh_name])
		elif target_node_found == self:
			print("Runtime: Script is on target node. Deletion of its children is skipped by this logic (target itself is replaced).")
		else:
			push_warning("Runtime: Target node '%s' not found. Cannot delete." % target_mesh_name)

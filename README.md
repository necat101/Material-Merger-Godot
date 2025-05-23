Godot Material Merger & Atlas Optimizer
Dramatically reduce draw calls and streamline your Godot Engine projects by merging materials and generating optimized texture atlases with ease.
![Screenshot 2025-05-23 002533](https://github.com/user-attachments/assets/f410558b-aeb6-4a59-bdc9-bec7f6942dee)

   ## 1. Overview

The Godot Material Merger & Atlas Optimizer is an editor plugin for the Godot Engine, meticulously designed to enhance 3D scene performance and improve overall asset management. Its primary function is to combine multiple StandardMaterial3D instances (and potentially other material types) into a single, unified material. Concurrently, it intelligently packs their associated textures—such as albedo, normal, metallic, roughness, ambient occlusion, and emission maps—into a consolidated texture atlas. This process is crucial for optimizing game assets for real-time rendering. The tool typically operates on MeshInstance3D nodes and their surface materials. The internal logic for identifying textures to be merged might involve functions that iterate through common texture slots within materials, for example, a function like _collect_texture_paths_from_material(material).

The adoption of this tool offers several key benefits to Godot developers:

Reduced Draw Calls: One of the most significant advantages is the substantial reduction in draw calls. In rendering, each material applied to an object visible on screen typically necessitates at least one draw call. By merging, for instance, ten materials into one, the number of draw calls for those objects can be reduced tenfold. This directly alleviates a common performance bottleneck, as excessive draw calls can heavily strain the CPU. Efficiently managing draw calls is fundamental to achieving smoother frame rates and more responsive gameplay, allowing for greater scene complexity without commensurate performance degradation.
Improved GPU Performance: Texture atlasing complements material merging by enhancing GPU efficiency. When the GPU renders a scene, using fewer, larger textures (atlases) instead of numerous small, individual textures minimizes texture swapping in GPU memory. This leads to improved cache coherency and faster texture lookups, contributing to overall rendering speed.
Optimized VRAM Usage: While a texture atlas can be a large texture, its use often leads to more efficient Video RAM (VRAM) utilization. This is because the overhead associated with managing many small textures, including their mipmaps and potential padding wastage if not atlased, can be greater than that of a single, well-packed atlas. However, the efficiency gained is dependent on the packing quality; a poorly packed atlas could inadvertently waste space.
Streamlined Asset Management: A reduction in the number of material and texture files simplifies project organization. This makes assets easier to manage, track in version control systems, and share among team members, leading to a more organized and maintainable project structure.
Simplified LOD (Level of Detail) Creation: Merged assets, with their single material and texture atlas, can serve as an excellent base for creating lower-polygon Level of Detail (LOD) models. This simplifies the LOD pipeline, as these optimized versions already share a unified material setup.
The tool's design reflects an understanding that performance is not merely a secondary concern but a primary driver for many development decisions. By directly addressing draw call overhead and texture management, it empowers developers to push the boundaries of their scene complexity or to ensure their projects run smoothly on a broader range of hardware. However, the introduction of any tool that modifies scene assets must be handled with care. The effectiveness of such a tool is not just in its optimization capabilities but also in how seamlessly it integrates into an existing development workflow. For instance, the process of merging materials could be destructive to the original scene setup if original assets are directly overwritten. Consequently, features that preserve original assets, such as creating duplicates or offering clear preview mechanisms, are paramount for user adoption and minimizing disruption during iterative development.

2. Features
This tool provides a suite of features designed to optimize 3D assets within the Godot editor:

Automatic Material Merging:
Combines multiple StandardMaterial3D instances from selected MeshInstance3D nodes into a single new material. The script specifically processes Albedo textures and Albedo colors from BaseMaterial3D or StandardMaterial3D.
The core logic for merging material properties, possibly located in a function like _merge_material_properties(materials_array), would define how differing properties (e.g., diffuse color, metallic, roughness) are consolidated. This might involve averaging values, prioritizing the properties of a specific material, or requiring uniformity for certain attributes. If ShaderMaterials are supported, this process becomes considerably more complex, potentially involving analysis of shader code or sophisticated merging of shader uniforms.
Texture Atlas Generation:
Packs all unique Albedo textures (from BaseMaterial3D/StandardMaterial3D) and solid Albedo colors (converted to small image blocks) from the source materials into a single, optimized texture atlas.
Supports various texture types and maps them to corresponding channels or regions in the atlas (e.g., albedo maps to the RGB channels, while roughness might be packed into a specific channel of an Occlusion-Roughness-Metallic (ORM) map).
Configurable Atlas Settings:
Target Atlas Size (atlas_target_size): User-definable target (and initial) size for the generated atlas (e.g., 2048x2048). The packer might adjust this.
Color Block Size (color_block_size): Defines the dimensions of the small square images created to represent solid Albedo colors within the atlas.
Regenerate Normals and Tangents (regenerate_normals_and_tangents): Option to regenerate normals and tangents for the combined mesh, which can be useful if the original vertex data or merging process affects them.
Atlas Material Cull Mode (atlas_material_cull_mode): Allows specifying the BaseMaterial3D.CullMode (Back, Front, Disabled) for the generated atlas material.
User control over these parameters, likely through UI elements such as input fields for atlas_max_width, atlas_max_height, and texture_padding, allows for fine-tuning the atlas generation to meet specific project requirements, such as memory budgets or target platform limitations.
UV Remapping:
Automatically adjusts the UV coordinates of the affected meshes' vertices. This critical and intricate step ensures that the meshes correctly sample textures from their new locations within the generated texture atlas.
A fundamental function, perhaps named _remap_mesh_uvs(mesh, original_uvs, atlas_rect_data), would be responsible for these transformations, calculating new UVs based on each original texture's new position and scale within the atlas. The accuracy and robustness of this UV remapping process are vital; any flaws here would render the merged asset unusable, as textures would appear distorted or incorrectly applied.
Skinned Mesh Support:
Attempts to preserve skinning data (bone indices and weights) from the source meshes.
Supports manual linking to a Skeleton3D node via the manual_skeleton_node_path property for explicit control, which is crucial if automatic detection is insufficient or if the skinning is complex.
Collision Handling:
If a collision_parent_path is specified, the tool will attempt to copy the collision setup from the original model.
It scans the parent of the target_mesh_name (or the target_mesh_name node itself if it has no parent) for StaticBody3D nodes.
For each found StaticBody3D, it creates a new StaticBody3D (named with an _coll_copy suffix) under the collision_parent_path node.
This new StaticBody3D will have its collision_layer, collision_mask, and global_transform copied from the original.
CollisionShape3D children of the original StaticBody3D are duplicated (with their shapes and relative transforms) under the new StaticBody3D.
This feature helps maintain the physical properties of the original model alongside the optimized visual mesh.
Editor Integration & Actions:
Operates as an editor tool (@tool).
Provides Inspector buttons (btn_combine_and_atlas, btn_clean_result) to trigger the main processing and cleanup actions.
Child Mesh Handling:
toggle_children_visibility: Option to automatically hide the original child meshes (containing the target_mesh_name) after a successful merge, and show them again after cleaning.
delete_child_meshes_on_play: Option to automatically queue the original child meshes for deletion when the game runs, further optimizing the runtime scene.
Non-Destructive Workflow Options:
Ideally, the tool offers options to create new, merged MeshInstance3D nodes and materials, leaving the original nodes and materials untouched. The current script modifies the node it's attached to, or replaces the target node's mesh if attached to a parent. The btn_clean_result allows reverting these changes.
An alternative or complementary option might be to duplicate original meshes before applying any modifications. Such features are crucial for allowing experimentation without risk to existing work.
Material Property Handling:
Defines a strategy for combining material properties when source materials differ (e.g., averaging numeric values, using the value from the first selected material, or flagging properties that must be identical for a successful merge).
Includes support for transparent materials, which may involve merging them separately, packing them onto a distinct atlas, or employing specific shader techniques to handle transparency correctly with an atlased texture.
Manages various PBR texture maps, including emission, ambient occlusion, roughness, metallic, and normal maps, ensuring they are correctly incorporated into the merged material and atlas. The tool's versatility is significantly enhanced by its ability to handle diverse material properties and types. For example, merging materials with fundamentally different rendering requirements (like an opaque material with a transparent one) into a single draw call using a standard shader can be problematic. Clear documentation on how such scenarios are handled is essential.
User Interface (UI) Integration:
Accessible directly within the Godot editor, for example, through a dedicated dock, a menu item (e.g., under "Project Tools"), or a button in the spatial editor's toolbar.
Provides clear visual feedback during processing, such as a progress bar or log messages, to keep the user informed of the tool's status.
Batch Processing (If applicable):
Offers the ability to process multiple selections of MeshInstance3D nodes or even entire scene branches simultaneously, improving workflow efficiency for larger-scale optimizations.
The variety of configuration options for atlas generation, such as size and padding, provides powerful control but also necessitates careful consideration. Optimal settings are context-dependent, influenced by factors like texture diversity, target platform constraints, and desired visual quality. Poor choices can lead to wasted texture space or visual artifacts. Therefore, providing sensible default values or even an "automatic" mode could be beneficial, particularly for users less familiar with the nuances of texture atlasing.

Feature Highlights
Feature	Description	Key Benefit
Material Merging	Combines multiple selected materials (Albedo only for now) into one.	Drastically reduces draw calls.
Texture Atlas Generation	Packs Albedo textures and solid colors from source materials into a single atlas.	Improves GPU texture caching, potentially reduces VRAM.
UV Remapping	Automatically adjusts mesh UVs to map to the new atlas.	Ensures textures display correctly on merged objects.
Skinned Mesh Support	Attempts to preserve bone/weight data and allows manual Skeleton3D linking.	Enables optimization of animated characters.
Collision Copying	Duplicates StaticBody3D and CollisionShape3D setup from original model to a specified parent.	Preserves physics interactions alongside visual optimization.
Configurable Atlas	Allows setting target size, color block size, cull mode, etc.	Tailors output to specific project needs and quality targets.
Editor Actions	Buttons in Inspector for easy combine/cleanup operations.	Streamlined workflow within the editor.
Child Handling	Options to toggle visibility or delete original meshes at runtime.	Reduces scene clutter and runtime overhead.
Non-Destructive Mode	(If available) Option to preserve original assets.	Safe experimentation and easy reversion.
Broad Material Support	Handles various texture maps (albedo, normal, ORM, emission).	Versatile for common PBR workflows.


3. Prerequisites
Before using the Godot Material Merger & Atlas Optimizer, ensure the following requirements are met:

Godot Engine Version:
This plugin is designed for specific versions of the Godot Engine. For example, it might require "Godot 4.x" (as indicated by its use of @tool and modern GDScript features). This information is critical and is typically found within the plugin.cfg file (e.g., a line like version="4.1") or indicated in the project settings. Using an incompatible Godot version will likely result in the plugin failing to load or operate correctly due to dependencies on specific API features of that Godot version. The tool's functionality is intrinsically linked to the Godot API version it was developed against; API changes in other Godot versions (older or newer) could break compatibility.
Operating System:
Generally, Godot editor plugins are cross-platform and should work on any operating system supported by Godot (Windows, macOS, Linux). Note any OS-specific dependencies if they exist, though this is uncommon for editor plugins.
Asset Pipeline Considerations:
For optimal results, consider the state of your assets before merging. For instance, ensure that textures are imported into Godot with lossless compression settings if the highest quality is desired for the generated atlas. The tool works best when source textures are prepared appropriately.
Source meshes should have valid UV coordinates for texture mapping.
For skinned meshes, ensure bone and weight data are present in the mesh arrays or provide a manual_skeleton_node_path.

5. Usage Guide
This section provides a comprehensive walkthrough of using the Material Merger & Atlas Optimizer.

Accessing the Tool
Once the script is attached to a MeshInstance3D node in your scene (this node will become the host for the merged mesh), its configuration options will appear in the Godot Inspector panel when that node is selected.

Preparing Your Scene and Meshes
Setup Host Node:
Create an empty MeshInstance3D in your scene. This node will receive the combined mesh and new atlas material. Attaching the script to an empty MeshInstance3D is recommended for clarity.
Alternatively, you can attach the script directly to the parent MeshInstance3D that contains the hierarchy you want to merge.
Attach the MaterialCombiner.gd script to this MeshInstance3D node.
Target Mesh Identification:
In the Inspector for the host node, set the Target Mesh Name property to the exact name of the MeshInstance3D node whose descendant materials and geometry you want to combine. This target mesh should typically be a child of the node where the script is attached, or a child of the script node's parent if the script is on a dedicated processing node.
Material Compatibility: Ensure that the materials applied to the surfaces of the target MeshInstance3D (and its relevant children, if applicable, though this script focuses on a single target mesh's surfaces) are BaseMaterial3D or StandardMaterial3D for their Albedo properties to be processed.
Collision Parent (Optional):
If you want to copy the collision shapes from the original model, create an empty Node3D (or a StaticBody3D itself if you prefer) in your scene to act as the parent for the copied collision objects.
In the Inspector for the host node, set the Collision Parent Path by selecting this newly created node. The script will then search for StaticBody3D nodes related to the original target_mesh_name (typically by looking at target_mesh_name.get_parent()) and replicate their structure under this path.
Skeleton Linking (Optional, for Skinned Meshes):
If you are merging a skinned mesh (e.g., a character), and you want to ensure correct rigging, you can specify the Manual Skeleton Node Path. Point this to the Skeleton3D node that the merged mesh should be bound to. If left empty, the script will attempt some fallback logic to find an appropriate skeleton.
Understanding the UI (Inspector Properties)
The plugin's UI consists of exported variables in the Inspector panel for the node holding the script:

Target Mesh:
Target Mesh Name: String name of the MeshInstance3D to process.
Atlas Settings:
Atlas Target Size: Target resolution for the generated texture atlas (e.g., 2048).
Color Block Size: Size of the image blocks created for solid Albedo colors (e.g., 4x4 pixels).
Regenerate Normals And Tangents: Boolean, if true, new normals and tangents are generated for the combined mesh.
Atlas Material Cull Mode: Enum to set culling (Back, Front, Disabled) for the new material.
Collision Settings:
Collision Parent Path: NodePath to an existing node that will become the parent of copied collision objects.
Skeleton Linking:
Manual Skeleton Node Path: NodePath to the Skeleton3D to be used by the merged mesh.
Actions:
Btn Combine And Atlas: A boolean that acts as a button. Check it to trigger the merging process. It will automatically uncheck itself.
Btn Clean Result: A boolean that acts as a button. Check it to remove the generated mesh/material from this node and attempt to restore visibility of original children.
Child Handling:
Toggle Children Visibility: If true, the script will attempt to hide the original target mesh's parent hierarchy after combining and show it after cleaning.
Delete Child Meshes On Play: If true, the original target mesh's hierarchy will be queued for deletion when the game starts (not in the editor).
The design of the user interface and the clarity of its workflow are critical. A complex operation like material merging involves numerous parameters and steps; a well-structured UI with clear labels, helpful tooltips, and logical flow significantly improves user experience and reduces the likelihood of errors.

Step-by-Step Workflow Example
Setup:
Add a MeshInstance3D to your scene (e.g., name it "CombinedMeshHost").
Attach the MaterialCombiner.gd script to "CombinedMeshHost".
Ensure your character model (e.g., a GLB import named "PlayerModel" which contains a MeshInstance3D named "body") is a child of "CombinedMeshHost", or "CombinedMeshHost" is a child of "PlayerModel"'s parent.
Configuration (in Inspector for "CombinedMeshHost"):
Set Target Mesh Name to "body" (or the name of your character's main mesh).
Adjust Atlas Target Size if needed (default is 2048).
If your model has collision:
Create an empty Node3D (e.g., "CopiedCollisions").
Set Collision Parent Path on "CombinedMeshHost" to point to "CopiedCollisions".
If your model is skinned:
Set Manual Skeleton Node Path to point to the Skeleton3D node for "PlayerModel".
Review other settings like Regenerate Normals And Tangents and Atlas Material Cull Mode.
Execution:
Check the Btn Combine And Atlas box in the Inspector.
Wait for the process to complete. Observe console output for progress and any errors.
The "CombinedMeshHost" node should now display the merged mesh.
New resources (_atlas.png, _atlas_mat.tres, _atlas_debug_direct.png) will be saved in the same directory as the script.
Review Results:
Inspect the "CombinedMeshHost" in the editor. Check for visual correctness.
If Collision Parent Path was set, check the "CopiedCollisions" node for the duplicated StaticBody3Ds (named like OriginalBodyName_coll_copy) and their CollisionShape3D children.
If Toggle Children Visibility is true, the original "PlayerModel" (or its relevant parts) might now be hidden.
Cleanup (If Needed):
To revert the changes on "CombinedMeshHost" and delete copied collisions, check the Btn Clean Result box.
Tips for Optimal Use & Best Practices
Texture Preparation:
For best results, try to use source textures that have a relatively consistent texel density (pixels per unit of surface area).
Merging materials with vastly different source texture resolutions can lead to some textures appearing blurrier or sharper than others in the final atlas. Understand these implications or rescale textures beforehand if consistency is paramount.
Ensure source textures are in a format and have import settings (e.g., compression type) suitable for atlasing. Lossless or high-quality compression is generally preferred for inputs.
Modular Assets: This tool is particularly effective with modular asset kits, where individual pieces are designed with the intention of eventually sharing materials or being combined.
Transparency:
The current script focuses on Albedo properties and does not explicitly detail advanced transparency handling (e.g., separate atlases for transparent surfaces, complex blend mode management). Merging opaque and transparent surfaces into a single material with one atlas can be problematic. It's often best to process them separately or ensure the generated material's transparency settings are manually adjusted if needed.
Normal Maps & Other PBR Maps: This script currently focuses on Albedo textures and colors. For merging other PBR maps (Normal, Roughness, Metallic, AO, Emission), the script would need to be extended to collect, pack, and set up these additional texture slots in the generated StandardMaterial3D.
Iteration and Batching:
Start by processing a small, representative group of objects to understand the tool's behavior and results before attempting to merge large, complex parts of your scene.
For very large scenes or numerous objects, process them in manageable batches to avoid excessive processing times or high memory usage.
Saving: Save your scene and project frequently, especially before initiating significant merge operations. Utilize version control (like Git) to safeguard your work.
Collision Copying: The collision copying feature duplicates StaticBody3D nodes and their shapes. It assumes collisions are primarily static. For RigidBody3D or CharacterBody3D, the approach might need adjustments or manual setup after merging. The copied StaticBody3D nodes will have _coll_copy appended to their names.
File Paths: Generated atlas texture, material, and debug image are saved in the same directory as the script itself. You may want to move these to an organized project asset folder afterwards.
Effective texture atlasing is more than just a mechanical process; it involves understanding certain trade-offs. Users might not intuitively grasp how to achieve the best balance between atlas resolution, wasted space, and potential artifacts. The goal of these tips is to educate on these underlying principles, moving beyond simple operational instructions to empower users to make informed decisions.

Atlas Configuration Parameters
This table details common parameters found in atlas generation tools. Refer to the specific UI of this plugin for exact names and availability.

Parameter	UI Element (Example)	Description	Default (Example)	Recommended Range/Values	Impact
Target Atlas Size	atlas_target_size (Inspector)	Target (and initial) resolution for the atlas width and height. Packer may adjust.	2048	512, 1024, 2048, 4096, 8192	Affects atlas resolution and ability to fit textures. Larger = more detail/space but more VRAM.
Color Block Size	color_block_size (Inspector)	Size in pixels for image blocks representing solid Albedo colors.	4	2-16	Small blocks for colors, larger values waste more atlas space if many unique colors.
Regenerate Normals/Tangents	regenerate_normals_and_tangents (Inspector)	If checked, new normals and tangents are generated for the combined mesh.	true	true/false	Useful if merging distorts shading or if source data is inconsistent.
Atlas Material Cull Mode	atlas_material_cull_mode (Inspector)	Sets the BaseMaterial3D.CullMode for the generated material.	CULL_BACK	CULL_BACK, CULL_FRONT, CULL_DISABLED	Determines which faces of the mesh are rendered.
Output Directory	N/A (Implicit)	Generated files are saved in the same directory as the script.	Script's directory	N/A	Helps organize generated assets and keep the project tidy.
Texture Compression	N/A (Implicit)	Output atlas is an ImageTexture from an Image, typically saved as PNG.	Lossless (PNG)	VRAM Comp.(BasisU/KTX)	Balances file size, VRAM usage, and quality. VRAM compression is crucial for runtime performance. Apply via Godot's import dock after generation.


6. Advanced Configuration / Technical Details
This section covers more advanced aspects of the tool, for users who need finer control or are working with complex scenarios.

ShaderMaterial Support Details:
The current script (MaterialCombiner.gd) is specifically designed to work with BaseMaterial3D and StandardMaterial3D for Albedo properties. It does not include explicit support for merging generic ShaderMaterial instances. Merging arbitrary ShaderMaterials is significantly more complex as it would require parsing shader code, managing varying uniforms, and potentially combining shader logic, which is beyond the scope of this tool.
Texture Channel Packing Logic:
The script currently focuses on Albedo textures (albedo_texture) and Albedo colors (albedo_color).
Albedo textures are used as is.
Albedo colors are converted into small, solid-color Image blocks of color_block_size x color_block_size.
These images (from textures and colors) are then packed into a single RGBA8 atlas. The generated StandardMaterial3D uses this atlas in its Albedo texture slot and sets its Albedo color to white (to avoid tinting the atlas).
For other PBR maps (Normal, ORM, Emission), the script would need to be extended.
Collision Copying Logic:
The copy_collisions_recursive function scans for StaticBody3D nodes. It starts its scan from the parent of the target_mesh_name node. If the target_mesh_name node has no parent (e.g., it's the root of its own imported scene branch), the scan starts from the target_mesh_name node itself.
It duplicates the StaticBody3D (including its collision layer/mask and global transform) and its child CollisionShape3Ds (duplicating their shapes and local transforms) into the node specified by collision_parent_path.
Copied StaticBody3D nodes are named with an _coll_copy suffix.
Custom Scripting/Automation Hooks:
The primary way to trigger the tool is via its exported boolean properties (btn_combine_and_atlas, btn_clean_result) in the Inspector. These could potentially be set from another GDScript in an editor tool context:

# Assuming 'merger_node' is a reference to the MeshInstance3D with the MaterialCombiner.gd script
# To trigger combine:
# merger_node.set("btn_combine_and_atlas", true)
# To trigger clean:
# merger_node.set("btn_clean_result", true)
Directly calling functions like combine_and_atlas(true) from another script in the editor should also work, provided the necessary properties (target_mesh_name, etc.) are set up on the node.
Performance Considerations of the Tool Itself:
"The process of merging materials, packing textures, and especially remapping UVs for very complex meshes or a large number of high-resolution textures can be computationally intensive. This may result in significant processing time and memory consumption by the Godot editor during the operation."
"It is recommended to process assets in manageable batches rather than attempting to merge an entire complex scene in a single operation."
"Close other resource-intensive applications while using the tool on large datasets to ensure Godot has sufficient system resources."
7. Troubleshooting / FAQ
This section addresses common issues and frequently asked questions.

Common Issues and Solutions
Problem	Potential Cause(s)	Suggested Solution(s)
Textures look blurry or pixelated after merging.	Atlas resolution (atlas_target_size) too low. Original textures were low resolution. Inappropriate texture import settings in Godot.	Increase atlas_target_size. Ensure source textures are of adequate quality. Check Godot's import settings for the generated atlas (e.g., filter mode).
Visible seams or artifacts at UV edges.	Packer places textures too close (no explicit padding parameter in this script). UV precision issues. Mesh UVs might have issues.	The script uses a basic grid packer; if bleeding occurs, you might need to modify the packer or manually ensure textures have some empty border. Ensure source mesh UVs are clean.
Plugin panel/window doesn't appear.	Script not attached to a MeshInstance3D. Godot Engine version incompatibility. Errors during script initialization.	Ensure the script is attached to a MeshInstance3D node. Its properties will be in the Inspector. Confirm Godot 4.x. Check Godot editor's console output for errors.
Merging process is very slow or Godot freezes/crashes.	Processing very complex target_mesh_name. Very large source textures. Insufficient system RAM.	Simplify the target mesh if possible before merging. Optimize texture sizes. Ensure adequate RAM and close other demanding applications.
Transparent objects don't look right after merging.	Script primarily handles Albedo, advanced transparency (blend modes, separate atlases) not explicitly managed. Merged material's blend mode not set correctly.	This script is basic for Albedo. For complex transparency, manual material adjustment or a more advanced tool might be needed. Ensure the final merged material has the correct blend mode and transparency settings if you adapt it.
Output material/texture not saved or saved to wrong location.	Script saves files in its own directory. File system permission issues.	Generated files (_atlas.png, _atlas_mat.tres, _atlas_debug_direct.png) are saved alongside MaterialCombiner.gd. Check for console errors if saving fails.
Collisions are not copied, or copied incorrectly.	collision_parent_path not set or points to an invalid node. Original model has no StaticBody3D where the script expects to find them (parent of target_mesh_name). Collision structure is not StaticBody3D -> CollisionShape3D.	Ensure collision_parent_path is correctly set to an existing Node3D. Verify your original model's collision setup; the script looks for StaticBody3Ds in the parent of target_mesh_name. Check console for warnings.
Skinned mesh is distorted or not working after merge.	manual_skeleton_node_path not set or incorrect. Original mesh lacks bone/weight data or it's in an unexpected format. Complex skinning.	Ensure manual_skeleton_node_path points to the correct Skeleton3D. Check original mesh data. The script makes a best effort but complex skinning might require manual adjustments.


FAQ
Q: Can I merge materials that use different custom shaders (ShaderMaterial)?
A: No, MaterialCombiner.gd is specifically designed for BaseMaterial3D and StandardMaterial3D, focusing on their Albedo properties. It does not support merging generic ShaderMaterials.
Q: Does this tool work with 2D sprites or CanvasItem materials?
A: No, this tool is specifically designed for optimizing 3D assets, operating on MeshInstance3D nodes and their associated 3D materials. For 2D sprite sheet generation or CanvasItem material optimization, Godot provides built-in features like SpriteFrames, AtlasTexture resources, or dedicated 2D atlasing tools.
Q: What happens to my original materials and meshes when I use this tool?
A: The script modifies the MeshInstance3D node it is attached to, assigning it the new combined mesh and material. If the target_mesh_name is a child of this node's parent, the toggle_children_visibility option may hide the original. The btn_clean_result action attempts to revert these changes. The delete_child_meshes_on_play option will remove the original target at runtime. It's always good practice to work with version control (like Git) or on duplicates.
Q: How does the tool decide on final material properties if the source materials have different values (e.g., different albedo colors)?
A: This script processes each surface of the target_mesh_name individually. If a surface uses an Albedo texture, that texture is added to the atlas. If it uses an Albedo color, that color is converted to a small image block and added to the atlas. All these are combined into one atlas, and the final merged mesh uses this single atlas. The generated material has its Albedo color set to white to correctly display the atlas. It doesn't "merge" properties like averaging colors between different original materials in the traditional sense; rather, it preserves each original surface's Albedo appearance by mapping it to a region in the atlas.
Q: Can the generated atlas texture be compressed?
A: The script saves the atlas as a .png file from an ImageTexture. After generation, you can re-import this .png into Godot and apply VRAM compression (like Basis Universal or S3TC/ETC) via Godot's import dock settings for optimal in-game performance.
Q: Why do my copied collision bodies have _coll_copy in their names?
A: This naming convention (OriginalName_coll_copy) is used for StaticBody3D nodes duplicated by the collision copying feature. It helps distinguish them from original collision bodies in the scene and allows the btn_clean_result function to identify and remove only the copied collision objects.
Q: Where does the script look for original collisions to copy?
A: When collision_parent_path is set, the script first looks at the parent node of the MeshInstance3D specified by target_mesh_name. It searches this parent and its children for StaticBody3D nodes to copy. If the target_mesh_name node has no parent, the script will scan the target_mesh_name node itself and its children.
8. Contributing

Reporting Bugs:
If you encounter a bug, please open an issue on the GitHub Issues Page for this repository.
In your bug report, please include:
The Godot Engine version you are using.
The version of the Material Merger & Atlas Optimizer plugin/script.
Clear, step-by-step instructions to reproduce the bug.
The behavior you expected.
The actual behavior you observed.
Screenshots, error messages from the Godot console, or a minimal reproduction project (a small Godot project demonstrating the issue) are extremely helpful.
Suggesting Features:
Feature requests and ideas for enhancements are welcome. Please submit them as an issue on the GitHub Issues Page.
Provide a clear explanation of the proposed feature, its potential benefits, and any relevant use cases.
Submitting Pull Requests (Code Contributions):
If you'd like to contribute directly to the codebase (e.g., bug fixes, new features):
Fork the repository (if available on a platform like GitHub).
Create a new branch in your fork for your feature or bugfix (e.g., git checkout -b feature/my-new-feature or bugfix/issue-123).
Commit your changes to your branch.
Ensure your code adheres to the existing code style (e.g., follow the official GDScript style guide).
Thoroughly test your changes to ensure they work as expected and do not introduce regressions.
Submit a pull request from your branch to the main repository's main or develop branch. Provide a clear description of your changes in the pull request.
Well-defined contribution pathways encourage community involvement, which can significantly enhance the tool's quality, feature set, and longevity.


10. Acknowledgements
Author: This tool was created and is maintained by Makhi Burroughs (GitHub: necat101, Discord: netcat7).

@tool
extends EditorPlugin

var export_plugin: PleosVehicleExportPlugin


func _enter_tree() -> void:
	export_plugin = PleosVehicleExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


# Adds the Android pieces of the plugin to the exported APK:
# the AAR, the Vehicle SDK dependency, the CAR_DOORS permission and the plugin entry.
class PleosVehicleExportPlugin extends EditorExportPlugin:

	func _get_name() -> String:
		return "PleosVehicle"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		# Paths are relative to res://addons/
		return PackedStringArray(["pleos_vehicle/PleosVehicle.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["ai.pleos.playground:Vehicle:2.3.2"])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["https://nexus-playground.pleos.ai/repository/maven-releases/"])

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<uses-permission android:name="pleos.car.permission.CAR_DOORS" />'

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="org.godotengine.plugin.v2.PleosVehicle" android:value="com.gleo.mafia.pleos.PleosVehiclePlugin" />'

package com.gleo.mafia.pleos

import ai.pleos.playground.vehicle.Vehicle
import ai.pleos.playground.vehicle.api.model.area.DoorArea
import ai.pleos.playground.vehicle.constant.area.DoorValue
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot Android plugin that wraps the Pleos Connect Vehicle SDK.
 *
 * GDScript usage:
 *   var pleos = Engine.get_singleton("PleosVehicle")
 *   pleos.initializeVehicle()
 *   pleos.getCurrentDoorPosition()   # answers via the signals below
 */
class PleosVehiclePlugin(godot: Godot) : GodotPlugin(godot) {

    private var vehicle: Vehicle? = null

    override fun getPluginName(): String = "PleosVehicle"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("door_position_result", Int::class.javaObjectType),
        SignalInfo("door_position_failed", String::class.java)
    )

    /** Creates the Vehicle SDK client and starts connecting to the vehicle service. Safe to call more than once. */
    @UsedByGodot
    fun initializeVehicle() {
        if (vehicle != null) return
        val act = activity ?: return
        vehicle = Vehicle(act).also { it.initialize() }
    }

    /** Reads the front-left door position. Emits door_position_result on success, door_position_failed on error. */
    @UsedByGodot
    fun getCurrentDoorPosition() {
        initializeVehicle()
        val client = vehicle
        if (client == null) {
            emitFailure("Vehicle SDK is not available (no activity)")
            return
        }
        client.getDoor().getCurrentDoorPosition(
            DoorArea(DoorValue.ROW_1_LEFT),
            { position -> runOnMain { emitSignal("door_position_result", position ?: -1) } },
            { error -> emitFailure(error.message ?: error.toString()) }
        )
    }

    private fun emitFailure(message: String) {
        runOnMain { emitSignal("door_position_failed", message) }
    }

    private fun runOnMain(block: () -> Unit) {
        val act = activity
        if (act == null) block() else act.runOnUiThread(block)
    }
}

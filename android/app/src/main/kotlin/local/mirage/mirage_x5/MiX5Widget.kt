package local.mirage.mirage_x5

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MiX5Widget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        val snapshot = try { JSONObject(data.getString("snapshot", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        val dps = snapshot.optJSONObject("dps") ?: JSONObject()
        val configured = snapshot.optBoolean("configured")
        val busy = snapshot.optBoolean("busy")
        val available = configured && !busy && dps.has("1")
        val temperature = if (dps.has("2")) dps.optInt("2").toString() else "—"
        val power = dps.optBoolean("1")
        val modes = mapOf("cold" to "Frío", "auto" to "Auto", "wet" to "Seco", "wind" to "Ventilación")
        val fans = mapOf("auto" to "Auto", "mute" to "Silencioso", "low" to "Bajo", "middle" to "Medio", "high" to "Alto", "strong" to "Turbo")
        val updated = snapshot.optLong("updated")
        val status = when {
            !configured -> "Configura Mi X5 en la app"
            busy -> "Sincronizando…"
            !snapshot.isNull("message") -> snapshot.optString("message")
            updated > 0 -> "Actualizado " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(updated))
            else -> "Toca para actualizar"
        }
        val launch = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.mi_x5_widget)
            views.setTextViewText(R.id.widget_ambient, if (dps.has("3")) "Habitación ${dps.optInt("3")}°C" else "Habitación —°C")
            views.setTextViewText(R.id.widget_temperature, "$temperature°C")
            views.setTextViewText(R.id.widget_display_temperature, temperature)
            views.setTextColor(R.id.widget_display_temperature, Color.parseColor(if (power && dps.optBoolean("36")) "#FFFFFF" else "#68746E"))
            views.setTextViewText(R.id.widget_mode_value, modes[dps.optString("4")] ?: "—")
            views.setTextViewText(R.id.widget_fan_value, fans[dps.optString("5")] ?: "—")
            views.setTextViewText(R.id.widget_status, status)
            views.setOnClickPendingIntent(R.id.widget_open, launch)
            for ((view, action) in mapOf(
                R.id.widget_power to "power", R.id.widget_down to "down", R.id.widget_up to "up",
                R.id.widget_mode to "mode", R.id.widget_fan to "fan", R.id.widget_sleep to "sleep",
                R.id.widget_swing to "swing", R.id.widget_display to "display", R.id.widget_refresh to "refresh"
            )) {
                val enabled = when (action) {
                    "refresh" -> true // Lets a refresh recover from an interrupted background job.
                    "sleep" -> available && dps.has("25")
                    "swing" -> available && dps.has("31")
                    "display" -> available && power && dps.has("36")
                    else -> available
                }
                views.setBoolean(view, "setEnabled", enabled)
                views.setFloat(view, "setAlpha", if (enabled) 1f else .45f)
                views.setOnClickPendingIntent(view, if (!configured) launch else WidgetCommandService.pendingIntent(context, Uri.parse("mix5://widget/$action")))
            }
            for ((view, active) in mapOf(R.id.widget_power to power, R.id.widget_sleep to dps.optBoolean("25"), R.id.widget_swing to (dps.optString("31") == "same"))) {
                views.setInt(view, "setColorFilter", Color.parseColor(if (active) "#FFFFFF" else "#AAA68E"))
            }
            views.setContentDescription(R.id.widget_power, if (power) "Apagar minisplit" else "Encender minisplit")
            views.setContentDescription(R.id.widget_sleep, if (dps.optBoolean("25")) "Desactivar Sueño" else "Activar Sueño")
            views.setContentDescription(R.id.widget_swing, if (dps.optString("31") == "same") "Detener oscilación vertical" else "Activar oscilación vertical")
            manager.updateAppWidget(id, views)
        }
    }
}

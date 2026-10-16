package local.mirage.mirage_x5

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.ArrayDeque

/** A widget tap starts a temporary foreground task so Android keeps LAN access alive. */
class WidgetCommandService : Service() {
    private val queue = ArrayDeque<String>()
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var startId = 0
    private val deadline = Runnable {
        reportFailure("No hubo respuesta · toca para reintentar")
        finishAction()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, id: Int): Int {
        val uri = intent?.data
        if (uri?.scheme != "mix5" || uri.host != "widget" || uri.pathSegments.size != 1 || uri.lastPathSegment !in actions) {
            if (engine == null && queue.isEmpty()) stopSelf(id)
            return START_NOT_STICKY
        }
        startId = id
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(channelId, "Control del minisplit", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.widget_swing).setContentTitle("Mi X5")
            .setContentText("Sincronizando minisplit…").setOngoing(true).setOnlyAlertOnce(true).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(1815, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(1815, notification)
        queue.add(uri.toString())
        runNext()
        return START_NOT_STICKY
    }

    private fun runNext() {
        if (engine != null || queue.isEmpty()) return
        val uri = queue.removeFirst()
        handler.postDelayed(deadline, 20000)
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val current = FlutterEngine(applicationContext)
            engine = current
            MethodChannel(current.dartExecutor.binaryMessenger, "mi_x5/widget_service").setMethodCallHandler { call, result ->
                if (call.method == "completed") {
                    result.success(null)
                    handler.post { if (engine === current) finishAction() }
                } else result.notImplemented()
            }
            current.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(), "package:mirage_x5/home_widget.dart", "widgetServiceMain"
            ), listOf(uri))
        } catch (_: Exception) {
            reportFailure("No se pudo enviar · toca para reintentar")
            finishAction()
        }
    }

    private fun reportFailure(message: String) {
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val snapshot = try { JSONObject(prefs.getString("snapshot", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        snapshot.put("busy", false).put("message", message)
        prefs.edit().putString("snapshot", snapshot.toString()).apply()
        val manager = AppWidgetManager.getInstance(this)
        MiX5Widget().onUpdate(this, manager, manager.getAppWidgetIds(ComponentName(this, MiX5Widget::class.java)), prefs)
    }

    private fun finishAction() {
        handler.removeCallbacks(deadline)
        engine?.destroy()
        engine = null
        if (queue.isEmpty()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelfResult(startId)
        } else runNext()
    }

    override fun onDestroy() {
        handler.removeCallbacks(deadline)
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    companion object {
        private const val channelId = "mi_x5_widget_sync"
        private val actions = setOf("refresh", "power", "down", "up", "mode", "fan", "sleep", "swing", "display")
        fun pendingIntent(context: Context, uri: Uri): PendingIntent {
            val intent = Intent(context, WidgetCommandService::class.java).setData(uri)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(context, 0, intent, flags)
                else PendingIntent.getService(context, 0, intent, flags)
        }
    }
}

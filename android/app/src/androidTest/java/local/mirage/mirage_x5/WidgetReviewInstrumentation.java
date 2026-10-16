package local.mirage.mirage_x5;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.PendingIntent;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.TextView;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;

/** Uses a fresh emulator, public broadcasts and display snapshots; never creates a device connection. */
public class WidgetReviewInstrumentation extends Instrumentation {
    private boolean network;
    private boolean offline;
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        network = arguments != null && "true".equals(arguments.getString("network"));
        offline = arguments != null && "true".equals(arguments.getString("offline"));
        start();
    }
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            require(android.os.Build.HARDWARE.equals("ranchu") || android.os.Build.HARDWARE.equals("goldfish"), "Use a fresh emulator");
            getUiAutomation().adoptShellPermissionIdentity("android.permission.BIND_APPWIDGET");
            Context context = getTargetContext();
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            AppWidgetHost host = new AppWidgetHost(context, 1505);
            int id = host.allocateAppWidgetId();
            ComponentName component = new ComponentName(context.getPackageName(), "local.mirage.mirage_x5.MiX5Widget");
            require(manager.bindAppWidgetIdIfAllowed(id, component), "Could not bind widget");
            SharedPreferences data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE);
            int temperatureId = context.getResources().getIdentifier("widget_temperature", "id", context.getPackageName());
            int statusId = context.getResources().getIdentifier("widget_status", "id", context.getPackageName());
            String initial = "{\"configured\":true,\"busy\":false,\"updated\":1791860400000,\"message\":null,\"dps\":{\"1\":true,\"2\":23,\"3\":28,\"4\":\"cold\",\"5\":\"auto\",\"25\":true,\"31\":\"same\",\"36\":true}}";
            AppWidgetHostView[] view = new AppWidgetHostView[1];
            runOnMainSync(() -> {
                host.startListening();
                view[0] = host.createView(context, id, manager.getAppWidgetInfo(id));
            });
            String[] names = {"widget-controls", "widget-busy", "widget-offline"};
            String[] snapshots = {initial, new JSONObject(initial).put("busy", true).toString(), new JSONObject(initial).put("message", "Sin conexión · toca para reintentar").toString()};
            String[] expected = {"23°C", "Sincronizando…", "Sin conexión · toca para reintentar"};
            for (int index = 0; index < names.length; index++) {
                final int i = index;
                data.edit().putString("snapshot", snapshots[i]).commit();
                context.sendBroadcast(new Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(component).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, new int[] {id}));
                Thread.sleep(500);
                runOnMainSync(() -> {
                    AppWidgetHostView widget = view[0];
                    require(widget.findViewById(temperatureId) != null, "RemoteViews inflation failed");
                    TextView text = widget.findViewById(i == 0 ? temperatureId : statusId);
                    require(text.getText().toString().equals(expected[i]), "Unexpected widget state: " + text.getText());
                    float density = context.getResources().getDisplayMetrics().density;
                    int width = (int) (360 * density), height = (int) (300 * density);
                    widget.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
                    widget.layout(0, 0, width, height);
                    Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
                    widget.draw(new Canvas(bitmap));
                    try (FileOutputStream stream = new FileOutputStream(new File(context.getExternalFilesDir(null), names[i] + ".png"))) {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
                    } catch (java.io.IOException error) { throw new AssertionError(error); }
                    bitmap.recycle();
                });
            }
            if (network) {
                // The app was configured through its normal UI with 10.0.2.2 and the simulator's dummy key.
                String[] controls = {"widget_refresh", "widget_power", "widget_mode", "widget_fan", "widget_down", "widget_up", "widget_sleep", "widget_swing", "widget_display"};
                String[] dp = {"1", "1", "4", "5", "2", "2", "25", "31", "36"};
                Object[] values = {true, false, "auto", "mute", 22, 23, true, "same", true};
                // The display button is disabled while off; finish with power on, then display off.
                for (int i = 0; i < 8; i++) {
                    final int viewId = context.getResources().getIdentifier(controls[i], "id", context.getPackageName());
                    runOnMainSync(() -> require(view[0].findViewById(viewId).performClick(), "Widget click not handled"));
                    JSONObject current = null;
                    boolean busySeen = false;
                    long oldUpdate = new JSONObject(data.getString("snapshot", "{}")).optLong("updated");
                    for (int attempt = 0; attempt < 80; attempt++) {
                        Thread.sleep(100);
                        current = new JSONObject(data.getString("snapshot", "{}"));
                        busySeen |= current.optBoolean("busy");
                        if (!current.optBoolean("busy") && current.isNull("message") && current.optLong("updated") > oldUpdate && values[i].equals(current.optJSONObject("dps").opt(dp[i]))) break;
                    }
                    require(busySeen, "No asynchronous action observed for " + controls[i]);
                    require(current != null && !current.optBoolean("busy") && current.isNull("message") && values[i].equals(current.optJSONObject("dps").opt(dp[i])), "Network action failed: " + controls[i]);
                }
                runOnMainSync(() -> view[0].findViewById(context.getResources().getIdentifier("widget_power", "id", context.getPackageName())).performClick());
                waitForState(data, "1", true);
                Thread.sleep(300);
                runOnMainSync(() -> view[0].findViewById(context.getResources().getIdentifier("widget_display", "id", context.getPackageName())).performClick());
                waitForState(data, "36", false);
            } else {
                data.edit().putString("snapshot", initial).commit();
                Intent intent = new Intent().setComponent(new ComponentName(context.getPackageName(), "local.mirage.mirage_x5.WidgetCommandService"))
                    .setData(Uri.parse("mix5://widget/refresh"));
                PendingIntent.getForegroundService(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE).send();
                boolean completed = false;
                for (int i = 0; i < 120; i++) {
                    Thread.sleep(100);
                    JSONObject current = new JSONObject(data.getString("snapshot", "{}"));
                    if (offline ? (!current.optBoolean("busy") && current.optString("message").contains("Sin conexión")) : !current.optBoolean("configured")) completed = true;
                }
                require(completed, "Foreground Dart action did not complete");
            }
            android.app.ActivityManager activity = (android.app.ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
            boolean stopped = false;
            for (int i = 0; i < 30; i++) {
                Thread.sleep(100);
                stopped = true;
                for (android.app.ActivityManager.RunningServiceInfo service : activity.getRunningServices(100)) {
                    if (service.service.getClassName().equals("local.mirage.mirage_x5.WidgetCommandService")) stopped = false;
                }
                if (stopped) break;
            }
            require(stopped, "Widget foreground service stayed running after completion");
            runOnMainSync(() -> { host.stopListening(); host.deleteAppWidgetId(id); });
            getUiAutomation().dropShellPermissionIdentity();
            result.putString("result", "PASS: widget states and " + (network ? "10 encrypted LAN actions through real widget clicks" : offline ? "LAN failure recovers without getting stuck" : "headless secure-storage callback"));
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("result", "FAIL: " + error.getClass().getSimpleName() + ": " + error.getMessage());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
    private static void waitForState(SharedPreferences data, String dp, Object value) throws Exception {
        for (int i = 0; i < 100; i++) {
            Thread.sleep(100);
            JSONObject snapshot = new JSONObject(data.getString("snapshot", "{}"));
            if (!snapshot.optBoolean("busy") && snapshot.isNull("message") && value.equals(snapshot.optJSONObject("dps").opt(dp))) return;
        }
        throw new AssertionError("State not confirmed: " + dp);
    }
}

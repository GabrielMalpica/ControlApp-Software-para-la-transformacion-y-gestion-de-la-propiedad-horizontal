package co.com.controlsas.controlapp

import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Reloj que no cambia si el operario mueve la hora del celular: los
        // milisegundos desde que se encendió (lib/service/reloj_confiable.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "controlapp/reloj")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                    else -> result.notImplemented()
                }
            }
    }
}

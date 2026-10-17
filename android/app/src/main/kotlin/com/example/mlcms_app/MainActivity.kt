package com.example.mlcms_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // The channel the server sends alerts to, set to pop up on screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "mlcms_alerts",
                "Cold-chain alerts",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Temperature breaches and escalations"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
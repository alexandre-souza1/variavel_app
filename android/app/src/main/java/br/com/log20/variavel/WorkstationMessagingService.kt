package br.com.log20.variavel

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class WorkstationMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences("push", 0).edit().putString("fcm_token", token).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val user = getSharedPreferences("push", 0).getString("user", null) ?: return
        if (user != message.data["user_id"]) return
        val id = message.data["notification_id"] ?: return
        if (!id.matches(Regex("[1-9][0-9]*"))) return
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.push_channel), NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("notification_id", id)
            putExtra("notification_user", user)
            data = android.net.Uri.parse("workstation://notification/$id")
        }
        val pending = PendingIntent.getActivity(this, id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val title = message.data["title"]?.takeIf { it.isNotBlank() } ?: getString(R.string.app_name)
        val body = message.data["body"]?.takeIf { it.isNotBlank() } ?: getString(R.string.push_message)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build()
        manager.notify("workstation-$id", id.hashCode(), notification)
    }

    companion object { const val CHANNEL = "workstation_notifications" }
}

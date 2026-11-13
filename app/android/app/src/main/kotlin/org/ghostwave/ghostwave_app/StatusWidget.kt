package org.ghostwave.ghostwave_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget: the radio link and what needs attention (unread, overdue
 * trip contacts, SOS), with Check in and SOS buttons that open the app there.
 * The app pushes the text whenever it changes; the widget only shows it.
 */
class StatusWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context, manager, ids)

    companion object {
        fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val (status, detail, alert) = HomeSurfaces.widgetText(context)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.ghostwave_widget)
                views.setTextViewText(R.id.widget_status, status)
                views.setTextViewText(R.id.widget_detail, detail)
                views.setViewVisibility(R.id.widget_detail, if (detail.isEmpty()) View.GONE else View.VISIBLE)
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundResource",
                    if (alert) R.drawable.widget_background_alert else R.drawable.widget_background,
                )
                views.setOnClickPendingIntent(R.id.widget_root, open(context, "chats", 1))
                views.setOnClickPendingIntent(R.id.widget_checkin, open(context, "checkin", 2))
                views.setOnClickPendingIntent(R.id.widget_sos, open(context, "sos", 3))
                manager.updateAppWidget(id, views)
            }
        }

        private fun open(context: Context, action: String, code: Int): PendingIntent = PendingIntent.getActivity(
            context,
            code,
            HomeSurfaces.openIntent(context, action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

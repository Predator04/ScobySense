package com.scobysense.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ScobySenseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_scobysense).apply {
                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("name", null) ?: "ScobySense",
                )
                setTextViewText(
                    R.id.widget_f1,
                    widgetData.getString("f1", null) ?: "F1: --",
                )
                setTextViewText(
                    R.id.widget_f2,
                    widgetData.getString("f2", null) ?: "F2: --",
                )
                setTextViewText(
                    R.id.widget_updated,
                    widgetData.getString("updated", null) ?: "Open ScobySense",
                )

                val launch = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                )
                setOnClickPendingIntent(R.id.widget_root, launch)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

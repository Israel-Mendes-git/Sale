package com.israelmendes.sale

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// O widget "Chamar o grupo" da tela inicial: um toque e o app abre direto no
/// Chamado do grupo. Faz o mesmo que o atalho de segurar o ícone, e por isso
/// abre o app com o mesmo extra que o plugin quick_actions lê
/// (QuickActions.EXTRA_ACTION): do lado do Flutter, os dois são um toque só
/// (lib/push/atalhos.dart).
class WidgetChamar : AppWidgetProvider() {
    override fun onUpdate(contexto: Context, gerente: AppWidgetManager, ids: IntArray) {
        val abrir = contexto.packageManager
            .getLaunchIntentForPackage(contexto.packageName)!!
            .setAction(Intent.ACTION_RUN)
            .putExtra(EXTRA_DO_ATALHO, ATALHO_CHAMAR_GRUPO)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val toque = PendingIntent.getActivity(
            contexto,
            0,
            abrir,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in ids) {
            val vista = RemoteViews(contexto.packageName, R.layout.widget_chamar)
            vista.setOnClickPendingIntent(R.id.widget_chamar, toque)
            gerente.updateAppWidget(id, vista)
        }
    }

    companion object {
        /// O nome do extra no plugin quick_actions_android. Se o plugin mudar,
        /// o widget passa a só abrir o app.
        const val EXTRA_DO_ATALHO = "some unique action key"

        /// O mesmo valor de atalhoChamarGrupo, em lib/push/atalhos.dart.
        const val ATALHO_CHAMAR_GRUPO = "chamar_grupo"
    }
}

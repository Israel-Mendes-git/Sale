package com.israelmendes.sale

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// O som que o grupo subiu precisa de um endereço que o Android consiga ler
/// sozinho: quem toca a notificação é o sistema, não o app, e ele não entra na
/// pasta privada do aplicativo. Registrar o arquivo no acervo de sons do
/// aparelho (MediaStore) devolve esse endereço, e é dele que nasce o canal de
/// notificação daquele som.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "sale/sons")
            .setMethodCallHandler { chamada, resposta ->
                when (chamada.method) {
                    "registrar" ->
                        resposta.success(registrar(chamada.arguments as String))
                    else -> resposta.notImplemented()
                }
            }
    }

    /// Põe o arquivo no acervo de sons de notificação e devolve o endereço
    /// (`content://…`). Nulo quando não deu: Android antigo, onde isso pediria
    /// acesso a todos os arquivos do aparelho, ou arquivo que sumiu. Nesses
    /// casos o Chamado toca o som da marca.
    private fun registrar(caminho: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val arquivo = File(caminho)
        if (!arquivo.exists()) return null

        val acervo =
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

        // Já registrado numa abertura anterior: reaproveita em vez de encher o
        // acervo de cópias do mesmo som.
        contentResolver.query(
            acervo,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DISPLAY_NAME} = ?",
            arrayOf(arquivo.name),
            null,
        )?.use { busca ->
            if (busca.moveToFirst()) {
                val id = busca.getLong(0)
                return acervo.buildUpon().appendPath(id.toString()).build().toString()
            }
        }

        val dados = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, arquivo.name)
            put(MediaStore.Audio.Media.MIME_TYPE, tipo(arquivo.name))
            put(MediaStore.Audio.Media.RELATIVE_PATH, "Notifications/Sale")
            put(MediaStore.Audio.Media.IS_NOTIFICATION, 1)
            put(MediaStore.Audio.Media.IS_MUSIC, 0)
        }
        val endereco = contentResolver.insert(acervo, dados) ?: return null
        return try {
            contentResolver.openOutputStream(endereco)!!.use { saida ->
                arquivo.inputStream().use { entrada -> entrada.copyTo(saida) }
            }
            endereco.toString()
        } catch (erro: Exception) {
            // Entrada pela metade não serve de som: sai do acervo.
            contentResolver.delete(endereco, null, null)
            null
        }
    }

    private fun tipo(nome: String) =
        when (nome.substringAfterLast('.', "").lowercase()) {
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "m4a", "aac" -> "audio/mp4"
            else -> "audio/ogg"
        }
}

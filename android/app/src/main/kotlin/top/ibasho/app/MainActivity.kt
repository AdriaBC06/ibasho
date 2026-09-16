// Ibasho — actividad de Android.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

package top.ibasho.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * La unica actividad. Ademas de Flutter, expone lo que ningun plugin de la app
 * cubre y el sistema necesita saber o decir: el foco de audio, que se pide y
 * se suelta, y que avisa cuando otra app se lo queda.
 *
 * Todo lo que suena en Ibasho —musica, efectos y voces— es audio de medios,
 * asi que el modo del timbre no pinta nada aqui: en silencio el sistema calla
 * el tono y las notificaciones, no el juego, igual que no calla un video.
 *
 * Canal de metodos `top.ibasho.app/system`: `requestAudioFocus` (bool) y
 * `abandonAudioFocus`. Canal de eventos `top.ibasho.app/system/events`: mapas
 * `{"focus": gain | loss | lossTransient | duck}`.
 */
class MainActivity : FlutterActivity() {
    private lateinit var audio: AudioManager
    private var events: EventChannel.EventSink? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val name = when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> "gain"
            AudioManager.AUDIOFOCUS_LOSS -> "loss"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "lossTransient"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "duck"
            else -> return@OnAudioFocusChangeListener
        }
        hasFocus = change == AudioManager.AUDIOFOCUS_GAIN
        events?.success(mapOf("focus" to name))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "top.ibasho.app/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioFocus" -> result.success(requestFocus())
                "abandonAudioFocus" -> {
                    abandonFocus()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "top.ibasho.app/system/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            },
        )
    }

    override fun onDestroy() {
        abandonFocus()
        super.onDestroy()
    }

    private fun requestFocus(): Boolean {
        if (hasFocus) return true
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(false)
                .build()
                .also { focusRequest = it }
            audio.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        hasFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    private fun abandonFocus() {
        if (!hasFocus) return
        hasFocus = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusListener)
        }
    }
}

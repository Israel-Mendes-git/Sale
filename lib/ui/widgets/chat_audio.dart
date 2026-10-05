import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import 'chat_image.dart';

String _mmss(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  return '${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// O recado de voz de uma mensagem: tocar/pausar, uma barra que anda e o tempo.
///
/// O arquivo é baixado uma vez por aparelho (como a imagem) e, enquanto não
/// chega, a bolha já mostra a duração que a mensagem guarda. Cada bolha tem o
/// próprio player, fechado junto com ela.
class ChatAudio extends ConsumerStatefulWidget {
  const ChatAudio({super.key, required this.attachment, required this.mine});

  final Attachment attachment;
  final bool mine;

  @override
  ConsumerState<ChatAudio> createState() => _ChatAudioState();
}

class _ChatAudioState extends ConsumerState<ChatAudio> {
  final _player = AudioPlayer();
  var _playing = false;
  var _position = Duration.zero;
  Duration? _total;

  @override
  void initState() {
    super.initState();
    final segundos = widget.attachment.duration;
    if (segundos != null) _total = Duration(seconds: segundos);
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle(Uint8List bytes) async {
    if (_playing) {
      await _player.pause();
    } else if (_position == Duration.zero) {
      await _player.play(BytesSource(bytes));
    } else {
      await _player.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(attachmentProvider(widget.attachment.path));
    final cor = widget.mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final total = _total ?? Duration.zero;
    final progresso = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    // Enquanto toca, o tempo conta para trás; parado, mostra a duração cheia.
    final mostra = _position > Duration.zero ? total - _position : total;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          switch (bytes) {
            AsyncData(:final value) => IconButton(
              tooltip: _playing ? 'Pausar' : 'Tocar',
              iconSize: 40,
              color: cor,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
              onPressed: () => _toggle(value),
            ),
            AsyncError() => IconButton(
              tooltip: 'Tentar de novo',
              iconSize: 40,
              color: cor,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.invalidate(attachmentProvider(widget.attachment.path)),
            ),
            _ => SizedBox.square(
              dimension: 40,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: CircularProgressIndicator(strokeWidth: 2, color: cor),
              ),
            ),
          },
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic, size: 14, color: cor),
                    const SizedBox(width: 2),
                    Text('Recado', style: TextStyle(fontSize: 12, color: cor)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progresso,
                    color: cor,
                    backgroundColor: cor.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_mmss(mostra), style: TextStyle(fontSize: 12, color: cor)),
        ],
      ),
    );
  }
}

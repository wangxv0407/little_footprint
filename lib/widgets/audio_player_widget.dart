import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// 简易音频播放器（播放/暂停、进度条）
class AudioPlayerWidget extends StatefulWidget {
  final String filePath;
  const AudioPlayerWidget({super.key, required this.filePath});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) => setState(() => _duration = d));
    _player.onPositionChanged.listen((p) => setState(() => _position = p));
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state == PlayerState.playing;
        _loading = state == PlayerState.loading;
      });
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.setSource(DeviceFileSource(widget.filePath));
        await _player.resume();
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final pos = _position.inMilliseconds.clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4A7C77).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              _loading
                  ? Icons.hourglass_top
                  : _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
              color: const Color(0xFF4A7C77),
              size: 34,
            ),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: total <= 0 ? 1 : total.toDouble(),
              value: pos.toDouble().clamp(0.0, total <= 0 ? 1 : total.toDouble()),
              activeColor: const Color(0xFF4A7C77),
              onChanged: total <= 0
                  ? null
                  : (v) => _player.seek(Duration(milliseconds: v.round())),
            ),
          ),
          Text(
            '${_fmt(_position)} / ${_fmt(_duration)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF707070)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Preview the position locally while dragging, but request one seek only
/// after the gesture ends. Streaming sources may issue a new HTTP Range for
/// every seek, so doing this on each Slider.onChanged floods the transport.
class AddKoSeekSlider extends StatefulWidget {
  const AddKoSeekSlider({
    super.key,
    required this.duration,
    required this.position,
    required this.onSeek,
  });

  final Duration duration;
  final Duration position;
  final Future<void> Function(Duration) onSeek;

  @override
  State<AddKoSeekSlider> createState() => _AddKoSeekSliderState();
}

class _AddKoSeekSliderState extends State<AddKoSeekSlider> {
  double? _dragPositionMs;

  @override
  void didUpdateWidget(covariant AddKoSeekSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new video invalidates any preview position from the old one.
    if (widget.duration != oldWidget.duration) {
      _dragPositionMs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds;
    final maxValue = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final current = widget.position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxValue)
        .toDouble();
    return Slider(
      min: 0,
      max: maxValue,
      value: durationMs <= 0
          ? 0.0
          : (_dragPositionMs ?? current).clamp(0.0, maxValue).toDouble(),
      onChanged: durationMs <= 0
          ? null
          : (value) => setState(() => _dragPositionMs = value),
      onChangeEnd: durationMs <= 0
          ? null
          : (value) async {
              try {
                await widget.onSeek(
                  Duration(milliseconds: value.round()),
                );
              } on Object {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Não foi possível mudar a posição do vídeo.'),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _dragPositionMs = null);
              }
            },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Lapisan kontrol pemutar (bilah atas, tombol tengah, seekbar + aksi bawah).
/// Hanya membaca [controller] lewat ValueListenableBuilder agar rebuild murah.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.visible,
    required this.locked,
    required this.title,
    required this.episodeLabel,
    required this.qualityLabel,
    required this.speed,
    required this.hasSubtitles,
    required this.subtitleOn,
    required this.hasPrev,
    required this.hasNext,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekRelative,
    required this.onSeekTo,
    required this.onToggleLock,
    required this.onSpeed,
    required this.onQuality,
    required this.onSubtitles,
    required this.onPrev,
    required this.onNext,
    required this.onEpisodes,
    required this.onMore,
  });

  final VideoPlayerController controller;
  final bool visible;
  final bool locked;
  final String title;
  final String episodeLabel;
  final String qualityLabel;
  final double speed;
  final bool hasSubtitles;
  final bool subtitleOn;
  final bool hasPrev;
  final bool hasNext;

  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeekRelative;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onToggleLock;
  final VoidCallback onSpeed;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onEpisodes;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        // Terkunci: hanya tombol gembok yang tampil.
        if (locked) {
          return AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !visible,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: _RoundButton(
                    icon: Icons.lock_rounded,
                    size: 48,
                    onTap: onToggleLock,
                  ),
                ),
              ),
            ),
          );
        }

        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: IgnorePointer(
            ignoring: !visible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradasi atas & bawah agar teks terbaca
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.25, 0.7, 1.0],
                      colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      _TopBar(
                        title: title,
                        episodeLabel: episodeLabel,
                        onBack: onBack,
                        onMore: onMore,
                        onEpisodes: onEpisodes,
                      ),
                      const Spacer(),
                      _CenterControls(
                        value: v,
                        onPlayPause: onPlayPause,
                        onSeekRelative: onSeekRelative,
                      ),
                      const Spacer(),
                      _BottomBar(
                        value: v,
                        qualityLabel: qualityLabel,
                        speed: speed,
                        hasSubtitles: hasSubtitles,
                        subtitleOn: subtitleOn,
                        hasPrev: hasPrev,
                        hasNext: hasNext,
                        onSeekTo: onSeekTo,
                        onToggleLock: onToggleLock,
                        onSpeed: onSpeed,
                        onQuality: onQuality,
                        onSubtitles: onSubtitles,
                        onPrev: onPrev,
                        onNext: onNext,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.episodeLabel,
    required this.onBack,
    required this.onMore,
    required this.onEpisodes,
  });

  final String title;
  final String episodeLabel;
  final VoidCallback onBack;
  final VoidCallback onMore;
  final VoidCallback onEpisodes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  episodeLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Daftar episode',
            onPressed: onEpisodes,
            icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 26),
          ),
          IconButton(
            tooltip: 'Lainnya',
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.value,
    required this.onPlayPause,
    required this.onSeekRelative,
  });

  final VideoPlayerValue value;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeekRelative;

  @override
  Widget build(BuildContext context) {
    final buffering = value.isBuffering && !value.hasError;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.replay_10_rounded,
          size: 50,
          iconSize: 28,
          onTap: () => onSeekRelative(const Duration(seconds: -10)),
        ),
        const SizedBox(width: 36),
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _RoundButton(
                icon: value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 72,
                iconSize: 44,
                filled: true,
                onTap: onPlayPause,
              ),
              if (buffering)
                const SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(width: 36),
        _RoundButton(
          icon: Icons.forward_10_rounded,
          size: 50,
          iconSize: 28,
          onTap: () => onSeekRelative(const Duration(seconds: 10)),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.value,
    required this.qualityLabel,
    required this.speed,
    required this.hasSubtitles,
    required this.subtitleOn,
    required this.hasPrev,
    required this.hasNext,
    required this.onSeekTo,
    required this.onToggleLock,
    required this.onSpeed,
    required this.onQuality,
    required this.onSubtitles,
    required this.onPrev,
    required this.onNext,
  });

  final VideoPlayerValue value;
  final String qualityLabel;
  final double speed;
  final bool hasSubtitles;
  final bool subtitleOn;
  final bool hasPrev;
  final bool hasNext;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onToggleLock;
  final VoidCallback onSpeed;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final speedLabel = speed == speed.roundToDouble()
        ? '${speed.toInt()}.0x'
        : '${speed}x';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeekBar(value: value, onSeekTo: onSeekTo),
          Row(
            children: [
              _PillButton(label: speedLabel, icon: Icons.speed_rounded, onTap: onSpeed),
              const SizedBox(width: 6),
              _PillButton(label: qualityLabel, icon: Icons.hd_outlined, onTap: onQuality),
              const SizedBox(width: 6),
              _PillButton(
                label: subtitleOn ? 'CC' : 'CC off',
                icon: Icons.closed_caption_outlined,
                onTap: onSubtitles,
                active: subtitleOn,
                enabled: hasSubtitles,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Episode sebelumnya',
                onPressed: hasPrev ? onPrev : null,
                icon: Icon(Icons.skip_previous_rounded,
                    color: hasPrev ? Colors.white : Colors.white30),
              ),
              IconButton(
                tooltip: 'Episode berikutnya',
                onPressed: hasNext ? onNext : null,
                icon: Icon(Icons.skip_next_rounded,
                    color: hasNext ? Colors.white : Colors.white30),
              ),
              IconButton(
                tooltip: 'Kunci layar',
                onPressed: onToggleLock,
                icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Seekbar dengan posisi lokal saat digeser + rentang buffer.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.value, required this.onSeekTo});

  final VideoPlayerValue value;
  final ValueChanged<Duration> onSeekTo;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final total = v.duration.inMilliseconds.toDouble();
    final hasDuration = total > 0;
    final posMs = v.position.inMilliseconds.toDouble();
    final double current =
        _drag ?? (hasDuration ? posMs.clamp(0.0, total).toDouble() : 0.0);
    final remaining = hasDuration
        ? Duration(milliseconds: (total - current).round())
        : Duration.zero;

    double buffered = 0;
    for (final r in v.buffered) {
      final end = r.end.inMilliseconds.toDouble();
      if (end > buffered) buffered = end;
    }

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            formatDuration(Duration(milliseconds: current.round())),
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Jalur buffer
              if (hasDuration)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (buffered / total).clamp(0.0, 1.0).toDouble(),
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      color: Colors.white38,
                    ),
                  ),
                ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  inactiveTrackColor: Colors.white24,
                ),
                child: Slider(
                  min: 0,
                  max: hasDuration ? total : 1,
                  value: hasDuration ? current.clamp(0.0, total).toDouble() : 0,
                  onChangeStart: hasDuration ? (x) => setState(() => _drag = x) : null,
                  onChanged: hasDuration ? (x) => setState(() => _drag = x) : null,
                  onChangeEnd: hasDuration
                      ? (x) {
                          widget.onSeekTo(Duration(milliseconds: x.round()));
                          setState(() => _drag = null);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            hasDuration ? '-${formatDuration(remaining)}' : '--:--',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 24,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.accent : Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white30
        : active
            ? AppColors.accentSoft
            : Colors.white;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.6)),
          color: active ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

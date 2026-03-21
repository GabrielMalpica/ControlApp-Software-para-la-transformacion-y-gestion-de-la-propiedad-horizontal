import 'package:flutter/material.dart';

class AnimatedFadeSlide extends StatefulWidget {
  const AnimatedFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
    this.duration = const Duration(milliseconds: 560),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;
  final Curve curve;

  @override
  State<AnimatedFadeSlide> createState() => _AnimatedFadeSlideState();
}

class _AnimatedFadeSlideState extends State<AnimatedFadeSlide> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : widget.offset,
      duration: widget.duration,
      curve: widget.curve,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}

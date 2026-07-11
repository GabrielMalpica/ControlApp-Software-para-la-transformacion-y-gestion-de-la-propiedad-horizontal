import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final double starSize;
  final Color filledColor;
  final Color emptyColor;

  const StarRating({
    super.key,
    required this.rating,
    this.starSize = 24,
    this.filledColor = Colors.amber,
    this.emptyColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final fractional = rating - fullStars;
    final hasHalf = fractional >= 0.25 && fractional < 0.75;
    final emptyStars = 5 - fullStars - (hasHalf ? 1 : 0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(fullStars, (_) => _star(Icons.star, filledColor)),
        if (hasHalf) _star(Icons.star_half, filledColor),
        ...List.generate(
          emptyStars > 0 ? emptyStars : 0,
          (_) => _star(Icons.star_border, emptyColor),
        ),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: starSize * 0.6,
            fontWeight: FontWeight.w600,
            color: filledColor,
          ),
        ),
      ],
    );
  }

  Widget _star(IconData icon, Color color) {
    return Icon(icon, size: starSize, color: color);
  }
}

class StarRatingInput extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double> onChanged;
  final double itemSize;

  const StarRatingInput({
    super.key,
    this.initialRating = 0,
    this.itemSize = 34,
    required this.onChanged,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  void _setRating(double r) {
    final clamped = r.clamp(1.0, 5.0).roundToDouble();
    setState(() {
      _rating = clamped;
    });
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 1; i <= 5; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setRating(i.toDouble()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.itemSize,
              height: widget.itemSize,
              decoration: BoxDecoration(
                color: i <= _rating
                    ? Colors.amber.withValues(alpha: 0.16)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: i <= _rating ? Colors.amber : Colors.grey.shade300,
                ),
              ),
              child: Center(
                child: Text(
                  '$i',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: i <= _rating
                        ? Colors.amber.shade800
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

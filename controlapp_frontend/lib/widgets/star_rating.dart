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
            emptyStars > 0 ? emptyStars : 0, (_) => _star(Icons.star_border, emptyColor)),
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

  const StarRatingInput({
    super.key,
    this.initialRating = 0,
    required this.onChanged,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _rating;
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _textController = TextEditingController(
      text: widget.initialRating > 0
          ? widget.initialRating.toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _setRating(double r) {
    final clamped = r.clamp(0.0, 5.0).roundToDouble();
    setState(() {
      _rating = clamped;
      _textController.text =
          clamped > 0 ? clamped.toStringAsFixed(1) : '';
    });
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (int i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => _setRating(i.toDouble()),
                child: Icon(
                  i <= _rating.round()
                      ? Icons.star
                      : i <= _rating.ceil() && _rating - (i - 1) > 0
                          ? Icons.star_half
                          : Icons.star_border,
                  size: 36,
                  color: i <= _rating.round()
                      ? Colors.amber
                      : i <= _rating.ceil() && _rating - (i - 1) > 0
                          ? Colors.amber
                          : Colors.grey.shade400,
                ),
              ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _textController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0.0',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 14),
                onSubmitted: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null) {
                    _setRating(parsed);
                  }
                },
              ),
            ),
          ],
        ),
        if (_rating > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Slider(
              value: _rating,
              min: 0,
              max: 5,
              divisions: 50,
              label: _rating.toStringAsFixed(1),
              onChanged: _setRating,
            ),
          ),
      ],
    );
  }
}

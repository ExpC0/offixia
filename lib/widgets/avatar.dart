import 'package:flutter/material.dart';

import '../models/employee.dart';

/// Profile photo, falling back to initials on a colour derived from the name.
///
/// Deriving the colour from the name rather than picking at random means the
/// same person is the same colour on every screen and across restarts, which
/// is what makes an avatar scannable in a long list.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.employee, this.radius = 20});

  final Employee employee;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hue = (employee.uid.isEmpty ? employee.name : employee.uid).hashCode
        .abs();
    final background = HSLColor.fromAHSL(
      1,
      (hue % 360).toDouble(),
      0.45,
      Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.78,
    ).toColor();

    if (employee.photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: background,
        foregroundImage: NetworkImage(employee.photoUrl),
        // Shown if the image fails; a broken URL should not leave a blank disc.
        child: Text(
          employee.initials,
          style: TextStyle(
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        employee.initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black87,
        ),
      ),
    );
  }
}

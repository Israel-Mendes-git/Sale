import 'package:flutter/material.dart';

import '../../domain/models.dart';

class Avatar extends StatelessWidget {
  const Avatar(this.profile, {super.key, this.radius = 20});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(profile.color).withValues(alpha: 0.25),
      child: Text(profile.emoji, style: TextStyle(fontSize: radius * 0.9)),
    );
  }
}

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, this.radius = 20});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary.withValues(alpha: 0.2),
      child: Icon(Icons.groups, color: scheme.primary, size: radius),
    );
  }
}

import 'package:flutter/material.dart';

import '../../domain/models.dart';

class Avatar extends StatelessWidget {
  const Avatar(this.profile, {super.key, this.radius = 20});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = profile.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(profile.color).withValues(alpha: 0.25),
      // A foto do Discord ou do Google por cima; se faltar ou não carregar
      // (link velho, sem rede), fica o emoji sobre a cor da pessoa.
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: Text(profile.emoji, style: TextStyle(fontSize: radius * 0.9)),
    );
  }
}

/// O avatar com a bolinha verde de quem está com o app aberto agora: ajuda a
/// decidir se vale chamar.
class ComPresenca extends StatelessWidget {
  const ComPresenca({
    super.key,
    required this.online,
    required this.child,
    this.size = 12,
  });

  final bool online;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!online) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -1,
          bottom: -1,
          child: Semantics(
            key: const ValueKey('presenca-online'),
            label: 'online',
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
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

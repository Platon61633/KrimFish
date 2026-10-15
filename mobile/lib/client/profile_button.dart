import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'profile_screen.dart';

/// Круглый значок профиля в правом верхнем углу.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: 'Профиль',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
      ),
      icon: const Icon(Icons.person_outline),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        minimumSize: const Size(44, 44),
      ),
    );
  }
}

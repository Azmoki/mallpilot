import 'package:flutter/material.dart';
import '../models/store.dart';

/// Shows the store logo; falls back to a floor badge if there is no image.
/// Shared by the directory page and the chat page.
class StoreLogo extends StatelessWidget {
  final Store store;
  const StoreLogo({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(child: Text(store.floorLabel));
    if (store.logo.isEmpty) return fallback;
    return SizedBox(
      width: 48,
      height: 48,
      child: Image.asset(
        'assets/logos/${store.logo}',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

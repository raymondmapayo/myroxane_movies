import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PageLoader extends StatelessWidget {
  const PageLoader({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: const SizedBox.square(
      dimension: 34,
      child: CircularProgressIndicator(strokeWidth: 3),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _StateFrame(icon: Icons.signal_wifi_connected_no_internet_4),
          const SizedBox(height: 18),
          Text('Couldn’t connect', style: AppTheme.display(27)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('TRY AGAIN'),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.search = false});
  final bool search;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateFrame(
            icon: search
                ? Icons.search_off_rounded
                : Icons.movie_filter_outlined,
          ),
          const SizedBox(height: 18),
          Text('No matches found', style: AppTheme.display(27)),
          const SizedBox(height: 6),
          Text(
            search
                ? 'Try a shorter title or a franchise name.'
                : 'Try another genre, language, or media type.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _StateFrame extends StatelessWidget {
  const _StateFrame({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: const ShapeDecoration(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(36)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    child: Icon(icon, size: 30, color: AppColors.muted),
  );
}

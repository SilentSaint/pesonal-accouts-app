import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class HistoricalBackfillCard extends StatelessWidget {
  final VoidCallback onScanPressed;
  final bool isScanning;
  final bool isCompleted;
  final DateTime? lastScannedAt;

  const HistoricalBackfillCard({
    super.key,
    required this.onScanPressed,
    this.isScanning = false,
    this.isCompleted = false,
    this.lastScannedAt,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isCompleted ? AppColors.success : AppColors.primary;
    final statusBg = isCompleted ? const Color(0x1A10B981) : const Color(0x1A6366F1);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? const Color(0x4010B981) : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          if (isCompleted)
            const BoxShadow(
              color: Color(0x1410B981),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle_outline : Icons.history_toggle_off,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      isCompleted ? '30-Day Sync Active' : '30-Day Auto Backfill',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isCompleted ? 'SYNCED' : 'PENDING',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isCompleted
                      ? 'Scanned at ${lastScannedAt?.hour.toString().padLeft(2, '0')}:${lastScannedAt?.minute.toString().padLeft(2, '0')}:${lastScannedAt?.second.toString().padLeft(2, '0')}. All accounts mapped.'
                      : 'Scan SMS & financial receipts to discover accounts & balances.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: isScanning ? null : onScanPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isCompleted ? AppColors.surfaceElevated : AppColors.primary,
              foregroundColor: isCompleted ? AppColors.successLight : Colors.white,
              elevation: 0,
              side: isCompleted
                  ? const BorderSide(color: Color(0x4010B981))
                  : BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: isScanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isCompleted ? 'Incremental' : 'Scan 30 Days',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
          ),
        ],
      ),
    );
  }
}

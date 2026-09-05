import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/developer_mode_service.dart';
import 'theme/app_theme.dart';

class DeveloperAuditPanel extends StatefulWidget {
  final Future<PhaseScanAudit?> Function(int phaseIndex, int afterSec, int beforeSec) onRunPhaseScan;
  final bool isScanning;

  const DeveloperAuditPanel({
    super.key,
    required this.onRunPhaseScan,
    this.isScanning = false,
  });

  @override
  State<DeveloperAuditPanel> createState() => _DeveloperAuditPanelState();
}

class _DeveloperAuditPanelState extends State<DeveloperAuditPanel> {
  int _selectedPhaseForDetails = 1;
  int? _activeScanningPhase;

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final devService = DeveloperModeService();
    final p1 = devService.getPhase1Range();
    final p2 = devService.getPhase2Range();
    final p3 = devService.getPhase3Range();

    return AnimatedBuilder(
      animation: devService,
      builder: (context, _) {
        if (!devService.isEnabled) return const SizedBox.shrink();

        final activeAudit = devService.phaseAudits[_selectedPhaseForDetails];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Slate 900
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.5), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F8B5CF6),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.developer_mode, color: Color(0xFFA78BFA), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: const [
                            Text(
                              'Developer Mode: Phased 30-Day Audit',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.2,
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x338B5CF6),
                                borderRadius: BorderRadius.all(Radius.circular(6)),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text(
                                  'PROD FLAG ON',
                                  style: TextStyle(
                                    color: Color(0xFFA78BFA),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Test 30-day historical window in 3 granular 10-day phases to audit anomalies & promo filtering.',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: const Color(0x22A78BFA),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.sync, color: Color(0xFFA78BFA), size: 14),
                    label: const Text('Refresh Token', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      final ok = await AuthService().requestGmailAccess();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Fresh Gmail token acquired!' : 'Failed to refresh token.'),
                            backgroundColor: ok ? AppColors.success : AppColors.danger,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    tooltip: 'Disable Developer Mode',
                    onPressed: () => devService.setEnabled(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3 Phase Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 650;
                  final cards = [
                    _buildPhaseCard(p1, 1, devService),
                    _buildPhaseCard(p2, 2, devService),
                    _buildPhaseCard(p3, 3, devService),
                  ];

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[2]),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 10),
                        cards[1],
                        const SizedBox(height: 10),
                        cards[2],
                      ],
                    );
                  }
                },
              ),

              // Detailed Audit Section (if a phase has been scanned)
              if (activeAudit != null) ...[
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Phase $_selectedPhaseForDetails Audit Breakdown (${activeAudit.items.length} Emails)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            backgroundColor: const Color(0xFF1E293B),
                          ),
                          icon: const Icon(Icons.copy, size: 14, color: Color(0xFF38BDF8)),
                          label: const Text(
                            'Copy Diagnostic JSON',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                          ),
                          onPressed: () {
                            final jsonStr = devService.exportPhaseAuditJson(_selectedPhaseForDetails);
                            Clipboard.setData(ClipboardData(text: jsonStr));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Phase $_selectedPhaseForDetails diagnostic JSON copied to clipboard!'),
                                backgroundColor: AppColors.success,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildAuditItemList(activeAudit),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhaseCard(Map<String, dynamic> phaseRange, int phaseIndex, DeveloperModeService devService) {
    final audit = devService.phaseAudits[phaseIndex];
    final isSelected = _selectedPhaseForDetails == phaseIndex;
    final isScanningThis = widget.isScanning && _activeScanningPhase == phaseIndex;

    final startDateStr = _formatDate(phaseRange['startDate'] as DateTime);
    final endDateStr = _formatDate(phaseRange['endDate'] as DateTime);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPhaseForDetails = phaseIndex;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0B132B).withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    phaseRange['title'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                if (audit != null)
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16)
                else
                  const Icon(Icons.pending_outlined, color: Colors.white38, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$startDateStr – $endDateStr',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            const SizedBox(height: 10),
            if (audit != null) ...[
              Text(
                '• ${audit.emailsScanned} emails scanned',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                '• ${audit.candidatesCount} transactions found (${audit.autoAccountedCount} auto-accounted)',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ] else ...[
              const Text(
                'Ready to scan & audit',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: audit != null ? const Color(0xFF334155) : const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: widget.isScanning
                    ? null
                    : () async {
                        setState(() {
                          _activeScanningPhase = phaseIndex;
                          _selectedPhaseForDetails = phaseIndex;
                        });
                        try {
                          await widget.onRunPhaseScan(
                            phaseIndex,
                            phaseRange['afterSec'] as int,
                            phaseRange['beforeSec'] as int,
                          );
                        } finally {
                          if (mounted) {
                            setState(() {
                              _activeScanningPhase = null;
                            });
                          }
                        }
                      },
                child: isScanningThis
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        audit != null ? 'Re-scan Phase $phaseIndex' : 'Scan Phase $phaseIndex',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditItemList(PhaseScanAudit audit) {
    if (audit.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No emails found in this 10-day phase.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: audit.items.length,
        separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 1),
        itemBuilder: (context, index) {
          final item = audit.items[index];
          final isTxn = item.isCandidate;
          final isAuto = item.status == 'AUTO_CONFIRMED';
          final isNeedsReview = item.status == 'NEEDS_REVIEW';

          Color badgeBg = const Color(0xFF334155);
          Color badgeColor = const Color(0xFF94A3B8);
          String badgeText = 'PROMOTIONAL / IGNORED';

          if (isAuto) {
            badgeBg = const Color(0x3310B981);
            badgeColor = const Color(0xFF10B981);
            badgeText = 'AUTO-ACCOUNTED (${item.merchantName ?? "Mapped"})';
          } else if (isNeedsReview) {
            badgeBg = const Color(0x33F59E0B);
            badgeColor = const Color(0xFFF59E0B);
            badgeText = 'NEEDS REVIEW (₹${item.amount?.toStringAsFixed(0) ?? "?"})';
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isTxn ? Icons.receipt_long : Icons.mark_email_read_outlined,
                  size: 16,
                  color: isTxn ? const Color(0xFF10B981) : Colors.white38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.subject.isNotEmpty ? item.subject : '(No Subject)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'From: ${item.from} • ${item.date}',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.snippet.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.snippet,
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

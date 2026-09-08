import 'package:flutter/material.dart';

import '../data/safety_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Opens a modal bottom sheet that collects a report reason for [targetType]/
/// [targetId] and submits it via [SafetyRepository.report].
///
/// Validation ([ReportValidationError]) is surfaced inline; on a successful
/// submit the sheet closes and an optimistic 'Reported' confirmation snackbar
/// is shown (guarded persistence means an offline submit still confirms — see
/// [SafetyRepository.report]). [targetLabel] is a human-readable description of
/// the target (e.g. 'this post', '@aria.codes') used in the sheet copy.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String targetLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: _ReportForm(
          targetType: targetType,
          targetId: targetId,
          targetLabel: targetLabel,
        ),
      );
    },
  );
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
  });

  final String targetType;
  final String targetId;
  final String targetLabel;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await SafetyRepository.instance.report(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _controller.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Reported. Thanks for letting us know.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on ReportValidationError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Report ${widget.targetLabel}', style: AppTextStyles.title),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Tell us what is wrong. Your report is private.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 5,
          maxLength: SafetyRepository.maxReasonLength,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: 'Reason',
            errorText: _error,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Submitting…' : 'Submit report'),
          ),
        ),
      ],
    );
  }
}

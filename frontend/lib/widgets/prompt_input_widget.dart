import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playground_providers.dart';
import 'template_picker.dart';

/// Text area + submit button for entering and submitting a prompt.
///
/// Validates that:
///   - the prompt text is not empty / whitespace
///   - at least one model is selected
///
/// On valid submission it calls [onSubmit] with the current prompt text and
/// selected model IDs.
///
/// A "Templates" icon button above the text field opens [TemplatePicker] as
/// a bottom sheet. On selection, the text field is populated with the template
/// body and the cursor is placed at the first `[` bracket so the user can
/// immediately start filling in placeholder values. The prompt is NOT submitted
/// automatically (Req 8 AC4).
class PromptInputWidget extends ConsumerStatefulWidget {
  const PromptInputWidget({super.key, required this.onSubmit});

  /// Called when the user presses Submit and validation passes.
  final void Function(String prompt, List<String> models) onSubmit;

  @override
  ConsumerState<PromptInputWidget> createState() => _PromptInputWidgetState();
}

class _PromptInputWidgetState extends ConsumerState<PromptInputWidget> {
  final TextEditingController _controller = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    final selected = ref.read(selectedModelsProvider);

    if (selected.isEmpty) {
      setState(() {
        _validationError = 'Please select at least one model before submitting.';
      });
      return;
    }

    if (text.isEmpty) {
      setState(() {
        _validationError = 'Prompt cannot be empty.';
      });
      return;
    }

    setState(() => _validationError = null);

    // Sync the text into the provider for other widgets that may read it.
    ref.read(promptTextProvider.notifier).setText(text);
    widget.onSubmit(text, selected.toList());
  }

  /// Opens the [TemplatePicker] bottom sheet. If the user selects a template,
  /// populates the text field and positions the cursor — does NOT auto-submit.
  Future<void> _openTemplatePicker() async {
    // Close the keyboard before showing the sheet for a cleaner UX.
    FocusScope.of(context).unfocus();

    final body = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const TemplatePicker(),
    );

    if (body == null) return; // User dismissed the sheet without selecting.

    // Populate the text field with the template body (Req 8 AC2, AC3).
    _controller.text = body;

    // Position cursor at the first `[` so the user can immediately fill in
    // the placeholder. Fall back to end-of-text if no bracket is found.
    final bracketIndex = body.indexOf('[');
    final cursorOffset = bracketIndex >= 0 ? bracketIndex : body.length;
    _controller.selection = TextSelection.collapsed(offset: cursorOffset);

    // Clear any stale validation error now that we have content.
    if (_validationError != null) {
      setState(() => _validationError = null);
    }

    // Re-focus the text field so the user can start editing immediately.
    // ignore: use_build_context_synchronously
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Templates button row — aligned to the trailing edge above the field.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _openTemplatePicker,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Templates'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelMedium,
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          maxLines: 5,
          minLines: 3,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: 'Enter your prompt here…',
            border: const OutlineInputBorder(),
            errorText: _validationError,
            // Clear validation error as the user types.
            errorMaxLines: 2,
          ),
          onChanged: (_) {
            if (_validationError != null) {
              setState(() => _validationError = null);
            }
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _handleSubmit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Submit'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: theme.textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

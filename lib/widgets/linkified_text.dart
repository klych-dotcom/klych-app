import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/klych_theme.dart';

/// Renders [text] with any embedded URLs made interactive:
///
/// * **Tap** a link → opens it in the system browser / Maps app.
/// * **Long-press** the message → action sheet to open or copy each link.
///
/// Flutter has no built-in URL detector, so detection is a focused regex;
/// rendering uses [TextSpan]s (not [WidgetSpan]) so links wrap naturally and
/// still respect [maxLines] / [overflow] inside narrow history tiles.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

// http(s)/www URLs, plus bare domains ending in a common TLD with optional path.
final RegExp _urlRegex = RegExp(
  r'((https?:\/\/|www\.)[^\s<>()]+)'
  r'|([a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9\-]+)*'
  r'\.(?:com|org|net|gov|edu|mil|io|app|co|info|me|ua|maps)(?:\/[^\s<>()]*)?)',
  caseSensitive: false,
);

const String _trailingPunctuation = '.,;:!?»"\'';

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];
  final List<String> _links = [];
  List<InlineSpan> _spans = const [];

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(covariant LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.linkStyle != widget.linkStyle) {
      _build();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _build() {
    _disposeRecognizers();
    _links.clear();

    final text = widget.text;
    final baseStyle = widget.style ?? const TextStyle();
    final linkStyle = widget.linkStyle ??
        baseStyle.copyWith(
          color: KlychTheme.accent,
          decoration: TextDecoration.underline,
          decorationColor: KlychTheme.accent,
          fontWeight: FontWeight.w600,
        );

    final spans = <InlineSpan>[];
    var start = 0;

    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }

      var raw = match.group(0)!;
      // Keep trailing sentence punctuation out of the link.
      var trailing = '';
      while (raw.isNotEmpty &&
          _trailingPunctuation.contains(raw[raw.length - 1])) {
        trailing = '${raw[raw.length - 1]}$trailing';
        raw = raw.substring(0, raw.length - 1);
      }

      final url = raw;
      _links.add(url);
      final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: raw, style: linkStyle, recognizer: recognizer));

      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    _spans = spans;
  }

  Uri? _toUri(String raw) {
    var value = raw.trim();
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/').hasMatch(value)) {
      value = 'https://$value';
    }
    return Uri.tryParse(value);
  }

  Future<void> _open(String raw) async {
    final uri = _toUri(raw);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('LinkifiedText._open: $e');
    }
  }

  Future<void> _copy(String raw) async {
    final uri = _toUri(raw);
    await Clipboard.setData(ClipboardData(text: uri?.toString() ?? raw));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Посилання скопійовано')),
    );
  }

  void _showLinksSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KlychTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KlychTheme.radiusLg)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final link in _links) ...[
                ListTile(
                  leading:
                      const Icon(Icons.open_in_new, color: KlychTheme.accent),
                  title: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KlychTheme.bodyMedium,
                  ),
                  subtitle: const Text('Відкрити'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _open(link);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.copy, color: KlychTheme.textSecondary),
                  title: const Text('Копіювати посилання'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copy(link);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Text.rich(
      TextSpan(style: widget.style, children: _spans),
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );

    if (_links.isEmpty) return body;

    return GestureDetector(
      onLongPress: _showLinksSheet,
      child: body,
    );
  }
}

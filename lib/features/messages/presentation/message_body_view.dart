import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/message_body.dart';

/// Treść wiadomości bez WebView: brak JavaScriptu i zasobów zewnętrznych.
/// Odnośniki są wyróżnione, a ich adresy wypisane poniżej do skopiowania.
class MessageBodyView extends StatelessWidget {
  const MessageBodyView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    final spans = htmlToSpans(html);
    final theme = Theme.of(context);
    if (spans.isEmpty) {
      return Text(
        '(brak treści)',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final links = {for (final s in spans) ?s.link}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          TextSpan(
            style: theme.textTheme.bodyLarge,
            children: [
              for (final s in spans)
                TextSpan(
                  text: s.text,
                  style: TextStyle(
                    fontWeight: s.bold ? FontWeight.bold : null,
                    fontStyle: s.italic ? FontStyle.italic : null,
                    color: s.link != null ? theme.colorScheme.primary : null,
                    decoration: s.link != null
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Odnośniki w wiadomości', style: theme.textTheme.labelLarge),
          for (final link in links)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Kopiuj adres',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Skopiowano adres. Otwórz go w przeglądarce, jeśli mu ufasz.',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}

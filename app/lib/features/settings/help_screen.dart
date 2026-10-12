import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../theme/tokens.dart';

/// Basic helpdesk — posts to vitalog.cc → BSOC Console Desk.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  static final _endpoint = Uri.parse('https://vitalog.cc/api/help');

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _status = null;
      _ok = false;
    });
    try {
      final res = await http
          .post(
            _endpoint,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'name': _name.text.trim(),
              'email': _email.text.trim(),
              'message': _message.text.trim(),
              'source': 'app',
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = data is Map && data['error'] is Map
            ? (data['error']['message'] as String?)
            : null;
        throw StateError(
          msg ?? 'Could not send. Try again, or email outreach@bsoc.space.',
        );
      }
      final ticket = data is Map ? data['ticket'] as String? : null;
      if (!mounted) return;
      setState(() {
        _ok = true;
        _status = ticket == null || ticket.isEmpty
            ? "Sent. We'll reply by email."
            : "Sent. We'll reply by email. Ticket $ticket.";
        _message.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _status = e is StateError
            ? e.message
            : 'Could not reach support. Check your connection, or email outreach@bsoc.space.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      backgroundColor: BodylineColors.paper,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Message the BSOC desk. This is for product questions and closed testing — not medical advice.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Name (optional)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: BodylineColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                  ),
                  enabled: !_busy,
                ),
                const SizedBox(height: 16),
                Text(
                  'Email',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: BodylineColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                  ),
                  enabled: !_busy,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Enter an email so we can reply.';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) {
                      return 'That doesn’t look like an email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Message',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: BodylineColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _message,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    hintText: 'What do you need help with?',
                    alignLabelWithHint: true,
                  ),
                  enabled: !_busy,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.length < 8) {
                      return 'Write a short message (a few words is enough).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy ? 'Sending…' : 'Send message'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _ok ? BodylineColors.tealDark : BodylineColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Or email outreach@bsoc.space. Your health records stay on this device — only what you type here is sent.',
            style: theme.textTheme.bodySmall?.copyWith(color: BodylineColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

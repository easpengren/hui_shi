import 'package:flutter/material.dart';
import '../widgets/classical_chrome.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.65),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Center(
            child: Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Lu Ji',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Center(
            child: Text('Offline TTS Reader', style: muted),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Version 1.0.0', style: muted),
          ),
          const SizedBox(height: 28),
          const DoubleRule(),
          const SizedBox(height: 20),
          DossierPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What is Lu Ji?',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Lu Ji is an offline text-to-speech reader for books and documents. '
                  'It supports TXT, PDF, and EPUB files, and can read aloud using '
                  'your device\'s built-in voices or the offline Piper neural TTS engine.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DossierPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Engines',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _EngineRow(
                  name: 'System TTS',
                  description:
                      'Uses Android\'s built-in text-to-speech. Supports '
                      'Google\'s Neural2, WaveNet, Journey, and Studio voices '
                      'when installed.',
                ),
                const SizedBox(height: 10),
                _EngineRow(
                  name: 'Piper (Offline)',
                  description:
                      'Fully offline neural TTS using the Piper engine via '
                      'sherpa-onnx. Voice models are downloaded on first use '
                      'and stored on-device.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DossierPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open Source',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Lu Ji uses the following open-source projects:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _CreditRow(project: 'sherpa-onnx', note: 'Piper TTS runtime'),
                _CreditRow(project: 'piper', note: 'Neural TTS voices'),
                _CreditRow(project: 'pdfrx', note: 'PDF rendering'),
                _CreditRow(project: 'epubx', note: 'EPUB parsing'),
                _CreditRow(project: 'just_audio', note: 'Audio playback'),
                _CreditRow(project: 'flutter_tts', note: 'System TTS bridge'),
                _CreditRow(project: 'provider', note: 'State management'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineRow extends StatelessWidget {
  final String name;
  final String description;
  const _EngineRow({required this.name, required this.description});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.record_voice_over_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(description,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String project;
  final String note;
  const _CreditRow({required this.project, required this.note});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.6),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(project,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Text('— $note', style: muted),
        ],
      ),
    );
  }
}

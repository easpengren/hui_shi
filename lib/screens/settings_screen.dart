import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../state/reader_state.dart';
import '../widgets/classical_chrome.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            IconButton(
              icon: Icon(
                state.themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              tooltip: state.themeMode == ThemeMode.dark
                  ? 'Switch to light mode'
                  : 'Switch to dark mode',
              onPressed: state.toggleThemeMode,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About',
              onPressed: () => Navigator.pushNamed(context, '/about'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            DossierHeader(title: 'Text-to-Speech'),
            const SizedBox(height: 12),
            DossierPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Engine', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  ToggleButtons(
                    isSelected: TtsEngine.values
                        .map((e) => e == state.selectedEngine)
                        .toList(),
                    onPressed: (i) => state.setEngine(TtsEngine.values[i]),
                    color: const Color(0xFF1A242B),
                    selectedColor: const Color(0xFFFBF8F1),
                    fillColor: const Color(0xFF1F5975),
                    borderColor: const Color(0xFFC7BCAB),
                    selectedBorderColor: const Color(0xFF1F5975),
                    borderRadius: BorderRadius.circular(8),
                    constraints: const BoxConstraints(minHeight: 36),
                    children: TtsEngine.values
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              e.displayName,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (state.selectedEngine == TtsEngine.piper) ...[
              DossierPanel(
                padding: const EdgeInsets.all(16),
                child: _PiperVoiceSection(state: state),
              ),
              const SizedBox(height: 12),
            ],
            if (state.selectedEngine == TtsEngine.system &&
                state.systemVoices.isNotEmpty) ...[
              DossierPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Android Voice',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: state.selectedSystemVoiceName.isNotEmpty
                          ? '${state.selectedSystemVoiceLocale}\u0001${state.selectedSystemVoiceName}'
                          : 'default',
                      style: const TextStyle(
                        color: Color(0xFF1A242B),
                        fontSize: 14,
                      ),
                      dropdownColor: const Color(0xFFFBF8F1),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFFFBF8F1),
                      ),
                      isExpanded: true,
                      items: state.systemVoiceOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option['id'],
                              child: Text(
                                option['label'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF1A242B),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (selection) {
                        if (selection == null) return;
                        if (selection == 'default') {
                          state.setSystemVoice('', '');
                          return;
                        }
                        final i = selection.indexOf('\u0001');
                        if (i <= 0) return;
                        final locale = selection.substring(0, i);
                        final name = selection.substring(i + 1);
                        state.setSystemVoice(name, locale);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            DossierPanel(
              padding: const EdgeInsets.all(16),
              child: _SpeedSection(state: state),
            ),
            const SizedBox(height: 24),
            DossierHeader(title: 'Appearance'),
            const SizedBox(height: 12),
            DossierPanel(
              padding: const EdgeInsets.all(4),
              child: SwitchListTile(
                title: const Text('Dark mode'),
                value: state.themeMode == ThemeMode.dark,
                onChanged: (_) => state.toggleThemeMode(),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('About Lu Ji'),
                onPressed: () => Navigator.pushNamed(context, '/about'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedSection extends StatefulWidget {
  final ReaderState state;
  const _SpeedSection({required this.state});

  @override
  State<_SpeedSection> createState() => _SpeedSectionState();
}

class _SpeedSectionState extends State<_SpeedSection> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final speed = _draft ?? widget.state.playbackSpeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Playback Speed', style: Theme.of(context).textTheme.labelLarge),
        Row(
          children: [
            const Text('Slow'),
            Expanded(
              child: Slider(
                min: 0.1,
                max: 2.0,
                divisions: 19,
                value: speed,
                label: '${speed.toStringAsFixed(1)}×',
                onChanged: (v) => setState(() => _draft = v),
                onChangeEnd: (v) async {
                  await widget.state.setSpeed(v);
                  if (mounted) setState(() => _draft = null);
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${speed.toStringAsFixed(1)}×',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PiperVoiceSection extends StatelessWidget {
  final ReaderState state;
  const _PiperVoiceSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Piper Voice', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: state.selectedVoice,
          style: const TextStyle(color: Color(0xFF1A242B), fontSize: 14),
          dropdownColor: const Color(0xFFFBF8F1),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Color(0xFFFBF8F1),
          ),
          isExpanded: true,
          items: kPiperVoices
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(
                    piperVoiceLabel(v),
                    style: const TextStyle(color: Color(0xFF1A242B)),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) state.setVoice(v);
          },
        ),
        const SizedBox(height: 12),
        if (!state.piperModelDownloaded)
          state.isDownloading
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: state.downloadProgress),
                    const SizedBox(height: 4),
                    Text(
                      state.downloadStatus,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: Text(
                        'Download ${piperVoiceLabel(state.selectedVoice)}',
                      ),
                      onPressed: state.downloadPiperModel,
                    ),
                    if (state.downloadStatus.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        state.downloadStatus,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ],
                )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Model ready',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: state.downloadPiperModel,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Re-download'),
                  ),
                ],
              ),
              if (state.downloadStatus.isNotEmpty)
                Text(
                  state.downloadStatus,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
      ],
    );
  }
}

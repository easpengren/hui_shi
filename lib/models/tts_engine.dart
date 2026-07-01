enum TtsEngine {
  system('System TTS (Android / iOS)'),
  piper('Piper (Offline)');

  final String displayName;
  const TtsEngine(this.displayName);
}

// Default and available Piper voices (sherpa-onnx VITS/Piper releases).
// Each name maps to:
//   https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-{name}.tar.bz2
// All entries below were verified to exist as release assets.
const String kDefaultPiperVoice = 'en_US-lessac-medium';

const List<String> kPiperVoices = [
  // US English
  'en_US-lessac-medium',
  'en_US-amy-medium',
  'en_US-ryan-medium',
  'en_US-hfc_female-medium',
  'en_US-hfc_male-medium',
  'en_US-kristin-medium',
  'en_US-libritts_r-medium',
  // UK English
  'en_GB-jenny_dioco-medium',
  'en_GB-alan-medium',
  'en_GB-alba-medium',
  'en_GB-cori-high',
  'en_GB-northern_english_male-medium',
];

/// Human-friendly label for a Piper voice id, for the voice picker.
/// Falls back to a generic prettifier if a voice isn't in the table.
String piperVoiceLabel(String id) {
  const labels = {
    'en_US-lessac-medium': 'Lessac — US, neutral',
    'en_US-amy-medium': 'Amy — US, female',
    'en_US-ryan-medium': 'Ryan — US, male',
    'en_US-hfc_female-medium': 'HFC — US, female',
    'en_US-hfc_male-medium': 'HFC — US, male',
    'en_US-kristin-medium': 'Kristin — US, female',
    'en_US-libritts_r-medium': 'LibriTTS-R — US, multi-speaker',
    'en_GB-jenny_dioco-medium': 'Jenny — UK, female',
    'en_GB-alan-medium': 'Alan — UK, male',
    'en_GB-alba-medium': 'Alba — UK, female',
    'en_GB-cori-high': 'Cori — UK, female (high quality)',
    'en_GB-northern_english_male-medium': 'Northern English — UK, male',
  };
  final hit = labels[id];
  if (hit != null) return hit;
  // Generic fallback: "en_US-foo-medium" → "Foo (en_US, medium)"
  final parts = id.split('-');
  if (parts.length >= 3) {
    final locale = parts.first;
    final name = parts[1];
    final quality = parts.last;
    final pretty = name.isEmpty
        ? name
        : name[0].toUpperCase() + name.substring(1);
    return '$pretty ($locale, $quality)';
  }
  return id;
}

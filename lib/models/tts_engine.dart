enum TtsEngine {
  system('System TTS (Android / iOS)'),
  piper('Piper (Offline)');

  final String displayName;
  const TtsEngine(this.displayName);
}

// Default and available Piper voices (sherpa-onnx VITS/Piper releases).
// Each name maps to:
//   https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-{name}.tar.bz2
const String kDefaultPiperVoice = 'en_US-lessac-medium';

// All names below are verified sherpa-onnx `vits-piper-*.tar.bz2` release
// assets, so each resolves to a real download (no 404s). Ordered US then GB.
const List<String> kPiperVoices = [
  'en_US-lessac-medium',
  'en_US-lessac-high',
  'en_US-libritts_r-medium',
  'en_US-amy-medium',
  'en_US-ryan-high',
  'en_US-hfc_female-medium',
  'en_US-hfc_male-medium',
  'en_US-joe-medium',
  'en_US-kristin-medium',
  'en_US-ljspeech-high',
  'en_US-glados-high',
  'en_GB-jenny_dioco-medium',
  'en_GB-alan-medium',
  'en_GB-alba-medium',
  'en_GB-cori-high',
  'en_GB-northern_english_male-medium',
  'en_GB-southern_english_female-medium',
];

const Map<String, String> kPiperVoiceLabels = {
  'en_US-lessac-medium': 'Lessac (en-US) · Medium',
  'en_US-lessac-high': 'Lessac (en-US) · High',
  'en_US-libritts_r-medium': 'LibriTTS R (en-US) · Medium',
  'en_US-amy-medium': 'Amy (en-US) · Medium',
  'en_US-ryan-high': 'Ryan (en-US) · High',
  'en_US-hfc_female-medium': 'HFC Female (en-US) · Medium',
  'en_US-hfc_male-medium': 'HFC Male (en-US) · Medium',
  'en_US-joe-medium': 'Joe (en-US) · Medium',
  'en_US-kristin-medium': 'Kristin (en-US) · Medium',
  'en_US-ljspeech-high': 'LJSpeech (en-US) · High',
  'en_US-glados-high': 'GLaDOS (en-US) · High',
  'en_GB-jenny_dioco-medium': 'Jenny (en-GB) · Medium',
  'en_GB-alan-medium': 'Alan (en-GB) · Medium',
  'en_GB-alba-medium': 'Alba (en-GB, Scottish) · Medium',
  'en_GB-cori-high': 'Cori (en-GB) · High',
  'en_GB-northern_english_male-medium': 'Northern English Male (en-GB) · Medium',
  'en_GB-southern_english_female-medium':
      'Southern English Female (en-GB) · Medium',
};

String piperVoiceLabel(String voice) => kPiperVoiceLabels[voice] ?? voice;

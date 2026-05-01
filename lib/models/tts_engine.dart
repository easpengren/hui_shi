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

const List<String> kPiperVoices = [
  'en_US-lessac-medium',
  'en_US-libritts_r-medium',
  'en_GB-jenny_dioco-medium',
];

package com.example.lu_ji

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (not FlutterActivity) so audio_service's media session
// binds correctly for lock-screen / notification / headset controls.
class MainActivity : AudioServiceActivity()

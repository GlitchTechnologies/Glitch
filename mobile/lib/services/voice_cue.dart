enum VoiceCue {
  message('assets/sounds/glitch_message.mp3', 'audio/mpeg', 'glitch_message'),

  deafen('assets/sounds/glitch_voice_deafen.mp3', 'audio/mpeg', 'voice_deafen'),
  undeafen('assets/sounds/glitch_voice_undeafen.mp3', 'audio/mpeg', 'voice_undeafen'),
  micOff('assets/sounds/glitch_voice_mic_off.mp3', 'audio/mpeg', 'voice_mic_off'),
  micOn('assets/sounds/glitch_voice_mic_on.mp3', 'audio/mpeg', 'voice_mic_on'),
  connected('assets/sounds/glitch_voice_connected.mp3', 'audio/mpeg', 'voice_connected'),
  disconnected('assets/sounds/glitch_voice_disconnected.wav', 'audio/wav', 'voice_disconnected'),

  moved('assets/sounds/glitch_voice_moved.mp3', 'audio/mpeg', 'voice_moved'),

  pttOn('assets/sounds/glitch_voice_ptt_on.mp3', 'audio/mpeg', 'voice_ptt_on'),
  pttOff('assets/sounds/glitch_voice_ptt_off.mp3', 'audio/mpeg', 'voice_ptt_off'),

  streamOn('assets/sounds/glitch_voice_stream_on.mp3', 'audio/mpeg', 'voice_stream_on'),
  streamOff('assets/sounds/glitch_voice_stream_off.mp3', 'audio/mpeg', 'voice_stream_off'),

  ringtone('assets/sounds/glitch_voice_calling.mp3', 'audio/mpeg', 'call_ringtone'),
  ringback('assets/sounds/ringback.ogg', 'audio/ogg', 'call_ringback');

  final String asset;
  final String mimeType;
  final String androidRes;

  const VoiceCue(this.asset, this.mimeType, this.androidRes);
}

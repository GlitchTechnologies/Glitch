import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../core/l10n.dart';
import '../core/achievement_model_style.dart';
import '../theme/app_theme.dart';
class AchievementModelSurface extends StatelessWidget {
  final String url;
  final String poster;
  final VoidCallback onClose;
  const AchievementModelSurface({super.key, required this.url, required this.poster, required this.onClose});
  @override
  Widget build(BuildContext context) => ModelViewer(
                    src: url,
                    alt: context.s.achievements,
                    poster: poster,
                    cameraControls: true,
                    disableZoom: false,
                    ar: false,
                    autoRotate: false,
                    debugLogging: false,
                    backgroundColor: Colors.transparent,
                    onWebViewCreated: (controller) {
                      controller.setBackgroundColor(Colors.transparent);
                      controller.addJavaScriptChannel('AwardClose', onMessageReceived: (_) => onClose());
                    },
                    relatedJs: '''
const award = document.querySelector('model-viewer');
customElements.whenDefined('model-viewer').then(() => {
  if (!award || !award.isConnected) return;
  const focusStyle = document.createElement('style');
  focusStyle.textContent = ${jsonEncode(achievementModelFocusCss)};
  award.shadowRoot.appendChild(focusStyle);
});
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (window.AwardClose) window.AwardClose.postMessage('close');
}, true);
if (award) {
  function showFailure() {
    const note = document.createElement('div');
    note.textContent = ${jsonEncode(context.s.errorLoad)};
    note.style.cssText = 'position:absolute;inset:0;display:grid;place-items:center;padding:24px;text-align:center;';
    note.style.color = ${jsonEncode('#${GlitchColors.textPrimary.value.toRadixString(16).padLeft(8, '0').substring(2)}')};
    award.replaceWith(note);
  }
  award.addEventListener('error', showFailure, {once:true});
  setTimeout(() => { if (award.isConnected && !award.loaded) showFailure(); }, 45000);
}
''',
                  );
}

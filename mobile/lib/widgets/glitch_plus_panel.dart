import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/glitchplus.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/glitch_plus_purchase.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_dialog.dart';
import 'glitch_plus_perks.dart';
import 'glitch_toast.dart';
import 'settings_window.dart' show SettingsBlock;

class GlitchPlusPanel extends StatefulWidget {
  final EdgeInsets padding;

  const GlitchPlusPanel({super.key, this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 30)});

  @override
  State<GlitchPlusPanel> createState() => _GlitchPlusPanelState();
}

class _GlitchPlusPanelState extends State<GlitchPlusPanel> {
  GlitchPlusStatus? _status;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    authService.currentUserListenable.addListener(_onMeChanged);
  }

  @override
  void dispose() {
    authService.currentUserListenable.removeListener(_onMeChanged);
    super.dispose();
  }

  void _onMeChanged() {
    final user = authService.currentUser;
    if (mounted && user != null && user.isGlitchPlus != _status?.isActive) _load();
  }

  int _loadVersion = 0;

  Future<void> _load() async {
    final version = ++_loadVersion;
    final sessionToken = authService.token;
    setState(() { _loading = true; _error = null; });
    try {
      final status = await api.getGlitchPlusStatus();
      if (mounted && version == _loadVersion && authService.token == sessionToken) setState(() { _status = status; _loading = false; });
    } catch (e) {
      if (mounted && version == _loadVersion && authService.token == sessionToken) setState(() { _error = errorMessage(e); _loading = false; });
    }
  }

  Future<void> _subscribe() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await startGlitchPlusPurchase();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() => _changeSubscription(api.cancelGlitchPlus);

  Future<void> _resume() => _changeSubscription(api.resumeGlitchPlus);

  Future<void> _changeSubscription(Future<GlitchPlusStatus> Function() change) async {
    if (_busy) return;
    final sessionToken = authService.token;
    setState(() => _busy = true);
    try {
      final status = await change();
      if (!mounted || authService.token != sessionToken) return;
      ++_loadVersion;
      setState(() {
        _status = status;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && authService.token == sessionToken) {
        GlitchToast.show(context, errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detachCard() async {
    if (_busy) return;
    final sessionToken = authService.token;
    final confirmed = await glitchConfirm(context,
        title: context.s.glitchPlusDetachCardTitle,
        body: context.s.glitchPlusDetachCardBody,
        confirmLabel: context.s.glitchPlusDetachConfirm);
    if (!confirmed || !mounted || authService.token != sessionToken) return;
    await _changeSubscription(api.detachGlitchPlusCard);
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    if (_loading) return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: Text(context.s.retry, style: TextStyle(color: GlitchColors.accentBlue))),
          ],
        ),
      );
    }
    final status = _status!;
    final subscription = SettingsBlock(
      title: context.s.glitchPlusSubscriptionTitle,
      child: status.isActive ? _buildActiveCard(status) : _buildOffer(status),
    );
    final perks = SettingsBlock(title: context.s.glitchPlusPerksTitle, child: const GlitchPlusPerks());
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: status.isActive
            ? [subscription, const SizedBox(height: 24), perks]
            : [perks, const SizedBox(height: 24), subscription],
      ),
    );
  }

  Widget _buildActiveCard(GlitchPlusStatus status) {
    final until = status.currentPeriodEnd;
    final untilStr = until != null
        ? '${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')}.${until.year}'
        : '—';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GlitchColors.borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bolt_rounded, color: GlitchColors.accentBlue, size: 22),
            const SizedBox(width: 8),
            Text(context.s.glitchPlusActiveTitle, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
          ]),
          const SizedBox(height: 10),
          Text(
            status.willRenew
                ? context.s.glitchPlusAutoRenewUntil(untilStr)
                : context.s.glitchPlusActiveUntilFixed(untilStr),
            style: TextStyle(fontSize: 14.5, color: GlitchColors.textSecond),
          ),
          if (status.willRenew || status.hasPaymentMethod) ...[
            const SizedBox(height: 20),
            GlitchActionButton(
              label: status.willRenew ? context.s.glitchPlusCancelAutoRenew : context.s.glitchPlusEnableAutoRenew,
              soft: true,
              loading: _busy,
              onTap: status.willRenew ? _cancel : _resume,
            ),
          ],
          if (status.hasPaymentMethod) ...[
            const SizedBox(height: 10),
            GlitchActionButton(
              label: context.s.glitchPlusDetachCardButton,
              onTap: _busy ? null : _detachCard,
              destructive: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOffer(GlitchPlusStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.s.glitchPlusPriceMonth(status.priceRub), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: GlitchColors.textPrimary)),
        Text(context.s.glitchPlusAutoRenewNote, style: TextStyle(fontSize: 13, color: GlitchColors.textHint)),
        const SizedBox(height: 20),
        GlitchActionButton(
          label: context.s.glitchPlusSubscribeButton,
          loading: _busy,
          onTap: _subscribe,
        ),
      ],
    );
  }

}

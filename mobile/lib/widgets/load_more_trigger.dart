import 'package:flutter/material.dart';

class LoadMoreTrigger extends StatefulWidget {
  final VoidCallback onVisible;

  const LoadMoreTrigger({super.key, required this.onVisible});

  @override
  State<LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}

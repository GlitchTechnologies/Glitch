import 'package:flutter/material.dart';

const double kMaxFormWidth = 460;

class FormWidthLimit extends StatelessWidget {
  final Widget child;

  final double maxWidth;

  const FormWidthLimit({
    super.key,
    required this.child,
    this.maxWidth = kMaxFormWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class CenteredFormBody extends StatelessWidget {
  final Widget child;

  final EdgeInsets padding;

  final double maxWidth;

  const CenteredFormBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
    this.maxWidth = kMaxFormWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight - padding.vertical;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: available > 0 ? available : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

/// Shows a Material dialog and completes only after its exit transition and
/// overlay disposal have finished.
///
/// Flutter's regular [showDialog] future completes as soon as the route is
/// popped, before the reverse animation starts. That is usually convenient,
/// but a confirmed action that replaces the whole session Navigator can then
/// dispose the Navigator while the dialog still has inherited-widget
/// dependents. Waiting for [TransitionRoute.completed] keeps those lifecycle
/// operations strictly ordered.
Future<T?> showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: themes,
    barrierDismissible: barrierDismissible,
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

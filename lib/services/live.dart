import 'dart:async';

/// Shared, replaying Firestore streams.
///
/// `snapshots()` returns a brand-new stream on every call, and Flutter calls
/// `build()` constantly -- switching tabs rebuilds every page in the shell's
/// IndexedStack, and a keystroke in a search field rebuilds that screen. Each
/// rebuild was therefore tearing down a Firestore listener and opening
/// another, which showed up as lists flashing their loading spinner, and quietly
/// cost a fresh read of the whole collection every time.
///
/// [Live.of] hands back the *same* stream for the same key. New subscribers
/// immediately receive the most recent value, so a StreamBuilder that attaches
/// after the data has already arrived renders it straight away instead of
/// starting again at `waiting` -- which is the part that actually stops the
/// flicker.
class Live {
  Live._();

  static final Map<String, _Shared<Object?>> _entries = {};

  /// Returns the shared stream for [key], creating it with [create] the first
  /// time. The key must capture every argument that changes the query, or two
  /// different queries would collide on one entry.
  static Stream<T> of<T>(String key, Stream<T> Function() create) {
    final existing = _entries[key];
    if (existing != null) return (existing as _Shared<T>).stream;

    final shared = _Shared<T>(create());
    _entries[key] = shared as _Shared<Object?>;
    return shared.stream;
  }

  /// Drops every cached stream. Called when the session ends: the next person
  /// to sign in must not be served the previous one's data, and the underlying
  /// listeners have to be closed or they keep reading as the wrong user.
  static Future<void> clear() async {
    final entries = _entries.values.toList();
    _entries.clear();
    for (final entry in entries) {
      await entry.dispose();
    }
  }
}

class _Shared<T> {
  _Shared(Stream<T> source) {
    _subscription = source.listen(
      (value) {
        _latest = value;
        _hasLatest = true;
        _error = null;
        if (!_controller.isClosed) _controller.add(value);
      },
      onError: (Object error) {
        // Held so a late subscriber learns about the failure too, rather than
        // hanging on `waiting` forever because it missed the event.
        _error = error;
        if (!_controller.isClosed) _controller.addError(error);
      },
    );
  }

  final StreamController<T> _controller = StreamController<T>.broadcast();
  late final StreamSubscription<T> _subscription;

  T? _latest;
  bool _hasLatest = false;
  Object? _error;

  /// One object, reused for every subscriber.
  ///
  /// The identity matters as much as the contents. StreamBuilder compares the
  /// stream it was given against the previous one and resubscribes when they
  /// differ, so an `async*` getter -- which mints a fresh Stream on every call
  /// -- left the flicker exactly where it was: each rebuild handed
  /// StreamBuilder a new object, it tore the subscription down, and the list
  /// dropped back to its spinner. `Stream.multi` is the piece that allows both
  /// at once: a single stable object that still supports many listeners and
  /// can replay to each of them individually as they arrive.
  late final Stream<T> stream = Stream<T>.multi((controller) {
    if (_hasLatest) {
      controller.add(_latest as T);
    } else if (_error != null) {
      controller.addError(_error!);
    }

    final subscription = _controller.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }
}

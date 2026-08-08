import 'dart:async';

import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/call.dart';
import '../models/group_call.dart';
import '../models/organization.dart';
import '../services/chat_alerts_service.dart';
import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../services/session_service.dart';
import 'attendance_screen.dart';
import 'chats_screen.dart';
import 'dashboard_screen.dart';
import 'directory_screen.dart';
import 'incoming_call_screen.dart';
import 'incoming_group_call_screen.dart';
import 'leave_screen.dart';
import 'tasks_screen.dart';

/// The signed-in frame: five tabs, kept alive so switching between them does
/// not re-subscribe every Firestore stream.
///
/// It reads the session itself rather than taking it as a constructor argument
/// so that a change made to your own record -- HR promoting you to manager,
/// say -- reaches the tabs immediately.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _alertsFor;

  @override
  void dispose() {
    unawaited(ChatAlertsService.instance.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Session>(
      valueListenable: SessionService.instance.state,
      builder: (context, session, _) {
        // The gate only shows this shell for a ready session; anything else is
        // a momentary state during sign-out.
        if (session is! SessionReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _build(context, session.organization, session.me);
      },
    );
  }

  Widget _build(BuildContext context, Organization org, Employee me) {
    // Started here rather than in main() because it needs the org and the
    // signed-in employee, which only exist once the session is ready.
    if (_alertsFor != me.uid) {
      _alertsFor = me.uid;
      unawaited(ChatAlertsService.instance.start(orgId: org.id, uid: me.uid));
    }

    final pages = [
      DashboardScreen(
        organization: org,
        me: me,
        onOpenTab: (index) => setState(() => _index = index),
      ),
      AttendanceScreen(organization: org, me: me),
      TasksScreen(organization: org, me: me),
      LeaveScreen(organization: org, me: me),
      DirectoryScreen(organization: org, me: me),
      ChatsScreen(organization: org, me: me),
    ];

    return _CallWatcher(
      organization: org,
      me: me,
      child: _buildShell(context, org, me, pages),
    );
  }

  Widget _buildShell(
    BuildContext context,
    Organization org,
    Employee me,
    List<Widget> pages,
  ) {
    return Scaffold(
      // No in-app banner: the system notification already announces the
      // message with the device's own tone and vibration, and a snackbar on
      // top of it was the same news twice. The unread badge and highlighted
      // row are what remain, because those persist rather than interrupt.
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fingerprint_outlined),
            selectedIcon: Icon(Icons.fingerprint),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            selectedIcon: Icon(Icons.event_available),
            label: 'Leave',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Team',
          ),
          NavigationDestination(
            // Badged from the same unread set the Chats list uses, so the
            // count and the dots can never disagree.
            icon: ValueListenableBuilder<Set<String>>(
              valueListenable: ChatAlertsService.instance.unread,
              builder: (context, unread, _) => Badge(
                isLabelVisible: unread.isNotEmpty,
                label: Text('${unread.length}'),
                child: const Icon(Icons.forum_outlined),
              ),
            ),
            selectedIcon: const Icon(Icons.forum),
            label: 'Chats',
          ),
        ],
      ),
    );
  }
}

/// Watches for calls ringing for this person and puts the ring screen up over
/// whatever they were doing.
///
/// It lives at the shell rather than on any one screen because a call cannot
/// wait for the recipient to navigate somewhere first. Only one is ever shown:
/// a second call arriving while the first rings is left in the queue rather
/// than stacking another full-screen route.
class _CallWatcher extends StatefulWidget {
  const _CallWatcher({
    required this.organization,
    required this.me,
    required this.child,
  });

  final Organization organization;
  final Employee me;
  final Widget child;

  @override
  State<_CallWatcher> createState() => _CallWatcherState();
}

class _CallWatcherState extends State<_CallWatcher> {
  StreamSubscription<List<Call>>? _sub;
  StreamSubscription<List<GroupCall>>? _groupSub;
  String? _showing;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _groupSub?.cancel();
    _sub = CallService.instance
        .incoming(widget.organization.id, widget.me.uid)
        .listen(
          _onCalls,
          onError: (Object e) {
            debugPrint('offixia/call: incoming watch failed: $e');
          },
        );
    _groupSub = GroupCallService.instance
        .incoming(widget.organization.id, widget.me.uid)
        .listen(
          _onGroupCalls,
          onError: (Object e) {
            debugPrint('offixia/group-call: incoming watch failed: $e');
          },
        );
  }

  @override
  void didUpdateWidget(covariant _CallWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organization.id != widget.organization.id ||
        oldWidget.me.uid != widget.me.uid) {
      _showing = null;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _groupSub?.cancel();
    super.dispose();
  }

  Future<void> _onGroupCalls(List<GroupCall> calls) async {
    if (!mounted || calls.isEmpty || _showing != null) return;
    final call = calls.first;
    _showing = 'group:${call.id}';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingGroupCallScreen(
          organization: widget.organization,
          me: widget.me,
          call: call,
        ),
      ),
    );
    _showing = null;
  }

  Future<void> _onCalls(List<Call> calls) async {
    if (!mounted || calls.isEmpty) return;
    if (_showing != null) return;

    // Failed/terminated app sessions can leave old documents marked ringing.
    // Never let an arbitrary stale first result hide a newer real call.
    final fresh =
        calls
            .where((call) => call.ringingFor <= const Duration(minutes: 2))
            .toList()
          ..sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
    if (fresh.isEmpty) return;

    final call = fresh.first;

    _showing = call.id;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          organization: widget.organization,
          me: widget.me,
          call: call,
        ),
      ),
    );
    _showing = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

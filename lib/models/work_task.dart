import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskPriority {
  low('Low', 0),
  normal('Normal', 1),
  high('High', 2),
  urgent('Urgent', 3);

  const TaskPriority(this.label, this.weight);
  final String label;
  final int weight;

  static TaskPriority fromName(String? name) => TaskPriority.values.firstWhere(
    (priority) => priority.name == name,
    orElse: () => TaskPriority.normal,
  );
}

enum TaskStatus {
  todo('To do'),
  inProgress('In progress'),
  done('Done');

  const TaskStatus(this.label);
  final String label;

  static TaskStatus fromName(String? name) => TaskStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => TaskStatus.todo,
  );
}

/// Named `WorkTask` rather than `Task` so it never gets confused with the
/// scheduling primitives that share that name in Dart tooling.
class WorkTask {
  const WorkTask({
    required this.id,
    required this.title,
    required this.assigneeUid,
    required this.assigneeName,
    required this.createdByUid,
    required this.createdByName,
    required this.priority,
    required this.status,
    this.description = '',
    this.dueAt,
    this.createdAt,
    this.completedAt,
    this.teamId,
  });

  final String id;
  final String title;
  final String assigneeUid;
  final String assigneeName;
  final String createdByUid;
  final String createdByName;
  final TaskPriority priority;
  final TaskStatus status;
  final String description;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Set when a team lead assigned this to one of their own members.
  ///
  /// Not decoration: it is how the security rules verify the assignment. A
  /// lead has no company-wide authority to hand out work, so the rule reads
  /// this team and checks that the caller leads it and the assignee is in it.
  final String? teamId;

  bool get isDone => status == TaskStatus.done;

  /// Overdue only means anything for work still outstanding, so a task finished
  /// after its due date does not keep shouting.
  bool get isOverdue {
    final due = dueAt;
    if (due == null || isDone) return false;
    return due.isBefore(DateTime.now());
  }

  factory WorkTask.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return WorkTask(
      id: doc.id,
      title: data['title'] as String? ?? 'Untitled task',
      assigneeUid: data['assigneeUid'] as String? ?? '',
      assigneeName: data['assigneeName'] as String? ?? '',
      createdByUid: data['createdByUid'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? '',
      priority: TaskPriority.fromName(data['priority'] as String?),
      status: TaskStatus.fromName(data['status'] as String?),
      description: data['description'] as String? ?? '',
      dueAt: (data['dueAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      teamId: data['teamId'] as String?,
    );
  }
}

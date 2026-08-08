import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../models/work_task.dart';
import 'db.dart';
import 'live.dart';

/// Assigning work and tracking it to done.
class TaskService {
  TaskService._();

  static final TaskService instance = TaskService._();

  Stream<List<WorkTask>> assignedTo(String orgId, String uid) {
    return Live.of('tasks/assigned/$orgId/$uid', () {
      return Db.tasks(orgId)
          .where('assigneeUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(WorkTask.fromDoc).toList());
    });
  }

  Stream<List<WorkTask>> createdBy(String orgId, String uid) {
    return Live.of('tasks/created/$orgId/$uid', () {
      return Db.tasks(orgId)
          .where('createdByUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(WorkTask.fromDoc).toList());
    });
  }

  Stream<List<WorkTask>> all(String orgId) {
    return Db.tasks(orgId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(WorkTask.fromDoc).toList());
  }

  Future<void> create({
    required String orgId,
    required Employee createdBy,
    required Employee assignee,
    required String title,
    required String description,
    required TaskPriority priority,
    DateTime? dueAt,
    String? teamId,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw Exception('Give the task a title.');

    await Db.tasks(orgId).add({
      'title': cleanTitle,
      'description': description.trim(),
      'assigneeUid': assignee.uid,
      'assigneeName': assignee.name,
      'createdByUid': createdBy.uid,
      'createdByName': createdBy.name,
      'priority': priority.name,
      'status': TaskStatus.todo.name,
      'dueAt': dueAt == null ? null : Timestamp.fromDate(dueAt),
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': null,
      // Present only for a team lead's assignment; the rules require it in
      // that case and ignore it otherwise.
      'teamId': ?teamId,
    });
  }

  Future<void> updateStatus({
    required String orgId,
    required WorkTask task,
    required TaskStatus status,
  }) async {
    await Db.tasks(orgId).doc(task.id).update({
      'status': status.name,
      // Cleared when a task is reopened, so "completed" never outlives being
      // done and the history stays honest.
      'completedAt': status == TaskStatus.done
          ? FieldValue.serverTimestamp()
          : null,
    });
  }

  Future<void> edit({
    required String orgId,
    required WorkTask task,
    required String title,
    required String description,
    required TaskPriority priority,
    required Employee assignee,
    DateTime? dueAt,
  }) async {
    await Db.tasks(orgId).doc(task.id).update({
      'title': title.trim(),
      'description': description.trim(),
      'priority': priority.name,
      'assigneeUid': assignee.uid,
      'assigneeName': assignee.name,
      'dueAt': dueAt == null ? null : Timestamp.fromDate(dueAt),
    });
  }

  Future<void> delete({required String orgId, required WorkTask task}) async {
    await Db.tasks(orgId).doc(task.id).delete();
  }
}

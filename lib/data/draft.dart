import 'models.dart';

/// Kept only on this device. Never sent to InkApi.
class Draft {
  const Draft({required this.id, required this.day, required this.topic, required this.body,
    required this.updated, this.kind = EntryKind.original, this.title = '', this.author = ''});
  final String id, day, topic, body, title, author;
  final EntryKind kind;
  final DateTime updated;
  Map<String, dynamic> toJson() => {'id': id, 'day': day, 'topic': topic, 'body': body,
    'kind': kind.name, 'title': title, 'author': author, 'updated': updated.toIso8601String()};
  factory Draft.fromJson(Map<String, dynamic> j) => Draft(id: j['id'] as String, day: j['day'] as String,
    topic: j['topic'] as String, body: j['body'] as String, updated: DateTime.parse(j['updated'] as String),
    kind: j['kind'] == 'quote' ? EntryKind.quote : EntryKind.original,
    title: j['title'] as String? ?? '', author: j['author'] as String? ?? '');
}

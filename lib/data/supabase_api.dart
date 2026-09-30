import 'package:supabase_flutter/supabase_flutter.dart';

import 'ink_api.dart';
import 'models.dart';

/// Supabase RPC 로 서버와 이야기한다. 함수 목록은 supabase/schema.sql.
class SupabaseInkApi implements InkApi {
  SupabaseInkApi(this.client);

  final SupabaseClient client;

  Future<T> _call<T>(String fn, Map<String, dynamic>? params, T Function(dynamic) parse) async {
    try {
      final res = await client.rpc(fn, params: params);
      return parse(res);
    } on PostgrestException catch (e) {
      throw InkError.fromMessage(e.message);
    } on AuthException catch (e) {
      throw InkError('auth', e.message);
    } on InkError {
      rethrow;
    } catch (e) {
      throw InkError('network', '$e');
    }
  }

  static Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);

  @override
  Future<void> ensureSignedIn() async {
    if (client.auth.currentSession != null) return;
    try {
      await client.auth.signInAnonymously();
    } on AuthException catch (e) {
      throw InkError('auth', e.message);
    } catch (e) {
      throw InkError('network', '$e');
    }
  }

  @override
  Future<Board> board({DateTime? day}) => _call(
        'get_board',
        {'p_day': day == null ? null : '${day.year}-${two(day.month)}-${two(day.day)}'},
        (r) => Board.fromJson(_map(r)),
      );

  @override
  Future<PostResult> post(String body, {EntryKind kind = EntryKind.original, String? title, String? author}) =>
      _call(
        'post_entry',
        {
          'p_body': body,
          'p_kind': kind == EntryKind.quote ? 'quote' : 'original',
          'p_title': title,
          'p_author': author,
        },
        (r) {
          final m = _map(r);
          return PostResult((m['slot'] as num).toInt(), (m['count'] as num).toInt(), (m['cap'] as num).toInt());
        },
      );

  @override
  Future<LikeResult> like(int id) => _call('toggle_like', {'p_id': id}, (r) {
        final m = _map(r);
        return LikeResult((m['likes'] as num).toInt(), m['liked'] as bool);
      });

  @override
  Future<bool> report(int id, String reason) =>
      _call('report_post', {'p_id': id, 'p_reason': reason}, (r) => _map(r)['hidden'] as bool? ?? false);

  @override
  Future<void> deleteMine(int id) => _call('delete_my_post', {'p_id': id}, (_) {});

  @override
  Future<Hall> hall() => _call('get_hall', null, (r) => Hall.fromJson(_map(r)));

  @override
  Future<List<Entry>> mine() => _call('my_posts', null, (r) => [
        for (final e in (r as List? ?? const [])) Entry.fromJson(_map(e)),
      ]);
}

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/pen_shop.dart' show ShopEvent;
import 'ink_api.dart';
import 'models.dart';

/// Supabase RPC 로 서버와 이야기한다. 함수 목록은 supabase/schema.sql.
class SupabaseInkApi implements InkApi {
  SupabaseInkApi(this.client, {this.deviceId});

  final SupabaseClient client;

  /// 이 기기의 ID (lib/data/device_id.dart). 로그인 뒤 한 번 서버에 묶는다.
  final Future<String?> Function()? deviceId;
  bool _bound = false;

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
    if (client.auth.currentSession == null) {
      try {
        await client.auth.signInAnonymously();
      } on AuthException catch (e) {
        throw InkError('auth', e.message);
      } catch (e) {
        throw InkError('network', '$e');
      }
    }
    await _bindDevice();
  }

  /// 앱을 다시 깔아 새 익명 사용자가 돼도 같은 기기로 알아보게 한다. 실패하면 다음에 다시.
  Future<void> _bindDevice() async {
    final get = deviceId;
    if (_bound || get == null) return;
    final id = await get();
    if (id == null) return;
    try {
      await client.rpc('bind_device', params: {'p_device': id});
      _bound = true;
    } catch (e) {
      // 글쓰기 등에서 'ink:device' 로 알려진다.
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
  Future<PenStatus> myPen() => _call('my_pen', null, (r) => PenStatus.fromJson(_map(r)));

  @override
  Future<PenStatus> setPen(String name) => _call('set_pen', {'p_name': name}, (r) => PenStatus.fromJson(_map(r)));

  /// supabase/functions/claim-pen 이 Apple 서명을 확인한다.
  @override
  Future<PenStatus> claimPen(String receipt) async {
    try {
      final body = receipt.startsWith(ShopEvent.googleReceiptPrefix)
          ? {'google': jsonDecode(receipt.substring(ShopEvent.googleReceiptPrefix.length))}
          : {'jws': receipt};
      final res = await client.functions.invoke('claim-pen', body: body);
      return PenStatus.fromJson(_map(res.data));
    } on FunctionException catch (e) {
      final d = e.details;
      final code = d is Map && d['error'] is String ? d['error'] as String : 'pen_receipt';
      throw InkError(code == 'server' ? 'network' : code, '${e.status} ${e.details}');
    } catch (e) {
      throw InkError('network', '$e');
    }
  }

  @override
  Future<List<Entry>> mine() => _call('my_posts', null, (r) => [
        for (final e in (r as List? ?? const [])) Entry.fromJson(_map(e)),
      ]);
}

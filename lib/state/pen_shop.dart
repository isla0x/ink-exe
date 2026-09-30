import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 결제 창구에서 온 소식.
enum ShopStatus { pending, done, error, canceled }

class ShopEvent {
  const ShopEvent(this.status, {this.receipt, this.restored = false, this.error, this.raw});

  final ShopStatus status;

  /// done 일 때: 서버에 보낼 영수증 (StoreKit 2 JWS)
  final String? receipt;
  final bool restored;
  final String? error;

  /// 결제를 마무리할 때 쓰는 원본 (IAP 의 PurchaseDetails)
  final Object? raw;
}

/// 펜네임 결제 창구. 실제는 [IapPenShop], 테스트 · 데모는 [DemoPenShop].
abstract class PenShop {
  /// App Store Connect 에 이 ID 로 비소모성 상품을 만든다.
  static const productId = 'ink_exe_pen';

  /// 스토어에 연결하고 상품을 불러온다. 결제할 수 있으면 true.
  Future<bool> connect();

  /// Apple 이 알려준 가격 (`₩2,200`). 못 불러왔으면 null.
  String? get price;

  Stream<ShopEvent> get events;

  Future<void> buy();

  Future<void> restore();

  /// 서버가 영수증을 받아 준 뒤에 부른다. 부르기 전까지는 앱을 다시 켤 때마다 다시 온다.
  Future<void> finish(ShopEvent e);

  void dispose();
}

/// App Store 인앱결제 (in_app_purchase, StoreKit 2).
class IapPenShop implements PenShop {
  IapPenShop({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  final _events = StreamController<ShopEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _available = false;

  @override
  String? get price => _product?.price;

  @override
  Stream<ShopEvent> get events => _events.stream;

  @override
  Future<bool> connect() async {
    try {
      _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        _events.add(ShopEvent(ShopStatus.error, error: '$e'));
      });
      _available = await _iap.isAvailable();
      if (_available) await _loadProduct();
    } catch (e) {
      debugPrint('ink.exe pen: 스토어 연결 실패 ($e)');
      _available = false;
    }
    return _available && _product != null;
  }

  Future<void> _loadProduct() async {
    try {
      final res = await _iap.queryProductDetails({PenShop.productId});
      _product = res.productDetails.isEmpty ? null : res.productDetails.first;
      if (_product == null) debugPrint('ink.exe pen: 상품 없음 ${res.notFoundIDs} ${res.error}');
    } catch (e) {
      debugPrint('ink.exe pen: 상품 조회 실패 ($e)');
    }
  }

  @override
  Future<void> buy() async {
    if (!_available || _product == null) {
      await connect();
      if (_product == null) throw StateError('store');
    }
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: _product!));
  }

  @override
  Future<void> restore() async {
    if (!_available) await connect();
    await _iap.restorePurchases();
  }

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.productID != PenShop.productId) {
        // 모르는 상품은 그냥 마무리한다.
        if (p.pendingCompletePurchase) unawaited(_iap.completePurchase(p));
        continue;
      }
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const ShopEvent(ShopStatus.pending));
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          _events.add(ShopEvent(
            ShopStatus.done,
            receipt: p.verificationData.serverVerificationData,
            restored: p.status == PurchaseStatus.restored,
            raw: p,
          ));
        case PurchaseStatus.error:
          _events.add(ShopEvent(ShopStatus.error, error: p.error?.message, raw: p));
          if (p.pendingCompletePurchase) unawaited(_iap.completePurchase(p));
        case PurchaseStatus.canceled:
          _events.add(ShopEvent(ShopStatus.canceled, raw: p));
          if (p.pendingCompletePurchase) unawaited(_iap.completePurchase(p));
      }
    }
  }

  @override
  Future<void> finish(ShopEvent e) async {
    final p = e.raw;
    if (p is PurchaseDetails && p.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(p);
      } catch (err) {
        debugPrint('ink.exe pen: completePurchase 실패 ($err)');
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}

/// 가짜 결제 창구: 누르면 바로 결제된 것으로 친다.
class DemoPenShop implements PenShop {
  DemoPenShop({this.receipt = 'demo-receipt', this.hasPurchase = false});

  /// 결제하면 나오는 영수증.
  String receipt;

  /// 복원할 구매가 있는지.
  bool hasPurchase;

  final _events = StreamController<ShopEvent>.broadcast();
  int finished = 0;

  @override
  String? get price => '₩2,200';

  @override
  Stream<ShopEvent> get events => _events.stream;

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> buy() async {
    hasPurchase = true;
    _events.add(ShopEvent(ShopStatus.done, receipt: receipt));
  }

  @override
  Future<void> restore() async {
    if (hasPurchase) _events.add(ShopEvent(ShopStatus.done, receipt: receipt, restored: true));
  }

  @override
  Future<void> finish(ShopEvent e) async => finished++;

  @override
  void dispose() => _events.close();
}

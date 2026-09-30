// 펜네임 결제 확인 (Supabase Edge Function: claim-pen)
//
// 앱 → 로그인 토큰 + 영수증 하나
//   iOS    : { jws }                         StoreKit 2 거래 영수증
//   Android: { google: { data, signature } } Google Play 구매 원본 JSON + 서명
//   1. 로그인한 익명 사용자가 누구인지 확인
//   2. iOS: Apple 서명 · 번들 · 상품 · 환불 여부 확인 (verifyAppleJws · checkPenPurchase)
//      Android: Google Play 라이선스 공개키로 서명 확인 · 패키지 · 상품 · 구매 완료 여부 (verifyGooglePurchase)
//      공개키는 Supabase 함수 Secrets 의 GOOGLE_PLAY_PUBLIC_KEY (Play Console → 수익 창출 설정 → 라이선스)
//   3. service_role 로 ink_grant_pen 을 불러 이 사용자에게 펜네임 권한을 준다
// ← { owned, name, next_change } 또는 { error: '<코드>' }
//
// service_role 키는 Supabase 가 함수 안에 자동으로 넣어 준다. 앱이나 저장소에는 절대 없다.
// 대시보드 편집기에 그대로 붙여 넣을 수 있게 파일 하나로 되어 있다. 테스트: test.ts

import * as x509 from 'npm:@peculiar/x509@1.14.3';
import { createClient } from 'npm:@supabase/supabase-js@2';

const BUNDLE_ID = 'com.isla0x.inkExe';
const PRODUCT_ID = 'ink_exe_pen'; // lib/state/pen_shop.dart 의 PenShop.productId 와 같게
const PACKAGE_NAME = 'com.isla0x.ink_exe'; // android/app/build.gradle.kts 의 applicationId

x509.cryptoProvider.set(crypto);

// ─────────────── Apple StoreKit 2 거래 영수증(JWS) 확인 ───────────────
// 외부 키 없이 Apple 인증서 체인만으로:
//   1. 헤더의 x5c = [leaf, intermediate, root] 인증서 3장
//   2. root 가 Apple Root CA - G3 인지 (SHA-256 지문 비교)
//   3. root → intermediate → leaf 서명이 이어지는지, 기간이 유효한지, Apple 표식(OID)이 있는지
//   4. leaf 공개키로 JWS 서명(ES256)이 맞는지

export const APPLE_ROOT_CA_G3_SHA256 =
  '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';
const OID_LEAF = '1.2.840.113635.100.6.11.1';
const OID_INTERMEDIATE = '1.2.840.113635.100.6.2.1';

export class JwsError extends Error {}

function b64urlToBytes(s: string) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}
function b64ToBytes(s: string) {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
async function sha256Hex(bytes: BufferSource): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...d].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** 확인된 거래 내용(payload)을 돌려준다. 테스트에서는 rootSha256 · now 를 바꿔 넣는다. */
export async function verifyAppleJws(
  jws: unknown,
  { rootSha256 = APPLE_ROOT_CA_G3_SHA256, now = new Date() }: { rootSha256?: string; now?: Date } = {},
  // deno-lint-ignore no-explicit-any
): Promise<Record<string, any>> {
  if (typeof jws !== 'string') throw new JwsError('format');
  const parts = jws.split('.');
  if (parts.length !== 3) throw new JwsError('format');
  // deno-lint-ignore no-explicit-any
  let header: any, payload: any;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
  } catch {
    throw new JwsError('format');
  }
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError('header');

  const ders = (header.x5c as string[]).map(b64ToBytes);
  if ((await sha256Hex(ders[2])) !== rootSha256.toLowerCase().replace(/:/g, '')) throw new JwsError('root');
  const [leaf, mid, root] = ders.map((d) => new x509.X509Certificate(d));

  for (const c of [leaf, mid, root]) {
    if (!(c.notBefore <= now && now <= c.notAfter)) throw new JwsError('expired');
  }
  if (!(await mid.verify({ publicKey: root.publicKey, signatureOnly: true }))) throw new JwsError('chain');
  if (!(await leaf.verify({ publicKey: mid.publicKey, signatureOnly: true }))) throw new JwsError('chain');
  if (!mid.getExtension(OID_INTERMEDIATE) || !leaf.getExtension(OID_LEAF)) throw new JwsError('oid');

  const key = await leaf.publicKey.export({ name: 'ECDSA', namedCurve: 'P-256' }, ['verify']);
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(parts[0] + '.' + parts[1]),
  );
  if (!ok) throw new JwsError('signature');
  return payload;
}

/** 펜네임 구매가 맞는지. 맞으면 {txn, env} 를 돌려준다. */
export function checkPenPurchase(
  // deno-lint-ignore no-explicit-any
  t: Record<string, any>,
  { bundleId, productId }: { bundleId: string; productId: string },
): { txn: string; env: string } {
  if (t.bundleId !== bundleId) throw new JwsError('bundle');
  if (t.productId !== productId) throw new JwsError('product');
  if (t.revocationDate) throw new JwsError('revoked');
  const txn = String(t.originalTransactionId ?? '');
  if (!txn) throw new JwsError('txn');
  return { txn, env: String(t.environment ?? '') };
}

// ─────────────── Google Play 구매 확인 ───────────────
// Play 가 구매 원본 JSON 을 앱의 라이선스 키(RSA)로 서명해 준다 (SHA1withRSA).
// 공개키로 서명만 확인하면 돼서 서비스 계정 같은 비밀 키가 필요 없다.

function b64ToBuf(s: string) {
  return Uint8Array.from(atob(s.replace(/\s+/g, '')), (c) => c.charCodeAt(0));
}

/** 서명이 맞으면 구매 내용(JSON)을 돌려준다. */
export async function verifyGooglePurchase(
  data: unknown,
  signature: unknown,
  publicKeyB64: string | undefined,
  // deno-lint-ignore no-explicit-any
): Promise<Record<string, any>> {
  if (!publicKeyB64) throw new JwsError('no_key');
  if (typeof data !== 'string' || typeof signature !== 'string' || !data || !signature) throw new JwsError('format');
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      'spki', b64ToBuf(publicKeyB64), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-1' }, false, ['verify'],
    );
  } catch {
    throw new JwsError('bad_key');
  }
  let sig: Uint8Array<ArrayBuffer>;
  try {
    sig = b64ToBuf(signature);
  } catch {
    throw new JwsError('format');
  }
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, new TextEncoder().encode(data));
  if (!ok) throw new JwsError('signature');
  try {
    return JSON.parse(data);
  } catch {
    throw new JwsError('format');
  }
}

/** Google Play 펜네임 구매가 맞는지. 맞으면 {txn, env}. txn 은 구매 토큰 (구매 복원해도 같다). */
export function checkGooglePenPurchase(
  // deno-lint-ignore no-explicit-any
  p: Record<string, any>,
  { packageName, productId }: { packageName: string; productId: string },
): { txn: string; env: string } {
  if (p.packageName !== packageName) throw new JwsError('bundle');
  const products: unknown[] = Array.isArray(p.productIds) ? p.productIds : [p.productId];
  if (!products.includes(productId)) throw new JwsError('product');
  // purchaseState: 0 구매 완료 · 1 취소 · 2 대기
  if ((p.purchaseState ?? 0) !== 0) throw new JwsError('state');
  const token = String(p.purchaseToken ?? '');
  if (!token) throw new JwsError('txn');
  // 라이선스 테스터의 테스트 구매는 주문 번호가 없다.
  return { txn: 'gp:' + token, env: p.orderId ? 'GooglePlay' : 'GooglePlayTest' };
}

// ─────────────── 요청 처리 ───────────────

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Supabase 가 함수에 자동으로 넣어 주는 서버 전용 키. 옛 방식(service_role)이 없으면 새 방식(secret) 키.
function serviceKey(): string {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>;
    return keys.default ?? Object.values(keys)[0] ?? '';
  } catch {
    return '';
  }
}

function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'method' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(url, serviceKey(), { auth: { persistSession: false } });

  // 로그인 토큰 확인은 여기서 직접 한다 (대시보드의 'Verify JWT with legacy secret' 은 꺼 둔다:
  // 이 프로젝트는 새 ES256 서명 키를 써서 legacy 검사로는 사용자 토큰이 통과하지 못한다).
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: u, error: authError } = token ? await admin.auth.getUser(token) : { data: null, error: true };
  if (authError || !u?.user) return reply(401, { error: 'auth' });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: 'pen_receipt' });
  }

  let txn: string, env: string;
  try {
    if (body?.google) {
      const p = await verifyGooglePurchase(body.google.data, body.google.signature, Deno.env.get('GOOGLE_PLAY_PUBLIC_KEY'));
      ({ txn, env } = checkGooglePenPurchase(p, { packageName: PACKAGE_NAME, productId: PRODUCT_ID }));
    } else {
      const t = await verifyAppleJws(body?.jws);
      ({ txn, env } = checkPenPurchase(t, { bundleId: BUNDLE_ID, productId: PRODUCT_ID }));
    }
  } catch (e) {
    const why = e instanceof JwsError ? e.message : 'unknown';
    console.warn('claim-pen rejected:', why);
    return reply(400, { error: 'pen_receipt', why });
  }

  const { data, error } = await admin.rpc('ink_grant_pen', { p_user: u.user.id, p_txn: txn, p_env: env });
  if (error) {
    console.error('ink_grant_pen failed:', error.message);
    return reply(500, { error: 'server' });
  }
  return reply(200, data);
});

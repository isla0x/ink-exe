// claim-pen 테스트: 가짜 Apple 인증서 체인을 만들어 확인 로직을 검사한다.
//   deno test --allow-net --allow-env supabase/functions/claim-pen/test.ts
import * as x509 from 'npm:@peculiar/x509@1.14.3';

// index.ts 를 불러올 때 서버가 뜨지 않게.
// deno-lint-ignore no-explicit-any
(Deno as any).serve = () => {};
const { verifyAppleJws, checkPenPurchase, JwsError } = await import('./index.ts');

x509.cryptoProvider.set(crypto);
const P256 = { name: 'ECDSA', namedCurve: 'P-256', hash: 'SHA-256' };
const P384 = { name: 'ECDSA', namedCurve: 'P-384', hash: 'SHA-384' };
const NULL = new Uint8Array([5, 0]);
const now = new Date('2026-10-01T00:00:00Z');
const from = new Date('2025-01-01T00:00:00Z'), to = new Date('2030-01-01T00:00:00Z');

async function chain({ oids = true } = {}) {
  const rootKeys = await crypto.subtle.generateKey(P384, true, ['sign', 'verify']) as CryptoKeyPair;
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: '01', name: 'CN=Fake Apple Root', notBefore: from, notAfter: to, signingAlgorithm: P384, keys: rootKeys,
  });
  const midKeys = await crypto.subtle.generateKey(P256, true, ['sign', 'verify']) as CryptoKeyPair;
  const mid = await x509.X509CertificateGenerator.create({
    serialNumber: '02', subject: 'CN=Fake WWDR', issuer: root.subject, notBefore: from, notAfter: to,
    signingAlgorithm: P384, publicKey: midKeys.publicKey, signingKey: rootKeys.privateKey,
    extensions: oids ? [new x509.Extension('1.2.840.113635.100.6.2.1', false, NULL)] : [],
  });
  const leafKeys = await crypto.subtle.generateKey(P256, true, ['sign', 'verify']) as CryptoKeyPair;
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: '03', subject: 'CN=Fake StoreKit', issuer: mid.subject, notBefore: from, notAfter: to,
    signingAlgorithm: P256, publicKey: leafKeys.publicKey, signingKey: midKeys.privateKey,
    extensions: oids ? [new x509.Extension('1.2.840.113635.100.6.11.1', false, NULL)] : [],
  });
  const fp = [...new Uint8Array(await crypto.subtle.digest('SHA-256', root.rawData))]
    .map((b) => b.toString(16).padStart(2, '0')).join('');
  return { certs: [leaf, mid, root], leafKey: leafKeys.privateKey, fp };
}

const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const b64url = (u: Uint8Array) => b64(u).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));

async function sign(c: Awaited<ReturnType<typeof chain>>, payload: unknown, key = c.leafKey) {
  const h = enc({ alg: 'ES256', x5c: c.certs.map((x) => b64(new Uint8Array(x.rawData))) });
  const p = enc(payload);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${b64url(sig)}`;
}

const tx = {
  bundleId: 'com.isla0x.inkExe', productId: 'com.isla0x.inkExe.pen', originalTransactionId: '2000000123',
  transactionId: '2000000456', environment: 'Sandbox', type: 'Non-Consumable',
};
const want = { bundleId: 'com.isla0x.inkExe', productId: 'com.isla0x.inkExe.pen' };

async function rejects(p: Promise<unknown>, why: string) {
  try {
    await p;
  } catch (e) {
    if (e instanceof JwsError && e.message === why) return;
    throw new Error(`expected ${why}, got ${e}`);
  }
  throw new Error(`expected ${why}, but passed`);
}

Deno.test('정상 영수증은 통과하고 거래 번호를 돌려준다', async () => {
  const c = await chain();
  const t = await verifyAppleJws(await sign(c, tx), { rootSha256: c.fp, now });
  const r = checkPenPurchase(t, want);
  if (r.txn !== '2000000123' || r.env !== 'Sandbox') throw new Error(JSON.stringify(r));
});

Deno.test('진짜 Apple 루트가 아니면 거절 (기본값 = Apple Root CA G3)', async () => {
  const c = await chain();
  await rejects(verifyAppleJws(await sign(c, tx), { now }), 'root');
});

Deno.test('내용을 바꾸면 서명이 안 맞는다', async () => {
  const c = await chain();
  const [h, , s] = (await sign(c, tx)).split('.');
  await rejects(verifyAppleJws(`${h}.${enc({ ...tx, productId: 'x' })}.${s}`, { rootSha256: c.fp, now }), 'signature');
});

Deno.test('다른 키로 서명하면 거절', async () => {
  const c = await chain();
  const other = await crypto.subtle.generateKey(P256, true, ['sign', 'verify']) as CryptoKeyPair;
  await rejects(verifyAppleJws(await sign(c, tx, other.privateKey), { rootSha256: c.fp, now }), 'signature');
});

Deno.test('체인이 이어지지 않으면 거절', async () => {
  const a = await chain(), b = await chain();
  const mixed = { ...a, certs: [a.certs[0], b.certs[1], a.certs[2]] };
  await rejects(verifyAppleJws(await sign(mixed, tx), { rootSha256: a.fp, now }), 'chain');
});

Deno.test('Apple 표식(OID)이 없으면 거절', async () => {
  const c = await chain({ oids: false });
  await rejects(verifyAppleJws(await sign(c, tx), { rootSha256: c.fp, now }), 'oid');
});

Deno.test('기간이 지난 인증서는 거절', async () => {
  const c = await chain();
  await rejects(verifyAppleJws(await sign(c, tx), { rootSha256: c.fp, now: new Date('2031-01-01') }), 'expired');
});

Deno.test('형식이 이상하면 거절', async () => {
  await rejects(verifyAppleJws('abc'), 'format');
  await rejects(verifyAppleJws(123), 'format');
  await rejects(verifyAppleJws(`${enc({ alg: 'none' })}.${enc(tx)}.`), 'header');
});

Deno.test('다른 앱 · 다른 상품 · 환불된 구매는 거절', () => {
  const bad = (t: Record<string, unknown>, why: string) => {
    try {
      checkPenPurchase(t, want);
    } catch (e) {
      if (e instanceof JwsError && e.message === why) return;
      throw e;
    }
    throw new Error(`expected ${why}`);
  };
  bad({ ...tx, bundleId: 'com.other.app' }, 'bundle');
  bad({ ...tx, productId: 'com.isla0x.inkExe.tip' }, 'product');
  bad({ ...tx, revocationDate: 1760000000000 }, 'revoked');
  bad({ ...tx, originalTransactionId: '' }, 'txn');
});

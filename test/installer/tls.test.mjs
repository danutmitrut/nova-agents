import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rootCertificates } from 'node:tls';
const mod = await import('../../scripts/installer/tls.mjs').catch(() => ({}));
test('approved CA validation rejects bypasses, ambiguous keys and invalid PEM', () => {
    assert.equal(typeof mod.validateCA, 'function');
    const dir = mkdtempSync(join(tmpdir(), 'nova-ca-'));
    try {
        const path = join(dir, 'ca.pem');
        writeFileSync(path, rootCertificates[0]);
        assert.deepEqual(mod.validateCA({}), { path: null });
        assert.deepEqual(mod.validateCA({ NODE_EXTRA_CA_CERTS: path }), { path });
        for (const env of [{ NODE_TLS_REJECT_UNAUTHORIZED: '0' }, { NODE_EXTRA_CA_CERTS: 'relative' }, { NODE_EXTRA_CA_CERTS: join(dir, 'missing') }, { NODE_EXTRA_CA_CERTS: path, node_extra_ca_certs: path }]) {
            assert.throws(() => mod.validateCA(env));
        }
        writeFileSync(path, rootCertificates[0] + '\nnot a certificate');
        assert.throws(() => mod.validateCA({ NODE_EXTRA_CA_CERTS: path }));
    }
    finally {
        rmSync(dir, { recursive: true });
    }
});
test('probe uses selected fresh Node, bounded timeout and sanitized failure', async () => {
    assert.equal(typeof mod.probeTLS, 'function');
    let seen;
    await mod.probeTLS({ hostname: 'api.telegram.org', node: '/selected/node', env: {} }, { run: (...args) => { seen = args; return { stdout: '{"ok":true}' }; } });
    assert.equal(seen[0], '/selected/node');
    assert.equal(seen[2].timeoutMs, 10000);
    await assert.rejects(mod.probeTLS({ hostname: 'slack.com', node: '/selected/node', env: {} }, { run: () => ({ stdout: '{"code":"CERT_HAS_EXPIRED"}' }) }), { code: 'TLS_CERT_HAS_EXPIRED' });
});

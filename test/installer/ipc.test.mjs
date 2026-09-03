import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const mod = await import('../../scripts/installer/ipc.mjs').catch(() => ({}));
test('IPC handles fragmented response, rejection, timeout, size and connection failure', async () => {
    assert.equal(typeof mod.requestIPC, 'function');
    const dir = mkdtempSync(join(tmpdir(), 'nova-ipc-'));
    const endpoint = join(dir, 's');
    let mode = 'fragment';
    const sockets = new Set();
    const server = net.createServer(socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); socket.on('error', () => { }); socket.once('data', data => { assert.deepEqual(JSON.parse(data), { type: 'status', source: 'nova-installer' }); if (mode === 'fragment') {
        socket.write('{"success":');
        setImmediate(() => socket.end('true,"data":[]}'));
    } if (mode === 'reject') {
        socket.end('{"success":false}');
    } if (mode === 'large') {
        socket.end('x'.repeat(2000));
    } }); });
    await new Promise(resolve => server.listen(endpoint, resolve));
    try {
        assert.deepEqual(await mod.requestIPC({ type: 'status', source: 'nova-installer' }, { endpoint }), { success: true, data: [] });
        for (const [value, code] of [['reject', 'IPC_REJECTED'], ['large', 'IPC_TOO_LARGE'], ['timeout', 'IPC_TIMEOUT']]) {
            mode = value;
            await assert.rejects(mod.requestIPC({ type: 'status', source: 'nova-installer' }, { endpoint, timeoutMs: 30, maxBytes: 1000 }), { code });
        }
    }
    finally {
        for (const socket of sockets) {
            socket.destroy();
        }
        await new Promise(resolve => server.close(resolve));
        rmSync(dir, { recursive: true });
    }
    await assert.rejects(mod.requestIPC({ type: 'status' }, { endpoint }), { code: 'IPC_CONNECTION_FAILED' });
});

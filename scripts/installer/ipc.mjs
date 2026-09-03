import net from 'node:net';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { InstallError } from './system.mjs';
/** Pinned engine protocol, without the CLI's implicit start/save fallback. */
export function requestIPC(request, { endpoint = process.platform === 'win32' ? '\\\\.\\pipe\\cortextos-default' : join(homedir(), '.cortextos', 'default', 'daemon.sock'), timeoutMs = 5000, maxBytes = 1024 * 1024 } = {}) {
    return new Promise((resolve, reject) => {
        let bytes = 0;
        const chunks = [];
        const socket = net.createConnection(endpoint);
        const finish = (code, result) => {
            clearTimeout(timer);
            socket.destroy();
            if (code) {
                reject(new InstallError(code, code));
            }
            else {
                resolve(result);
            }
        };
        const timer = setTimeout(() => finish('IPC_TIMEOUT'), timeoutMs);
        socket.once('connect', () => socket.write(JSON.stringify(request)));
        socket.on('data', chunk => {
            bytes += chunk.length;
            if (bytes > maxBytes) {
                finish('IPC_TOO_LARGE');
            }
            else {
                chunks.push(chunk);
            }
        });
        socket.once('error', () => finish('IPC_CONNECTION_FAILED'));
        socket.once('end', () => {
            let result;
            try {
                result = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            }
            catch {
                return finish('IPC_INVALID_RESPONSE');
            }
            if (result?.success !== true) {
                return finish('IPC_REJECTED');
            }
            finish(null, result);
        });
    });
}

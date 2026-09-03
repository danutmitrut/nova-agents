import { existsSync, readFileSync, statSync, openSync, readSync, closeSync } from 'node:fs';
import { homedir, userInfo } from 'node:os';
import { join, isAbsolute, resolve } from 'node:path';
import net from 'node:net';
import { InstallError, run, resolveNodeTool, samePath } from './system.mjs';
import { validateCA, validateEnvironment, probeTLS } from './tls.mjs';
import { requestIPC } from './ipc.mjs';
import { verifyEngine } from './engine.mjs';
const fail = code => {
    throw new InstallError(code, code);
};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const alive = pid => {
    try {
        process.kill(pid, 0);
        return true;
    }
    catch (error) {
        return error.code === 'EPERM';
    }
};
function pidFile(path) {
    if (!existsSync(path)) {
        return null;
    }
    try {
        const text = readFileSync(path, 'utf8').trim();
        if (!/^[1-9]\d*$/.test(text)) {
            fail('RUNTIME_PID_INVALID');
        }
        return Number(text);
    }
    catch (error) {
        if (error instanceof InstallError) {
            throw error;
        }
        fail('RUNTIME_PID_INVALID');
    }
}
function context(options = {}, adapters = {}) {
    const env = options.env ?? process.env;
    validateEnvironment(env);
    const root = resolve(options.root ?? env.CORTEXTOS_DIR ?? join(homedir(), 'cortextos'));
    const stateRoot = resolve(options.stateRoot ?? join(homedir(), '.cortextos', 'default'));
    const pm2Home = env.PM2_HOME ?? join(homedir(), '.pm2');
    if (!isAbsolute(pm2Home)) {
        fail('PM2_HOME_MISMATCH');
    }
    if ((options.instance ?? 'default') !== 'default' || (env.CTX_INSTANCE_ID && env.CTX_INSTANCE_ID !== 'default') || (env.CTX_ROOT && !samePath(env.CTX_ROOT, stateRoot))) {
        fail('UNSUPPORTED_INSTANCE');
    }
    for (const key of ['CTX_FRAMEWORK_ROOT', 'CTX_PROJECT_ROOT']) {
        if (env[key] && !samePath(env[key], root)) {
            fail('PM2_IDENTITY_MISMATCH');
        }
    }
    const tool = (adapters.resolveNodeTool ?? resolveNodeTool)('pm2', { env });
    return { ...options, env, root, stateRoot, pm2Home, tool, instance: 'default' };
}
function select(record) {
    const e = record.pm2_env ?? record;
    validateEnvironment(e);
    const nested = e.env ?? {};
    validateEnvironment(nested);
    for (const key of ['CTX_INSTANCE_ID', 'CTX_ROOT', 'CTX_FRAMEWORK_ROOT', 'CTX_PROJECT_ROOT', 'NODE_EXTRA_CA_CERTS', 'NODE_TLS_REJECT_UNAUTHORIZED', 'PM2_HOME']) {
        if (key in e && key in nested && e[key] !== nested[key]) {
            fail('PM2_ENV_CONFLICT');
        }
    }
    const effective = { ...e, ...nested };
    validateEnvironment(effective);
    return {
        id: record.pm_id ?? e.pm_id, name: record.name ?? e.name,
        pid: record.pid ?? e.pid, status: e.status,
        cwd: e.pm_cwd, script: e.pm_exec_path, node: e.exec_interpreter,
        instance: effective.CTX_INSTANCE_ID, stateRoot: effective.CTX_ROOT,
        frameworkRoot: effective.CTX_FRAMEWORK_ROOT, projectRoot: effective.CTX_PROJECT_ROOT,
        extraCA: effective.NODE_EXTRA_CA_CERTS ?? null, pm2Home: effective.PM2_HOME,
        username: e.username, restarts: e.restart_time, startedAt: e.pm_uptime,
        stdoutPath: e.pm_out_log_path, stderrPath: e.pm_err_log_path,
    };
}
function parse(text) {
    try {
        const raw = JSON.parse(text);
        if (!Array.isArray(raw)) {
            fail('PM2_INVALID_RESPONSE');
        }
        return raw.map(select);
    }
    catch (error) {
        if (error instanceof InstallError) {
            throw error;
        }
        fail('PM2_INVALID_RESPONSE');
    }
}
function daemon(p) {
    return p.name?.startsWith('cortextos') || p.script?.replaceAll('\\', '/').endsWith('/dist/daemon.js');
}
function identity(p, c, { exactNode = false } = {}) {
    if (!Number.isInteger(p.id) || p.id < 0) {
        fail('PM2_IDENTITY_MISMATCH');
    }
    persistentIdentity(p, c, { exactNode });
}
/** PM2 removes live-only pm_id when saving; persistent identity excludes it. */
function persistentIdentity(p, c, { exactNode = true } = {}) {
    if (p.instance !== 'default') {
        fail('PM2_IDENTITY_MISMATCH');
    }
    const expectedPaths = [
        [p.stateRoot, c.stateRoot], [p.frameworkRoot, c.root],
        [p.projectRoot, c.root], [p.cwd, c.root],
        [p.script, join(c.root, 'dist', 'daemon.js')],
    ];
    for (const [actual, expected] of expectedPaths) {
        if (!actual || !samePath(actual, expected)) {
            fail('PM2_IDENTITY_MISMATCH');
        }
    }
    const unresolvedLegacyNode = !exactNode && p.node === 'node';
    if (!unresolvedLegacyNode && (!p.node || !isAbsolute(p.node) || !samePath(p.node, c.tool.node))) {
        fail('PM2_IDENTITY_MISMATCH');
    }
    if (typeof p.pm2Home !== 'string' || !isAbsolute(p.pm2Home) || typeof p.username !== 'string' || !p.username.trim()) {
        fail('PM2_RECOVERY_REQUIRED');
    }
    if (!samePath(p.pm2Home, c.pm2Home)) {
        fail('PM2_HOME_MISMATCH');
    }
    if (p.username !== userInfo().username) {
        fail('PM2_USER_MISMATCH');
    }
}
async function pm2(c, args, adapters, mutation = false, env = c.env) {
    const timeoutMs = remaining(c, adapters, 10000);
    try {
        return await (adapters.run ?? run)(c.tool.node, [c.tool.script, ...args], { cwd: c.root, env, timeoutMs });
    }
    catch {
        fail(mutation ? 'PM2_MUTATION_FAILED' : 'PM2_ACCESS_FAILED');
    }
}
function remaining(c, adapters, maximum) {
    const left = c.readinessDeadline === undefined ? maximum : c.readinessDeadline - (adapters.now ?? Date.now)();
    if (left <= 0) {
        fail('RUNTIME_READINESS_TIMEOUT');
    }
    return Math.min(maximum, left);
}
/** Parse immediately into the allowlisted ProcessInfo fields. Caller must preflight the PM2 pid. */
export async function readProcesses(adapters = {}) {
    const c = context(adapters.options ?? {}, adapters);
    dumps(c);
    const pid = pidFile(join(c.pm2Home, 'pm2.pid'));
    if (!pid || !(adapters.isAlive ?? alive)(pid)) {
        fail('PM2_NOT_RUNNING');
    }
    const result = parse((await pm2(c, ['jlist'], adapters)).stdout);
    if (pidFile(join(c.pm2Home, 'pm2.pid')) !== pid || !(adapters.isAlive ?? alive)(pid)) {
        fail('PM2_CONTEXT_CHANGED');
    }
    return result;
}
async function pipePresent(endpoint) {
    return new Promise(resolve => {
        const socket = net.createConnection(endpoint);
        let finished = false;
        const finish = value => {
            if (finished) {
                return;
            }
            finished = true;
            socket.destroy();
            resolve(value);
        };
        socket.setTimeout(200, () => finish(false));
        socket.once('connect', () => finish(true));
        socket.once('error', () => finish(false));
    });
}
function dumps(c) {
    return ['dump.pm2', 'dump.pm2.bak'].map(name => {
        const path = join(c.pm2Home, name);
        return { path, exists: existsSync(path), processes: existsSync(path) ? parse(readFileSync(path, 'utf8')) : [] };
    });
}
/** Read-only preflight: do not invoke PM2 when its intended daemon is absent. */
export async function inspectRuntime(options = {}, adapters = {}) {
    const c = context(options, adapters);
    const saved = dumps(c);
    const pm2Pid = pidFile(join(c.pm2Home, 'pm2.pid'));
    const live = pm2Pid && (adapters.isAlive ?? alive)(pm2Pid);
    if ((adapters.platform ?? process.platform) === 'win32' && !live && await (adapters.pipePresent ?? pipePresent)('\\\\.\\pipe\\rpc.sock')) {
        fail('PM2_HOME_MISMATCH');
    }
    let processes = [];
    if (live) {
        processes = await readProcesses({ ...adapters, options: c });
        if (pidFile(join(c.pm2Home, 'pm2.pid')) !== pm2Pid || !(adapters.isAlive ?? alive)(pm2Pid)) {
            fail('PM2_CONTEXT_CHANGED');
        }
    }
    const candidates = processes.filter(daemon);
    if (candidates.length > 1) {
        fail('PM2_AMBIGUOUS');
    }
    const selected = candidates[0] ?? null;
    if (!selected && saved.some(d => d.processes.some(daemon))) {
        fail('PM2_RECOVERY_REQUIRED');
    }
    if (!live && saved.some(d => d.exists)) {
        fail('PM2_RECOVERY_REQUIRED');
    }
    if (selected) {
        identity(selected, c);
        if (selected.status !== 'online' || !Number.isInteger(selected.pid) || selected.pid <= 0) {
            fail('PM2_UNHEALTHY');
        }
        if (!c.env.NODE_EXTRA_CA_CERTS && selected.extraCA) {
            fail('CA_RESTORE_REQUIRED');
        }
    }
    else {
        const daemonPid = pidFile(join(c.stateRoot, 'daemon.pid'));
        if (daemonPid && (adapters.isAlive ?? alive)(daemonPid)) {
            fail('UNMANAGED_DAEMON');
        }
        const endpoint = (adapters.platform ?? process.platform) === 'win32' ? '\\\\.\\pipe\\cortextos-default' : join(c.stateRoot, 'daemon.sock');
        if (await (adapters.pipePresent ?? pipePresent)(endpoint)) {
            fail('UNMANAGED_DAEMON');
        }
    }
    return { processes, selected, pm2Pid: live ? pm2Pid : null, dumps: saved.map(d => ({ path: d.path, exists: d.exists })) };
}
const signature = snapshot => JSON.stringify(snapshot.processes.map(p => p).sort((a, b) => a.id - b.id));
function offsets(paths) {
    return paths.map(path => {
        if (!path || !isAbsolute(path)) {
            fail('RUNTIME_LOGS_MISSING');
        }
        if (!existsSync(path)) {
            return { path, size: 0, ino: null };
        }
        const s = statSync(path);
        return { path, size: s.size, ino: s.ino };
    });
}
function delta(logs) {
    return logs.map(log => {
        if (!existsSync(log.path)) {
            fail('RUNTIME_LOGS_MISSING');
        }
        const s = statSync(log.path);
        if (s.size < log.size || (log.ino !== null && s.ino !== log.ino) || s.size - log.size > 1024 * 1024) {
            fail('RUNTIME_LOGS_AMBIGUOUS');
        }
        const fd = openSync(log.path, 'r');
        const buffer = Buffer.alloc(s.size - log.size);
        try {
            readSync(fd, buffer, 0, buffer.length, log.size);
        }
        finally {
            closeSync(fd);
        }
        return buffer.toString('utf8');
    }).join('\n');
}
async function health(c, adapters, { logs, requireBootstrap = false } = {}) {
    const snapshot = await inspectRuntime(c, adapters);
    const p = snapshot.selected;
    if (!p) {
        fail('PM2_UNHEALTHY');
    }
    identity(p, c, { exactNode: true });
    if (p.extraCA !== (c.env.NODE_EXTRA_CA_CERTS ?? null)) {
        fail('PM2_CA_MISMATCH');
    }
    if (pidFile(join(c.stateRoot, 'daemon.pid')) !== p.pid) {
        fail('RUNTIME_PID_MISMATCH');
    }
    if (logs) {
        const fresh = delta(logs);
        if (/SELF_SIGNED_CERT|CERT_HAS_EXPIRED|UNABLE_TO_VERIFY_LEAF_SIGNATURE|UNABLE_TO_GET_ISSUER_CERT|certificate verify failed/i.test(fresh)) {
            fail('RUNTIME_TLS_ERROR');
        }
        if (requireBootstrap && !fresh.includes(`[daemon] Running (pid: ${p.pid})`)) {
            fail('RUNTIME_BOOTSTRAP_MISSING');
        }
    }
    const response = await (adapters.requestIPC ?? requestIPC)({ type: 'status', source: 'nova-installer' }, { endpoint: (adapters.platform ?? process.platform) === 'win32' ? '\\\\.\\pipe\\cortextos-default' : join(c.stateRoot, 'daemon.sock'), timeoutMs: remaining(c, adapters, 5000) });
    remaining(c, adapters, 5000);
    if (response?.success !== true || !Array.isArray(response.data)) {
        fail('IPC_INVALID_RESPONSE');
    }
    return { ...snapshot, boss: response.data.find(a => a.name === 'boss' && a.status === 'running' && Number.isInteger(a.pid) && a.pid > 0 && !a.awaitingConfirmation && !a.dormant) };
}
/** Save only an unchanged, reverified process set; validate the resulting dump in memory. */
export async function guardedSave(options, adapters = {}) {
    const c = context(options, adapters);
    validateCA(c.env);
    await (adapters.verifyEngine ?? verifyEngine)(c, { ...adapters, inspectRuntime });
    const first = await health(c, adapters);
    if (c.confirmedSnapshot && signature(c.confirmedSnapshot) !== signature(first)) {
        fail('PM2_PROCESS_SET_CHANGED');
    }
    if (!first.boss) {
        fail('BOSS_NOT_RUNNING');
    }
    if (first.processes.length > 1 && !c.allowGlobalSave) {
        fail('GLOBAL_SAVE_CONSENT_REQUIRED');
    }
    if (c.expectedSnapshot && signature(first) !== c.expectedSnapshot) {
        fail('PM2_PROCESS_SET_CHANGED');
    }
    const second = await health(c, adapters);
    if (!second.boss) {
        fail('BOSS_NOT_RUNNING');
    }
    if (signature(first) !== signature(second)) {
        fail('PM2_PROCESS_SET_CHANGED');
    }
    await pm2(c, ['save'], adapters, true);
    const saved = dumps(c)[0].processes.filter(daemon);
    if (saved.length !== 1) {
        fail('PM2_SAVE_INVALID');
    }
    persistentIdentity(saved[0], c);
    if (saved[0].extraCA !== (c.env.NODE_EXTRA_CA_CERTS ?? null)) {
        fail('PM2_SAVE_INVALID');
    }
    return { saved: true, autoStartVerified: false };
}
/** Revalidate receipt, then mutate only the identified daemon with explicit consent. */
export async function ensureRuntime(options, adapters = {}) {
    const c = context(options, adapters);
    validateCA(c.env);
    await (adapters.verifyEngine ?? verifyEngine)(c, { ...adapters, inspectRuntime });
    const first = await inspectRuntime(c, adapters);
    if (c.confirmedSnapshot && signature(c.confirmedSnapshot) !== signature(first)) {
        fail('PM2_PROCESS_SET_CHANGED');
    }
    if (first.selected && !c.allowRestart) {
        fail('RESTART_CONSENT_REQUIRED');
    }
    if (!['telegram', 'slack'].includes(c.channel) || !c.org || !/^[a-zA-Z0-9_-]+$/.test(c.org)) {
        fail('RUNTIME_ARGUMENTS_INVALID');
    }
    await (adapters.probeTLS ?? probeTLS)({ hostname: c.channel === 'telegram' ? 'api.telegram.org' : 'slack.com', node: c.tool.node, env: c.env }, adapters);
    const second = await inspectRuntime(c, adapters);
    if (signature(first) !== signature(second) || first.pm2Pid !== second.pm2Pid) {
        fail('PM2_PROCESS_SET_CHANGED');
    }
    const env = { ...c.env, CTX_INSTANCE_ID: 'default', CTX_ROOT: c.stateRoot, CTX_FRAMEWORK_ROOT: c.root, CTX_PROJECT_ROOT: c.root, CTX_ORG: c.org };
    const out = first.selected?.stdoutPath ?? join(c.stateRoot, 'logs', 'daemon-out.log');
    const err = first.selected?.stderrPath ?? join(c.stateRoot, 'logs', 'daemon-error.log');
    const logs = offsets([out, err]);
    if (first.selected) {
        await pm2(c, ['restart', String(first.selected.id), '--interpreter', c.tool.node, '--update-env'], adapters, true, env);
    }
    else {
        await pm2(c, ['start', join(c.root, 'dist', 'daemon.js'), '--name', 'cortextos-daemon', '--cwd', c.root, '--interpreter', c.tool.node, '--output', out, '--error', err, '--', '--instance', 'default'], adapters, true, env);
    }
    const now = adapters.now ?? Date.now;
    const started = now();
    c.readinessDeadline = started + 30000;
    let observed;
    let asked = false;
    let lastError;
    do {
        try {
            const current = await health(c, adapters, { logs, requireBootstrap: true });
            if (observed && (observed.selected.pid !== current.selected.pid || observed.selected.restarts !== current.selected.restarts)) {
                fail('RUNTIME_UNSTABLE');
            }
            observed ??= current;
            if (!current.boss && !asked) {
                asked = true;
                await (adapters.requestIPC ?? requestIPC)({ type: 'start-agent', agent: 'boss', source: 'nova-installer' }, { endpoint: (adapters.platform ?? process.platform) === 'win32' ? '\\\\.\\pipe\\cortextos-default' : join(c.stateRoot, 'daemon.sock'), timeoutMs: remaining(c, adapters, 5000) });
            }
            if (current.boss) {
                await (adapters.sleep ?? pause)(remaining(c, adapters, 1000));
                const stable = await health(c, adapters, { logs, requireBootstrap: true });
                if (stable.selected.pid !== current.selected.pid || stable.selected.restarts !== current.selected.restarts) {
                    fail('RUNTIME_UNSTABLE');
                }
                if (!stable.boss) {
                    fail('BOSS_NOT_RUNNING');
                }
                const initialOthers = { processes: first.processes.filter(p => p.id !== first.selected?.id) };
                const finalOthers = { processes: stable.processes.filter(p => p.id !== stable.selected.id) };
                if (signature(initialOthers) !== signature(finalOthers)) {
                    fail('PM2_PROCESS_SET_CHANGED');
                }
                return guardedSave({ ...c, readinessDeadline: undefined, confirmedSnapshot: undefined, expectedSnapshot: signature(stable) }, adapters);
            }
        }
        catch (error) {
            if (!['IPC_CONNECTION_FAILED', 'IPC_TIMEOUT', 'RUNTIME_BOOTSTRAP_MISSING', 'RUNTIME_PID_MISMATCH', 'RUNTIME_LOGS_MISSING'].includes(error.code)) {
                throw error;
            }
            lastError = error;
        }
        await (adapters.sleep ?? pause)(remaining(c, adapters, 250));
    } while (now() - started < 30000);
    throw lastError ?? new InstallError('BOSS_NOT_RUNNING', 'BOSS_NOT_RUNNING');
}

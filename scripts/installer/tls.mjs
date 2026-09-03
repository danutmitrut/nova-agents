import { readFileSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { X509Certificate } from 'node:crypto';
import { InstallError, run } from './system.mjs';
export function validateEnvironment(env) {
    const seen = new Set();
    for (const key of Object.keys(env)) {
        const upper = key.toUpperCase();
        if (seen.has(upper)) {
            throw new InstallError('ENV_CASE_CONFLICT', 'ENV_CASE_CONFLICT');
        }
        seen.add(upper);
        if ((upper === 'NODE_TLS_REJECT_UNAUTHORIZED' && String(env[key]) === '0') || (upper === 'NPM_CONFIG_STRICT_SSL' && String(env[key]).toLowerCase() === 'false')) {
            throw new InstallError('TLS_BYPASS_REFUSED', 'TLS_BYPASS_REFUSED');
        }
    }
}
/** Validate only explicitly approved trust; never modify global environment. */
export function validateCA(env = process.env) {
    validateEnvironment(env);
    const path = env.NODE_EXTRA_CA_CERTS;
    if (!path) {
        return { path: null };
    }
    if (!isAbsolute(path)) {
        throw new InstallError('CA_INVALID', 'CA_INVALID');
    }
    try {
        const pem = readFileSync(path, 'utf8');
        const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
        if (!blocks?.length || pem.replace(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g, '').trim()) {
            throw Error();
        }
        for (const block of blocks) {
            new X509Certificate(block);
        }
    }
    catch {
        throw new InstallError('CA_INVALID', 'CA_INVALID');
    }
    return { path };
}
/** NODE_EXTRA_CA_CERTS is read at process startup; probe in selected fresh Node. */
export async function probeTLS({ hostname, node, env }, adapters = {}) {
    validateCA(env);
    if (!['api.telegram.org', 'slack.com'].includes(hostname)) {
        throw new InstallError('TLS_HOST_REFUSED', 'TLS_HOST_REFUSED');
    }
    const source = `const https=require('node:https');const r=https.get({hostname:process.argv[1],path:'/',timeout:9000},s=>{s.destroy();console.log(JSON.stringify({ok:true}));});r.on('timeout',()=>r.destroy(Object.assign(new Error(),{code:'TIMEOUT'})));r.on('error',e=>console.log(JSON.stringify({code:e.code})));`;
    let result;
    try {
        result = JSON.parse((await (adapters.run ?? run)(node, ['-e', source, hostname], { env, timeoutMs: 10000 })).stdout);
    }
    catch {
        throw new InstallError('TLS_PROBE_FAILED', 'TLS_PROBE_FAILED');
    }
    if (result.ok === true) {
        return;
    }
    const allowed = ['CERT_HAS_EXPIRED', 'SELF_SIGNED_CERT_IN_CHAIN', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'ENOTFOUND', 'ECONNRESET', 'ECONNREFUSED', 'TIMEOUT'];
    const code = allowed.includes(result.code) ? `TLS_${result.code}` : 'TLS_PROBE_FAILED';
    throw new InstallError(code, code);
}

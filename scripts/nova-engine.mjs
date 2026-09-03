#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { prepareEngine, verifyEngine } from './installer/engine.mjs';
import { InstallError } from './installer/system.mjs';
import { inspectRuntime, ensureRuntime, guardedSave } from './installer/pm2.mjs';
import { createInterface } from 'node:readline/promises';
async function confirm(prompt) {
    if (!process.stdin.isTTY || !process.stdout.isTTY) {
        return false;
    }
    const input = createInterface({ input: process.stdin, output: process.stdout });
    try {
        return (await input.question(`${prompt} [da/NU] `)).trim().toLowerCase() === 'da';
    }
    catch {
        return false;
    }
    finally {
        input.close();
    }
}
/** Uses only the bundled release; runtime inspection is wired by Task 3 integration. */
export async function main(args = process.argv.slice(2), adapters = {}) {
    try {
        const command = args[0];
        const validStart = command === 'start' && args.length === 5 && args[1] === '--org' && /^[a-zA-Z0-9_-]+$/.test(args[2]) && args[3] === '--channel' && ['telegram', 'slack'].includes(args[4]);
        if (!validStart && !(args.length === 1 && ['prepare', 'check', 'save'].includes(command))) {
            throw new InstallError('ARGUMENTE_INVALIDE', 'ARGUMENTE_INVALIDE');
        }
        const release = JSON.parse(readFileSync(new URL('./installer/engine-release.json', import.meta.url), 'utf8'));
        const runtimeAdapters = { inspectRuntime, ...adapters };
        if (command === 'start' || command === 'save') {
            const options = { release, env: process.env, org: args[2], channel: args[4] };
            const snapshot = await runtimeAdapters.inspectRuntime(options, runtimeAdapters);
            if (command === 'start' && snapshot.selected) {
                options.allowRestart = await (adapters.confirm ?? confirm)('Repornirea daemonului întrerupe agenții existenți. Aprobați?');
                if (!options.allowRestart) {
                    throw new InstallError('RESTART_CONSENT_REQUIRED', 'Consimțământul pentru repornire lipsește.');
                }
            }
            if (snapshot.processes.length > (snapshot.selected ? 1 : 0)) {
                options.allowGlobalSave = await (adapters.confirm ?? confirm)('PM2 save salvează și celelalte aplicații. Aprobați snapshotul global?');
                if (!options.allowGlobalSave) {
                    throw new InstallError('GLOBAL_SAVE_CONSENT_REQUIRED', 'Consimțământul pentru salvarea globală lipsește.');
                }
            }
            options.confirmedSnapshot = snapshot;
            await (command === 'start' ? (adapters.ensureRuntime ?? ensureRuntime) : (adapters.guardedSave ?? guardedSave))(options, runtimeAdapters);
            process.stdout.write('Salvat pentru restaurare; pornirea automată Windows nu este verificată.\n');
            return 0;
        }
        const receipt = await (command === 'prepare' ? prepareEngine : verifyEngine)({ release, env: process.env }, runtimeAdapters);
        process.stdout.write(`Engine verificat: ${receipt.sha}\n`);
        if (args[0] === 'prepare') {
            process.stdout.write('Procesele existente nu au fost repornite. KB, voce și dashboard: configurare opțională separată.\n');
        }
        return 0;
    }
    catch (error) {
        process.stderr.write(`Oprit: ${error instanceof InstallError ? error.message : 'EROARE_INSTALARE'}\n`);
        if (error.sourceSha) {
            process.stderr.write(`Sursă: ${error.sourceSha}; ultima compilare reușită: ${error.lastSuccessfulSha ?? 'lipsește'}\n`);
        }
        return 1;
    }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    process.exitCode = await main();
}

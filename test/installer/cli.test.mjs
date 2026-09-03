import test from 'node:test';
import assert from 'node:assert/strict';
import { main } from '../../scripts/nova-engine.mjs';
test('fresh start asks global consent when one unrelated app already exists', async () => {
    let prompted = false;
    const result = await main(['start', '--org', 'test', '--channel', 'telegram'], {
        inspectRuntime: async () => ({ selected: null, processes: [{ id: 4 }] }),
        confirm: async () => { prompted = true; return true; },
        ensureRuntime: async options => assert.equal(options.allowGlobalSave, true),
    });
    assert.equal(result, 0);
    assert.equal(prompted, true);
});
test('CLI start requests explicit restart/global save consent and supplies bundled release', async () => {
    const calls = [];
    const result = await main(['start', '--org', 'test', '--channel', 'telegram'], { inspectRuntime: async () => ({ selected: { id: 0 }, processes: [{}, {}] }), confirm: async (prompt) => { calls.push(prompt); return true; }, ensureRuntime: async (options) => { assert.equal(options.allowRestart, true); assert.equal(options.allowGlobalSave, true); assert.equal(options.channel, 'telegram'); assert.match(options.release.sha, /^[0-9a-f]{40}$/); calls.push('start'); } });
    assert.equal(result, 0);
    assert.equal(calls.length, 3);
});
test('CLI refuses restart when interactive consent is absent', async () => {
    let started = false;
    assert.equal(await main(['start', '--org', 'test', '--channel', 'slack'], { inspectRuntime: async () => ({ selected: { id: 0 }, processes: [{}] }), confirm: async () => false, ensureRuntime: async () => { started = true; } }), 1);
    assert.equal(started, false);
});
test('CLI save passes approved snapshot boundary and does not dispatch invalid args', async () => {
    let saved = false;
    const adapters = { inspectRuntime: async () => ({ selected: { id: 0 }, processes: [{}] }), guardedSave: async () => { saved = true; } };
    assert.equal(await main(['save'], adapters), 0);
    assert.equal(saved, true);
    assert.equal(await main(['start', '--org', 'x'], adapters), 1);
});

// Consume raw PM2 output only in Node, never in PowerShell's JSON parser.
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
    try {
        const all = JSON.parse(input);
        if (!Array.isArray(all)) throw Error();
        const bridge = all.filter(record => record?.name === 'nova-slack-bridge');
        if (bridge.length !== 1 || bridge[0].pm2_env?.status !== 'online') throw Error();
        process.stdout.write('online\n');
    } catch {
        process.exitCode = 1;
    }
});

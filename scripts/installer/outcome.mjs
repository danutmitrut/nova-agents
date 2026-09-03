/** Allowlisted evidence only; never retain environment or process records. */
export function phaseOutcome(c, receipt, { build = 'verified', runtime = false } = {}) {
    return {
        root: receipt?.root ?? c.root,
        requestedSha: c.release?.sha ?? null,
        sourceSha: receipt?.sha ?? null,
        build,
        ca: c.env.NODE_EXTRA_CA_CERTS ? (runtime ? 'validated-propagated' : 'configured-not-validated') : 'absent',
        daemon: runtime ? 'verified-online' : 'restart-pending',
        boss: runtime ? 'verified-running' : 'not-verified',
        saved: runtime,
        saveReason: runtime ? null : 'runtime-not-verified',
        autoStartVerified: false,
        channelRoundtripVerified: false,
    };
}

export function printOutcome(outcome, write = text => process.stdout.write(text)) {
    // Select fields explicitly, even when an adapter adds other result fields.
    write(`Engine: ${JSON.stringify(outcome.root)}\nSHA cerut: ${outcome.requestedSha ?? 'neverificat'}; sursă: ${outcome.sourceSha ?? 'neverificată'}\n`);
    write(`Build: ${outcome.build}; CA: ${outcome.ca}\nDaemon: ${outcome.daemon}; BOSS: ${outcome.boss}\n`);
    write(outcome.saved ? 'PM2: salvat pentru restaurare.\n' : `PM2: salvare neverificată (${outcome.saveReason}).\n`);
    write('Pornirea automată Windows: neverificată. Telegram/Slack capăt-la-capăt: neverificat.\n');
}

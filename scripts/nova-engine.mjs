#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {prepareEngine,verifyEngine} from './installer/engine.mjs';
import {InstallError} from './installer/system.mjs';

/** Uses only the bundled release; runtime inspection is wired by Task 3 integration. */
export async function main(args=process.argv.slice(2),adapters={}) {
  try {
    if(args.length!==1||!['prepare','check'].includes(args[0]))throw new InstallError('ARGUMENTE_INVALIDE','ARGUMENTE_INVALIDE');
    const release=JSON.parse(readFileSync(new URL('./installer/engine-release.json',import.meta.url),'utf8'));
    const receipt=await (args[0]==='prepare'?prepareEngine:verifyEngine)({release,env:process.env},adapters);
    process.stdout.write(`Engine verificat: ${receipt.sha}\n`);
    if(args[0]==='prepare')process.stdout.write('Procesele existente nu au fost repornite. KB, voce și dashboard: configurare opțională separată.\n');
    return 0;
  } catch(error) {
    process.stderr.write(`Oprit: ${error instanceof InstallError?error.message:'EROARE_INSTALARE'}\n`);
    if(error.sourceSha)process.stderr.write(`Sursă: ${error.sourceSha}; ultima compilare reușită: ${error.lastSuccessfulSha??'lipsește'}\n`);
    return 1;
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)process.exitCode=await main();

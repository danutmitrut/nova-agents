import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync, readFileSync, mkdirSync, existsSync, rmSync, statSync, symlinkSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {fixtureRepo} from './fixtures.mjs';
import {run, InstallError} from '../../scripts/installer/system.mjs';

const engine = await import('../../scripts/installer/engine.mjs').catch(() => ({}));
function fixture(t) {
  const f = fixtureRepo(t);
  const canonical = 'https://github.com/danutmitrut/cortextos.git';
  const sg = args => run('git', ['-C', f.source, ...args], {env: process.env, timeoutMs:5000});
  for (const [name, data] of Object.entries({'package.json':JSON.stringify({name:'cortextos'}),'package-lock.json':'{}','.gitignore':'dist/\nnode_modules/\n'})) writeFileSync(join(f.source,name),data);
  sg(['add','.']); sg(['commit','-m','engine package']);
  f.newSha=sg(['rev-parse','HEAD']).stdout.trim();
  f.git(['remote','set-url','origin',canonical]);
  f.git(['checkout','--detach',f.oldSha]);
  f.release={schema:1,repo:canonical,ref:'refs/heads/main',sha:f.newSha};
  f.env={...process.env,CORTEXTOS_STATE_DIR:join(f.source,'..','state')};
  let linked=null;
  f.commands=[];
  f.adapters={
    findTool:()=>linked,
    resolveNodeTool:()=>({node:process.execPath,script:'controlled-npm'}),
    inspectRuntime:async()=>({}),
    run(command,args,options) {
      f.commands.push([command,...args]);
      if(command==='git') return run(command,['-c',`url.${f.source}.insteadOf=${canonical}`,...args],options);
      assert.equal(args[0],'controlled-npm');
      if (args[1]==='run') {
        mkdirSync(join(f.root,'dist'),{recursive:true});
        run(process.execPath,['-e',`require('fs').writeFileSync('dist/daemon.js','new daemon\\n');require('fs').writeFileSync('dist/cli.js','// cli\\n')`],options);
      } else if(args[1]==='link') linked=join(f.root,'dist','cli.js');
      return {stdout:'',stderr:''};
    },
  };
  f.prepare=()=>engine.prepareEngine({root:f.root,stateRoot:f.env.CORTEXTOS_STATE_DIR,release:f.release,env:f.env},f.adapters);
  f.verify=()=>engine.verifyEngine({root:f.root,stateRoot:f.env.CORTEXTOS_STATE_DIR,release:f.release,env:f.env},f.adapters);
  return f;
}
test('engine public preparation contract exists',()=>assert.equal(typeof engine.prepareEngine,'function'));
test('stale engine fast forwards, builds accepted artifact and read-only check accepts later untracked template',async t=>{
  const f=fixture(t); const receipt=await f.prepare();
  assert.equal(f.git(['rev-parse','HEAD']).stdout.trim(),f.newSha);
  assert.equal(receipt.sha,f.newSha); assert.equal(readFileSync(join(f.root,'dist/daemon.js'),'utf8'),'new daemon\n');
  writeFileSync(join(f.root,'template.md'),'student template');
  assert.deepEqual(await f.verify(),receipt);
  assert.ok(f.commands.some(c=>c.includes('--ignore-scripts')&&c.includes('--package-lock=false')));
  writeFileSync(join(f.root,'dist/daemon.js'),'tampered');
  await assert.rejects(f.verify(),{code:'ARTIFACT_MISMATCH'});
});
for(const kind of ['untracked','tracked','rename']) test(`${kind} Unicode changes refuse update without altering HEAD or data`,async t=>{
  const f=fixture(t); const name=kind==='tracked'?'package.json':'notă student.txt';
  if(kind==='rename') f.git(['mv','build.mjs',name]); else writeFileSync(join(f.root,name),'keep me');
  await assert.rejects(f.prepare(),{code:'DIRTY_WORKTREE'});
  assert.equal(f.git(['rev-parse','HEAD']).stdout.trim(),f.oldSha); assert.ok(existsSync(join(f.root,name)));
});
test('fresh no-checkout clone initializes narrow private state without optional installers',async t=>{
  const f=fixture(t); rmSync(f.root,{recursive:true}); await f.prepare();
  assert.equal(readFileSync(join(f.env.CORTEXTOS_STATE_DIR,'config/enabled-agents.json'),'utf8'),'{}\n');
  assert.equal(readFileSync(join(f.env.CORTEXTOS_STATE_DIR,'config/bus-signing-key'),'utf8').trim().length,64);
  if(process.platform!=='win32') assert.equal(statSync(join(f.env.CORTEXTOS_STATE_DIR,'.env')).mode&0o777,0o600);
  assert.ok(f.commands.some(c=>c.includes('--no-checkout')));
  assert.ok(!f.commands.some(c=>c.includes('install')));
});
test('matching upstream remote and exact SHA preserve branch and existing state',async t=>{
  const f=fixture(t); f.git(['remote','rename','origin','upstream']);f.git(['switch','-c','student']);
  mkdirSync(f.env.CORTEXTOS_STATE_DIR); writeFileSync(join(f.env.CORTEXTOS_STATE_DIR,'.env'),'keep secret');
  await f.prepare(); await f.prepare();
  assert.equal(f.git(['remote']).stdout.trim(),'upstream');
  assert.equal(readFileSync(join(f.env.CORTEXTOS_STATE_DIR,'.env'),'utf8'),'keep secret');
  assert.equal(f.git(['branch','--show-current']).stdout.trim(),'student');
  assert.ok(!existsSync(join(f.env.CORTEXTOS_STATE_DIR,'config')));
});
test('existing clean engine with genuinely absent state initializes it',async t=>{
  const f=fixture(t);await f.prepare();assert.ok(existsSync(join(f.env.CORTEXTOS_STATE_DIR,'config/bus-signing-key')));
});
for(const kind of ['remote','non-git','ahead','fetch','ref','build','link','global','runtime','missing-runtime']) test(`${kind} fails closed`,async t=>{
  const f=fixture(t);
  const codes={remote:'REMOTE_MISMATCH','non-git':'NOT_ENGINE_REPOSITORY',ahead:'NON_FAST_FORWARD',fetch:'FETCH_FAILED',ref:'RELEASE_NOT_REACHABLE',build:'BUILD_FAILED',link:'LINK_FAILED',global:'GLOBAL_LINK_MISMATCH',runtime:'RUNTIME_PATH_MISMATCH','missing-runtime':'RUNTIME_INSPECTION_REQUIRED'};
  if(kind==='remote') f.git(['remote','set-url','origin','https://example.invalid/wrong.git']);
  if(kind==='non-git') rmSync(join(f.root,'.git'),{recursive:true});
  if(kind==='ahead') { f.release.sha=f.oldSha; f.git(['checkout','--detach', 'main']); }
  if(kind==='ref') f.release.sha='1'.repeat(40);
  if(kind==='global') f.adapters.findTool=()=>'/wrong/dist/cli.js';
  if(kind==='runtime') f.adapters.inspectRuntime=()=>{throw new InstallError('RUNTIME_PATH_MISMATCH','wrong');};
  if(kind==='missing-runtime') delete f.adapters.inspectRuntime;
  if(['fetch','build','link'].includes(kind)) { const original=f.adapters.run; f.adapters.run=(c,a,o)=>{if(a.includes(kind==='build'?'build':kind)) throw new Error('secret raw failure'); return original(c,a,o);}; }
  await assert.rejects(f.prepare(),e=>e.code===codes[kind]&&!e.message.includes('secret raw failure'));
  assert.ok(!existsSync(join(f.root,'.git/nova-installer/build.json')));
});
test('failed rebuild preserves previous receipt and distinguishes source from last build',async t=>{
  const f=fixture(t); const first=await f.prepare();
  const before=readFileSync(join(f.root,'.git/nova-installer/build.json'),'utf8');
  const original=f.adapters.run; f.adapters.run=(c,a,o)=>{if(a.includes('build'))throw new Error('private');return original(c,a,o);};
  await assert.rejects(f.prepare(),e=>e.code==='BUILD_FAILED'&&e.sourceSha===f.newSha&&e.lastSuccessfulSha===first.sha);
  assert.equal(readFileSync(join(f.root,'.git/nova-installer/build.json'),'utf8'),before);
});
test('divergence refuses without altering branch',async t=>{
  const f=fixture(t); f.git(['switch','-c','student']);f.git(['config','user.name','Student']);f.git(['config','user.email','student@example.invalid']);
  writeFileSync(join(f.root,'student.txt'),'mine');f.git(['add','.']);f.git(['commit','-m','student']);
  const head=f.git(['rev-parse','HEAD']).stdout;
  await assert.rejects(f.prepare(),{code:'NON_FAST_FORWARD'});
  assert.equal(f.git(['rev-parse','HEAD']).stdout,head);assert.equal(f.git(['branch','--show-current']).stdout.trim(),'student');
});
test('changed fetched ref cannot bless previously downloaded but unreachable commit',async t=>{
  const f=fixture(t);await f.prepare();
  run('git',['-C',f.source,'update-ref','refs/heads/main',f.oldSha],{env:process.env,timeoutMs:5000});
  await assert.rejects(f.prepare(),{code:'RELEASE_NOT_REACHABLE'});
});
test('POSIX executable repair touches only real dependency spawn-helper files',async t=>{
  if(process.platform==='win32')return t.skip('POSIX permission contract');
  const f=fixture(t); const own=join(f.source,'..','external-helper');writeFileSync(own,'keep',{mode:0o600});
  const original=f.adapters.run;
  f.adapters.run=(c,a,o)=>{
    if(a.includes('ci')) {mkdirSync(join(f.root,'node_modules/node-pty/prebuilds'),{recursive:true});writeFileSync(join(f.root,'node_modules/node-pty/prebuilds/spawn-helper'),'helper',{mode:0o600});symlinkSync(own,join(f.root,'node_modules/node-pty/spawn-helper'));writeFileSync(join(f.root,'node_modules/node-pty/other'),'keep',{mode:0o600});}
    return original(c,a,o);
  };
  await f.prepare(); assert.equal(statSync(join(f.root,'node_modules/node-pty/prebuilds/spawn-helper')).mode&0o111,0o111);
  assert.equal(statSync(own).mode&0o777,0o600);assert.equal(statSync(join(f.root,'node_modules/node-pty/other')).mode&0o777,0o600);
});
test('unsafe fresh state is rejected before cloning',async t=>{
  const f=fixture(t);rmSync(f.root,{recursive:true});symlinkSync(f.source,f.env.CORTEXTOS_STATE_DIR);
  await assert.rejects(f.prepare(),{code:'UNSAFE_STATE'});assert.ok(!existsSync(f.root));
});
test('nondefault runtime instance refuses before mutation',async t=>{
  const f=fixture(t);f.env.CTX_INSTANCE_ID='student';await assert.rejects(f.prepare(),{code:'UNSUPPORTED_INSTANCE'});assert.equal(f.commands.length,0);
});
test('CLI rejects unknown arguments without child mutation',()=>{
  const result=spawnSync(process.execPath,['scripts/nova-engine.mjs','prepare','--release=evil'],{encoding:'utf8'});
  assert.equal(result.status,1);assert.match(result.stderr,/ARGUMENTE_INVALIDE/);assert.doesNotMatch(result.stderr,/ERR_MODULE_NOT_FOUND/);
});
test('read-only check rejects tracked edits and a replaced global command',async t=>{
  const f=fixture(t);await f.prepare();
  f.adapters.findTool=()=>'/wrong/cortextos';await assert.rejects(f.verify(),{code:'GLOBAL_LINK_MISMATCH'});
  f.adapters.findTool=()=>join(f.root,'dist/cli.js');writeFileSync(join(f.root,'package.json'),'changed');
  await assert.rejects(f.verify(),{code:'DIRTY_WORKTREE'});
});
for(const kind of ['package','lock'])test(`accepted commit with invalid ${kind} refuses before npm`,async t=>{
  const f=fixture(t);
  if(kind==='package')writeFileSync(join(f.source,'package.json'),'{"name":"imposter"}');else rmSync(join(f.source,'package-lock.json'));
  const sg=args=>run('git',['-C',f.source,...args],{env:process.env,timeoutMs:5000});
  sg(['add','-A']);sg(['commit','-m','invalid package']);f.release.sha=sg(['rev-parse','HEAD']).stdout.trim();
  await assert.rejects(f.prepare());assert.ok(!f.commands.some(c=>c.includes('controlled-npm')));
});
const npmWindowsWrapper = [
  '@ECHO off', 'GOTO start', ':find_dp0', 'SET dp0=%~dp0', 'EXIT /b',
  ':start', 'SETLOCAL', 'CALL :find_dp0', '',
  'IF EXIST "%dp0%\\node.exe" (', '  SET "_prog=%dp0%\\node.exe"',
  ') ELSE (', '  SET "_prog=node"', '  SET PATHEXT=%PATHEXT:;.JS;=;%', ')', '',
  'endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\cortextos\\dist\\cli.js" %*', '',
].join('\r\n');
for (const stage of ['prepare', 'verify']) {
  test(`${stage} rejects modified Windows shim despite correct adjacent package`, async t => {
    const f = fixture(t);
    await f.prepare();
    const bin = join(f.source, '..', 'global-bin');
    mkdirSync(join(bin, 'node_modules'), {recursive: true});
    symlinkSync(f.root, join(bin, 'node_modules', 'cortextos'), 'junction');
    const shim = join(bin, 'cortextos.cmd');
    writeFileSync(shim, npmWindowsWrapper);
    f.adapters.findTool = () => shim;
    f.adapters.platform = 'win32';
    // A valid npm wrapper and correct adjacency must still work.
    await f.verify();
    writeFileSync(shim, npmWindowsWrapper.replace('node_modules\\cortextos\\dist\\cli.js', 'other-checkout\\dist\\cli.js'));
    const count = f.commands.length;
    await assert.rejects(f[stage](), {code: 'GLOBAL_LINK_MISMATCH'});
    assert.equal(f.commands.length, count);
    writeFileSync(shim, npmWindowsWrapper + 'node other-checkout\\dist\\cli.js\r\n');
    await assert.rejects(f[stage](), {code: 'GLOBAL_LINK_MISMATCH'});
  });
}

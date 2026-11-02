import { appendFile, writeFile, mkdir, chmod } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { collectPublicSnapshot, reviewKey } from './public-monitor.mjs';
import { githubRequest } from './maintenance-core.mjs';

const repo = 'danielkupka/clay-cli-windows';
export function releaseDecision(s) {
  const old = s.acceptedBaseline;
  const changed = [...new Set([...Object.keys(old.files), ...Object.keys(s.files)])].some(p => old.files[p] !== s.files[p]);
  if (changed || !s.installerMatches) return 'review';
  const parse = v => /^clay-cli-v(\d+)\.(\d+)\.(\d+)$/.exec(v)?.slice(1).map(Number);
  const a = parse(old.cliRelease), b = parse(s.cliRelease);
  if (!a || !b || a[0] !== b[0]) return 'review';
  const order = b[0]-a[0] || b[1]-a[1] || b[2]-a[2];
  return order < 0 ? 'review' : order === 0 ? 'current' : 'update';
}
export function verifiedAsset(release) {
  const asset = release.assets?.find(a => a.name === 'clay-linux-x64');
  const expected = `https://github.com/clay-run/agent-plugins/releases/download/${release.tag_name}/clay-linux-x64`;
  if (!/^clay-cli-v\d+\.\d+\.\d+$/.test(release.tag_name) || !asset || asset.browser_download_url !== expected || !/^sha256:[a-f0-9]{64}$/.test(asset.digest)) throw new Error('Official release asset or SHA-256 digest missing');
  return asset;
}
export async function inspect() {
  const s = await collectPublicSnapshot();
  const decision = releaseDecision(s);
  const asset = verifiedAsset(s.release);
  for (const [key,value] of Object.entries({decision,tag:s.cliRelease,digest:asset.digest,head:s.bridgeCommit})) {
    if (process.env.GITHUB_OUTPUT) await appendFile(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
  }
  console.log(JSON.stringify({decision,release:s.cliRelease,head:s.bridgeCommit}));
}
export async function smoke() {
  const tag = process.env.RELEASE_TAG, digest = process.env.RELEASE_DIGEST;
  const asset = verifiedAsset({tag_name:tag,assets:[{name:'clay-linux-x64',browser_download_url:`https://github.com/clay-run/agent-plugins/releases/download/${tag}/clay-linux-x64`,digest}]});
  const root = resolve('.test-output/real-cli');
  await mkdir(root,{recursive:true});
  const response = await fetch(asset.browser_download_url,{signal:AbortSignal.timeout(120000)});
  if (!response.ok) throw new Error(`Release download failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (`sha256:${createHash('sha256').update(bytes).digest('hex')}` !== digest) throw new Error('Release checksum mismatch');
  const binary = resolve(root,'clay');
  await writeFile(binary,bytes); await chmod(binary,0o755);
  const env = {PATH:process.env.PATH,HOME:root,XDG_CONFIG_HOME:root,NO_COLOR:'1'};
  const run = (file,args) => {
    const result = spawnSync(file,args,{env,encoding:'utf8',timeout:30000,maxBuffer:8*1024*1024});
    if (result.error) throw result.error;
    if (result.signal || result.status === null) throw new Error('CLI terminated unexpectedly');
    return result;
  };
  const version = run(binary,['--version']);
  if (version.status !== 0 || version.stdout.trim().split('+')[0] !== tag.replace('clay-cli-v','')) throw new Error('CLI version mismatch');
  const help = run(binary,['--help']);
  if (help.status !== 0 || !help.stdout.includes('login')) throw new Error('CLI help failed');
  // Generate the real bridge forwarder using the repository installer functions.
  const exported = run('pwsh',['-NoProfile','-File','tests/Test-Installer.ps1','-ExportScripts',`${root}/scripts`,'-FixtureExecutable',binary]);
  if (exported.status !== 0) throw new Error(`Forwarder generation failed: ${exported.stderr}`);
  const forwarder = `${root}/scripts/quoted-forwarder.sh`;
  for (const args of [['--version'],['--help'],['definitely-not-a-clay-command']]) {
    const direct = run(binary,args), forwarded = run('sh',[forwarder,...args]);
    if (direct.status !== forwarded.status || direct.stdout !== forwarded.stdout) throw new Error('Real CLI forwarding changed exit status or output');
    if (args[0].startsWith('definitely') && direct.status === 0) throw new Error('Invalid command unexpectedly succeeded');
  }
  console.log(`Verified ${tag}: SHA-256, version, help and real bridge forwarding. No Clay credentials used.`);
}
async function openIssues(token, request) {
  const all=[];
  for(let page=1;page<=20;page++) {
    const items=await request(token,`repos/${repo}/issues?state=open&per_page=100&page=${page}`);
    all.push(...items.filter(i=>!i.pull_request));
    if(items.length<100) return all;
  }
  throw new Error('Issue listing exceeded limit; refusing duplicate notifications');
}
export async function finish({env=process.env,collect=collectPublicSnapshot,request=githubRequest}={}) {
  const token=env.GH_TOKEN;
  if(!token) throw new Error('Missing workflow token');
  const s=await collect();
  // Never acknowledge a release against a different main revision or different asset.
  if(s.bridgeCommit!==env.TESTED_HEAD || s.cliRelease!==env.RELEASE_TAG || verifiedAsset(s.release).digest!==env.RELEASE_DIGEST) throw new Error('Repository or release changed during testing; retry on the next run');
  const decision=releaseDecision(s);
  const healthy=env.PLATFORM_RESULT==='success' && env.SMOKE_RESULT==='success' && decision!=='review';
  const marker=`<!-- clay-auto-review:${reviewKey(s)} -->`;
  const issues=await openIssues(token,request);
  const ours=issues.filter(i=>i.user?.login==='github-actions[bot]' && i.body?.includes('<!-- clay-auto-review:'));
  if(!healthy) {
    if(!ours.some(i=>i.body.includes(marker))) {
      await request(token,`repos/${repo}/issues`,{method:'POST',body:{title:`Clay maintenance needs review: ${s.cliRelease}`,body:`${marker}\n\nAutomatic acceptance stopped.\n\n- Metadata decision: ${decision}\n- Windows/Linux tests: ${env.PLATFORM_RESULT}\n- Actual CLI smoke test: ${env.SMOKE_RESULT}\n\n[Inspect checks](https://github.com/${repo}/actions/runs/${env.GITHUB_RUN_ID})\n[Release notes](${s.releaseUrl})\n\nNo source repairs or CLI credentials were used. This issue is reused while the same release and metadata remain unresolved.`,assignees:['danielkupka']}});
    }
    console.log('Review recorded; repeat notifications suppressed by the open issue.');
    return;
  }
  if(decision==='update') {
    const file=await request(token,`repos/${repo}/contents/scripts/upstream-baseline.json?ref=main`);
    const baseline=JSON.parse(Buffer.from(file.content,'base64').toString('utf8'));
    if(JSON.stringify(baseline)!==JSON.stringify(s.acceptedBaseline)) throw new Error('Baseline changed during testing');
    baseline.cliRelease=s.cliRelease;
    await request(token,`repos/${repo}/contents/scripts/upstream-baseline.json`,{method:'PUT',body:{branch:'main',sha:file.sha,message:`Accept tested ${s.cliRelease}`,content:Buffer.from(JSON.stringify(baseline,null,2)+'\n').toString('base64')}});
  }
  for(const issue of ours) await request(token,`repos/${repo}/issues/${issue.number}`,{method:'PATCH',body:{state:'closed',state_reason:'completed'}});
  console.log(`Accepted ${s.cliRelease}; no deployment needed.`);
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const commands={inspect,smoke,finish};
  if(!commands[process.argv[2]]) throw new Error('Expected inspect, smoke or finish');
  await commands[process.argv[2]]();
}

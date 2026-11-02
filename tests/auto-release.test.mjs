import test from 'node:test';
import assert from 'node:assert/strict';
import {releaseDecision,verifiedAsset,finish} from '../scripts/auto-release.mjs';
import {reviewKey} from '../scripts/public-monitor.mjs';
const snapshot={acceptedBaseline:{cliRelease:'clay-cli-v1.12.0',files:{setup:'a',minimum:'b'}},cliRelease:'clay-cli-v1.13.0',files:{minimum:'b',setup:'a'},installerMatches:true};
function fixture(overrides={}) {
  const tag=snapshot.cliRelease, digest='sha256:'+'a'.repeat(64);
  const s={...structuredClone(snapshot),bridgeCommit:'head',release:{tag_name:tag,assets:[{name:'clay-linux-x64',digest,browser_download_url:`https://github.com/clay-run/agent-plugins/releases/download/${tag}/clay-linux-x64`}]},...overrides};
  const writes=[];
  const env={GH_TOKEN:'test-only',TESTED_HEAD:'head',RELEASE_TAG:tag,RELEASE_DIGEST:digest,PLATFORM_RESULT:'success',SMOKE_RESULT:'success'};
  const request=async(token,path,options)=>{
    if(options) {writes.push({path,...options});return {};}
    if(path.includes('/issues?')) return [];
    return {sha:'file-sha',content:Buffer.from(JSON.stringify(s.acceptedBaseline)).toString('base64')};
  };
  return {s,writes,options:{env,collect:async()=>s,request}};
}
test('successful tests write only the accepted version with optimistic locking',async()=>{
  const f=fixture(); await finish(f.options);
  assert.equal(f.writes.length,1); assert.equal(f.writes[0].method,'PUT');
  assert.equal(f.writes[0].body.sha,'file-sha');
  const accepted=JSON.parse(Buffer.from(f.writes[0].body.content,'base64'));
  assert.deepEqual(accepted,{...snapshot.acceptedBaseline,cliRelease:snapshot.cliRelease});
});
test('failed smoke tests create one issue and never update the baseline',async()=>{
  const f=fixture(); f.options.env.SMOKE_RESULT='failure'; await finish(f.options);
  assert.equal(f.writes.length,1); assert.equal(f.writes[0].method,'POST');
  const issue={number:1,user:{login:'github-actions[bot]'},body:f.writes[0].body.body};
  f.writes.length=0;
  f.options.request=async(t,p,o)=>{if(o) f.writes.push(o);return [issue];};
  await finish(f.options); assert.equal(f.writes.length,0);
});
test('a concurrent main change stops all writes',async()=>{
  const f=fixture({bridgeCommit:'different'});
  await assert.rejects(()=>finish(f.options),/changed during testing/); assert.equal(f.writes.length,0);
});
test('only newer same-major releases with unchanged installation metadata qualify',()=>{
  assert.equal(releaseDecision(snapshot),'update');
  for(const change of [{files:{setup:'changed',minimum:'b'}},{files:{setup:'a'}},{installerMatches:false},{cliRelease:'clay-cli-v2.0.0'},{cliRelease:'clay-cli-v1.11.0'},{cliRelease:'bad'}]) assert.equal(releaseDecision({...snapshot,...change}),'review');
  assert.equal(releaseDecision({...snapshot,cliRelease:'clay-cli-v1.12.0'}),'current');
});
test('review fingerprints survive object ordering but distinguish releases and metadata',()=>{
  assert.equal(reviewKey(snapshot),reviewKey({...snapshot,files:{setup:'a',minimum:'b'}}));
  assert.notEqual(reviewKey(snapshot),reviewKey({...snapshot,cliRelease:'clay-cli-v1.14.0'}));
  assert.notEqual(reviewKey(snapshot),reviewKey({...snapshot,installerMatches:false}));
});
test('asset validation rejects alternate origins, absent digests and injected tags',()=>{
  const release={tag_name:'clay-cli-v1.13.0',assets:[{name:'clay-linux-x64',digest:'sha256:'+'a'.repeat(64),browser_download_url:'https://github.com/clay-run/agent-plugins/releases/download/clay-cli-v1.13.0/clay-linux-x64'}]};
  assert.ok(verifiedAsset(release));
  for(const asset of [{...release.assets[0],digest:null},{...release.assets[0],browser_download_url:'https://example.com/clay'}]) assert.throws(()=>verifiedAsset({...release,assets:[asset]}));
  assert.throws(()=>verifiedAsset({...release,tag_name:'clay-cli-v1.13.0;echo nope'}));
});

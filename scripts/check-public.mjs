import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { assessSnapshot, collectPublicSnapshot } from './public-monitor.mjs';

// Use the baseline fetched at the observed main revision, not an older checkout.
export async function checkPublic(collect = collectPublicSnapshot, now = Date.now()) {
  const snapshot = await collect();
  return assessSnapshot(snapshot.acceptedBaseline, snapshot, now);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const result = await checkPublic();
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.status === 'healthy' ? 0 : result.status === 'pending' ? 2 : 1;
  } catch (error) {
    console.error(`Public check could not complete: ${error.message}`);
    process.exitCode = 1;
  }
}

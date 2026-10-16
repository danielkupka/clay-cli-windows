export async function githubRequest(token, path, options = {}) {
  const response = await fetch(`https://api.github.com/${path}`, {
    method: options.method ?? "GET",
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json" },
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(30000)
  });
  if (!response.ok) {
    const error = new Error(`GitHub request failed (${response.status}) for ${path}`);
    error.status = response.status;
    throw error;
  }
  return response.status === 204 ? null : response.json();
}

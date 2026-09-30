/**
 * A stand-in for the GitHub API, for the workflow scripts' tests. `answers` maps
 * "METHOD path" to a value, or to a function of the request body. The query string is left
 * out of the key. Every call is recorded, so a test can check what was done.
 */
export function fakeGitHub(answers) {
  const calls = [];
  const api = async (method, path, body) => {
    calls.push({ method, path, body });
    const answer = answers[`${method} ${path.split('?')[0]}`];
    if (typeof answer === 'function') return answer(body);
    return answer ?? null;
  };
  const find = (method, path) => calls.filter((c) => c.method === method && c.path.split('?')[0] === path);
  return { api, calls, find, did: (method, prefix) => calls.some((c) => c.method === method && c.path.startsWith(prefix)) };
}

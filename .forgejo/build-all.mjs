#!/usr/bin/env node
// Builds Quine Linux with what it depends on, in order (.forgejo/workflows/
// build-all.yml, README "Building everything"): each stage's workflows run at
// the same time, and the next stage starts only once they all succeeded. A
// failure stops it, with links to the runs.
//
// Env: TOKEN (a Forgejo token that may run Actions in every repo below),
// GITHUB_API_URL (the forge's API; Forgejo sets it in Actions), WAIT_FOR_LAST
// ("true": wait for the last stage too; otherwise it's started and linked).
//
// To add a dependency, add it to its stage: the repo, its workflow file and
// the branch to run it on.
const STAGES = [
  {
    name: "Quine's RPMs (the image installs them from the forge's `quine` RPM group)",
    runs: [
      {repo: 'quine-global/layer-wizard', workflow: 'rpm.yml', ref: 'main'},
      {repo: 'quine-global/dnf-package-store', workflow: 'rpm.yml', ref: 'main'},
      {repo: 'quine-global/swap-watchdog', workflow: 'rpm.yml', ref: 'main'}
    ]
  },
  {
    name: 'The image, qcow2 and ISO',
    runs: [{repo: 'quine-global/quine-linux', workflow: 'iso.yml', ref: 'main'}]
  }
];

const POLL_MS = 30_000;
const STAGE_TIMEOUT_MS = 24 * 3600_000; // the forge's own job limit
const DONE = {success: true, skipped: true, failure: false, cancelled: false, blocked: false};

const api = (process.env.GITHUB_API_URL || 'https://forge.in.quineglobal.com/api/v1').replace(/\/$/, '');
const token = process.env.TOKEN || '';
if (!token) {
  console.error('TOKEN is not set: a Forgejo token that may run Actions in each repo (README "Building everything")');
  process.exit(1);
}
const waitForLast = process.env.WAIT_FOR_LAST === 'true';

const forge = async (method, path, body) => {
  const res = await fetch(`${api}${path}`, {
    method,
    headers: {Authorization: `token ${token}`, 'Content-Type': 'application/json', Accept: 'application/json'},
    body: body && JSON.stringify(body)
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${text.trim()}`);
  return text ? JSON.parse(text) : null;
};

const label = (r) => `${r.repo} ${r.workflow}`;

// Starts the workflow and returns its run id.
const start = async (r) => {
  const out = await forge('POST', `/repos/${r.repo}/actions/workflows/${r.workflow}/dispatches`, {
    ref: r.ref,
    inputs: {},
    return_run_info: true
  });
  if (!out || !out.id) throw new Error(`${label(r)}: the forge didn't say which run it started`);
  return out.id;
};

// Waits until the run ends; returns its status and link.
const finish = async (r, id, deadline) => {
  let last = '';
  for (;;) {
    const run = await forge('GET', `/repos/${r.repo}/actions/runs/${id}`);
    if (run.status !== last) {
      console.log(`  ${label(r)}: ${run.status}  ${run.html_url}`);
      last = run.status;
    }
    if (run.status in DONE) return {ok: DONE[run.status], status: run.status, url: run.html_url};
    if (Date.now() > deadline) return {ok: false, status: 'still running at the time limit', url: run.html_url};
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
};

for (const [i, stage] of STAGES.entries()) {
  const last = i === STAGES.length - 1;
  console.log(`\n== ${i + 1}/${STAGES.length}: ${stage.name}`);
  const ids = await Promise.all(stage.runs.map(start));
  if (last && !waitForLast) {
    for (const [j, r] of stage.runs.entries()) {
      const run = await forge('GET', `/repos/${r.repo}/actions/runs/${ids[j]}`);
      console.log(`  ${label(r)}: started, not waiting  ${run.html_url}`);
    }
    break;
  }
  const deadline = Date.now() + STAGE_TIMEOUT_MS;
  const results = await Promise.all(stage.runs.map((r, j) => finish(r, ids[j], deadline)));
  const failed = results.filter((x) => !x.ok);
  if (failed.length) {
    console.error(`\n${failed.length} of ${stage.runs.length} didn't succeed; stopping before the next stage:`);
    for (const f of failed) console.error(`  ${f.status}: ${f.url}`);
    process.exit(1);
  }
}
console.log('\nAll done.');

-- actions_data: what GitHub Actions completion offers without asking GitHub: popular actions
-- with their newest major version, and the contexts and functions of `${{ }}` expressions.
-- The versions were checked against each action's releases in October 2026. Typing `@` after
-- an action asks GitHub for its tags, so a newer version still shows there.

---@class LangGitfiles.Action
---@field repo string Such as `actions/checkout`, or a path inside a repository.
---@field version string
---@field doc string

---@class LangGitfiles.ExprName
---@field name string
---@field doc string

---@class LangGitfiles.ExprFunction: LangGitfiles.ExprName
---@field signature string Such as `contains(search, item)`.

---@class LangGitfiles.ActionsDataModule
local M = {}

---@type LangGitfiles.Action[]
M.actions = {
  {
    repo = 'actions/checkout',
    version = 'v7',
    doc = 'Checks out the repository, so the job can work on its files.',
  },
  {
    repo = 'actions/setup-node',
    version = 'v7',
    doc = 'Installs a Node.js version, and can keep npm, Yarn or pnpm packages between runs.',
  },
  {
    repo = 'actions/setup-python',
    version = 'v7',
    doc = 'Installs a Python version, and can keep pip packages between runs.',
  },
  {
    repo = 'actions/setup-go',
    version = 'v7',
    doc = 'Installs a Go version, and keeps Go modules between runs.',
  },
  {
    repo = 'actions/setup-java',
    version = 'v6',
    doc = 'Installs a Java JDK, such as Temurin, and can keep Maven or Gradle files between runs.',
  },
  {
    repo = 'actions/setup-dotnet',
    version = 'v6',
    doc = 'Installs a .NET SDK.',
  },
  {
    repo = 'actions/cache',
    version = 'v6',
    doc = 'Keeps folders between runs, such as downloaded packages, under a key.',
  },
  {
    repo = 'actions/upload-artifact',
    version = 'v7',
    doc = 'Uploads files from the job, to download later or to use in another job.',
  },
  {
    repo = 'actions/download-artifact',
    version = 'v8',
    doc = 'Downloads files that an earlier job uploaded.',
  },
  {
    repo = 'actions/github-script',
    version = 'v9',
    doc = 'Runs JavaScript with a GitHub API client that is already signed in.',
  },
  {
    repo = 'actions/configure-pages',
    version = 'v6',
    doc = 'Sets up GitHub Pages for a site the workflow builds.',
  },
  {
    repo = 'actions/upload-pages-artifact',
    version = 'v5',
    doc = 'Uploads a built site for GitHub Pages.',
  },
  {
    repo = 'actions/deploy-pages',
    version = 'v5',
    doc = 'Publishes the uploaded site on GitHub Pages.',
  },
  {
    repo = 'actions/labeler',
    version = 'v7',
    doc = 'Labels pull requests by the files they change.',
  },
  {
    repo = 'actions/stale',
    version = 'v11',
    doc = 'Marks and closes issues and pull requests that nobody touched for a while.',
  },
  {
    repo = 'actions/create-github-app-token',
    version = 'v3',
    doc = 'Makes a short-lived token for a GitHub App.',
  },
  {
    repo = 'actions/attest-build-provenance',
    version = 'v4',
    doc = 'Signs a statement of how and where a file was built.',
  },
  {
    repo = 'actions/dependency-review-action',
    version = 'v5',
    doc = 'Checks the dependencies a pull request adds for known security problems.',
  },
  {
    repo = 'github/codeql-action/init',
    version = 'v4',
    doc = 'Starts a CodeQL scan for security problems.',
  },
  {
    repo = 'github/codeql-action/analyze',
    version = 'v4',
    doc = 'Finishes a CodeQL scan and uploads what it found.',
  },
  {
    repo = 'docker/setup-qemu-action',
    version = 'v4',
    doc = 'Installs QEMU, so Docker can build images for other processors.',
  },
  {
    repo = 'docker/setup-buildx-action',
    version = 'v4',
    doc = 'Sets up Docker Buildx, which builds images for several platforms.',
  },
  {
    repo = 'docker/login-action',
    version = 'v4',
    doc = 'Signs in to a container registry, such as Docker Hub or ghcr.io.',
  },
  {
    repo = 'docker/metadata-action',
    version = 'v6',
    doc = 'Makes image tags and labels from the branch, tag or pull request.',
  },
  {
    repo = 'docker/build-push-action',
    version = 'v7',
    doc = 'Builds a Docker image and pushes it to a registry.',
  },
  {
    repo = 'softprops/action-gh-release',
    version = 'v3',
    doc = 'Makes a GitHub release and uploads files to it.',
  },
  {
    repo = 'peaceiris/actions-gh-pages',
    version = 'v4',
    doc = 'Publishes a folder to the gh-pages branch.',
  },
  {
    repo = 'JamesIves/github-pages-deploy-action',
    version = 'v4',
    doc = 'Publishes a folder to a branch for GitHub Pages.',
  },
  {
    repo = 'peter-evans/create-pull-request',
    version = 'v8',
    doc = 'Opens a pull request with the changes the job made.',
  },
  {
    repo = 'stefanzweifel/git-auto-commit-action',
    version = 'v7',
    doc = 'Commits and pushes the changes the job made.',
  },
  {
    repo = 'googleapis/release-please-action',
    version = 'v5',
    doc = 'Keeps a release pull request with a changelog, from conventional commit messages.',
  },
  {
    repo = 'changesets/action',
    version = 'v2',
    doc = 'Opens a release pull request, or publishes packages, with Changesets.',
  },
  {
    repo = 'dtolnay/rust-toolchain',
    version = 'stable',
    doc = 'Installs a Rust toolchain. The version names it: stable, beta, nightly or a number.',
  },
  {
    repo = 'Swatinem/rust-cache',
    version = 'v2',
    doc = "Keeps Cargo's downloads and build files between runs.",
  },
  {
    repo = 'taiki-e/install-action',
    version = 'v2',
    doc = 'Installs command line tools, such as cargo-nextest, from their releases.',
  },
  {
    repo = 'pnpm/action-setup',
    version = 'v6',
    doc = 'Installs pnpm.',
  },
  {
    repo = 'oven-sh/setup-bun',
    version = 'v2',
    doc = 'Installs Bun.',
  },
  {
    repo = 'denoland/setup-deno',
    version = 'v2',
    doc = 'Installs Deno.',
  },
  {
    repo = 'astral-sh/setup-uv',
    version = 'v7',
    doc = 'Installs uv, the Python package manager.',
  },
  {
    repo = 'ruby/setup-ruby',
    version = 'v1',
    doc = 'Installs Ruby, and can run `bundle install` and keep the gems between runs.',
  },
  {
    repo = 'shivammathur/setup-php',
    version = 'v2',
    doc = 'Installs PHP with extensions and tools such as Composer.',
  },
  {
    repo = 'erlef/setup-beam',
    version = 'v1',
    doc = 'Installs Erlang, Elixir or Gleam.',
  },
  {
    repo = 'haskell-actions/setup',
    version = 'v2',
    doc = 'Installs GHC, and Cabal or Stack.',
  },
  {
    repo = 'subosito/flutter-action',
    version = 'v2',
    doc = 'Installs Flutter.',
  },
  {
    repo = 'gradle/actions/setup-gradle',
    version = 'v6',
    doc = 'Sets up Gradle, and keeps its files between runs.',
  },
  {
    repo = 'jdx/mise-action',
    version = 'v5',
    doc = 'Installs the tools a mise.toml file lists.',
  },
  {
    repo = 'cachix/install-nix-action',
    version = 'v31',
    doc = 'Installs Nix.',
  },
  {
    repo = 'hashicorp/setup-terraform',
    version = 'v4',
    doc = 'Installs Terraform.',
  },
  {
    repo = 'aws-actions/configure-aws-credentials',
    version = 'v6',
    doc = 'Signs in to AWS, for the steps after it.',
  },
  {
    repo = 'azure/login',
    version = 'v3',
    doc = 'Signs in to Azure, for the steps after it.',
  },
  {
    repo = 'google-github-actions/auth',
    version = 'v3',
    doc = 'Signs in to Google Cloud, for the steps after it.',
  },
  {
    repo = 'codecov/codecov-action',
    version = 'v7',
    doc = 'Uploads test coverage reports to Codecov.',
  },
  {
    repo = 'golangci/golangci-lint-action',
    version = 'v9',
    doc = 'Runs golangci-lint on Go code.',
  },
  {
    repo = 'crate-ci/typos',
    version = 'v1',
    doc = 'Finds spelling mistakes in code and text.',
  },
  {
    repo = 'pre-commit/action',
    version = 'v3.0.1',
    doc = 'Runs the pre-commit hooks of the repository.',
  },
  {
    repo = 'JohnnyMorganz/stylua-action',
    version = 'v5',
    doc = 'Checks or formats Lua with StyLua.',
  },
  {
    repo = 'leafo/gh-actions-lua',
    version = 'v13',
    doc = 'Installs Lua or LuaJIT.',
  },
}

---The contexts an expression can read.
---@type LangGitfiles.ExprName[]
M.contexts = {
  {
    name = 'github',
    doc = 'The run and the event that started it: the repository, branch, commit and more.',
  },
  {
    name = 'env',
    doc = 'Environment variables set with `env:` in the workflow, the job or the step.',
  },
  {
    name = 'vars',
    doc = 'Configuration variables set for the repository, the organization or the environment.',
  },
  {
    name = 'secrets',
    doc = 'Secrets set for the repository, the organization or the environment. `secrets.GITHUB_TOKEN` is always there.',
  },
  {
    name = 'inputs',
    doc = 'The inputs of a reusable workflow, a manual run or an action.',
  },
  { name = 'matrix', doc = 'The values of this job in a matrix.' },
  {
    name = 'steps',
    doc = 'Steps of this job that have an `id` and have run: their outputs, outcome and conclusion.',
  },
  {
    name = 'needs',
    doc = 'The jobs this job needs: their outputs and result.',
  },
  {
    name = 'runner',
    doc = 'The machine that runs the job: its system, processor and folders.',
  },
  {
    name = 'job',
    doc = 'The job that is running: its container, services and status.',
  },
  {
    name = 'strategy',
    doc = 'The matrix strategy of the job: how many jobs there are, and which one this is.',
  },
}

---Properties of the contexts that have fixed ones.
---@type table<string, LangGitfiles.ExprName[]>
M.properties = {
  github = {
    { name = 'action', doc = 'The name of the step that is running.' },
    {
      name = 'action_path',
      doc = 'The folder of the action that is running.',
    },
    { name = 'actor', doc = 'The user who started the run.' },
    {
      name = 'actor_id',
      doc = 'The account number of the user who started the run.',
    },
    {
      name = 'api_url',
      doc = "The address of GitHub's REST API.",
    },
    {
      name = 'base_ref',
      doc = 'The branch a pull request goes into. Set for pull request events only.',
    },
    {
      name = 'event',
      doc = 'The whole event that started the run, as GitHub sent it to the webhook.',
    },
    {
      name = 'event_name',
      doc = 'The name of the event that started the run, such as `push` or `pull_request`.',
    },
    {
      name = 'head_ref',
      doc = 'The branch a pull request comes from. Set for pull request events only.',
    },
    { name = 'job', doc = 'The id of the job that is running.' },
    {
      name = 'ref',
      doc = 'The full name of the branch or tag that started the run, such as `refs/heads/main`.',
    },
    {
      name = 'ref_name',
      doc = 'The short name of the branch or tag, such as `main` or `v1.2.0`.',
    },
    {
      name = 'ref_protected',
      doc = 'True when the branch or tag has protection rules.',
    },
    {
      name = 'ref_type',
      doc = 'What `ref` names: `branch` or `tag`.',
    },
    {
      name = 'repository',
      doc = 'The owner and name of the repository, such as `octocat/hello-world`.',
    },
    {
      name = 'repository_id',
      doc = 'The number of the repository.',
    },
    {
      name = 'repository_owner',
      doc = 'The user or organization that owns the repository.',
    },
    {
      name = 'repositoryUrl',
      doc = 'The Git address of the repository.',
    },
    {
      name = 'retention_days',
      doc = 'How many days logs and artifacts are kept.',
    },
    {
      name = 'run_id',
      doc = 'A number for this run, which stays the same when it runs again.',
    },
    {
      name = 'run_number',
      doc = 'How many times this workflow has run, counting this run.',
    },
    {
      name = 'run_attempt',
      doc = 'Which attempt of this run this is, from 1.',
    },
    {
      name = 'server_url',
      doc = 'The address of GitHub, such as `https://github.com`.',
    },
    { name = 'sha', doc = 'The commit that started the run.' },
    {
      name = 'token',
      doc = 'The token the run signs in to GitHub with. It is the same as `secrets.GITHUB_TOKEN`.',
    },
    {
      name = 'triggering_actor',
      doc = 'The user who started this attempt of the run.',
    },
    { name = 'workflow', doc = 'The name of the workflow.' },
    {
      name = 'workflow_ref',
      doc = 'The path of the workflow file and the branch or tag it came from.',
    },
    {
      name = 'workspace',
      doc = 'The folder the steps run in, where `actions/checkout` puts the files.',
    },
  },
  runner = {
    { name = 'name', doc = 'The name of the runner.' },
    {
      name = 'os',
      doc = 'The system the runner has: `Linux`, `Windows` or `macOS`.',
    },
    {
      name = 'arch',
      doc = 'The processor of the runner: `X86`, `X64`, `ARM` or `ARM64`.',
    },
    {
      name = 'temp',
      doc = 'A folder for temporary files. It is emptied after each job.',
    },
    {
      name = 'tool_cache',
      doc = 'The folder that holds the tools GitHub installs on its runners.',
    },
    {
      name = 'debug',
      doc = 'Set to `1` when debug logging is on.',
    },
    {
      name = 'environment',
      doc = '`github-hosted` or `self-hosted`.',
    },
  },
  job = {
    {
      name = 'container',
      doc = "The job's container: its `id` and `network`.",
    },
    {
      name = 'services',
      doc = "The job's service containers, by their ids.",
    },
    {
      name = 'status',
      doc = 'How the job is going: `success`, `failure` or `cancelled`.',
    },
  },
  strategy = {
    {
      name = 'fail-fast',
      doc = 'True when one failed job cancels the others in the matrix.',
    },
    {
      name = 'job-index',
      doc = 'Which job of the matrix this is, from 0.',
    },
    {
      name = 'job-total',
      doc = 'How many jobs the matrix has.',
    },
    {
      name = 'max-parallel',
      doc = 'How many jobs of the matrix may run at once.',
    },
  },
  secrets = {
    {
      name = 'GITHUB_TOKEN',
      doc = 'A token GitHub makes for each run, with the permissions the workflow gives it.',
    },
  },
}

-- What a step that has run holds, after `steps.<id>.`.
---@type LangGitfiles.ExprName[]
M.step = {
  {
    name = 'outputs',
    doc = 'The outputs the step set, such as with `echo "name=value" >> "$GITHUB_OUTPUT"`.',
  },
  {
    name = 'outcome',
    doc = 'How the step ended, before `continue-on-error` counts: `success`, `failure`, `cancelled` or `skipped`.',
  },
  {
    name = 'conclusion',
    doc = 'How the step ended, after `continue-on-error` counts: `success`, `failure`, `cancelled` or `skipped`.',
  },
}

-- What a job this job needs holds, after `needs.<id>.`.
---@type LangGitfiles.ExprName[]
M.need = {
  { name = 'outputs', doc = 'The outputs the job set in its `outputs:`.' },
  {
    name = 'result',
    doc = 'How the job ended: `success`, `failure`, `cancelled` or `skipped`.',
  },
}

---@type LangGitfiles.ExprFunction[]
M.functions = {
  {
    name = 'contains',
    signature = 'contains(search, item)',
    doc = 'True when the text `search` holds `item`, or when the list `search` has it. Case does not matter.',
  },
  {
    name = 'startsWith',
    signature = 'startsWith(searchString, searchValue)',
    doc = 'True when the text starts with the value. Case does not matter.',
  },
  {
    name = 'endsWith',
    signature = 'endsWith(searchString, searchValue)',
    doc = 'True when the text ends with the value. Case does not matter.',
  },
  {
    name = 'format',
    signature = 'format(string, replaceValue0, replaceValue1, ...)',
    doc = 'Puts the values into the text in place of `{0}`, `{1}` and so on. `{{` and `}}` give braces.',
  },
  {
    name = 'join',
    signature = 'join(array, optionalSeparator)',
    doc = 'Joins the values of a list into one text, with `,` between them unless a separator is given.',
  },
  {
    name = 'toJSON',
    signature = 'toJSON(value)',
    doc = 'The value as JSON text, laid out to read easily.',
  },
  {
    name = 'fromJSON',
    signature = 'fromJSON(value)',
    doc = 'Reads JSON text into a value, such as a matrix made by an earlier job.',
  },
  {
    name = 'hashFiles',
    signature = 'hashFiles(path)',
    doc = "A SHA-256 hash of the files that fit the patterns, such as `hashFiles('**/package-lock.json')`. It suits cache keys.",
  },
  {
    name = 'success',
    signature = 'success()',
    doc = 'True when no step or job before it failed or was cancelled. An `if:` without a status function uses it.',
  },
  {
    name = 'always',
    signature = 'always()',
    doc = 'Always true, so the step runs even after a failure or a cancel.',
  },
  {
    name = 'cancelled',
    signature = 'cancelled()',
    doc = 'True when the workflow was cancelled.',
  },
  {
    name = 'failure',
    signature = 'failure()',
    doc = 'True when a step or job before it failed.',
  },
}

---The bundled entry for an action, or nil.
---@param repo string
---@return LangGitfiles.Action?
function M.action (repo)
  local wanted = repo:lower ()
  for _, a in ipairs (M.actions) do
    if a.repo:lower () == wanted then
      return a
    end
  end
  return nil
end

return M

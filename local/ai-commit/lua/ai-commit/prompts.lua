local M = {}

M.commit_header = [[You are a git commit message generator following Conventional Commits v1.0.0 specification.

STRUCTURE:
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]

SPECIFICATION (https://www.conventionalcommits.org/en/v1.0.0/):

1. Commits MUST be prefixed with a type, which consists of a noun, feat, fix, etc., followed by the OPTIONAL scope, OPTIONAL !, and REQUIRED terminal colon and space.
2. The type feat MUST be used when a commit adds a new feature to your application or library.
3. The type fix MUST be used when a commit represents a bug fix for your application.
4. A scope MAY be provided after a type. A scope MUST consist of a noun describing a section of the codebase surrounded by parenthesis, e.g., fix(parser):
5. A description MUST immediately follow the colon and space after the type/scope prefix. The description is a short summary of the code changes, e.g., fix: array parsing issue when multiple spaces were contained in string.
6. A longer commit body MAY be provided after the short description, providing additional contextual information about the code changes. The body MUST begin one blank line after the description.
7. A commit body is free-form and MAY consist of any number of newline separated paragraphs.
8. One or more footers MAY be provided one blank line after the body. Each footer MUST consist of a word token, followed by either a :<space> or <space># separator, followed by a string value (this is inspired by the git trailer convention).
9. A footer's token MUST use - in place of whitespace characters, e.g., Acked-by (this helps differentiate the footer section from a multi-paragraph body). An exception is made for BREAKING CHANGE, which MAY also be used as a token.
10. A footer's value MAY contain spaces and newlines, and parsing MUST terminate when the next valid footer token/separator pair is observed.
11. Breaking changes MUST be indicated in the type/scope prefix of a commit, or as an entry in the footer.
12. If included as a footer, a breaking change MUST consist of the uppercase text BREAKING CHANGE, followed by a colon, space, and description, e.g., BREAKING CHANGE: environment variables now take precedence over config files.
13. If included in the type/scope prefix, breaking changes MUST be indicated by a ! immediately before the :. If ! is used, BREAKING CHANGE: MAY be omitted from the footer section, and the commit description SHALL be used to describe the breaking change.
14. Types other than feat and fix MAY be used in your commit messages, e.g., docs: update ref docs.

ADDITIONAL GUIDELINES:
- Description: Use lowercase, imperative mood, no ending period, target max 100 chars
- Header Only: Most of the time, ONLY output the single header line (type[scope]: description).
- Header: DO NOT use vague descriptions like `update stuff`, `fix bug`, or `misc changes`.
- Body: FORBIDDEN for 75% of commits. DO NOT include a body for small changes, simple fixes, or minor features.
- Body: ONLY include a body if the change is a massive architectural shift, highly complex, or a BREAKING CHANGE.
- Body: DO mention user/API/data/security/deployment impact when relevant.
- Body: DO mention tradeoffs or known limitations only if future maintainers need them.
- Body: DO use neutral factual tone; DO NOT use jokes, apologies, blame, or uncertainty.
- Body: DO NOT list changed files/functions unless the location itself matters.
- Body Formatting: If a body is absolutely necessary, wrap at 80 chars, explain WHAT and WHY (not HOW). DO NOT ramble or over-explain.
- Type casing: Any casing may be used, but be consistent (prefer lowercase)
- SemVer relationship: fix = PATCH, feat = MINOR, BREAKING CHANGE = MAJOR
- Revert commits: Use "revert" type with footer referencing commit SHAs
- BREAKING CHANGE: Use SPARINGLY. ONLY for big, actual breaking changes.
- BREAKING CHANGE: Adding new features is NOT breaking. Only for removed/changed functionality.]]

---@param branch string
---@param sections table[]
---@return string
function M.commit(branch, sections)
  local parts = { M.commit_header, 'Current branch: ' .. branch }

  for _, section in ipairs(sections or {}) do
    if section.body and section.body ~= '' then
      if section.fenced then
        table.insert(parts, section.title .. ':\n```\n' .. section.body .. '\n```')
      else
        table.insert(parts, section.title .. ':\n' .. section.body)
      end
    end
  end

  table.insert(parts, 'Generate ONLY the commit message following the specification above:')
  return table.concat(parts, '\n\n')
end

---@param branch string
---@param message string
---@param failures string
---@param sections table[]
---@return string
function M.refine_commit(branch, message, failures, sections)
  message = vim.trim(message or '')
  message = message:gsub('```', '` ` `')
  local parts = {
    M.commit_header,
    'Current branch: ' .. branch,
    'Previously generated commit message:',
    '```\n' .. message .. '\n```',
    'Heuristic failures:',
    failures or 'Unknown failure.',
    table.concat({
      'Refinement constraints:',
      'Return a commit message, not an explanation. Do not copy these constraints into the commit message.',
      'Prefer one short first line only. If a body is necessary, keep it plain text, wrapped at 80 chars, and without bullets.',
      'Do not use ! or BREAKING CHANGE unless the staged files clearly show removed or changed public behavior.',
    }, '\n'),
  }

  for _, section in ipairs(sections or {}) do
    if section.body and section.body ~= '' then
      if section.fenced then
        table.insert(parts, section.title .. ':\n```\n' .. section.body .. '\n```')
      else
        table.insert(parts, section.title .. ':\n' .. section.body)
      end
    end
  end

  table.insert(parts, 'Output ONLY the corrected commit message:')
  return table.concat(parts, '\n\n')
end

M.session_summary = [[Summarize the following %s session for a git commit message generator.

The transcript is intentionally selective: it starts with the initial user request, then the tail of the session with recent user messages, assistant responses, and the final assistant response. Each message is labeled and fenced. Use this to recover what the user wanted, what changed during problem solving, and what final outcome matters for the commit message.

Transcript policy: thinking/reasoning parts are excluded, ignored context tags are replaced with markers such as [removed system-reminder], and the recent window contains the configured last user messages plus assistant responses between them.

Focus on user intent, important design decisions, problems encountered, and why the final change was made. Ignore tool output details unless they explain the intent or a fix. Keep it around 200 words. Do not invent facts.

Session title: %s
Workspace: %s

Selected transcript:
%s

Summary of this Session:]]

return M

vim.opt.runtimepath:append(vim.fn.getcwd() .. '/local/ai-commit')

local parser = require 'ai-commit.session_context.pi_parser'

local function json(value)
  return vim.json.encode(value)
end

local function assert_contains(text, expected)
  assert(text:find(expected, 1, true), string.format('expected transcript to contain %q\n%s', expected, text))
end

local function assert_excludes(text, unexpected)
  assert(not text:find(unexpected, 1, true), string.format('expected transcript to exclude %q\n%s', unexpected, text))
end

local lines = {
  json { type = 'session', version = 3, id = 'session-id', timestamp = '2026-01-01T00:00:00Z', cwd = '/tmp/project' },
  json { type = 'message', id = 'a', parentId = vim.NIL, message = { role = 'user', content = 'raw initial request' } },
  json {
    type = 'message',
    id = 'b',
    parentId = 'a',
    message = { role = 'assistant', content = { { type = 'text', text = 'raw initial response' } } },
  },
  json { type = 'message', id = 'x', parentId = 'b', message = { role = 'user', content = 'abandoned branch request' } },
  json {
    type = 'message',
    id = 'y',
    parentId = 'x',
    message = { role = 'assistant', content = { { type = 'text', text = 'abandoned branch response' } } },
  },
  json { type = 'message', id = 'c', parentId = 'b', message = { role = 'user', content = 'pre-compaction request' } },
  json {
    type = 'message',
    id = 'd',
    parentId = 'c',
    message = { role = 'assistant', content = { { type = 'text', text = 'pre-compaction response' } } },
  },
  json {
    type = 'compaction',
    id = 'e',
    parentId = 'd',
    summary = 'compacted implementation decisions',
    retainedTail = {
      { role = 'user', content = 'retained request' },
      { role = 'assistant', content = { { type = 'text', text = 'retained response' } } },
    },
  },
  json { type = 'branch_summary', id = 'f', parentId = 'e', summary = 'branch summary details' },
  json { type = 'message', id = 'g', parentId = 'f', message = { role = 'user', content = 'final request' } },
  json {
    type = 'message',
    id = 'h',
    parentId = 'g',
    message = {
      role = 'assistant',
      content = {
        { type = 'thinking', thinking = 'private reasoning' },
        { type = 'toolCall', id = 'tool', name = 'bash', arguments = { secret = 'tool argument' } },
        { type = 'text', text = 'final implementation response' },
      },
    },
  },
  json { type = 'session_info', id = 'i', parentId = 'h', name = 'Named Pi Session' },
  json { type = 'custom', id = 'j', parentId = 'i', customType = 'test', data = { ignored = true } },
  '{malformed',
}

local parsed = assert(parser.parse(lines, {
  recent_user_messages = 4,
  max_message_chars = 5000,
  max_transcript_chars = 30000,
}))

assert(parsed.id == 'session-id')
assert(parsed.cwd == '/tmp/project')
assert(parsed.title == 'Named Pi Session')
assert_contains(parsed.transcript, 'compacted implementation decisions')
assert_contains(parsed.transcript, 'retained request')
assert_contains(parsed.transcript, 'retained response')
assert_contains(parsed.transcript, 'branch summary details')
assert_contains(parsed.transcript, 'final request')
assert_contains(parsed.transcript, 'final implementation response')
assert_excludes(parsed.transcript, 'raw initial request')
assert_excludes(parsed.transcript, 'pre-compaction request')
assert_excludes(parsed.transcript, 'abandoned branch request')
assert_excludes(parsed.transcript, 'private reasoning')
assert_excludes(parsed.transcript, 'tool argument')

local version_two = vim.deepcopy(lines)
version_two[1] = json { type = 'session', version = 2, id = 'old', cwd = '/tmp/project' }
assert(parser.parse(version_two) == nil, 'Pi session version 2 should be rejected')

print 'Pi session context smoke test passed'

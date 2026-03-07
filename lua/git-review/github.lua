local M = {}

local function invalid_result_error(message)
  return {
    state = "command_error",
    message = message,
  }
end

local function normalize_run_result(result)
  if type(result) ~= "table" then
    return nil, "run_command must return a table"
  end

  if type(result.code) ~= "number" then
    return nil, "run_command result.code must be a number"
  end

  if result.stdout ~= nil and type(result.stdout) ~= "string" then
    return nil, "run_command result.stdout must be a string"
  end

  if result.stderr ~= nil and type(result.stderr) ~= "string" then
    return nil, "run_command result.stderr must be a string"
  end

  return {
    code = result.code,
    stdout = result.stdout or "",
    stderr = result.stderr or "",
  }
end

local function run_gh(argv)
  local completed = vim.system(argv, { text = true }):wait()

  return {
    code = completed.code,
    stdout = completed.stdout or "",
    stderr = completed.stderr or "",
  }
end

local function send_gh_api(request)
  local payload = ""
  if request.body ~= nil then
    payload = vim.json.encode(request.body)
  end

  local completed = vim.system({ "gh", "api", "--method", request.method, request.path, "--input", "-" }, {
    text = true,
    stdin = payload,
  }):wait()

  return {
    code = completed.code,
    stdout = completed.stdout or "",
    stderr = completed.stderr or "",
  }
end

function M.resolve_pr_for_branch(branch, run)
  vim.validate({
    branch = { branch, "string" },
  })

  if branch == "" then
    error("branch must be a non-empty string")
  end

  local run_command = run or run_gh
  local argv = {
    "gh",
    "pr",
    "list",
    "--head",
    branch,
    "--json",
    "id,number,title,body,author,baseRefName,headRefName,url",
  }
  local raw_result = run_command(argv)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh pr list failed",
      code = result.code,
    }
  end

  local ok, prs = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = prs,
    }
  end

  if type(prs) ~= "table" or not vim.islist(prs) then
    return {
      state = "parse_error",
      message = "gh pr list returned non-array JSON",
    }
  end

  if #prs == 1 then
    return {
      state = "single_pr",
      pr = prs[1],
    }
  end

  if #prs > 1 then
    return {
      state = "multiple_prs",
      prs = prs,
    }
  end

  return {
    state = "no_pr",
  }
end

local function normalize_review_threads(threads)
  if type(threads) ~= "table" or not vim.islist(threads) then
    return nil
  end

  local normalized = {}
  for _, thread in ipairs(threads) do
    local normalized_thread = thread
    if type(thread) == "table"
      and type(thread.comments) == "table"
      and type(thread.comments.nodes) == "table"
      and vim.islist(thread.comments.nodes)
    then
      normalized_thread = vim.tbl_extend("force", thread, {
        comments = thread.comments.nodes,
      })
    end

    table.insert(normalized, normalized_thread)
  end

  return normalized
end

local function fetch_review_threads_via_graphql(pr_number, run_command)
  local repo_raw = run_command({ "gh", "repo", "view", "--json", "nameWithOwner" })
  local repo_result, repo_result_error = normalize_run_result(repo_raw)
  if not repo_result then
    return nil, invalid_result_error(repo_result_error)
  end

  if repo_result.code ~= 0 then
    return nil, {
      state = "command_error",
      message = repo_result.stderr ~= "" and repo_result.stderr or "gh repo view failed",
      code = repo_result.code,
    }
  end

  local ok_repo, repo_payload = pcall(vim.json.decode, repo_result.stdout)
  if not ok_repo then
    return nil, {
      state = "parse_error",
      message = repo_payload,
    }
  end

  local name_with_owner = type(repo_payload) == "table" and repo_payload.nameWithOwner or nil
  if type(name_with_owner) ~= "string" or name_with_owner == "" then
    return nil, {
      state = "parse_error",
      message = "gh repo view returned invalid nameWithOwner payload",
    }
  end

  local owner, name = name_with_owner:match("^([^/]+)/([^/]+)$")
  if not owner or not name then
    return nil, {
      state = "parse_error",
      message = "Unable to parse repository owner and name",
    }
  end

  local graphql_raw = run_command({
    "gh",
    "api",
    "graphql",
    "-f",
    "query=query($owner: String!, $name: String!, $prNumber: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $prNumber) { reviewThreads(first: 100) { nodes { id isResolved path comments(first: 100) { nodes { author { login } body } } } } } } }",
    "-F",
    "owner=" .. owner,
    "-F",
    "name=" .. name,
    "-F",
    "prNumber=" .. tostring(pr_number),
  })
  local graphql_result, graphql_result_error = normalize_run_result(graphql_raw)
  if not graphql_result then
    return nil, invalid_result_error(graphql_result_error)
  end

  if graphql_result.code ~= 0 then
    return nil, {
      state = "command_error",
      message = graphql_result.stderr ~= "" and graphql_result.stderr or "gh api graphql failed",
      code = graphql_result.code,
    }
  end

  local ok_graphql, graphql_payload = pcall(vim.json.decode, graphql_result.stdout)
  if not ok_graphql then
    return nil, {
      state = "parse_error",
      message = graphql_payload,
    }
  end

  local review_threads = graphql_payload
    and graphql_payload.data
    and graphql_payload.data.repository
    and graphql_payload.data.repository.pullRequest
    and graphql_payload.data.repository.pullRequest.reviewThreads
    and graphql_payload.data.repository.pullRequest.reviewThreads.nodes

  local normalized = normalize_review_threads(review_threads)
  if normalized == nil then
    return nil, {
      state = "parse_error",
      message = "gh api graphql returned invalid reviewThreads payload",
    }
  end

  return {
    state = "ok",
    threads = normalized,
  }
end

function M.fetch_review_threads(pr_number, run)
  vim.validate({
    pr_number = { pr_number, "number" },
  })

  local run_command = run or run_gh
  local argv = { "gh", "pr", "view", tostring(pr_number), "--json", "reviewThreads" }
  local raw_result = run_command(argv)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    local stderr_lower = string.lower(result.stderr or "")
    if string.find(stderr_lower, "unknown json field", 1, true)
      and string.find(stderr_lower, "reviewthreads", 1, true)
    then
      local fallback_result, fallback_error = fetch_review_threads_via_graphql(pr_number, run_command)
      if fallback_result then
        return fallback_result
      end

      return fallback_error
    end

    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh pr view failed",
      code = result.code,
    }
  end

  local ok, payload = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = payload,
    }
  end

  local normalized_threads = normalize_review_threads(type(payload) == "table" and payload.reviewThreads or nil)
  if normalized_threads == nil then
    return {
      state = "parse_error",
      message = "gh pr view returned invalid reviewThreads payload",
    }
  end

  return {
    state = "ok",
    threads = normalized_threads,
  }
end

function M.submit_review(opts, send)
  vim.validate({
    opts = { opts, "table" },
  })

  vim.validate({
    repo = { opts.repo, "string" },
    pr_number = { opts.pr_number, "number" },
    event = { opts.event, "string" },
  })

  if opts.body ~= nil and type(opts.body) ~= "string" then
    error("body must be a string when provided")
  end

  local payload = {
    event = opts.event,
  }

  if type(opts.body) == "string" and opts.body ~= "" then
    payload.body = opts.body
  end

  local send_request = send or send_gh_api
  local request = {
    method = "POST",
    path = string.format("repos/%s/pulls/%d/reviews", opts.repo, opts.pr_number),
    body = payload,
  }

  local raw_result = send_request(request)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh api submit review failed",
      code = result.code,
    }
  end

  if result.stdout == "" then
    return {
      state = "ok",
      review = {},
    }
  end

  local ok, payload_result = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = payload_result,
    }
  end

  if type(payload_result) ~= "table" or vim.islist(payload_result) then
    return {
      state = "parse_error",
      message = "gh api submit review returned non-object JSON",
    }
  end

  return {
    state = "ok",
    review = payload_result,
  }
end

function M.create_review_comment(opts, send)
  vim.validate({
    opts = { opts, "table" },
  })

  vim.validate({
    repo = { opts.repo, "string" },
    pr_number = { opts.pr_number, "number" },
    body = { opts.body, "string" },
    commit_id = { opts.commit_id, "string" },
    path = { opts.path, "string" },
    position = { opts.position, "number" },
  })

  if opts.start_position ~= nil and type(opts.start_position) ~= "number" then
    error("start_position must be a number when provided")
  end

  local payload = {
    body = opts.body,
    commit_id = opts.commit_id,
    path = opts.path,
    position = opts.position,
  }

  if type(opts.start_position) == "number" then
    payload.start_position = opts.start_position
  end

  local send_request = send or send_gh_api
  local request = {
    method = "POST",
    path = string.format("repos/%s/pulls/%d/comments", opts.repo, opts.pr_number),
    body = payload,
  }

  local raw_result = send_request(request)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh api create review comment failed",
      code = result.code,
    }
  end

  if result.stdout == "" then
    return {
      state = "ok",
      comment = {},
    }
  end

  local ok, payload_result = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = payload_result,
    }
  end

  if type(payload_result) ~= "table" then
    return {
      state = "parse_error",
      message = "gh api create review comment returned non-object JSON",
    }
  end

  return {
    state = "ok",
    comment = payload_result,
  }
end

local REACTION_ALIASES = {
  ["+1"] = "THUMBS_UP",
  ["-1"] = "THUMBS_DOWN",
  ["👍"] = "THUMBS_UP",
  ["👎"] = "THUMBS_DOWN",
  ["🔥"] = "HOORAY",
  ["✅"] = "ROCKET",
  ["👀"] = "EYES",
  ["❤️"] = "HEART",
  ["❤"] = "HEART",
}

local VALID_REACTION_CONTENT = {
  THUMBS_UP = true,
  THUMBS_DOWN = true,
  LAUGH = true,
  HOORAY = true,
  CONFUSED = true,
  HEART = true,
  ROCKET = true,
  EYES = true,
}

function M.normalize_reaction_content(content)
  if type(content) ~= "string" then
    return nil
  end

  local trimmed = vim.trim(content)
  if trimmed == "" then
    return nil
  end

  local alias = REACTION_ALIASES[trimmed]
  if alias then
    return alias
  end

  local upper = string.upper(trimmed)
  if VALID_REACTION_CONTENT[upper] == true then
    return upper
  end

  return nil
end

function M.reply_to_thread(thread_id, body, send)
  vim.validate({
    thread_id = { thread_id, "string" },
    body = { body, "string" },
  })

  if thread_id == "" then
    error("thread_id must be a non-empty string")
  end

  local request = {
    method = "POST",
    path = "graphql",
    body = {
      query = [[mutation($input: AddPullRequestReviewThreadReplyInput!) {
  addPullRequestReviewThreadReply(input: $input) {
    comment {
      id
      body
    }
  }
}]],
      variables = {
        input = {
          pullRequestReviewThreadId = thread_id,
          body = body,
        },
      },
    },
  }

  local send_request = type(send) == "function" and send or send_gh_api

  local raw_result = send_request(request)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh api reply to thread failed",
      code = result.code,
    }
  end

  if result.stdout == "" then
    return {
      state = "ok",
      reply = {},
    }
  end

  local ok, payload_result = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = payload_result,
    }
  end

  if type(payload_result) ~= "table" then
    return {
      state = "parse_error",
      message = "gh api reply to thread returned non-object JSON",
    }
  end

  local data = payload_result.data
  local reply = type(data) == "table" and data.addPullRequestReviewThreadReply
  if type(reply) ~= "table" then
    return {
      state = "parse_error",
      message = "gh api reply to thread returned invalid payload",
    }
  end

  return {
    state = "ok",
    reply = reply,
  }
end

function M.add_thread_reaction(thread_id, content, send)
  vim.validate({
    thread_id = { thread_id, "string" },
    content = { content, "string" },
  })

  if thread_id == "" then
    error("thread_id must be a non-empty string")
  end

  local normalized_content = M.normalize_reaction_content(content)
  if normalized_content == nil then
    error("reaction content must be one of: THUMBS_UP, THUMBS_DOWN, LAUGH, HOORAY, CONFUSED, HEART, ROCKET, EYES")
  end

  local request = {
    method = "POST",
    path = "graphql",
    body = {
      query = [[mutation($input: AddReactionInput!) {
  addReaction(input: $input) {
    reaction {
      content
    }
    subject {
      id
    }
  }
}]],
      variables = {
        input = {
          subjectId = thread_id,
          content = normalized_content,
        },
      },
    },
  }

  local send_request = type(send) == "function" and send or send_gh_api
  local raw_result = send_request(request)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh api add reaction failed",
      code = result.code,
    }
  end

  if result.stdout == "" then
    return {
      state = "ok",
      reaction = {},
    }
  end

  local ok, payload_result = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      state = "parse_error",
      message = payload_result,
    }
  end

  if type(payload_result) ~= "table" then
    return {
      state = "parse_error",
      message = "gh api add reaction returned non-object JSON",
    }
  end

  local data = payload_result.data
  local reaction = type(data) == "table" and data.addReaction
  if type(reaction) ~= "table" then
    return {
      state = "parse_error",
      message = "gh api add reaction returned invalid payload",
    }
  end

  return {
    state = "ok",
    reaction = reaction,
  }
end

local function run_file_viewed_mutation(pull_request_id, path, mutation_name, send)
  vim.validate({
    pull_request_id = { pull_request_id, "string" },
    path = { path, "string" },
    mutation_name = { mutation_name, "string" },
  })

  if pull_request_id == "" then
    error("pull_request_id must be a non-empty string")
  end

  if path == "" then
    error("path must be a non-empty string")
  end

  local request = {
    method = "POST",
    path = "graphql",
    body = {
      query = string.format([[mutation($input: %%s!) {
  %s(input: $input) {
    clientMutationId
  }
}]], mutation_name),
      variables = {
        input = {
          pullRequestId = pull_request_id,
          path = path,
        },
      },
    },
  }

  local input_type = mutation_name == "markFileAsViewed" and "MarkFileAsViewedInput" or "UnmarkFileAsViewedInput"
  request.body.query = string.format(request.body.query, input_type)

  local send_request = type(send) == "function" and send or send_gh_api
  local raw_result = send_request(request)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return invalid_result_error(result_error)
  end

  if result.code ~= 0 then
    return {
      state = "command_error",
      message = result.stderr ~= "" and result.stderr or "gh api file viewed mutation failed",
      code = result.code,
    }
  end

  if result.stdout ~= "" then
    local ok, payload_result = pcall(vim.json.decode, result.stdout)
    if not ok then
      return {
        state = "parse_error",
        message = payload_result,
      }
    end

    if type(payload_result) ~= "table" then
      return {
        state = "parse_error",
        message = "gh api file viewed mutation returned non-object JSON",
      }
    end
  end

  return {
    state = "ok",
  }
end

function M.mark_file_viewed(pull_request_id, path, send)
  return run_file_viewed_mutation(pull_request_id, path, "markFileAsViewed", send)
end

function M.unmark_file_viewed(pull_request_id, path, send)
  return run_file_viewed_mutation(pull_request_id, path, "unmarkFileAsViewed", send)
end

return M

local T = require("sf.term")
local B = require("sf.sub.cmd_builder")
local TS = require("sf.ts")
local U = require("sf.util")
local S = require("sf.sub.test_sign")

local H = {}
local P = {}
local Test = {}

Test.is_sign_enabled = S.is_enabled
Test.refresh_and_place_sign = S.refresh_and_place
Test.setup_sign = S.setup
Test.toggle_sign = S.toggle
Test.uncovered_jump_forward = S.uncovered_jump_forward
Test.uncovered_jump_backward = S.uncovered_jump_backward
Test.refresh_current_file_covered_percent = S.refresh_current_file_covered_percent
Test.covered_percent = function()
  return S.covered_percent
end

Test.open = function()
  P.open()
end

Test.run_current_test_with_coverage = function()
  local ok_class, test_class_name = pcall(H.validateInTestClass)
  if not ok_class then
    return
  end

  local ok_method, test_name = pcall(H.validateInTestMethod)
  if not ok_method then
    return
  end

  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({
      ["-t"] = test_class_name .. "." .. test_name,
      ["-r"] = "human",
      ["-w"] = vim.g.sf.sf_wait_time,
      ["-c"] = "",
    })
    :build()

  U.last_tests = cmd
  T.run(cmd, H.save_test_coverage_locally)
end

---@return nil
Test.run_current_test = function()
  local ok_class, test_class_name = pcall(H.validateInTestClass)
  if not ok_class then
    return
  end

  local ok_method, test_name = pcall(H.validateInTestMethod)
  if not ok_method then
    return
  end

  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({
      ["-t"] = test_class_name .. "." .. test_name,
      ["-r"] = "human",
      ["-w"] = vim.g.sf.sf_wait_time,
    })
    :build()

  U.last_tests = cmd
  T.run(cmd, H.save_test_result_locally)
end

Test.run_all_tests_in_this_file_with_coverage = function()
  local ok_class, test_class_name = pcall(H.validateInTestClass)
  if not ok_class then
    return
  end

  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({
      ["-n"] = test_class_name,
      ["-r"] = "human",
      ["-w"] = vim.g.sf.sf_wait_time,
      ["-c"] = "",
    })
    :build()

  U.last_tests = cmd
  T.run(cmd, H.save_test_coverage_locally)
end

---@return nil
Test.run_all_tests_in_this_file = function()
  local ok_class, test_class_name = pcall(H.validateInTestClass)
  if not ok_class then
    return
  end

  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({
      ["-n"] = test_class_name,
      ["-r"] = "human",
      ["-w"] = vim.g.sf.sf_wait_time,
    })
    :build()

  U.last_tests = cmd
  T.run(cmd, H.save_test_result_locally)
end

Test.repeat_last_tests = function()
  if U.is_empty_str(U.last_tests) then
    return U.show_warn("Last test command is empty.")
  end

  T.run(U.last_tests)
end

--- Re-run only the failed tests from the last test execution.
--- Reads test_result.json from the plugin cache folder,
--- extracts tests with Outcome "Fail" or "CompileFail",
--- and builds a new test command targeting only those.
Test.rerun_failed_tests = function()
  local tbl = U.read_file_in_plugin_folder("test_result.json")
  if not tbl then
    return U.show_warn("No test results found. Run tests first.")
  end

  local tests = vim.tbl_get(tbl, "result", "tests")
  if not tests or vim.tbl_isempty(tests) then
    return U.show_warn("No test data in results.")
  end

  local failed_tests = {}
  for _, test in ipairs(tests) do
    if test.Outcome == "Fail" or test.Outcome == "CompileFail" then
      table.insert(failed_tests, test.FullName)
    end
  end

  if #failed_tests == 0 then
    return U.show("All tests passed! Nothing to rerun.")
  end

  local test_params = ""
  for _, name in ipairs(failed_tests) do
    test_params = test_params .. " -t " .. name
  end

  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({ ["-r"] = "human", ["-w"] = vim.g.sf.sf_wait_time })
    :addParamStr(test_params)
    :build()

  U.last_tests = cmd
  U.show(string.format("Re-running %d failed test(s)...", #failed_tests))
  T.run(cmd, H.save_test_result_locally)
end

Test.run_local_tests = function()
  -- local cmd = string.format("sf apex run test --test-level RunLocalTests --code-coverage -r human --wait 180 -o %s", U.get())
  local cmd = B:new()
    :cmd("apex")
    :act("run test")
    :addParams({
      ["-l"] = "RunLocalTests",
      ["-c"] = "",
      ["-r"] = "human",
      ["-w"] = 180,
    })
    :build()

  U.last_tests = cmd
  T.run(cmd)
end

Test.run_all_jests = function()
  T.run("npm run test:unit:coverage")
end

Test.run_jest_file = function()
  if vim.fn.expand("%"):match("(.*)%.test%.js$") == nil then
    vim.notify("Not in a jest test file", vim.log.levels.ERROR)
    return
  end
  T.run(string.format("npm run test:unit -- -- %s", vim.fn.expand("%")))
end

-- helper;

H.validateInTestClass = function()
  local test_class_name = TS.get_test_class_name()
  if U.is_empty_str(test_class_name) then
    U.notify_then_error("Not in a test class.")
  end

  return test_class_name
end

H.validateInTestMethod = function()
  local test_name = TS.get_current_test_method_name()
  if U.is_empty_str(test_name) then
    U.notify_then_error("Cursor not in a test method.")
  end

  return test_name
end

---@param lines table
---@return any
H.extract_test_run_id = function(lines)
  for _, line in ipairs(lines) do
    if string.find(line, "Test Run Id") then
      return string.match(line, "Test Run Id%s*(%w+)")
    end
  end
  return nil
end

--- Save test result JSON locally after a test run completes.
--- When with_coverage is true, includes code coverage data in the result.
---@param self table terminal instance with buf
---@param _ string the command that was run (unused)
---@param exit_code number exit code from the terminal
---@param with_coverage boolean whether to include code coverage
H.save_test_result = function(self, _, exit_code, with_coverage)
  U.create_plugin_folder_if_not_exist()

  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
  local id = H.extract_test_run_id(lines)
  if id == nil then
    return
  end

  local file_name = "test_result.json"
  local cmd_builder = B:new():cmd("apex"):act("get test"):addParams("-i", id):addParams("--json")
  if with_coverage then
    cmd_builder:addParams("-c")
  end
  local cmd = cmd_builder:build()
  cmd = cmd .. " > " .. U.get_plugin_folder_path() .. file_name

  local msg = with_coverage and "Test result + coverage saved." or "Test result saved."
  local err_msg = "Test result save failed! " .. cmd
  local cb = with_coverage and S.invalidate_cache_and_try_place or nil

  -- Use vim.system to execute through shell (supports redirection)
  vim.system({ "sh", "-c", cmd }, {}, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        U.show(msg)
        if cb ~= nil then
          cb()
        end
      else
        U.show_err(err_msg)
      end
    end)
  end)
end

--- Callback for test runs WITH code coverage
---@param self table
---@param cmd string
---@param exit_code number
H.save_test_coverage_locally = function(self, cmd, exit_code)
  H.save_test_result(self, cmd, exit_code, true)
end

--- Callback for test runs WITHOUT code coverage (still saves result JSON for rerun/results features)
---@param self table
---@param cmd string
---@param exit_code number
H.save_test_result_locally = function(self, cmd, exit_code)
  H.save_test_result(self, cmd, exit_code, false)
end

-- prompt below

local api = vim.api
local buftype = "nowrite"
local filetype = "sf_test_prompt"

P.buf = nil
P.win = nil
P.class = nil
P.tests = nil
P.test_num = nil
P.selected_tests = {}
P.prev_results = {} -- maps "ClassName.MethodName" -> "Pass"|"Fail"|"CompileFail"

P.open = function()
  local class = TS.get_test_class_name()
  if U.is_empty_str(class) then
    U.notify_then_error("Not an Apex test class.")
  end

  local test_names = TS.get_test_method_names_in_curr_file()
  if vim.tbl_isempty(test_names) then
    U.show("no Apex test found.")
  end

  local tests = {}
  local test_num = 0
  for _, name in ipairs(test_names) do
    table.insert(tests, name)
    test_num = test_num + 1
  end

  P.class = class
  P.tests = tests
  P.test_num = test_num

  -- Load previous test results for PASS/FAIL indicators
  P.prev_results = {}
  local tbl = U.read_file_in_plugin_folder("test_result.json")
  if tbl then
    local prev_tests = vim.tbl_get(tbl, "result", "tests")
    if prev_tests then
      for _, t in ipairs(prev_tests) do
        if t.FullName then
          P.prev_results[t.FullName] = t.Outcome
        end
      end
    end
  end

  local buf = P.use_existing_or_create_buf()
  local win = P.use_existing_or_create_win()
  P.buf = buf
  P.win = win

  api.nvim_win_set_buf(win, buf)

  P.set_keys()

  vim.bo[buf].modifiable = true
  P.display()
  vim.bo[buf].modifiable = false
end

-- Helper to get test keybindings from config
H.get_test_keys = function()
  local cfg = vim.g.sf.test_keys
  if cfg == false then
    return nil
  end
  return cfg or {}
end

-- Helper to set a keymap if the key is defined
H.set_test_keymap = function(mode, key, callback, buf, desc)
  if not key or key == "" then
    return
  end
  local opts = { buffer = buf, noremap = true }
  if desc then
    opts.desc = desc
  end
  vim.keymap.set(mode, key, callback, opts)
end

P.set_keys = function()
  local keys = H.get_test_keys()
  if not keys then
    return
  end

  local selector_keys = keys.selector or {}

  -- Toggle selection
  H.set_test_keymap("n", selector_keys.toggle, function()
    P.toggle()
  end, P.buf, "Toggle test selection")

  -- Select all / deselect all toggle
  H.set_test_keymap("n", selector_keys.select_all, function()
    vim.bo[P.buf].modifiable = true
    if #P.selected_tests >= P.test_num then
      -- All selected -> deselect all
      P.selected_tests = {}
    else
      -- Select all
      P.selected_tests = {}
      for _, test in ipairs(P.tests) do
        table.insert(P.selected_tests, string.format("%s.%s", P.class, test))
      end
    end
    P.display()
    vim.bo[P.buf].modifiable = false
    U.show("Selected: " .. vim.tbl_count(P.selected_tests))
  end, P.buf, "Select/deselect all tests")

  -- Invert selection
  H.set_test_keymap("n", selector_keys.invert_selection, function()
    vim.bo[P.buf].modifiable = true
    local new_selected = {}
    for _, test in ipairs(P.tests) do
      local class_test = string.format("%s.%s", P.class, test)
      if not vim.tbl_contains(P.selected_tests, class_test) then
        table.insert(new_selected, class_test)
      end
    end
    P.selected_tests = new_selected
    P.display()
    vim.bo[P.buf].modifiable = false
    U.show("Selected: " .. vim.tbl_count(P.selected_tests))
  end, P.buf, "Invert test selection")

  local create_cmd = function(tbl)
    local cmd_builder = B:new():cmd("apex"):act("run test"):addParams(tbl)

    local test_params = ""
    for _, test in ipairs(P.selected_tests) do
      test_params = test_params .. " -t " .. test
    end

    local cmd = cmd_builder:addParamStr(test_params):build()

    return cmd
  end

  -- Run selected tests
  H.set_test_keymap("n", selector_keys.run, function()
    if vim.tbl_isempty(P.selected_tests) then
      return U.show_err("No test is selected.")
    end

    local cmd = create_cmd({ ["-w"] = vim.g.sf.sf_wait_time, ["-r"] = "human" })

    P.close()
    T.run(cmd, H.save_test_result_locally)
    U.last_tests = cmd
    P.selected_tests = {}
  end, P.buf, "Run selected tests")

  -- Run selected tests with coverage
  H.set_test_keymap("n", selector_keys.run_with_coverage, function()
    if vim.tbl_isempty(P.selected_tests) then
      return U.show_err("No test is selected.")
    end

    local cmd = create_cmd({ ["-w"] = vim.g.sf.sf_wait_time, ["-r"] = "human", ["-c"] = "" })

    P.close()
    T.run(cmd, H.save_test_coverage_locally)
    U.last_tests = cmd
    P.selected_tests = {}
  end, P.buf, "Run selected tests with coverage")
end

P.display = function()
  api.nvim_set_current_win(P.win)
  local names = {}

  -- Build header with configured keys
  local keys = H.get_test_keys()
  local header_parts = {}
  if keys and keys.selector then
    local s = keys.selector
    if s.toggle then table.insert(header_parts, string.format('"%s": toggle', s.toggle)) end
    if s.select_all then table.insert(header_parts, string.format('"%s": all', s.select_all)) end
    if s.invert_selection then table.insert(header_parts, string.format('"%s": invert', s.invert_selection)) end
    if s.run then table.insert(header_parts, string.format('"%s": run', s.run)) end
    if s.run_with_coverage then table.insert(header_parts, string.format('"%s": run+coverage', s.run_with_coverage)) end
  end

  if #header_parts > 0 then
    table.insert(names, '** ' .. table.concat(header_parts, " | "))
  else
    table.insert(names, '** Test Selector')
  end

  -- Find the longest test name for alignment
  local max_len = 0
  for _, test in ipairs(P.tests) do
    if #test > max_len then
      max_len = #test
    end
  end

  for _, test in ipairs(P.tests) do
    local class_test = string.format("%s.%s", P.class, test)
    local checkbox = vim.tbl_contains(P.selected_tests, class_test) and "[x] " or "[ ] "

    -- Append previous result status if available
    local status_str = ""
    local outcome = P.prev_results[class_test]
    if outcome == "Pass" then
      status_str = string.rep(" ", max_len - #test + 2) .. "PASS"
    elseif outcome == "Fail" or outcome == "CompileFail" then
      status_str = string.rep(" ", max_len - #test + 2) .. "FAIL"
    end

    table.insert(names, checkbox .. test .. status_str)
  end
  api.nvim_buf_set_lines(P.buf, 0, 100, false, names)

  -- Apply highlights for PASS/FAIL indicators
  P.apply_result_highlights()
end

--- Apply syntax highlights for PASS/FAIL status text in the test selector buffer
P.apply_result_highlights = function()
  if not P.buf or not api.nvim_buf_is_loaded(P.buf) then
    return
  end

  local ns = api.nvim_create_namespace("sf_test_select")
  api.nvim_buf_clear_namespace(P.buf, ns, 0, -1)

  local lines = api.nvim_buf_get_lines(P.buf, 0, -1, false)
  for i, line in ipairs(lines) do
    -- Skip header line (index 0)
    if i > 1 then
      local pass_start = line:find("PASS$")
      local fail_start = line:find("FAIL$")
      if pass_start then
        api.nvim_buf_add_highlight(P.buf, ns, "DiagnosticOk", i - 1, pass_start - 1, -1)
      elseif fail_start then
        api.nvim_buf_add_highlight(P.buf, ns, "DiagnosticError", i - 1, fail_start - 1, -1)
      end
    end
  end
end

P.use_existing_or_create_buf = function()
  if P.buf and api.nvim_buf_is_loaded(P.buf) then
    return P.buf
  end

  local buf = api.nvim_create_buf(false, false)
  vim.bo[buf].buftype = buftype
  vim.bo[buf].filetype = filetype

  return buf
end

P.use_existing_or_create_win = function()
  local win_hight = P.test_num + 2

  if P.win and api.nvim_win_is_valid(P.win) then
    api.nvim_set_current_win(P.win)
    api.nvim_win_set_height(P.win, win_hight)
    return P.win
  end

  api.nvim_command(win_hight .. "split")

  return api.nvim_get_current_win()
end

P.toggle = function()
  if vim.bo[0].filetype ~= filetype then
    return U.show_err("file-type must be: " .. filetype)
  end

  vim.bo[0].modifiable = true

  local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
  if r == 1 then -- 1st row is title
    return
  end

  local row_index = r - 1

  local curr_value = api.nvim_buf_get_text(0, row_index, 1, row_index, 2, {})

  local name = P.tests[row_index]
  local class_test = string.format("%s.%s", P.class, name)
  local index = U.list_find(P.selected_tests, class_test)

  if curr_value[1] == "x" then
    if index ~= nil then
      table.remove(P.selected_tests, index)
    end
    api.nvim_buf_set_text(0, row_index, 1, row_index, 2, { " " })
  elseif curr_value[1] == " " then
    if index == nil then
      table.insert(P.selected_tests, class_test)
    end
    api.nvim_buf_set_text(0, row_index, 1, row_index, 2, { "x" })
  end

  U.show("Selected: " .. vim.tbl_count(P.selected_tests))

  vim.bo[0].modifiable = false
end

P.close = function()
  if P.win and api.nvim_win_is_valid(P.win) then
    api.nvim_win_close(P.win, false)
  end
end

-- Results panel ================================================================

local R = {}
R.buf = nil
R.win = nil
R.test_data = nil -- stores parsed test results for keybinding actions

--- Read and validate test_result.json, returning the parsed table or nil
---@return table|nil
H.read_test_results = function()
  local tbl = U.read_file_in_plugin_folder("test_result.json")
  if not tbl then
    U.show_warn("No test results found. Run tests first.")
    return nil
  end

  local tests = vim.tbl_get(tbl, "result", "tests")
  if not tests or vim.tbl_isempty(tests) then
    U.show_warn("No test data in results.")
    return nil
  end

  return tbl
end

--- Parse a Salesforce Apex stack trace line to extract class name, line number, and column.
--- Patterns handled:
---   "Class.ClassName.MethodName: line 45, column 1"
---   "Class.Namespace.ClassName.MethodName: line 45, column 1"
---   "Trigger.TriggerName: line 10, column 1"
---@param stack_trace string|nil
---@return string|nil class_name, number|nil lnum, number|nil col
H.parse_stack_trace = function(stack_trace)
  if not stack_trace or stack_trace == "" then
    return nil, nil, nil
  end

  -- Take only the first line of a multi-line stack trace
  local first_line = stack_trace:match("^([^\n]+)")
  if not first_line then
    return nil, nil, nil
  end

  -- Extract line and column numbers
  local lnum_str, col_str = first_line:match("line (%d+),? ?column? ?(%d*)")
  local lnum = lnum_str and tonumber(lnum_str) or nil
  local col = col_str and tonumber(col_str) or nil

  -- Extract class name: "Class.ClassName.MethodName: line ..." -> "ClassName"
  -- Also handles "Class.Namespace.ClassName.MethodName: line ..."
  local prefix = first_line:match("^(.-):%s*line")
  if not prefix then
    return nil, lnum, col
  end

  local parts = vim.split(prefix, ".", { plain = true })
  -- For "Class.ClassName.MethodName" -> parts = {"Class", "ClassName", "MethodName"}
  -- The class name is the second-to-last part (last is method name, first is "Class")
  if #parts >= 3 then
    return parts[#parts - 1], lnum, col
  elseif #parts == 2 then
    -- "Trigger.TriggerName" case
    return parts[2], lnum, col
  end

  return nil, lnum, col
end

--- Resolve a Salesforce class name to a local file path
---@param class_name string
---@return string|nil
H.resolve_class_to_file = function(class_name)
  local sf_root = U.get_sf_root()

  -- Try common locations in order
  local candidates = {
    sf_root .. "force-app/main/default/classes/" .. class_name .. ".cls",
    sf_root .. "force-app/main/default/triggers/" .. class_name .. ".trigger",
  }

  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  -- Fallback: search recursively from sf root
  local found = vim.fn.findfile(class_name .. ".cls", sf_root .. "**")
  if found ~= "" then
    return vim.fn.fnamemodify(found, ":p")
  end

  found = vim.fn.findfile(class_name .. ".trigger", sf_root .. "**")
  if found ~= "" then
    return vim.fn.fnamemodify(found, ":p")
  end

  return nil
end

--- Format a duration in milliseconds to a human-readable string
---@param ms number|nil
---@return string
H.format_duration = function(ms)
  if not ms or ms == vim.NIL then
    return "-.---s"
  end
  return string.format("%.3fs", ms / 1000)
end

--- Open the structured test results panel in a bottom split.
--- Shows PASS/FAIL status, timing, error messages, and stack traces.
--- Keybindings: <CR> to jump to error, r to rerun test, R to rerun all failed, l for log, q to close.
Test.show_results = function()
  R.open()
end

R.open = function()
  local tbl = H.read_test_results()
  if not tbl then
    return
  end

  local summary = vim.tbl_get(tbl, "result", "summary") or {}
  local tests = tbl.result.tests
  R.test_data = tests

  -- Build display lines
  local lines = {}
  local highlights = {} -- { line_idx, hl_group, col_start, col_end }

  -- Header
  local total = summary.testsRan or #tests
  local passing = summary.passing or 0
  local failing = summary.failing or 0
  local header = string.format(
    "Test Results (%d/%d PASS, %d FAIL)",
    passing, total, failing
  )
  table.insert(lines, header)
  table.insert(lines, string.rep("-", #header + 10))

  -- Track which line index maps to which test (for keybinding navigation)
  R.line_to_test = {} -- maps line_idx (0-based) -> test entry

  for _, test in ipairs(tests) do
    local class_name = test.ApexClass and test.ApexClass.Name or "Unknown"
    local method_name = test.MethodName or "unknown"
    local outcome = test.Outcome or "Unknown"
    local run_time = H.format_duration(test.RunTime)

    local status_icon
    local status_hl
    if outcome == "Pass" then
      status_icon = "PASS"
      status_hl = "DiagnosticOk"
    elseif outcome == "Fail" or outcome == "CompileFail" then
      status_icon = "FAIL"
      status_hl = "DiagnosticError"
    else
      status_icon = outcome
      status_hl = "DiagnosticWarn"
    end

    local line = string.format("  %s  %s.%s    %s", status_icon, class_name, method_name, run_time)
    local line_idx = #lines
    table.insert(lines, line)
    R.line_to_test[line_idx] = test

    -- Record highlight for the status icon
    table.insert(highlights, { line_idx, status_hl, 2, 2 + #status_icon })

    -- Show error message and stack trace for failed tests
    if outcome == "Fail" or outcome == "CompileFail" then
      if test.Message and test.Message ~= "" then
        -- Truncate long messages to a single line
        local msg = test.Message:match("^([^\n]+)") or test.Message
        local msg_line = "         > " .. msg
        table.insert(lines, msg_line)
        table.insert(highlights, { #lines - 1, "DiagnosticWarn", 0, -1 })
      end
      if test.StackTrace and test.StackTrace ~= "" then
        local trace = test.StackTrace:match("^([^\n]+)") or test.StackTrace
        local trace_line = "         > " .. trace
        table.insert(lines, trace_line)
        table.insert(highlights, { #lines - 1, "Comment", 0, -1 })
      end
    end
  end

  -- Create or reuse buffer
  if not R.buf or not api.nvim_buf_is_loaded(R.buf) then
    R.buf = api.nvim_create_buf(false, true)
    vim.bo[R.buf].buftype = "nofile"
    vim.bo[R.buf].filetype = "sf_test_results"
    vim.bo[R.buf].swapfile = false
  end

  vim.bo[R.buf].modifiable = true
  api.nvim_buf_set_lines(R.buf, 0, -1, false, lines)
  vim.bo[R.buf].modifiable = false

  -- Apply highlights
  local ns = api.nvim_create_namespace("sf_test_results")
  api.nvim_buf_clear_namespace(R.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_add_highlight(R.buf, ns, hl[2], hl[1], hl[3], hl[4])
  end
  -- Header highlight
  api.nvim_buf_add_highlight(R.buf, ns, "Title", 0, 0, -1)

  -- Open in bottom split
  local win_height = math.min(#lines + 1, math.floor(vim.o.lines * 0.4))
  if R.win and api.nvim_win_is_valid(R.win) then
    api.nvim_set_current_win(R.win)
    api.nvim_win_set_buf(R.win, R.buf)
    api.nvim_win_set_height(R.win, win_height)
  else
    vim.cmd("botright " .. win_height .. "split")
    R.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(R.win, R.buf)
  end

  vim.wo[R.win].number = false
  vim.wo[R.win].relativenumber = false
  vim.wo[R.win].signcolumn = "no"
  vim.wo[R.win].cursorline = true

  R.set_keys()
end

R.set_keys = function()
  local buf = R.buf
  local keys = H.get_test_keys()
  if not keys then
    return
  end

  local results_keys = keys.results or {}

  -- Close results panel
  H.set_test_keymap("n", results_keys.close, function()
    R.close()
  end, buf, "Close results panel")

  -- Jump to error location from stack trace
  H.set_test_keymap("n", results_keys.jump_to_error, function()
    local cursor = api.nvim_win_get_cursor(R.win)
    local line_idx = cursor[1] - 1

    -- Find the test associated with this line (could be the test line or an error line below it)
    local test = R.line_to_test[line_idx]
    if not test then
      -- Maybe we're on an error/trace line, look upward
      for check = line_idx - 1, 0, -1 do
        if R.line_to_test[check] then
          test = R.line_to_test[check]
          break
        end
      end
    end

    if not test then
      return
    end

    if test.Outcome ~= "Fail" and test.Outcome ~= "CompileFail" then
      return U.show("Test passed, no error to navigate to.")
    end

    local class_name, lnum, col = H.parse_stack_trace(test.StackTrace)
    if not class_name then
      return U.show_warn("Could not parse stack trace.")
    end

    local file_path = H.resolve_class_to_file(class_name)
    if not file_path then
      return U.show_warn("Could not find file for class: " .. class_name)
    end

    -- Close results panel and jump to the error location
    R.close()
    vim.cmd("edit " .. file_path)
    if lnum then
      api.nvim_win_set_cursor(0, { lnum, (col or 1) - 1 })
    end
  end, buf, "Jump to error location")

  -- Rerun the test under cursor
  H.set_test_keymap("n", results_keys.rerun_test, function()
    local cursor = api.nvim_win_get_cursor(R.win)
    local line_idx = cursor[1] - 1

    local test = R.line_to_test[line_idx]
    if not test then
      for check = line_idx - 1, 0, -1 do
        if R.line_to_test[check] then
          test = R.line_to_test[check]
          break
        end
      end
    end

    if not test or not test.FullName then
      return U.show_warn("No test found on this line.")
    end

    R.close()
    local cmd = B:new()
      :cmd("apex")
      :act("run test")
      :addParams({ ["-t"] = test.FullName, ["-r"] = "human", ["-w"] = vim.g.sf.sf_wait_time })
      :build()

    U.last_tests = cmd
    T.run(cmd, H.save_test_result_locally)
  end, buf, "Rerun test under cursor")

  -- Rerun all failed tests
  H.set_test_keymap("n", results_keys.rerun_failed, function()
    R.close()
    Test.rerun_failed_tests()
  end, buf, "Rerun all failed tests")

  -- Open test log
  H.set_test_keymap("n", results_keys.show_log, function()
    R.close()
    Test.show_test_log()
  end, buf, "Show test log")
end

R.close = function()
  if R.win and api.nvim_win_is_valid(R.win) then
    api.nvim_win_close(R.win, false)
  end
end

-- Quickfix integration =========================================================

--- Populate the quickfix list with failed test errors and their source locations.
--- Parses stack traces from the last test run to provide navigable error entries.
Test.populate_quickfix = function()
  local tbl = H.read_test_results()
  if not tbl then
    return
  end

  local tests = tbl.result.tests
  local qf_entries = {}
  local sf_root_ok, _ = pcall(U.get_sf_root)

  for _, test in ipairs(tests) do
    if test.Outcome == "Fail" or test.Outcome == "CompileFail" then
      local class_name, lnum, col = H.parse_stack_trace(test.StackTrace)

      local filename = nil
      if class_name and sf_root_ok then
        filename = H.resolve_class_to_file(class_name)
      end

      local text = string.format("[%s.%s] %s",
        test.ApexClass and test.ApexClass.Name or "Unknown",
        test.MethodName or "unknown",
        test.Message or "Test failed"
      )

      table.insert(qf_entries, {
        filename = filename,
        lnum = lnum or 0,
        col = col or 0,
        text = text,
        type = "E",
      })
    end
  end

  if #qf_entries == 0 then
    return U.show("All tests passed! No errors for quickfix.")
  end

  vim.fn.setqflist(qf_entries, "r")
  vim.fn.setqflist({}, "a", { title = "SF Test Failures" })
  vim.cmd("copen")
  U.show(string.format("%d test failure(s) added to quickfix.", #qf_entries))
end

-- Test log viewer ==============================================================

--- Download and open the debug log associated with the last test execution.
--- Extracts the ApexLogId from test_result.json and fetches the log from the org.
Test.show_test_log = function()
  local tbl = H.read_test_results()
  if not tbl then
    return
  end

  local tests = tbl.result.tests

  -- Find the first available ApexLogId
  local log_id = nil
  for _, test in ipairs(tests) do
    if test.ApexLogId and test.ApexLogId ~= vim.NIL then
      log_id = test.ApexLogId
      break
    end
  end

  if not log_id then
    return U.show_warn("No debug log found for the last test run.")
  end

  U.create_plugin_folder_if_not_exist()

  local logs_dir = U.get_plugin_folder_path() .. "logs/"
  if vim.fn.isdirectory(logs_dir) == 0 then
    vim.fn.mkdir(logs_dir, "p")
  end

  local log_path = logs_dir .. log_id .. ".log"

  -- If already downloaded, just open it
  if vim.fn.filereadable(log_path) == 1 then
    vim.cmd("botright split " .. log_path)
    return
  end

  -- Download the log from the org
  U.show("Downloading test log...")
  local get_cmd = B:new()
    :cmd("apex")
    :act("get")
    :subact("log")
    :addParams("-i", log_id)
    :addParams("-d", logs_dir)
    :buildAsTable()

  U.silent_system_call(get_cmd, nil, "Failed to download test log", function()
    vim.schedule(function()
      if vim.fn.filereadable(log_path) == 1 then
        vim.cmd("botright split " .. log_path)
      else
        U.show_err("Log file not found after download: " .. log_path)
      end
    end)
  end)
end

return Test

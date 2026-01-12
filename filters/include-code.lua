-- Pandoc/Quarto filter: replace code blocks whose attributes specify `file="..."`
-- with the contents of that file (optionally extracting a named snippet).

local function is_absolute_path(path)
  if path:match("^/") then
    return true
  end
  -- Windows drive letter, e.g. C:\...
  if path:match("^[A-Za-z]:[\\/].+") then
    return true
  end
  return false
end

local function join_path(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local function resolve_path(path)
  if is_absolute_path(path) then
    return path
  end

  local project_dir = os.getenv("QUARTO_PROJECT_DIR")
  if project_dir and #project_dir > 0 then
    return join_path(project_dir, path)
  end

  local input_files = PANDOC_STATE and PANDOC_STATE.input_files
  local first_input = input_files and input_files[1]
  if first_input then
    local input_dir = first_input:match("^(.*)/[^/]+$") or "."
    return join_path(input_dir, path)
  end

  return path
end

local function read_file(path)
  local file, open_err = io.open(path, "r")
  if not file then
    error("include-code.lua: failed to open file: " .. path .. " (" .. tostring(open_err) .. ")")
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function normalize_newlines(s)
  s = s:gsub("\r\n", "\n")
  s = s:gsub("\r", "\n")
  return s
end

local function split_lines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function trim_trailing_blank_lines(lines)
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines, #lines)
  end
  return lines
end

local function strip_snippet_marker_lines(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if not line:match("^%s*%-%-%s*snippet:%s*start%s+") and not line:match("^%s*%-%-%s*snippet:%s*end%s+") then
      table.insert(out, line)
    end
  end
  return out
end

local function maybe_uncomment(lines)
  local saw_nonblank = false
  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then
      saw_nonblank = true
      if not line:match("^%s*%-%-") then
        return lines
      end
    end
  end

  if not saw_nonblank then
    return lines
  end

  local out = {}
  for _, line in ipairs(lines) do
    local uncommented = line:gsub("^(%s*)%-%-%s?", "%1", 1)
    table.insert(out, uncommented)
  end
  return out
end

local function dedent(lines)
  local min_indent = nil
  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then
      local indent = line:match("^(%s*)")
      local spaces = #indent:gsub("\t", "    ")
      if min_indent == nil or spaces < min_indent then
        min_indent = spaces
      end
    end
  end

  if not min_indent or min_indent == 0 then
    return lines
  end

  local out = {}
  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      table.insert(out, line)
    else
      local expanded = line:gsub("\t", "    ")
      table.insert(out, expanded:sub(min_indent + 1))
    end
  end
  return out
end

local function escape_lua_pattern(s)
  return (s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

local function truthy(s)
  if not s then
    return false
  end
  s = tostring(s):lower()
  return s == "true" or s == "1" or s == "yes" or s == "on"
end

local function is_html_format()
  return FORMAT and tostring(FORMAT):match("html") ~= nil
end

local function extract_snippet(contents, snippet_name, file_path)
  local escaped = escape_lua_pattern(snippet_name)
  local start_pat = "^%s*%-%-%s*snippet:start%s+" .. escaped .. "%s*$"
  local end_pat = "^%s*%-%-%s*snippet:end%s+" .. escaped .. "%s*$"

  local lines = split_lines(contents)
  local start_idx = nil
  for i, line in ipairs(lines) do
    if line:match(start_pat) then
      start_idx = i + 1
      break
    end
  end

  if not start_idx then
    error("include-code.lua: snippet:start '" .. snippet_name .. "' not found in " .. file_path)
  end

  local out = {}
  for i = start_idx, #lines do
    if lines[i]:match(end_pat) then
      return out
    end
    table.insert(out, lines[i])
  end

  error("include-code.lua: snippet:end '" .. snippet_name .. "' not found in " .. file_path)
end

local function parse_lines_spec(spec)
  if not spec or #spec == 0 then
    return nil, nil
  end

  spec = tostring(spec):gsub("^%s+", ""):gsub("%s+$", "")

  local single = spec:match("^(%d+)$")
  if single then
    local n = tonumber(single)
    return n, n
  end

  local start_s, end_s = spec:match("^(%d+)%s*%-%s*(%d+)$")
  if start_s and end_s then
    return tonumber(start_s), tonumber(end_s)
  end

  local start_only = spec:match("^(%d+)%s*%-%s*$")
  if start_only then
    return tonumber(start_only), nil
  end

  local end_only = spec:match("^%-%s*(%d+)%s*$")
  if end_only then
    return nil, tonumber(end_only)
  end

  error('include-code.lua: invalid lines spec "' .. spec .. '" (expected e.g. "12-34", "12-", "-34", or "12")')
end

local function slice_lines(lines, start_line, end_line)
  local total = #lines
  local s = start_line or 1
  local e = end_line or total

  if s < 1 or e < 1 or s > total or e > total then
    error(
      "include-code.lua: requested line range "
        .. tostring(start_line or "")
        .. "-"
        .. tostring(end_line or "")
        .. " is out of bounds (1-"
        .. tostring(total)
        .. ")"
    )
  end
  if s > e then
    error("include-code.lua: requested line range start is greater than end")
  end

  local out = {}
  for i = s, e do
    table.insert(out, lines[i])
  end
  return out
end

function CodeBlock(el)
  local include_path = el.attributes["file"] or el.attributes["include"] or el.attributes["tac-file"]
  if not include_path then
    return nil
  end

  local resolved = resolve_path(include_path)
  local contents = normalize_newlines(read_file(resolved))

  local snippet_name = el.attributes["snippet"] or el.attributes["tac-snippet"]
  local lines
  if snippet_name and #snippet_name > 0 then
    lines = extract_snippet(contents, snippet_name, include_path)
  else
    lines = split_lines(contents)
  end

  local lines_spec = el.attributes["lines"] or el.attributes["line-range"] or el.attributes["line_range"]
  local start_attr = el.attributes["start-line"] or el.attributes["start_line"]
  local end_attr = el.attributes["end-line"] or el.attributes["end_line"]
  if lines_spec and (start_attr or end_attr) then
    error('include-code.lua: use either `lines="..."` or `start-line`/`end-line`, not both')
  end

  local start_line, end_line = nil, nil
  if lines_spec then
    start_line, end_line = parse_lines_spec(lines_spec)
  elseif start_attr or end_attr then
    if start_attr and #tostring(start_attr) > 0 then
      start_line = tonumber(start_attr)
      if not start_line then
        error('include-code.lua: invalid start-line "' .. tostring(start_attr) .. '" (must be a number)')
      end
    end
    if end_attr and #tostring(end_attr) > 0 then
      end_line = tonumber(end_attr)
      if not end_line then
        error('include-code.lua: invalid end-line "' .. tostring(end_attr) .. '" (must be a number)')
      end
    end
  end

  if start_line or end_line then
    lines = slice_lines(lines, start_line, end_line)
  end

  lines = strip_snippet_marker_lines(lines)
  lines = maybe_uncomment(lines)
  lines = trim_trailing_blank_lines(lines)
  lines = dedent(lines)

  el.text = table.concat(lines, "\n")

  local show_path = truthy(el.attributes["show-path"] or el.attributes["show_path"] or el.attributes["show-file"])
  if not show_path then
    return el
  end

  -- Ensure HTML can style a filename label via CSS using `attr(data-file)`.
  el.attributes["data-file"] = include_path
  el.attributes["data-show-path"] = "true"

  if is_html_format() then
    return el
  end

  local label = pandoc.Para({ pandoc.Str("Source:"), pandoc.Space(), pandoc.Code(include_path) })
  return pandoc.Div({ label, el }, pandoc.Attr("", { "include-code" }, { ["data-file"] = include_path }))
end

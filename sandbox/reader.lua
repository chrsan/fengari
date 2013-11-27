local M = {}

local lpeg = require('lpeg')

function M.create_string_reader(str, buf_len)
  local reader = {}
  local str_pos = 1

  buf_len = buf_len or 1

  local buf_pos = buf_len + 1
  local buf = {}

  function reader.read_char()
    local ch = nil
    if buf_pos <= buf_len then
      ch = buf[buf_pos]
      buf_pos = buf_pos + 1
    elseif str_pos <= #str then
      ch = str:sub(str_pos, str_pos)
      str_pos = str_pos + 1
    end
    return ch
  end

  function reader.peek_char()
    if buf_pos <= buf_len then
      return buf[buf_pos]
    elseif str_pos <= #str then
      return str:sub(str_pos, str_pos)
    end
  end

  function reader.unread(ch)
    if ch then
      if buf_pos == 1 then error("Pushback buffer is full") end
      buf_pos = buf_pos - 1
      buf[buf_pos] = ch
    end
  end

  return reader
end

function M.is_whitespace(ch)
  return ch and (ch == ',' or ch:find("%s") ~= nil)
end

function M.is_numeric(ch)
  return ch and ch:find("%d") ~= nil
end

function M.is_newline(ch)
  return not ch or ch == "\n"
end

function M.normalize_newline(reader, ch)
  if ch ~= "\r" then return ch end
  local c = reader.peek_char()
  if c == "\f" or c == "\n" then reader.read_char() end
  return "\n"
end

function M.is_number_literal(reader, ch)
  return M.is_numeric(ch) or
    ((ch == '+' or ch == '-') and M.is_numeric(reader.peek_char()))
end

function M.read_past(pred, reader)
  repeat
    ch = reader.read_char()
  until not pred(ch)
  return ch
end

function M.skip_line(reader)
  repeat
    local ch = reader.read_char()
  until M.is_newline(ch)
  return reader
end

function M.read_comment(reader)
  return M.skip_line(reader)
end

local sign = lpeg.S("-+")^-1
local zero = lpeg.P("0")
local int = lpeg.C(lpeg.R("19") * lpeg.R("09")^0)
local hex = zero * lpeg.S("xX") * lpeg.C(lpeg.R("09", "AF", "af")^1)
local octal = zero * lpeg.C(lpeg.R("07")^1)
local base = lpeg.C(lpeg.R("19") * lpeg.R("09")^-1) * lpeg.S("rR") * lpeg.C(lpeg.R("09", "AZ", "az")^1)
local n = lpeg.P("N")^-1

local function match_int(str)
  local function to_num(match, radix)
    local num = tonumber(match, radix)
    if str:sub(1, 1) == '-' then
      return -num
    end
    return num
  end

  if lpeg.match(sign * zero * n * -1, str) then
    return 0
  end

  local m = lpeg.match(sign * int * n * -1, str)
  if m then return to_num(m, 10) end

  m = lpeg.match(sign * hex * n * -1, str)
  if m then return to_num(m, 16) end

  m = lpeg.match(sign * octal * n * -1, str)
  if m then return to_num(m, 8) end

  local radix, n = lpeg.match(sign * base * n * -1, str)
  if radix then return to_num(n, to_numer(radix)) end
end

local ratio = lpeg.R("09")^1 * lpeg.P("/") * lpeg.C(lpeg.R("09")^1)

local function match_ratio(str)
  local numerator, denominator = lpeg.match(sign * ratio * -1, str)
  if numerator then
    numerator = tonumber(numerator)
    if str:sub(1, 1) == '-' then numerator = -numerator end
    return numerator / tonumber(denominator)
  end
end

local num = lpeg.R("09")^1
local frac = (lpeg.P(".") * lpeg.R("09")^0)^-1
local exp = (lpeg.S("eE") * lpeg.S("-+")^-1 * lpeg.R("09")^1)^-1
local float = lpeg.C(sign * num * frac * exp) * lpeg.P("M")^-1 * -1

local function match_float(str)
  local m = lpeg.match(float, str)
  if m then return tonumber(m) end
end

function M.match_number(str)
  local i = match_int(str)
  if i then return i end

  local f = match_float(str)
  if f then return f end

  local r = match_ratio(str)
  if r then return r end
end

function M.parse_symbol(str)
  if str == "" or str:find("::", 1, true) then return nil end
  local ns_index = str:find("/", 1, true)
  if ns_index and ns_index > 1 then
    local ns = str:sub(1, ns_index - 1)
    ns_index = ns_index + 1
    if ns_index ~= #str + 1 then
      local sym = str:sub(ns_index)
      if not M.is_numeric(sym:sub(1, 1)) and sym ~= "" or (sym == '/' and not sym:find('/', 1, true)) then
        return ns, sym
      end
    end
  else
    if str == '/' or not str:find('/', 1, true) then
      return nil, str
    end
  end
end

local function is_macro_terminating(ch)
  return string.find('";@^`~()[]{}\\', ch, 1, true) ~= nil
end

function M.read_token(reader, init_ch)
  if not init_ch then error("EOF while reading") end
  local sb = {init_ch}
  while true do
    local ch = reader.read_char()
    if not ch or M.is_whitespace(ch) or M.is_macro_terminating(ch) then
      reader.unread(ch)
      return table.concat(sb)
    end

    sb[#sb + 1] = ch
  end
end

-- TODO: Here

return M

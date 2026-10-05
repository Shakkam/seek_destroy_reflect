-- Minimal JSON decoder — LÖVE ships no JSON parser of its own, and this
-- port has exactly one consumer (campaign_map.lua reading an Atelier
-- Cartographe map export), so a small hand-rolled recursive-descent parser
-- beats vendoring a general-purpose library. Decode only — nothing here
-- ever needs to WRITE JSON. Not part of simulation/ (file I/O, purely an
-- orchestration-layer concern).

local json = {}

local function skip_whitespace(s, i)
	local _, stop = s:find("^[ \t\r\n]*", i)
	return stop + 1
end

local decode_value -- forward-declared: objects/arrays recurse into this

local function decode_string(s, i)
	-- i points at the opening quote.
	local out = {}
	i = i + 1
	while true do
		local c = s:sub(i, i)
		if c == "" then
			error("json: unterminated string")
		elseif c == '"' then
			return table.concat(out), i + 1
		elseif c == "\\" then
			local esc = s:sub(i + 1, i + 1)
			if esc == "n" then
				table.insert(out, "\n")
			elseif esc == "t" then
				table.insert(out, "\t")
			elseif esc == "r" then
				table.insert(out, "\r")
			elseif esc == "u" then
				local hex = s:sub(i + 2, i + 5)
				local code = tonumber(hex, 16) or 0
				-- Only the common BMP/ASCII range matters for map data
				-- (ids, type tags) — good enough without full UTF-16 pairing.
				table.insert(out, code < 128 and string.char(code) or "?")
				i = i + 4
			else
				table.insert(out, esc) -- \" \\ \/ and anything else pass through literally
			end
			i = i + 2
		else
			table.insert(out, c)
			i = i + 1
		end
	end
end

local function decode_number(s, i)
	local match, stop = s:match("^(-?%d+%.?%d*[eE]?[%+%-]?%d*)()", i)
	if not match then
		error("json: invalid number at position " .. i)
	end
	return tonumber(match), stop
end

local function decode_array(s, i)
	local arr = {}
	i = skip_whitespace(s, i + 1)
	if s:sub(i, i) == "]" then
		return arr, i + 1
	end
	while true do
		local value
		value, i = decode_value(s, i)
		table.insert(arr, value)
		i = skip_whitespace(s, i)
		local c = s:sub(i, i)
		if c == "," then
			i = skip_whitespace(s, i + 1)
		elseif c == "]" then
			return arr, i + 1
		else
			error("json: expected ',' or ']' at position " .. i)
		end
	end
end

local function decode_object(s, i)
	local obj = {}
	i = skip_whitespace(s, i + 1)
	if s:sub(i, i) == "}" then
		return obj, i + 1
	end
	while true do
		if s:sub(i, i) ~= '"' then
			error("json: expected string key at position " .. i)
		end
		local key
		key, i = decode_string(s, i)
		i = skip_whitespace(s, i)
		if s:sub(i, i) ~= ":" then
			error("json: expected ':' at position " .. i)
		end
		i = skip_whitespace(s, i + 1)
		local value
		value, i = decode_value(s, i)
		obj[key] = value
		i = skip_whitespace(s, i)
		local c = s:sub(i, i)
		if c == "," then
			i = skip_whitespace(s, i + 1)
		elseif c == "}" then
			return obj, i + 1
		else
			error("json: expected ',' or '}' at position " .. i)
		end
	end
end

decode_value = function(s, i)
	i = skip_whitespace(s, i)
	local c = s:sub(i, i)
	if c == "{" then
		return decode_object(s, i)
	elseif c == "[" then
		return decode_array(s, i)
	elseif c == '"' then
		return decode_string(s, i)
	elseif c == "t" and s:sub(i, i + 3) == "true" then
		return true, i + 4
	elseif c == "f" and s:sub(i, i + 4) == "false" then
		return false, i + 5
	elseif c == "n" and s:sub(i, i + 3) == "null" then
		return nil, i + 4
	elseif c:match("[%-%d]") then
		return decode_number(s, i)
	end
	error("json: unexpected character '" .. c .. "' at position " .. i)
end

-- Returns the decoded value (a table for objects/arrays, or a plain
-- string/number/boolean/nil), or nil + an error message on malformed JSON
-- — never throws, so callers can fall back gracefully (matching Godot's
-- own JSON.parse_string() returning null on failure).
function json.decode(s)
	local ok, result = pcall(function()
		local value, i = decode_value(s, 1)
		return value
	end)
	if not ok then
		return nil, result
	end
	return result
end

return json

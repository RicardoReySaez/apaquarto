-- Formats level 4 and 5 headers for APA format.
local supplementary_section_prefix = false
local supplementary_section_count = 0
local appendixword = "Appendix"

-- Does the string end with a specific character?
---http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
  return string.sub(str.text, -1) == ending
end

local function trim(s)
  if not s then
    return ""
  end
  return string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
end

local function first_value(tbl, keys)
  if not tbl then
    return nil
  end
  for _, key in ipairs(keys) do
    if tbl[key] ~= nil then
      return tbl[key]
    end
  end
  return nil
end

local function is_truthy(value)
  if not value then
    return false
  end
  if type(value) == "boolean" then
    return value
  end
  local text = string.lower(trim(pandoc.utils.stringify(value)))
  return not (text == "" or text == "false" or text == "0" or text == "no")
end

local function is_falsey(value)
  if value == nil then
    return false
  end
  if type(value) == "boolean" then
    return not value
  end
  local text = string.lower(trim(pandoc.utils.stringify(value)))
  return text == "" or text == "false" or text == "0" or text == "no"
end

local function is_supplementary_material(meta)
  return is_truthy(first_value(meta, {
    "supplementary-material",
    "supplementary_material",
    "Supplementary_material",
    "Supplementary-Material"
  }))
end

local function has_class(header, class)
  for _, value in ipairs(header.classes) do
    if value == class then
      return true
    end
  end
  return false
end

local function get_supplementary_header_options(meta)
  supplementary_section_prefix = is_supplementary_material(meta) and not is_falsey(first_value(meta, {
    "supplementary-section-prefix",
    "supplementary_section_prefix",
    "supplementary-header-prefix",
    "supplementary_header_prefix"
  }))
  if meta.language and meta.language["crossref-apx-prefix"] then
    appendixword = pandoc.utils.stringify(meta.language["crossref-apx-prefix"])
  end
end

local function add_supplementary_section_prefix(hx)
  if not supplementary_section_prefix or hx.level ~= 1 then
    return false
  end
  if has_class(hx, "unnumbered") or has_class(hx, "unlisted") then
    return false
  end
  if hx.identifier == "refs" or hx.identifier == "references" then
    return false
  end
  if hx.identifier and hx.identifier:find("^apx%-") then
    return false
  end
  local headerfirstword = pandoc.utils.stringify(hx.content[1])
  if headerfirstword == appendixword or headerfirstword == "Appendix" then
    return false
  end
  supplementary_section_count = supplementary_section_count + 1
  local original = hx.content:clone()
  hx.content = pandoc.Inlines({
    pandoc.Str("SM" .. supplementary_section_count .. ":"),
    pandoc.Space()
  })
  hx.content:extend(original)
  return true
end

local function Header(hx)
  local changed = add_supplementary_section_prefix(hx)
  if hx.level > 3 then
    -- Add a period unless a punctuation mark is already present
    if not (ends_with(hx.content[#hx.content], ".") or ends_with(hx.content[#hx.content], "?") or ends_with(hx.content[#hx.content], "?")) then
      hx.content[#hx.content + 1] = pandoc.Str(".")
      changed = true
    end
    if FORMAT == "docx" then
      -- Adds a "Style Separator" character that allows the headier to appear as if it were on the same line as the subsequent paragraph.
      local htext = pandoc.utils.stringify(hx.content)
      local prefix = "<w:p><w:pPr><w:pStyle w:val=\"Heading" ..
      hx.level .. "\"/><w:rPr><w:vanish/><w:specVanish/></w:rPr></w:pPr><w:r><w:t>"
      local suffix = "</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:p>"
      return pandoc.RawBlock('openxml', prefix .. htext .. suffix)
    end
    return hx
  end
  if changed then
    return hx
  end
end

return {
  { Meta = get_supplementary_header_options },
  { Header = Header }
}

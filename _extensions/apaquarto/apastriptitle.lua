--- Does the string end with a specific character?
--- http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
  return string.sub(str.text, -1) == ending
end

--- Trim string
local function trim(s)
  if not s then
    return ""
  end
  local l = 1
  while string.sub(s, l, l) == ' ' do
    l = l + 1
  end
  local r = string.len(s)
  while string.sub(s, r, r) == ' ' do
    r = r - 1
  end
  return string.sub(s, l, r)
end

local function has_content(value)
  if not value then
    return false
  end
  if type(value) == "boolean" then
    return value
  end
  local value_type = pandoc.utils.type(value)
  if value_type == "boolean" then
    return value
  end
  local text = string.lower(trim(pandoc.utils.stringify(value)))
  return text ~= "" and text ~= "false"
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

local function first_present(tbl, keys)
  if not tbl then
    return nil
  end
  for _, key in ipairs(keys) do
    if has_content(tbl[key]) then
      return tbl[key]
    end
  end
  return nil
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

local function enabled_unless_false(meta, keys)
  return not is_falsey(first_value(meta, keys))
end

local function as_inlines(value)
  if not has_content(value) then
    return nil
  end

  local value_type = pandoc.utils.type(value)
  if value_type == "Inlines" then
    return value:clone()
  end

  if value_type == "Blocks" then
    local result = pandoc.Inlines({})
    for _, block in ipairs(value) do
      if #result > 0 then
        result:extend({ pandoc.Space() })
      end
      if block.t == "Para" or block.t == "Plain" then
        result:extend(block.content)
      else
        result:extend({ pandoc.Str(pandoc.utils.stringify(block)) })
      end
    end
    return result
  end

  return pandoc.Inlines({ pandoc.Str(pandoc.utils.stringify(value)) })
end

local function append_inlines(target, value)
  local inlines = as_inlines(value)
  if inlines and #inlines > 0 then
    if #target > 0 then
      target:extend({ pandoc.Space() })
    end
    target:extend(inlines)
  end
end

local function make_shorttitle(text)
  return pandoc.Inlines({ pandoc.Str(text) })
end

local function is_supplementary_material(meta)
  return is_truthy(
    first_present(meta, {
      "supplementary-material",
      "supplementary_material",
      "Supplementary_material",
      "Supplementary-Material"
    })
  )
end

local function normalize_doi_url(value)
  local doi = trim(pandoc.utils.stringify(value))
  doi = doi:gsub("^doi:%s*", "")
  if doi == "" then
    return nil
  end
  if doi:match("^https?://") then
    return doi
  end
  if doi:match("^doi%.org/") then
    return "https://" .. doi
  end
  return "https://doi.org/" .. doi
end

local function find_apa_year(statement)
  return first_present(statement, { "apa-year", "apa_year", "year", "publication-year", "publication_year" })
end

local function make_doi_link(doi)
  local doi_url = normalize_doi_url(doi)
  if doi_url then
    return pandoc.Inlines({ pandoc.Link(pandoc.Inlines({ pandoc.Str(doi_url) }), doi_url) })
  end
  return nil
end

local function make_apa_notice(apa_year, doi)
  local copyright_symbol = "\194\169"
  local notice = pandoc.Inlines({
    pandoc.Str(copyright_symbol .. "American Psychological Association, " .. pandoc.utils.stringify(apa_year) .. ". This paper is not the copy of record and may not exactly replicate the authoritative document published in the APA journal. The final article is available, upon publication, at:")
  })

  if doi then
    local doi_link = make_doi_link(doi)
    if doi_link then
      notice:extend({
        pandoc.Space()
      })
      notice:extend(doi_link)
    end
  end

  return notice
end

local function make_accepted_sentence(journal)
  local journal_inlines = as_inlines(journal)
  if not journal_inlines then
    return nil
  end

  local sentence = pandoc.Inlines({})
  sentence:extend({
    pandoc.Strong(pandoc.Inlines({
      pandoc.Str("This paper has been peer reviewed and accepted for publication in "),
      pandoc.Emph(journal_inlines),
      pandoc.Str(".")
    }))
  })
  return sentence
end

local function set_apa_publication_template(meta, statement, journal, doi, custom_statement, notice)
  local apa_year = find_apa_year(statement)
  local doi_url = normalize_doi_url(doi)
  local custom_text = as_inlines(custom_statement)
  local custom_notice = as_inlines(notice)

  meta.publicationstatementapa = true
  meta.publicationstatementjournal = as_inlines(journal)
  if apa_year then
    meta.publicationstatementyear = pandoc.utils.stringify(apa_year)
  end
  if doi_url then
    meta.publicationstatementdoiurl = doi_url
  end
  if custom_text then
    meta.publicationstatementcustom = custom_text
  end
  if custom_notice then
    meta.publicationstatementnotice = custom_notice
  elseif apa_year then
    meta.publicationstatementapanotice = true
  end
  if doi_url and (custom_notice or not apa_year) then
    meta.publicationstatementdoilink = true
  end
end

local function make_publication_statement(meta)
  local statement = first_present(meta, { "publication-statement", "publication_statement" })
  if not statement then
    return nil
  end

  if type(statement) == "boolean" then
    return nil
  end

  local statement_type = pandoc.utils.type(statement)
  if statement_type ~= "table" and statement_type ~= "Map" and statement_type ~= "MetaMap" then
    return as_inlines(statement)
  end

  local result = pandoc.Inlines({})
  local custom_statement = first_present(statement, { "statement", "text" })
  local acceptance_statement = first_present(statement, { "accepted-statement", "acceptance-statement", "note" })
  local journal = first_present(statement, { "journal" })
  local notice = first_present(statement, { "notice", "publisher-statement", "publisher_statement" })
  local doi = first_present(statement, { "doi", "url" })
  local apa_year = find_apa_year(statement)

  if FORMAT:match 'latex' and journal and not acceptance_statement then
    set_apa_publication_template(meta, statement, journal, doi, custom_statement, notice)
  end

  if acceptance_statement then
    append_inlines(result, acceptance_statement)
  elseif journal then
    append_inlines(result, make_accepted_sentence(journal))
  end

  if custom_statement then
    append_inlines(result, custom_statement)
  end

  if notice then
    append_inlines(result, notice)
  elseif apa_year then
    append_inlines(result, make_apa_notice(apa_year, doi))
  end

  if doi and (notice or not apa_year) then
    append_inlines(result, make_doi_link(doi))
  end

  if #result > 0 then
    return result
  end
  return nil
end

local function find_ai_statement(meta)
  local authornote = first_present(meta, { "author-note", "author_note" })
  local nested_statement = nil

  if authornote then
    local disclosures = first_present(authornote, { "disclosures" })
    nested_statement = first_present(disclosures, { "ai-statement", "ai_statement" })
      or first_present(authornote, { "ai-statement", "ai_statement" })
  end

  return as_inlines(nested_statement or first_present(meta, { "ai-statement", "ai_statement" }))
end

local function apply_supplementary_title(meta)
  if not is_supplementary_material(meta) then
    return meta
  end

  meta["suppress-title-introduction"] = true
  if enabled_unless_false(meta, { "supplementary-float-prefix", "supplementary_float_prefix" }) then
    meta.supplementaryfloatprefix = true
  end
  if enabled_unless_false(meta, {
    "supplementary-section-prefix",
    "supplementary_section_prefix",
    "supplementary-header-prefix",
    "supplementary_header_prefix"
  }) then
    meta.supplementarysectionprefix = true
  end

  if not meta.apatitledisplay then
    return meta
  end

  local title = meta.apatitledisplay:clone()
  local supplementary_title = pandoc.Inlines({})

  if FORMAT:match 'latex' then
    supplementary_title:extend({
      pandoc.RawInline("latex", "{\\LARGE \\textbf{\\textit{\\underline{Supplementary Material}}}} \\\\[3em] ")
    })
    supplementary_title:extend(title)
  else
    supplementary_title:extend({
      pandoc.Strong(pandoc.Inlines({ pandoc.Emph(pandoc.Inlines({ pandoc.Str("Supplementary Material") })) })),
      pandoc.LineBreak(),
      pandoc.LineBreak()
    })
    supplementary_title:extend(title)
  end

  meta.apatitledisplay = supplementary_title
  meta.shorttitle = make_shorttitle("Supplementary Material")
  return meta
end

--- Put a space before the string
local function prependspace(s)
  if s then
    return " " .. pandoc.utils.stringify(s)
  else
    return ""
  end
end

-- Are the affiliations different or same across authors?
local are_affiliations_different = function(authors)
  -- Superscript id
  local superii = ""

  -- List of superii
  local hash = {}
  -- index of superii
  local res = {}

  --Check if affilations are the same for each author
  for i, a in ipairs(authors) do
    superii = ""
    if a.affiliations then
      for j, aff in ipairs(a.affiliations) do
        if j > 1 then
          superii = superii .. ","
        end
        superii = superii .. aff.number
      end
    end

    if (not hash[superii]) then
      res[#res + 1] = superii
      hash[superii] = true
    end
  end

  return #res > 1
end

local function makeauthorname(a)
  local authorname = a.literal
  -- Make author name
  if pandoc.utils.type(a.literal) == "List" then
    if a.literal[1].literal then
      authorname = a[1].literal
    else
      authorname = ""
      authorname = authorname .. prependspace(a.literal[1].given)
      authorname = authorname .. prependspace(a.literal[1]["dropping-particle"])
      authorname = authorname .. prependspace(a.literal[1]["non-dropping-particle"])
      authorname = authorname .. prependspace(a.literal[1].family)
      authorname = pandoc.Inlines(trim(authorname))
    end
  end
  return authorname
end

Meta = function(meta)
  meta.apatitle = nil
  meta.apatitledisplay = nil
  if meta.title then
    meta.apatitle = meta.title:clone()
    meta.apatitledisplay = meta.title:clone()
  end

  if meta["by-author"] then
    meta.affiliationsdifferent = are_affiliations_different(meta["by-author"])

    for i, j in ipairs(meta["by-author"]) do
      j.apaauthordisplay = makeauthorname(j.name)
    end
  end

  if meta.subtitle then
    if not ends_with(meta.apatitledisplay[#meta.apatitledisplay], ":") then
      meta.apatitledisplay:insert(pandoc.Str(":"))
    end
    meta.apatitledisplay:insert(pandoc.Space())
    meta.apatitledisplay:extend(meta.subtitle)
  end

  meta["apa-ai-statement"] = find_ai_statement(meta)
  meta.publicationstatement = make_publication_statement(meta)
  meta = apply_supplementary_title(meta)

  meta.apasubtitle = meta.subtitle
  meta.apaauthor = meta.author
  meta.apadate = meta.date
  meta.apaabstract = meta.abstract
  if meta.documentmode then
  else
    meta.documentmode = "man"
  end
  --Prevents pandoc from fomatting .docx document the way it thinks it should.
  if FORMAT == "docx" then
    meta.title = nil
    meta.subtitle = nil
    meta.author = nil
    meta.date = nil
    meta.abstract = nil
  end
  return meta
end

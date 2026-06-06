--- apareview.lua
--- Adds a "Response to Reviewers" document type to apaquarto.
--- Activated with `document: review` (or `documentmode: review`) in the YAML.
---
--- It mirrors the supplementary-material title behaviour (big heading on the
--- first page, keeping only title/authors/affiliations), switches the body to a
--- standard single-spaced layout instead of APA double-spacing, and provides
--- coloured environments to tell reviewer/editor comments apart from the
--- author's responses.
---
--- Comment/response blocks are written as fenced divs:
---   ::: {.reviewer}  ...reviewer or editor verbatim text... :::
---   ::: {.response}  ...our answer... :::
--- Accepted aliases: .reviewer / .editor / .comment  -> comment box
---                    .response / .answer            -> response box
--- An optional title can be given with `title="..."`.

local stringify = pandoc.utils.stringify

local function trim(s)
  return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

local function is_truthy(value)
  if value == nil then return false end
  if type(value) == "boolean" then return value end
  local text = string.lower(trim(stringify(value)))
  return not (text == "" or text == "false" or text == "0" or text == "no")
end

local function first_present(meta, keys)
  for _, key in ipairs(keys) do
    if meta[key] ~= nil then
      return meta[key]
    end
  end
  return nil
end

--- Is this a review-response document?
local function is_review(meta)
  local doc = first_present(meta, { "document", "Document" })
  if doc ~= nil and string.lower(trim(stringify(doc))) == "review" then
    return true
  end
  local mode = first_present(meta, { "documentmode" })
  if mode ~= nil and string.lower(trim(stringify(mode))) == "review" then
    return true
  end
  return is_truthy(first_present(meta, { "review", "review-response", "review_response" }))
end

--- Label shown at the start of a response box (localizable, "" suppresses it).
local function response_label(meta)
  local label = first_present(meta, { "review-response-label", "review_response_label" })
  if label == nil and meta.language then
    label = first_present(meta.language, { "review-response-label", "title-review-response" })
  end
  if label == nil then
    return "Response"
  end
  return trim(stringify(label))
end

--- Label shown at the start of a manuscript-change box ("" suppresses it).
local function modification_label(meta)
  local label = first_present(meta, { "review-modification-label", "review_modification_label" })
  if label == nil and meta.language then
    label = first_present(meta.language, { "review-modification-label", "title-review-modification" })
  end
  if label == nil then
    return "Manuscript change"
  end
  return trim(stringify(label))
end

--- Prefix for auto-numbered reviewer/editor comment boxes ("" disables it).
local function comment_label(meta)
  local label = first_present(meta, { "review-comment-label", "review_comment_label" })
  if label == nil and meta.language then
    label = first_present(meta.language, { "review-comment-label", "title-review-comment" })
  end
  if label == nil then
    return "Comment"
  end
  return trim(stringify(label))
end

--- Big heading printed above the title on page 1.
local function review_title_text(meta)
  local t = first_present(meta, { "review-title", "review_title" })
  if t == nil and meta.language then
    t = first_present(meta.language, { "review-title", "title-review" })
  end
  if t == nil then
    return "Response to Reviewers"
  end
  return trim(stringify(t))
end

-- ---------------------------------------------------------------------------
-- LaTeX preamble: colour definitions and tcolorbox environments.
-- ---------------------------------------------------------------------------
local function latex_preamble()
  return [[
% ---- apaquarto review-response styles ----
\usepackage{tcolorbox}
\tcbuselibrary{skins,breakable}
\usepackage{setspace}
\AtBeginDocument{\singlespacing}
% Reviewer/editor comments: understated blue. Author responses: green.
% Manuscript changes / new text: muted orange.
\definecolor{reviewbg}{HTML}{EAF1F8}
\definecolor{reviewrule}{HTML}{34618E}
\definecolor{responsebg}{HTML}{EAF3EC}
\definecolor{responserule}{HTML}{3E7D54}
\definecolor{modificationbg}{HTML}{FBF1E6}
\definecolor{modificationrule}{HTML}{B5732E}
\newtcolorbox{reviewcommentbox}[1][]{%
  breakable, enhanced, sharp corners,
  colback=reviewbg, colframe=reviewrule,
  boxrule=0pt, leftrule=3pt,
  left=8pt, right=8pt, top=6pt, bottom=6pt,
  before skip=8pt, after skip=8pt, #1}
\newtcolorbox{reviewresponsebox}[1][]{%
  breakable, enhanced, sharp corners,
  colback=responsebg, colframe=responserule,
  boxrule=0pt, leftrule=3pt,
  left=8pt, right=8pt, top=6pt, bottom=6pt,
  before skip=8pt, after skip=8pt, #1}
\newtcolorbox{reviewmodificationbox}[1][]{%
  breakable, enhanced, sharp corners,
  colback=modificationbg, colframe=modificationrule,
  boxrule=0pt, leftrule=3pt,
  left=8pt, right=8pt, top=6pt, bottom=6pt,
  before skip=8pt, after skip=8pt, #1}
% ---- end review-response styles ----
]]
end

local function html_preamble()
  return [[
<style>
/* Response-to-reviewers: standard single spacing */
body, p {line-height: 1.4em;}
</style>
]]
end

local function append_header_includes(meta, fmt, raw)
  local item = pandoc.MetaBlocks({ pandoc.RawBlock(fmt, raw) })
  local existing = meta["header-includes"]
  if existing == nil then
    meta["header-includes"] = pandoc.MetaList({ item })
  elseif existing.t == "MetaList" then
    existing[#existing + 1] = item
    meta["header-includes"] = existing
  else
    meta["header-includes"] = pandoc.MetaList({ existing, item })
  end
  return meta
end

-- ---------------------------------------------------------------------------
-- Meta: switch on review mode.
-- ---------------------------------------------------------------------------
local review_mode = false
local meta_response_label = "Response"
local meta_modification_label = "Manuscript change"
local meta_comment_label = "Comment"
local comment_counter = 0

function Meta(meta)
  if not is_review(meta) then
    return meta
  end
  review_mode = true
  meta_response_label = response_label(meta)
  meta_modification_label = modification_label(meta)
  meta_comment_label = comment_label(meta)

  -- A response letter is not an article: keep only title/authors/affiliations on
  -- page 1. These are forced because apaquarto's defaults set them to `false`,
  -- so a simple nil-check would never fire.
  meta["suppress-abstract"] = true
  meta["suppress-keywords"] = true
  meta["suppress-author-note"] = true
  meta["suppress-impact-statement"] = true
  -- Do not repeat the title as a first section heading in the body.
  meta["suppress-title-introduction"] = true

  -- Big "Response to Reviewers" heading above the title (page 1).
  if meta.apatitledisplay then
    local title = meta.apatitledisplay:clone()
    local heading = review_title_text(meta)
    local display = pandoc.Inlines({})
    if FORMAT:match("latex") then
      display:extend({
        pandoc.RawInline("latex",
          "{\\LARGE \\textbf{" .. heading .. "}} \\\\[2em] ")
      })
      display:extend(title)
    else
      display:extend({
        pandoc.Strong(pandoc.Inlines({ pandoc.Str(heading) })),
        pandoc.LineBreak(),
        pandoc.LineBreak()
      })
      display:extend(title)
    end
    meta.apatitledisplay = display
  end
  if not meta.shorttitle then
    meta.shorttitle = pandoc.Inlines({ pandoc.Str(review_title_text(meta)) })
  end

  if FORMAT:match("latex") then
    meta = append_header_includes(meta, "latex", latex_preamble())
  elseif FORMAT:match("html") then
    meta = append_header_includes(meta, "html", html_preamble())
  end

  return meta
end

-- ---------------------------------------------------------------------------
-- Divs: render comment / response blocks.
-- ---------------------------------------------------------------------------
local function has_class(div, names)
  for _, name in ipairs(names) do
    if div.classes:includes(name) then
      return true
    end
  end
  return false
end

local comment_classes = { "reviewer", "editor", "comment", "reviewer-comment" }
local response_classes = { "response", "answer", "author-response" }
local modification_classes = { "modification", "modifications", "change", "changes", "excerpt", "newtext", "manuscript-change" }

--- Optional explicit title from the div's `title` attribute.
local function div_title(div)
  local t = div.attributes["title"] or div.attributes["label"]
  if t and trim(t) ~= "" then
    return trim(t)
  end
  return nil
end

--- Prepend a bold lead-in label to the first paragraph of a block list.
local function prepend_label(blocks, label_text)
  if label_text == nil or label_text == "" then
    return blocks
  end
  local lead = pandoc.Strong(pandoc.Inlines({ pandoc.Str(label_text .. ":") }))
  local first = blocks[1]
  if first and (first.t == "Para" or first.t == "Plain") then
    local inlines = pandoc.Inlines({ lead, pandoc.Space() })
    inlines:extend(first.content)
    blocks[1] = pandoc.Para(inlines)
  else
    table.insert(blocks, 1, pandoc.Para(pandoc.Inlines({ lead })))
  end
  return blocks
end

function Div(div)
  if not review_mode then
    return nil
  end

  local is_comment = has_class(div, comment_classes)
  local is_response = has_class(div, response_classes)
  local is_modification = has_class(div, modification_classes)
  if not is_comment and not is_response and not is_modification then
    return nil
  end

  local explicit_title = div_title(div)
  local content = div.content

  if explicit_title == nil then
    if is_comment and meta_comment_label ~= "" then
      comment_counter = comment_counter + 1
      explicit_title = meta_comment_label .. " " .. tostring(comment_counter)
    elseif is_response then
      explicit_title = meta_response_label
    elseif is_modification then
      explicit_title = meta_modification_label
    end
  end

  -- HTML: keep the div + classes, let CSS style it. Normalize the class so the
  -- stylesheet only needs a few selectors, and inject the label as a heading.
  if FORMAT:match("html") then
    local variant = "review-comment"
    if is_response then
      variant = "review-response"
    elseif is_modification then
      variant = "review-modification"
    end
    local classes = { "review-block", variant }
    local blocks = pandoc.List(content:clone())
    if explicit_title then
      local lbl = pandoc.Div(
        pandoc.Plain(pandoc.Inlines({ pandoc.Str(explicit_title) })),
        pandoc.Attr("", { "review-label" })
      )
      blocks:insert(1, lbl)
    end
    return pandoc.Div(blocks, pandoc.Attr("", classes))
  end

  -- LaTeX: wrap in the matching tcolorbox.
  if FORMAT:match("latex") then
    local env = "reviewcommentbox"
    if is_response then
      env = "reviewresponsebox"
    elseif is_modification then
      env = "reviewmodificationbox"
    end
    local open = "\\begin{" .. env .. "}"
    local result = pandoc.List({ pandoc.RawBlock("latex", open) })
    if explicit_title then
      result:insert(pandoc.Para(pandoc.Inlines({
        pandoc.Strong(pandoc.Inlines({ pandoc.Str(explicit_title .. ":") }))
      })))
    end
    result:extend(content)
    result:insert(pandoc.RawBlock("latex", "\\end{" .. env .. "}"))
    return result
  end

  -- docx: coloured box via a custom paragraph style added to the reference doc.
  if FORMAT:match("docx") then
    local blocks = pandoc.List(content:clone())
    if explicit_title then
      blocks = prepend_label(blocks, explicit_title)
    end
    local style = "ReviewerComment"
    if is_response then
      style = "AuthorResponse"
    elseif is_modification then
      style = "ManuscriptChange"
    end
    return pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = style }))
  end

  -- typst / other (no easy colour): distinguish by layout instead. Reviewer or
  -- editor comments become an indented block quote; responses and manuscript
  -- changes are normal text with a bold lead-in label.
  local blocks = pandoc.List(content:clone())
  if is_response or is_modification then
    return prepend_label(blocks, explicit_title)
  end
  if explicit_title then
    blocks = prepend_label(blocks, explicit_title)
  end
  return pandoc.BlockQuote(blocks)
end

-- ---------------------------------------------------------------------------
-- Headers: larger level-1 section headings, each starting a new page.
-- ---------------------------------------------------------------------------
local first_section_seen = false

local function docx_page_break()
  return pandoc.RawBlock("openxml",
    "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
end

function Header(h)
  if not review_mode then
    return nil
  end

  -- Level-2 (and deeper) headers: user-defined sub-categories such as
  -- "Major comments" / "Minor comments". Give them a little extra breathing
  -- room above so they separate clearly from the preceding response block.
  if h.level >= 2 then
    -- A sub-category starts a fresh count, so when sub-sections exist the
    -- numbering restarts within each one ("Major comments" -> Comment 1,
    -- "Minor comments" -> Comment 1). When a section has no sub-headings,
    -- the level-1 reset below is the only one that fires.
    comment_counter = 0
    if FORMAT:match("latex") then
      return pandoc.List({ pandoc.RawBlock("latex", "\\vspace{0.8em}"), h })
    end
    if FORMAT:match("html") then
      local style = "margin-top: 1em;"
      local existing = h.attributes["style"]
      if existing and existing ~= "" then
        style = existing .. " " .. style
      end
      h.attributes["style"] = style
      return h
    end
    if FORMAT:match("docx") then
      return pandoc.Div(
        pandoc.Para(h.content),
        pandoc.Attr(h.identifier, {}, { ["custom-style"] = "ReviewSubHeading" })
      )
    end
    return nil
  end

  if h.level ~= 1 then
    return nil
  end

  -- New editor/reviewer section: restart comment numbering at 1.
  comment_counter = 0

  local add_break = first_section_seen
  first_section_seen = true

  if FORMAT:match("latex") then
    -- apa7 is incompatible with titlesec, so render the enlarged centred
    -- heading by hand instead of relying on \section.
    local inlines = pandoc.Inlines({ pandoc.RawInline("latex", "{\\centering\\Large\\bfseries\\underline{") })
    inlines:extend(h.content)
    inlines:insert(pandoc.RawInline("latex", "}\\par}"))
    local heading = pandoc.Para(inlines)
    if not add_break then
      return pandoc.List({ heading, pandoc.RawBlock("latex", "\\vspace{0.5em}") })
    end
    return pandoc.List({
      pandoc.RawBlock("latex", "\\newpage"),
      heading,
      pandoc.RawBlock("latex", "\\vspace{0.5em}")
    })
  end

  if FORMAT:match("html") then
    local style = "font-size: 1.5em; text-decoration: underline;"
    local existing = h.attributes["style"]
    if existing and existing ~= "" then
      style = existing .. " " .. style
    end
    h.attributes["style"] = style
    if not add_break then
      return h
    end
    return pandoc.List({
      pandoc.RawBlock("html",
        "<div style=\"page-break-before: always; break-before: page;\"></div>"),
      h
    })
  end

  if FORMAT:match("docx") then
    local heading = pandoc.Div(
      pandoc.Para(h.content),
      pandoc.Attr(h.identifier, {}, { ["custom-style"] = "ReviewSectionHeading" })
    )
    if not add_break then
      return heading
    end
    return pandoc.List({ docx_page_break(), heading })
  end

  return nil
end

return {
  { Meta = Meta },
  { Div = Div, Header = Header }
}

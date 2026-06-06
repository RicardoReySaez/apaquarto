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

--- Which kind of review block is this div, if any?
local function classify(div)
  if has_class(div, comment_classes) then return "comment" end
  if has_class(div, response_classes) then return "response" end
  if has_class(div, modification_classes) then return "modification" end
  return nil
end

--- Build a segment descriptor from a review div. Auto-numbers comment boxes.
local function make_segment(div, kind)
  local title = div_title(div)
  if title == nil then
    if kind == "comment" then
      if meta_comment_label ~= "" then
        comment_counter = comment_counter + 1
        title = meta_comment_label .. " " .. tostring(comment_counter)
      end
    elseif kind == "response" then
      title = meta_response_label
    elseif kind == "modification" then
      title = meta_modification_label
    end
  end

  local env, variant, style
  if kind == "comment" then
    env, variant, style = "reviewcommentbox", "review-comment", "ReviewerComment"
  elseif kind == "response" then
    env, variant, style = "reviewresponsebox", "review-response", "AuthorResponse"
  else
    env, variant, style = "reviewmodificationbox", "review-modification", "ManuscriptChange"
  end

  return {
    kind = kind,
    title = title,
    content = pandoc.List(div.content:clone()),
    env = env,
    variant = variant,
    style = style,
  }
end

--- Render a whole exchange (one comment + its response/modification, etc.) as a
--- single visual block: coloured stripes glued together, one per segment.
local function render_group(segments)
  local n = #segments

  -- LaTeX: stack tcolorboxes; only the first/last segment keep outer spacing so
  -- one exchange is separated from the next, while the stripes inside an
  -- exchange read as a continuous box.
  if FORMAT:match("latex") then
    local out = pandoc.List({})
    -- Outer spacing (before the first / after the last segment) separates one
    -- exchange from the next; inner segments carry no extra outer skip.
    local function seg_opts(i)
      local before = (i == 1) and "16pt" or "0pt"
      local after = (i == n) and "16pt" or "0pt"
      return "before skip=" .. before .. ", after skip=" .. after
    end
    for i, seg in ipairs(segments) do
      out:insert(pandoc.RawBlock("latex", "\\begin{" .. seg.env .. "}[" .. seg_opts(i) .. "]"))
      if seg.title then
        out:insert(pandoc.Para(pandoc.Inlines({
          pandoc.Strong(pandoc.Inlines({ pandoc.Str(seg.title .. ":") }))
        })))
      end
      out:extend(seg.content)
      out:insert(pandoc.RawBlock("latex", "\\end{" .. seg.env .. "}"))
    end
    return out
  end

  -- HTML: an outer container clips the stripes into one rounded box.
  if FORMAT:match("html") then
    local inner = pandoc.List({})
    for _, seg in ipairs(segments) do
      local blocks = pandoc.List(seg.content:clone())
      if seg.title then
        blocks:insert(1, pandoc.Div(
          pandoc.Plain(pandoc.Inlines({ pandoc.Str(seg.title) })),
          pandoc.Attr("", { "review-label" })
        ))
      end
      inner:insert(pandoc.Div(blocks, pandoc.Attr("", { "review-block", seg.variant })))
    end
    return pandoc.List({ pandoc.Div(inner, pandoc.Attr("", { "review-exchange" })) })
  end

  -- docx: stacked styled paragraphs with no inter-segment spacing (set in the
  -- styles), then a small spacer paragraph to separate this exchange from the
  -- next one.
  if FORMAT:match("docx") then
    local out = pandoc.List({})
    for _, seg in ipairs(segments) do
      local blocks = pandoc.List(seg.content:clone())
      if seg.title then
        blocks = prepend_label(blocks, seg.title)
      end
      out:insert(pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = seg.style })))
    end
    out:insert(pandoc.RawBlock("openxml",
      "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"280\" w:lineRule=\"exact\"/></w:pPr></w:p>"))
    return out
  end

  -- typst / other: no colour; distinguish by layout. Comments become an
  -- indented block quote, responses/changes a bold lead-in paragraph.
  local out = pandoc.List({})
  for _, seg in ipairs(segments) do
    local blocks = pandoc.List(seg.content:clone())
    if seg.kind == "comment" then
      if seg.title then
        blocks = prepend_label(blocks, seg.title)
      end
      out:insert(pandoc.BlockQuote(blocks))
    else
      out:extend(prepend_label(blocks, seg.title))
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Headers: larger level-1 section headings, each starting a new page.
-- ---------------------------------------------------------------------------
local first_section_seen = false

local function docx_page_break()
  return pandoc.RawBlock("openxml",
    "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
end

local function transform_header(h)
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
      return pandoc.List({ h })
    end
    if FORMAT:match("docx") then
      return pandoc.List({ pandoc.Div(
        pandoc.Para(h.content),
        pandoc.Attr(h.identifier, {}, { ["custom-style"] = "ReviewSubHeading" })
      ) })
    end
    return pandoc.List({ h })
  end

  if h.level ~= 1 then
    return pandoc.List({ h })
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
      return pandoc.List({ h })
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
      return pandoc.List({ heading })
    end
    return pandoc.List({ docx_page_break(), heading })
  end

  return pandoc.List({ h })
end

-- ---------------------------------------------------------------------------
-- Document pass: walk the body in order, grouping each comment with the
-- response/modification blocks that follow it (up to the next comment or
-- heading) into a single rendered exchange.
-- ---------------------------------------------------------------------------
function Pandoc(doc)
  if not review_mode then
    return doc
  end

  local out = pandoc.List({})
  local group = nil

  local function flush()
    if group and #group > 0 then
      out:extend(render_group(group))
    end
    group = nil
  end

  for _, blk in ipairs(doc.blocks) do
    local kind = (blk.t == "Div") and classify(blk) or nil
    if blk.t == "Header" then
      flush()
      out:extend(transform_header(blk))
    elseif kind ~= nil then
      local seg = make_segment(blk, kind)
      if kind == "comment" then
        -- A new comment opens a new exchange.
        flush()
        group = pandoc.List({ seg })
      else
        -- Response / modification attach to the open exchange.
        if not group then
          group = pandoc.List({})
        end
        group:insert(seg)
      end
    else
      flush()
      out:insert(blk)
    end
  end
  flush()

  doc.blocks = out
  return doc
end

return {
  { Meta = Meta },
  { Pandoc = Pandoc }
}

-- This filter creates prefixes for figures and tables in appendices.

-- List of appendix names
local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- Default prefix
local prefix = ""
-- Default pre-prefex if appendices exceed 26
local preprefix = ""
-- Prefix counter
local intprefix = 0
-- Pre-prefix counter
local intpreprefix = 0
-- Table counter
local tblnum = 0
-- Figure counter
local fignum = 0
-- Appendix counter
local appnum = 0
-- Table table
local tbl = {}
-- Figure table
local fig = {}
-- New style already used
local newsppendixstyle = true
-- Prefix all supplementary-material floats with S unless disabled
local supplementary_float_prefix = false

-- Word for appendix
local appendixword = "Appendix"
local referenceword = "References"

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

local function supplementary_option_enabled(meta, keys)
  return is_supplementary_material(meta) and not is_falsey(first_value(meta, keys))
end

local function current_float_prefix()
  if supplementary_float_prefix then
    return "S"
  end
  return prefix
end

getappendixword = function(meta)
  if meta.language and meta.language["crossref-apx-prefix"] then
    appendixword = pandoc.utils.stringify(meta.language["crossref-apx-prefix"])
  end
  -- Is there another word for reference section?
  if meta.language and meta.language["section-title-references"] then
    referenceword = pandoc.utils.stringify(meta.language["section-title-references"])
  end
  supplementary_float_prefix = supplementary_option_enabled(meta, {
    "supplementary-float-prefix",
    "supplementary_float_prefix"
  })
end


-- return table number associated with id
local tbllabel = function(id)
  if id ~= "" then
    -- Is id in tbl?
    if tbl[id] then
      -- Do nothing
    else
      -- Add id to tbl
      tblnum = tblnum + 1
      tbl[id] = tblnum
    end
    return tbl[id]
  end
end

-- return figure number associated with id
local figlabel = function(id, ss)
  if id ~= "" then
    -- Is id in fig?
    if fig[id] then
      -- Do nothing
    else
      if ss then
        -- Add id to fig
        fig[id] = fignum .. ss
      else
        -- increment fignum
        fignum = fignum + 1
        -- Add id to fig
        fig[id] = fignum
      end
    end
  end

  return fig[id]
end


local after_reference = false
local walkblock = function(b)
  
  if b.tag == "Div" and b.identifier and b.identifier:find("^apx%-") then
    after_reference = true
    return nil
  end
  
  
  -- Increment prefix for every level-1 header after References
  if b.tag == "Header" and b.level == 1 then
    local headerfirstword = pandoc.utils.stringify(b.content[1])
    if headerfirstword == referenceword or headerfirstword == "References" then
      after_reference = true
      return nil
    end
    if headerfirstword == appendixword or headerfirstword == "Appendix" or (b.identifier and b.identifier:find("^apx%-")) or after_reference then
      after_reference = true
      if not (b.identifier and b.identifier:find("^apx%-")) then
        b.identifier = "apx-" .. b.identifier
      end
      
      if (headerfirstword == appendixword or headerfirstword == "Appendix") and newsppendixstyle then
        print(
        "This style of creating appendices is deprecated:\n\n# Appendix A\n\n#Relationship Descriptive Scale\n\nInstead, use a single descriptive level-1 heading,\nfollowed by a an identifier with the apx prefix:\n\n# Relationship Description Scale {#apx-relationship}\n")
        newsppendixstyle = false
      end


      appnum = appnum + 1
      if intprefix == 26 then
        intprefix = 0
        intpreprefix = intpreprefix + 1
        preprefix = preprefix .. pandoc.text.sub(abc, intpreprefix, intpreprefix)
      end
      intprefix = intprefix + 1
      if not supplementary_float_prefix then
        tblnum = 0
        fignum = 0
      end
      prefix = preprefix .. pandoc.text.sub(abc, intprefix, intprefix)
      if b.attr then
        b.attr.attributes.appendixtitle = prefix
      end
    end
  end

  -- Assign prefixes and numbers
  if b.identifier then
    if b.identifier:find("^tbl%-") then
      b.attributes.prefix = current_float_prefix()
      b.attributes.tblnum = tbllabel(b.identifier)
    else
      if b.identifier:find("^fig%-") then
        b.attributes.prefix = current_float_prefix()
        b.attributes.fignum = figlabel(b.identifier)
        b.content:walk {
          Image = function(img)
            img.attributes.prefix = current_float_prefix()
            img.attributes.fignum = figlabel(b.identifier)
          end
        }



        local subfigcount = 0

        -- Find subfigures
        b.content:walk {
          Block = function(bb)
            if bb.identifier then
              if bb.identifier:find("^fig%-") then
                subfigcount = subfigcount + 1
                b.attributes.hassubfigs = "true"
                bb.attributes.prefix = current_float_prefix()
                bb.attributes.subfigscript = pandoc.text.sub(abc, subfigcount, subfigcount)
                bb.attributes.fignum = figlabel(bb.identifier, bb.attributes.subfigscript)
              end
            end
          end
        }
      else
        b:walk {
          Figure = function(fg)
            if fg.identifier then
              if fg.identifier:find("^fig%-") then
                fg.attributes.prefix = current_float_prefix()
                fg.attributes.fignum = figlabel(fg.identifier)
                fg.content:walk {
                  Image = function(img)
                    img.attributes.prefix = current_float_prefix()
                    img.attributes.fignum = figlabel(fg.identifier)
                  end
                }
              end
            end
          end
        }
      end
    end

    if b.identifier:find("^apx%-") then
      local a = pandoc.Header(1, appendixword .. " " .. prefix)
      return pandoc.List({ a, b })
    else
      return b
    end
  end
end



local filter = {
  traverse = 'topdown',
  Meta = getappendixword,
  Block = walkblock
}

return filter

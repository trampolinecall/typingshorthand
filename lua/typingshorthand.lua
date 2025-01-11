local config = nil

local shorthands = nil
local phrase_shorthands = nil
local allowed_chars = nil

local function setup(config_local)
    local function check_key_present(key)
        if config_local[key] == nil then
            error("typingshorthand setup config missing key '" .. key .. "'")
        end
    end

    check_key_present('shorthands_file')
    check_key_present('phraseable_words_file')

    config = config_local

    local long_to_short = {}

    shorthands = {}
    phrase_shorthands = {}
    allowed_chars = {}

    local update_allowed_chars = function(short)
            for i = 1,#short do
                allowed_chars[string.sub(short, i, i)] = true
            end
    end

    for _, line in ipairs(vim.fn.readfile(config.shorthands_file)) do
        if not vim.startswith(line, ";") and vim.fn.match(line, "^\\s*$") == -1 then
            local long, short = unpack(vim.split(line, " ", { plain = true }))
            assert(long ~= nil)
            assert(short ~= nil)

            update_allowed_chars(short)

            long_to_short[long] = short

            if shorthands[short] == nil then
                shorthands[short] = {}
            end
            table.insert(shorthands[short], long)
        end
    end

    for _, line in ipairs(vim.fn.readfile(config.phraseable_words_file)) do
        if not vim.startswith(line, ";") and vim.fn.match(line, "^\\s*$") == -1 then
            -- give the option of having custom short forms that can only be used in phrases
            local long, short_or_nil = unpack(vim.split(line, " ", { plain = true }))
            local short = short_or_nil or long_to_short[long]

            assert(long ~= nil)
            assert(short ~= nil)

            update_allowed_chars(short)

            if phrase_shorthands[short] == nil then
                phrase_shorthands[short] = {}
            end
            table.insert(phrase_shorthands[short], long)
        end
    end
end

local function syntax_off()
    if vim.w.typingshorthand_syntax_on == true then
        vim.cmd([[
            syn clear TypingShorthandConceal
            syn clear TypingShorthandSpecial
        ]])

        vim.w.typingshorthand_syntax_on = false
    end
end

local function syntax_on()
    if vim.w.typingshorthand_syntax_on == false or vim.w.typingshorthand_syntax_on == nil then
        -- TODO: fix this concealling and make it nicer
        vim.cmd([[
            syn region TypingShorthandSpecial start=/{{ typing shorthand:/ end=/ }}/ contains=TypingShorthandConceal
            syn match TypingShorthandConceal /{{ typing shorthand:/ contained conceal cchar=[
            syn match TypingShorthandConceal / }}/ contained conceal cchar=]

            hi link TypingShorthandSpecial Operator
            hi link TypingShorthandConceal Comment
        ]])

        vim.w.typingshorthand_syntax_on = true
    end
end

local function syntax_toggle()
    if vim.w.typingshorthand_syntax_on == true then
        syntax_off()
    elseif vim.w.typingshorthand_syntax_on == false or vim.w.typingshorthand_syntax_on == nil then
        syntax_on()
    end
end

local shorthand_special_regex = "{{ typing shorthand:(\\(.\\{-}\\)) \\(\\w\\{-}\\) \\(.\\{-}\\) }}"
local function create_shorthand_special(short, header, other)
    return "{{ typing shorthand:(" .. short .. ") " .. header .. " " .. other .. " }}"
end

local function review()
    vim.cmd("hi link ShorthandReview Search")
    local current_buf = vim.api.nvim_get_current_buf()
    while true do
        local current_match = vim.fn.matchbufline(current_buf, shorthand_special_regex, 1, "$", { submatches = true })[1]
        if current_match == nil then
            break
        end

        local original_short = current_match.submatches[1]
        local header = current_match.submatches[2]
        local other = current_match.submatches[3]

        local matchaddindex = vim.fn.matchadd("ShorthandReview", "\\%" .. current_match.lnum .. "l" .. "\\%" .. current_match.byteidx + 1 .. "c" .. ".\\{" .. string.len(current_match.text) .. "}")

        local function replace_special(replacement)
            vim.api.nvim_buf_set_text(current_buf, current_match.lnum - 1, current_match.byteidx, current_match.lnum - 1, current_match.byteidx + string.len(current_match.text), { replacement })
        end

        if header == "choice" then
            local choices = vim.fn.split(other, " | ")
            local choices_with_numbers = {}
            for ind, choice in ipairs(choices) do
                table.insert(choices_with_numbers, ind .. ". " .. choice)
            end

            vim.cmd("redraw!")
            vim.print("choose replacement (choose 0 for custom):")
            local chosen = vim.fn.inputlist(choices_with_numbers)
            if chosen ~= 0 then
                replace_special(choices[chosen])
            else
                -- TODO: unduplicate this code with below
                local replacement = vim.fn.input("replacement: ")
                replace_special(replacement)
                print("")
                -- TODO: add option to save it immediately to the shorthand file (although this would need tweaks to have the original short version)
            end

        elseif header == "unknown" then
            vim.cmd("redraw!")
            print("unknown shorthand: '" .. other .. "'")
            local replacement = vim.fn.input("replacement: ")
            replace_special(replacement)
            print("")
            -- TODO: add option to save it immediately into the shorthand file
        else
            error("invalid typing shorthand special header: " .. header)
        end

        vim.fn.matchdelete(matchaddindex)
    end
    vim.cmd("hi clear ShorthandReview")
end
local function convert(startline, endline)
    local allowed_chars_list = {}
    for char, _ in pairs(allowed_chars) do
        table.insert(allowed_chars_list, char)
    end
    local allowed_chars_str = table.concat(allowed_chars_list)

    vim.cmd("keeppatterns " .. startline .. "," .. endline .. "s/[" .. allowed_chars_str .. "]\\+/\\=v:lua.require'typingshorthand'.expand(submatch(0))/g")

    review()
end

local function expand(short)
    -- expand phrases
    local function helper(short)
        if short == "" then
            return {}
        else
            local possibilities = shorthands[short] or {}

            for i = 1, #short do
                local first = string.sub(short, 1, i)
                local more = string.sub(short, i + 1)

                local first_possibilities = phrase_shorthands[first] or {}
                local more_possibilities = helper(more)

                for _, first_long in ipairs(first_possibilities) do
                    for _, more_long in ipairs(more_possibilities) do
                        local current = first_long .. " " .. more_long
                        table.insert(possibilities, current)
                    end
                end
            end

            return possibilities
        end
    end

    local possibilities = helper(short)
    if #possibilities == 0 then
        return create_shorthand_special(short, "unknown", short)
    elseif #possibilities == 1 then
        return possibilities[1]
    else
        return create_shorthand_special(short, "choice", table.concat(possibilities, " | "))
    end
end

return {
    setup = setup,

    syntax_on = syntax_on,
    syntax_off = syntax_off,
    syntax_toggle = syntax_toggle,

    convert = convert,
    review = review,
    expand = expand,
}

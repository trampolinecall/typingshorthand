local config = nil

local shorthands = { short_to_long = {}, long_to_short = {} }
local phrase_shorthands = { short_to_long = {}, long_to_short = {} }
local allowed_chars = nil

local function add_shorthand(dictionary, long, short)
    if dictionary.short_to_long[short] == nil then
        dictionary.short_to_long[short] = {}
    end
    table.insert(dictionary.short_to_long[short], long)

    if dictionary.long_to_short[long] == nil then
        dictionary.long_to_short[long] = {}
    end
    table.insert(dictionary.long_to_short[long], short)
end

local function get_longs(dictionary, short)
    return dictionary.short_to_long[short] or {}
end
local function get_shorts(dictionary, long)
    return dictionary.long_to_short[long] or {}
end

local function reload_wordlists()
    shorthands = { short_to_long = {}, long_to_short = {} }
    phrase_shorthands = { short_to_long = {}, long_to_short = {} }
    allowed_chars = {}

    local update_allowed_chars = function(short)
        for i = 1,#short do
            allowed_chars[string.sub(short, i, i)] = true
        end
    end

    for _, line in ipairs(vim.fn.readfile(config.shorthands_file)) do
        if not vim.startswith(line, ";") and vim.fn.match(line, "^\\s*$") == -1 then
            local long, short = unpack(vim.split(line, " ", { plain = true }))
            assert(long ~= nil, "long is nil on line '" .. line .. "' of file '" .. config.shorthands_file .. "'")
            assert(short ~= nil, "short is nil on line '" .. line .. "' of file '" .. config.shorthands_file .. "'")

            update_allowed_chars(short)

            add_shorthand(shorthands, long, short)
        end
    end

    for _, line in ipairs(vim.fn.readfile(config.phraseable_words_file)) do
        if not vim.startswith(line, ";") and vim.fn.match(line, "^\\s*$") == -1 then
            -- give the option of having custom short forms that can only be used in phrases
            local long, short_or_nil = unpack(vim.split(line, " ", { plain = true }))
            local shorts
            if short_or_nil == nil then
                shorts = get_shorts(shorthands, long)
            else
                shorts = { short_or_nil }
            end

            assert(long ~= nil, "long is nil on line '" .. line .. "' of file '" .. config.phraseable_words_file .. "'")

            for _, short in ipairs(shorts) do
                update_allowed_chars(short)

                add_shorthand(phrase_shorthands, long, short)
            end
        end
    end
end

local function setup(config_local)
    local function check_key_present(key)
        if config_local[key] == nil then
            error("typingshorthand setup config missing key '" .. key .. "'")
        end
    end

    check_key_present('shorthands_file')
    check_key_present('phraseable_words_file')

    config = config_local

    reload_wordlists()
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

local function expand(short)
    -- expand phrases
    local function helper(short)
        if short == "" then
            return { {} }
        else
            local possibilities = {}
            for _, normal_long in ipairs(get_longs(shorthands, short)) do
                table.insert(possibilities, { normal_long })
            end

            for i = 1, #short-1 do
                local first = string.sub(short, 1, i)
                local more = string.sub(short, i + 1)

                local first_possibilities = get_longs(phrase_shorthands, first)
                local more_possibilities = helper(more)

                for _, first_long in ipairs(first_possibilities) do
                    for _, more_long in ipairs(more_possibilities) do
                        local current = { first_long, unpack(more_long) }
                        table.insert(possibilities, current)
                    end
                end
            end

            return possibilities
        end
    end

    local possibilities_arrays = helper(short)
    local possibilities = {}
    for _, possibility in ipairs(possibilities_arrays) do
        table.insert(possibilities, table.concat(possibility, " "))
    end
    return possibilities
end
local function make_special_from_possibilities(short, possibilities)
    if #possibilities == 0 then
        return create_shorthand_special(short, "unknown", short)
    elseif #possibilities == 1 then
        return possibilities[1]
    else
        return create_shorthand_special(short, "choice", table.concat(possibilities, " | "))
    end
end
local function expand_sub(short)
    return make_special_from_possibilities(short, expand(short))
end

local function add_new_words()
    local wordlist_words = vim.split(vim.fn.input("lines to add to wordlist (lines separated by semicolons): "), ";")
    local phraselist_words = vim.split(vim.fn.input("lines to add to phraseable word list (lines separated by semicolons): "), ";")

    if not (#wordlist_words == 1 and wordlist_words[1] == "") then
        local wordlist = vim.fn.readfile(config.shorthands_file)
        for _, wordlist_line in ipairs(wordlist_words) do
            table.insert(wordlist, wordlist_line:match("^%s*(.-)%s*$"))
        end
        vim.fn.writefile(wordlist, config.shorthands_file)
    end

    if not (#phraselist_words == 1 and phraselist_words[1] == "") then
        local phraselist = vim.fn.readfile(config.phraseable_words_file)
        for _, phraselist_line in ipairs(phraselist_words) do
            table.insert(phraselist, phraselist_line:match("^%s*(.-)%s*$"))
        end
        vim.fn.writefile(phraselist, config.phraseable_words_file)
    end

    reload_wordlists()
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

        vim.fn.cursor(current_match.lnum, current_match.byteidx + 1)
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

            vim.print("choose replacement (0 or empty to add word to wordlist):")
            local chosen = vim.fn.inputlist(choices_with_numbers)
            if chosen > 0 and chosen <= #choices then
                replace_special(choices[chosen])
            else
                add_new_words()
                replace_special(make_special_from_possibilities(original_short, expand(original_short)))
            end
        elseif header == "unknown" then
            -- first try reexapnding it in case the shorthand lists have changed:
            local possibilities = expand(original_short)
            if #possibilities == 0 then
                -- if there are still no possibilities
                vim.cmd("redraw!")
                print("unknown shorthand: '" .. other .. "'")
                add_new_words()
                replace_special(make_special_from_possibilities(original_short, expand(original_short)))
            else
                -- if there are possibilities, replace it with the special created from those possibilities and let the next iteration of the loop deal with it
                replace_special(make_special_from_possibilities(original_short, possibilities))
            end
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

    vim.cmd("keeppatterns " .. startline .. "," .. endline .. "s/[" .. allowed_chars_str .. "]\\+/\\=v:lua.require'typingshorthand'.expand_sub(submatch(0))/g")

    review()
end

return {
    setup = setup,

    syntax_on = syntax_on,
    syntax_off = syntax_off,
    syntax_toggle = syntax_toggle,

    add_new_words = add_new_words,

    convert = convert,
    review = review,
    expand_sub = expand_sub,
}

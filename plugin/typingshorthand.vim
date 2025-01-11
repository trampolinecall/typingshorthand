if exists('g:loaded_typing_shorthand')
  finish
endif
let g:loaded_typing_shorthand = 1

command! -range=% TypingShorthand lua require("typingshorthand").convert(<line1>, <line2>)
command! -range=% TypingShorthandConvert lua require("typingshorthand").convert(<line1>, <line2>)
command! TypingShorthandReview lua require("typingshorthand").review()
command! TypingShorthandSynToggle lua require("typingshorthand").syntax_toggle()
command! TypingShorthandSynOn lua require("typingshorthand").syntax_on()
command! TypingShorthandSynOff lua require("typingshorthand").syntax_off()
command! TypingShorthandAddNewWords lua require("typingshorthand").add_new_words()

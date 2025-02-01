if exists('g:loaded_typing_shorthand')
  finish
endif
let g:loaded_typing_shorthand = 1

command! TypingShorthandReview lua require("typingshorthand").review()
command! TypingShorthandToggle lua require("typingshorthand").toggle()
command! TypingShorthandOn lua require("typingshorthand").on()
command! TypingShorthandOff lua require("typingshorthand").off()
command! TypingShorthandAddNewWords lua require("typingshorthand").add_new_words()

# write_file.cmake
#
# vice_write_file(<path> <content>)
#
# Writes <content> to <path> byte for byte, with LF line endings on every
# host (file(WRITE) would turn LF into CRLF on Windows), and leaves the file
# untouched when its content is unchanged.

function(vice_write_file path content)
    # file(CONFIGURE) substitutes @VAR@; route every `@` through a variable
    # that holds an `@` so that the text is written as it is.
    string(REPLACE "@" "@VICE_AT@" _c "${content}")
    set(VICE_AT "@")
    file(CONFIGURE OUTPUT "${path}" CONTENT "${_c}" @ONLY NEWLINE_STYLE UNIX)
endfunction()

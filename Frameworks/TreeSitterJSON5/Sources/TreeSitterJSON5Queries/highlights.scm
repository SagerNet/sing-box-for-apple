(number) @number

(comment) @comment

(member name: (_) @property)

(member value: (string) @string)
(member value: (number) @number)
(member value: ["true" "false" "null"] @constant.builtin)

(array ((string) @string))
(array (number) @number)
(array ["true" "false" "null"] @constant.builtin)

(ERROR) @error

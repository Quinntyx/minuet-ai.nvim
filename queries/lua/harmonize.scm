;; Captures for harmonize's extra completion context.

;; Imports: calls to require with a string argument.
(function_call
  (identifier) @_require
  (arguments
    (string) @harmonize.import)
  (#eq? @_require "require"))

;; Enclosing scopes whose header is worth sending as context.
(function_declaration) @harmonize.scope
(function_definition) @harmonize.scope

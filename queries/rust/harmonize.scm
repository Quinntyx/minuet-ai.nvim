;; Captures for harmonize's extra completion context.

;; Imports
(use_declaration) @harmonize.import

;; Enclosing scopes whose header is worth sending as context.
(function_item) @harmonize.scope
(function_signature_item) @harmonize.scope
(impl_item) @harmonize.scope
(struct_item) @harmonize.scope
(enum_item) @harmonize.scope
(trait_item) @harmonize.scope
(mod_item) @harmonize.scope

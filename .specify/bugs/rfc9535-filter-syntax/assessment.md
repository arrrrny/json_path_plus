# Assessment: rfc9535-filter-syntax (Issue #1)

## Verdict

**Valid bug.** The package claims RFC 9535 compatibility ("valid RFC 9535 should work
without any workaround"), but three independent gaps prevent standard filter
expressions from matching.

## Root-cause analysis (verified in code)

### 1. Bare filter selectors `[?<expr>]` are not tokenized as filters

`lib/src/json_path.dart` — `JSONPath.toPathArray`, the preprocessor regex:

```dart
n = n.replaceAllMapped(RegExp(r'''\[(\??\(.*?\))\]'''), (m) { ... });
```

only recognizes `[?(expr)]` / `[(expr)]`. RFC 9535 filter selectors are
`[? <logical-expr> ]` — outer parentheses are **not** part of the syntax. A path like
`$[?match(key(@), "…")]` therefore falls through to the literal-property branches and
matches nothing.

### 2. `key()` function is missing from the sandbox

`SafeEval` resolves identifiers only from the sandbox context; nothing defines `key`.
The reference `json_path` (jessie) implementation provides `key(@)` → the member key /
array index under which the current node was found. In this package the equivalent
already exists as the magic variable `_$_property` (bound from `@property`).

### 3. `match()` / `search()` functions are missing; `String.match()` method missing

`SafeEval` has no function-identifier dispatch (only `_MethodProxy` member calls), and
`_MethodProxy` has no `match` case for strings. RFC 9535 §2.4.6–2.4.7 defines:

- `match(value, pattern)` — LogicalTrue iff **the entirety** of the string matches.
- `search(value, pattern)` — LogicalTrue iff the string **contains** a match.
- Non-string arguments → LogicalFalse (no coercion).
- Invalid regex pattern → LogicalFalse (no throw).

Verified against the reference implementation (f3ath/jessie,
`lib/src/fun/standard/string_matcher.dart`) — identical semantics, giving clean
migration parity for configs coming from `json_path`.

## Remediation plan

1. **`toPathArray` normalization** (json_path.dart): after the existing paren-form
   rewrite, add a balanced-ish rewrite for bare filters
   `\[\s*\?(?!\()((?:[^'"[\]]|'[^']*'|"[^"]*"|\[[^\]]*\])+)\]` → `#N` token holding
   `?(<expr>)`, so the existing `_trace` filter branch (`startsWith('?(')`) handles it
   unchanged. The alternation keeps single-level nested brackets and quoted strings
   intact. Deep nesting / escaped quotes remain a known limitation (filed separately).
2. **Built-in functions** (sandboxed_script.dart): introduce an internal
   `BuiltInFunction` wrapper; `SafeEval.evaluate` seeds the context with
   `match`, `search`, `key` (user sandbox entries shadow them). `_evalCall` gains a
   `BuiltInFunction` dispatch. `key()` ignores its argument and returns the current
   member key (the `_$_property` binding), matching `key(@)` and `@property`.
3. **`String.match()` method proxy** (sandboxed_script.dart): `.match(pattern)` returns
   the first matching substring or `null` (JS-like, truthiness-friendly in filters).
4. **Tests** (`test/rfc9535_filter_test.dart`): red-first reproduction of the issue,
   bare-filter forms (with/without spaces, arrays and maps), match vs search semantics,
   non-string/invalid-regex → false, `key()` in object and array contexts, paren-form
   regression guards.
5. Version bump to 1.2.0 (new feature, backwards compatible) + CHANGELOG + README.

## Scope guard

- Regex literals (`/pattern/`) in the filter tokenizer are **out of scope** — RFC 9535
  `match`/`search` take string patterns; file as a follow-up issue.
- The regex-based tokenizer's deeper limitations (nested `)]` inside strings in
  *paren-form* filters, multi-level bracket nesting, `JSONPath.cache` growth, static
  mutable state) are recorded as hardening follow-ups, not fixed here.

## Risk

Low. The bare-filter rewrite is additive (paren-form path untouched); built-ins are
shadowable by user sandbox entries; all 90 existing tests must stay green.

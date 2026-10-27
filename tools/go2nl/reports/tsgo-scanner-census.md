# go2nl census

Upstream: https://github.com/microsoft/typescript-go at 89d5d5b2849a0db0957065889ca58536fa6d2e4a

Roots: github.com/microsoft/typescript-go/internal/scanner.NewScanner, github.com/microsoft/typescript-go/internal/scanner.Scanner.*, github.com/microsoft/typescript-go/internal/scanner.GetIdentifierToken, github.com/microsoft/typescript-go/internal/scanner.IsValidIdentifier, github.com/microsoft/typescript-go/internal/scanner.IsIdentifierText, github.com/microsoft/typescript-go/internal/scanner.TokenToString, github.com/microsoft/typescript-go/internal/scanner.StringToToken, github.com/microsoft/typescript-go/internal/scanner.SkipTrivia, github.com/microsoft/typescript-go/internal/scanner.GetShebang, github.com/microsoft/typescript-go/internal/scanner.ComputeLineOfPosition

Reachable: 178 functions and methods (5462 lines), 24 types, 88 package variables, 235 constants.

Functions by package: ast 1, collections 4, core 9, debug 3, jsnum 19, json 1, scanner 125, stringutil 16,

| Construct | Sites | Meaning |
| --- | ---: | --- |
| closure | 10 | function literal (closure); next-lang has no closures |
| func-value | 9 | function or method used as a value |
| defer | 1 | defer statement |
| goroutine | 0 | go statement, channel or select |
| panic-recover | 8 | panic or recover call |
| interface-type | 0 | interface type declared or used as a value type |
| interface-call | 0 | method call through an interface value |
| type-switch | 1 | type switch or type assertion |
| any-conversion | 38 | value converted to an interface (boxing) |
| variadic | 15 | variadic function declared or called with ... |
| float | 21 | float32/float64 value (stage 0 has no floats) |
| unsigned-wide | 2 | uint, uint32, uint64 or uintptr value |
| generic | 16 | generic function or type, or an instantiation |
| range-func | 2 | range over a function (iterator) |
| range-map | 3 | range over a map (Go's order is random) |
| range-string | 6 | range over a string (decodes runes) |
| goto-label | 12 | goto, labeled statement or fallthrough |
| multi-return | 8 | function with more than one result |
| pointer-field | 1 | struct field or element of pointer type (object graph) |
| address-of | 77 | & address-of |
| pointer-param | 110 | pointer parameter or receiver |
| mutable-global | 1 | package variable written after initialisation |
| readonly-global | 87 | package variable only read (can become const) |
| map | 11 | map type |
| slice | 7 | slice type |
| slice-expr | 81 | slicing expression a[i:j] |
| append | 11 | append call |
| string-conv | 32 | conversion between string, []byte, []rune and rune |
| embedding | 1 | embedded struct field |
| method | 109 | method declaration |
| stdlib-call | 147 | call into the Go standard library |

## Standard library uses

| Name | Uses |
| --- | ---: |
| unicode/utf8.DecodeRuneInString | 20 |
| strings.Builder.WriteString | 17 |
| strconv.ParseInt | 8 |
| math.NaN | 7 |
| maps.Keys | 6 |
| unicode/utf8.RuneSelf | 6 |
| iter.Seq | 5 |
| strings.Builder | 5 |
| strings.Builder.String | 5 |
| strings.HasPrefix | 5 |
| strings.IndexByte | 5 |
| unicode/utf8.RuneError | 5 |
| strconv.FormatInt | 4 |
| strings.CutPrefix | 4 |
| strings.ToLower | 4 |
| strings.TrimLeft | 4 |
| fmt.Sprintf | 3 |
| github.com/go-json-experiment/json.Options | 3 |
| math.Min | 3 |
| unicode.Is | 3 |
| unicode/utf16.IsSurrogate | 3 |
| unicode/utf8.DecodeLastRuneInString | 3 |
| math.Floor | 2 |
| math.IsNaN | 2 |
| math/big.Int | 2 |
| math/big.Int.SetString | 2 |
| slices.Grow | 2 |
| strings.Compare | 2 |
| unicode.Range16 | 2 |
| unicode.Range32 | 2 |
| unicode.RangeTable | 2 |
| unicode.ToLower | 2 |
| errors.Is | 1 |
| fmt.Sprint | 1 |
| github.com/go-json-experiment/json.Marshal | 1 |
| github.com/go-json-experiment/json/jsontext.AllowInvalidUTF8 | 1 |
| maps.Copy | 1 |
| math.Ceil | 1 |
| math.Copysign | 1 |
| math.Inf | 1 |
| math.IsInf | 1 |
| math.MaxInt | 1 |
| math/big.Int.Float64 | 1 |
| math/big.Int.String | 1 |
| slices.Clip | 1 |
| strconv.Atoi | 1 |
| strconv.ErrRange | 1 |
| strconv.ParseFloat | 1 |
| strings.Builder.Grow | 1 |
| strings.Builder.Len | 1 |
| strings.Builder.WriteByte | 1 |
| strings.Builder.WriteRune | 1 |
| strings.Cut | 1 |
| strings.EqualFold | 1 |
| strings.HasSuffix | 1 |
| strings.IndexAny | 1 |
| strings.Join | 1 |
| strings.ReplaceAll | 1 |
| strings.TrimFunc | 1 |
| strings.TrimRight | 1 |
| strings.TrimSuffix | 1 |
| sync.Pool | 1 |
| sync.Pool.Get | 1 |
| sync.Pool.Put | 1 |
| unicode.Zs | 1 |
| unicode/utf16.DecodeRune | 1 |
| unicode/utf16.EncodeRune | 1 |
| unicode/utf16.RuneLen | 1 |

## Sites

### closure (10)

- internal/core/core.go:647 core.levenshteinBuffersPool
- internal/core/core.go:738 core.ConcatenateSeq
- internal/scanner/scanner.go:124 scanner.textToToken
- internal/scanner/scanner.go:1534 scanner.Scanner.scanIdentifier
- internal/scanner/scanner.go:1645 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:2051 scanner.Scanner.scanNumberFragment
- internal/scanner/scanner.go:2255 scanner.tokenToText
- internal/scanner/scanner.go:494 scanner.Scanner.Scan
- internal/scanner/scanner.go:621 scanner.Scanner.Scan
- internal/scanner/scanner.go:647 scanner.Scanner.Scan

### func-value (9)

- internal/core/core.go:638 core.GetSpellingSuggestionForStrings (Compare)
- internal/core/core.go:638 core.GetSpellingSuggestionForStrings (Identity)
- internal/jsnum/string.go:55 jsnum.FromString (isStrWhiteSpace)
- internal/scanner/scanner.go:1283 scanner.Scanner.ScanJsxTokenEx (errorAt)
- internal/scanner/scanner.go:34 scanner.ErrorCallback
- internal/scanner/scanner.go:759 scanner.Scanner.Scan (errorAt)
- internal/scanner/scanner.go:787 scanner.Scanner.Scan (errorAt)
- internal/scanner/scanner.go:812 scanner.Scanner.Scan (errorAt)
- internal/scanner/scanner.go:857 scanner.Scanner.Scan (errorAt)

### defer (1)

- internal/core/core.go:597 core.getSpellingSuggestion

### panic-recover (8)

- internal/debug/debug.go:14 debug.Fail
- internal/jsnum/pseudobigint.go:63 jsnum.ParsePseudoBigInt
- internal/scanner/scanner.go:1060 scanner.Scanner.ReScanAsteriskEqualsToken
- internal/scanner/scanner.go:1242 scanner.Scanner.ReScanQuestionToken
- internal/scanner/scanner.go:2411 scanner.isConflictMarkerTrivia
- internal/scanner/scanner.go:2458 scanner.scanConflictMarkerTrivia
- internal/scanner/scanner.go:2480 scanner.isShebangTrivia
- internal/scanner/scanner.go:294 scanner.Scanner.ResetPos

### type-switch (1)

- internal/core/core.go:596 core.getSpellingSuggestion

### any-conversion (38)

- internal/core/core.go:597 core.getSpellingSuggestion
- internal/debug/debug.go:14 debug.Fail
- internal/jsnum/pseudobigint.go:63 jsnum.ParsePseudoBigInt
- internal/jsnum/pseudobigint.go:63 jsnum.ParsePseudoBigInt
- internal/jsnum/string.go:36 jsnum.Number.String
- internal/scanner/regexp.go:1064 scanner.regExpParser.scanExpectedChar
- internal/scanner/regexp.go:1085 scanner.regExpParser.run
- internal/scanner/regexp.go:1089 scanner.regExpParser.run
- internal/scanner/regexp.go:1100 scanner.regExpParser.run
- internal/scanner/regexp.go:280 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:308 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:319 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:326 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:364 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:516 scanner.regExpParser.scanGroupName
- internal/scanner/regexp.go:53 scanner.Scanner.checkRegularExpressionFlagAvailability
- internal/scanner/regexp.go:688 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:745 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:749 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:754 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:756 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:863 scanner.regExpParser.scanClassSetCharacter
- internal/scanner/regexp.go:933 scanner.regExpParser.scanCharacterClassEscape
- internal/scanner/regexp.go:947 scanner.regExpParser.scanCharacterClassEscape
- internal/scanner/regexp.go:966 scanner.regExpParser.scanCharacterClassEscape
- ... 13 more

### variadic (15)

- internal/collections/set.go:138 collections.NewSetFromItems
- internal/core/core.go:737 core.ConcatenateSeq
- internal/debug/debug.go:45 debug.Assert
- internal/debug/debug.go:49 debug.Assert (spread)
- internal/debug/debug.go:52 debug.assertSlow
- internal/debug/debug.go:56 debug.assertSlow (spread)
- internal/json/json.go:14 json.Marshal
- internal/json/json.go:18 json.Marshal (spread)
- internal/json/json.go:20 json.Marshal (spread)
- internal/scanner/regexp.go:129 scanner.regExpParser.error
- internal/scanner/regexp.go:130 scanner.regExpParser.error (spread)
- internal/scanner/scanner.go:1067 scanner.Scanner.ReScanSlashToken
- internal/scanner/scanner.go:372 scanner.hasJSDocTag
- internal/scanner/scanner.go:417 scanner.Scanner.errorAt
- internal/scanner/scanner.go:419 scanner.Scanner.errorAt (spread)

### float (21)

- internal/core/core.go:594 core.getSpellingSuggestion
- internal/core/core.go:660 core.levenshteinWithMax
- internal/jsnum/jsnum.go:20 jsnum.Number
- internal/jsnum/jsnum.go:23 jsnum.NaN
- internal/jsnum/jsnum.go:23 jsnum.NaN
- internal/jsnum/jsnum.go:27 jsnum.Number.IsNaN
- internal/jsnum/jsnum.go:27 jsnum.Number.IsNaN
- internal/jsnum/jsnum.go:31 jsnum.Inf
- internal/jsnum/jsnum.go:31 jsnum.Inf
- internal/jsnum/jsnum.go:35 jsnum.Number.IsInf
- internal/jsnum/jsnum.go:35 jsnum.Number.IsInf
- internal/jsnum/string.go:130 jsnum.tryParseInt
- internal/jsnum/string.go:170 jsnum.tryParseInt
- internal/jsnum/string.go:19 jsnum.Number.String
- internal/jsnum/string.go:198 jsnum.parseFloatString
- internal/jsnum/string.go:277 jsnum.stringToFloat64
- internal/jsnum/string.go:30 jsnum.Number.String
- internal/jsnum/string.go:59 jsnum.FromString
- internal/jsnum/string.go:87 jsnum.FromString
- internal/scanner/scanner.go:2014 scanner.Scanner.scanNumber
- internal/scanner/scanner.go:2197 scanner.Scanner.scanBigIntSuffix

### unsigned-wide (2)

- internal/stringutil/identifier_parts_generated.go:1059 stringutil.unicodeESNextIdentifierPart
- internal/stringutil/identifier_parts_generated.go:373 stringutil.unicodeESNextIdentifierStart

### generic (16)

- internal/collections/set.go:138 collections.NewSetFromItems
- internal/collections/set.go:16 collections.Set.Has
- internal/collections/set.go:24 collections.Set.Add
- internal/collections/set.go:42 collections.Set.Keys
- internal/collections/set.go:5 collections.Set
- internal/core/core.go:402 core.IfElse
- internal/core/core.go:584 core.GetSpellingSuggestion
- internal/core/core.go:585 core.GetSpellingSuggestion (getSpellingSuggestion)
- internal/core/core.go:592 core.getSpellingSuggestion
- internal/core/core.go:638 core.GetSpellingSuggestionForStrings (GetSpellingSuggestion)
- internal/core/core.go:704 core.Identity
- internal/core/core.go:737 core.ConcatenateSeq
- internal/scanner/scanner.go:230 scanner.Scanner.Reset (cleared)
- internal/scanner/scanner.go:231 scanner.Scanner.Reset (cleared)
- internal/scanner/scanner.go:232 scanner.Scanner.Reset (cleared)
- internal/scanner/scanner.go:239 scanner.cleared

### range-func (2)

- internal/core/core.go:601 core.getSpellingSuggestion
- internal/core/core.go:743 core.ConcatenateSeq

### range-map (3)

- internal/scanner/regexp.go:170 scanner.regExpParser.scanDisjunction
- internal/scanner/regexp.go:180 scanner.regExpParser.scanDisjunction
- internal/scanner/scanner.go:2257 scanner.tokenToText

### range-string (6)

- internal/jsnum/string.go:287 jsnum.isAllDigits
- internal/jsnum/string.go:296 jsnum.isAllBinaryDigits
- internal/jsnum/string.go:305 jsnum.isAllOctalDigits
- internal/jsnum/string.go:314 jsnum.isAllHexDigits
- internal/jsnum/string.go:66 jsnum.FromString
- internal/scanner/scanner.go:2228 scanner.IsValidIdentifier

### goto-label (12)

- internal/scanner/regexp.go:333 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:361 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:424 scanner.regExpParser.scanAtomEscape
- internal/scanner/regexp.go:803 scanner.regExpParser.scanClassSetOperand
- internal/scanner/regexp.go:918 scanner.regExpParser.scanCharacterClassEscape
- internal/scanner/scanner.go:1085 scanner.Scanner.ReScanSlashToken
- internal/scanner/scanner.go:1443 scanner.Scanner.ScanJSDocToken
- internal/scanner/scanner.go:1707 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:1714 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:1831 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:2332 scanner.SkipTriviaEx
- internal/scanner/scanner.go:748 scanner.Scanner.Scan

### multi-return (8)

- internal/jsnum/string.go:120 jsnum.tryParseInt
- internal/jsnum/string.go:244 jsnum.cutAny
- internal/json/json.go:14 json.Marshal
- internal/scanner/scanner.go:1912 scanner.Scanner.scanLowSurrogateEscape
- internal/scanner/scanner.go:2090 scanner.Scanner.scanDigits
- internal/scanner/scanner.go:441 scanner.Scanner.charAndSize
- internal/stringutil/util.go:296 stringutil.CodePointToSurrogatePair
- internal/stringutil/util.go:334 stringutil.DecodeJSStringRune

### pointer-field (1)

- internal/scanner/regexp.go:78 scanner.regExpParser.scanner

### address-of (77)

- internal/collections/set.go:139 collections.NewSetFromItems
- internal/core/core.go:648 core.levenshteinBuffersPool
- internal/diagnostics/diagnostics_generated.go:17 diagnostics.Asterisk_Slash_expected
- internal/diagnostics/diagnostics_generated.go:183 diagnostics.Octal_literals_are_not_allowed_Use_the_syntax_0
- internal/diagnostics/diagnostics_generated.go:187 diagnostics.Digit_expected
- internal/diagnostics/diagnostics_generated.go:189 diagnostics.Hexadecimal_digit_expected
- internal/diagnostics/diagnostics_generated.go:191 diagnostics.Unexpected_end_of_text
- internal/diagnostics/diagnostics_generated.go:193 diagnostics.Invalid_character
- internal/diagnostics/diagnostics_generated.go:239 diagnostics.Unterminated_template_literal
- internal/diagnostics/diagnostics_generated.go:241 diagnostics.Unterminated_regular_expression_literal
- internal/diagnostics/diagnostics_generated.go:2689 diagnostics.Numeric_separators_are_not_allowed_here
- internal/diagnostics/diagnostics_generated.go:2691 diagnostics.Multiple_consecutive_numeric_separators_are_not_permitted
- internal/diagnostics/diagnostics_generated.go:271 diagnostics.Binary_digit_expected
- internal/diagnostics/diagnostics_generated.go:273 diagnostics.Octal_digit_expected
- internal/diagnostics/diagnostics_generated.go:287 diagnostics.Merge_conflict_marker_encountered
- internal/diagnostics/diagnostics_generated.go:313 diagnostics.An_extended_Unicode_escape_value_must_be_between_0x0_and_0x10FFFF_inclusive
- internal/diagnostics/diagnostics_generated.go:315 diagnostics.Unterminated_Unicode_escape_sequence
- internal/diagnostics/diagnostics_generated.go:3693 diagnostics.X_can_only_be_used_at_the_start_of_a_file
- internal/diagnostics/diagnostics_generated.go:3761 diagnostics.Regular_expression_pattern_modifiers_are_only_available_when_targeting_0_or_later
- internal/diagnostics/diagnostics_generated.go:3763 diagnostics.Duplicate_named_capturing_groups_are_only_available_when_targeting_0_or_later
- internal/diagnostics/diagnostics_generated.go:5 diagnostics.Unterminated_string_literal
- internal/diagnostics/diagnostics_generated.go:575 diagnostics.An_identifier_or_keyword_cannot_immediately_follow_a_numeric_literal
- internal/diagnostics/diagnostics_generated.go:577 diagnostics.A_bigint_literal_cannot_use_exponential_notation
- internal/diagnostics/diagnostics_generated.go:579 diagnostics.A_bigint_literal_must_be_an_integer
- internal/diagnostics/diagnostics_generated.go:611 diagnostics.Did_you_mean_0
- ... 52 more

### pointer-param (110)

- internal/collections/set.go:16 collections.Set.Has (receiver)
- internal/collections/set.go:24 collections.Set.Add (receiver)
- internal/collections/set.go:42 collections.Set.Keys (receiver)
- internal/core/core.go:652 core.levenshteinWithMax (buffers)
- internal/scanner/regexp.go:1005 scanner.regExpParser.scanWordCharacters (receiver)
- internal/scanner/regexp.go:1017 scanner.regExpParser.scanSourceCharacter (receiver)
- internal/scanner/regexp.go:1060 scanner.regExpParser.scanExpectedChar (receiver)
- internal/scanner/regexp.go:1068 scanner.regExpParser.scanDigits (receiver)
- internal/scanner/regexp.go:1076 scanner.regExpParser.run (receiver)
- internal/scanner/regexp.go:109 scanner.regExpParser.pos (receiver)
- internal/scanner/regexp.go:117 scanner.regExpParser.incPos (receiver)
- internal/scanner/regexp.go:121 scanner.regExpParser.char (receiver)
- internal/scanner/regexp.go:125 scanner.regExpParser.charAt (receiver)
- internal/scanner/regexp.go:129 scanner.regExpParser.error (msg)
- internal/scanner/regexp.go:129 scanner.regExpParser.error (receiver)
- internal/scanner/regexp.go:133 scanner.regExpParser.text (receiver)
- internal/scanner/regexp.go:156 scanner.regExpParser.scanDisjunction (receiver)
- internal/scanner/regexp.go:224 scanner.regExpParser.scanAlternative (receiver)
- internal/scanner/regexp.go:377 scanner.regExpParser.scanPatternModifiers (receiver)
- internal/scanner/regexp.go:406 scanner.regExpParser.scanAtomEscape (receiver)
- internal/scanner/regexp.go:434 scanner.regExpParser.scanDecimalEscape (receiver)
- internal/scanner/regexp.go:460 scanner.regExpParser.scanCharacterEscape (receiver)
- internal/scanner/regexp.go:500 scanner.regExpParser.scanGroupName (receiver)
- internal/scanner/regexp.go:51 scanner.Scanner.checkRegularExpressionFlagAvailability (receiver)
- internal/scanner/regexp.go:525 scanner.regExpParser.namedCapturingGroupsContains (receiver)
- ... 85 more

### mutable-global (1)

- internal/core/core.go:646 core.levenshteinBuffersPool

### readonly-global (87)

- internal/core/scripttarget_stringer_generated.go:36 core._ScriptTarget_index_0
- internal/core/scripttarget_stringer_generated.go:37 core._ScriptTarget_index_1
- internal/diagnostics/diagnostics_generated.go:17 diagnostics.Asterisk_Slash_expected
- internal/diagnostics/diagnostics_generated.go:183 diagnostics.Octal_literals_are_not_allowed_Use_the_syntax_0
- internal/diagnostics/diagnostics_generated.go:187 diagnostics.Digit_expected
- internal/diagnostics/diagnostics_generated.go:189 diagnostics.Hexadecimal_digit_expected
- internal/diagnostics/diagnostics_generated.go:191 diagnostics.Unexpected_end_of_text
- internal/diagnostics/diagnostics_generated.go:193 diagnostics.Invalid_character
- internal/diagnostics/diagnostics_generated.go:239 diagnostics.Unterminated_template_literal
- internal/diagnostics/diagnostics_generated.go:241 diagnostics.Unterminated_regular_expression_literal
- internal/diagnostics/diagnostics_generated.go:2689 diagnostics.Numeric_separators_are_not_allowed_here
- internal/diagnostics/diagnostics_generated.go:2691 diagnostics.Multiple_consecutive_numeric_separators_are_not_permitted
- internal/diagnostics/diagnostics_generated.go:271 diagnostics.Binary_digit_expected
- internal/diagnostics/diagnostics_generated.go:273 diagnostics.Octal_digit_expected
- internal/diagnostics/diagnostics_generated.go:287 diagnostics.Merge_conflict_marker_encountered
- internal/diagnostics/diagnostics_generated.go:313 diagnostics.An_extended_Unicode_escape_value_must_be_between_0x0_and_0x10FFFF_inclusive
- internal/diagnostics/diagnostics_generated.go:315 diagnostics.Unterminated_Unicode_escape_sequence
- internal/diagnostics/diagnostics_generated.go:3693 diagnostics.X_can_only_be_used_at_the_start_of_a_file
- internal/diagnostics/diagnostics_generated.go:3761 diagnostics.Regular_expression_pattern_modifiers_are_only_available_when_targeting_0_or_later
- internal/diagnostics/diagnostics_generated.go:3763 diagnostics.Duplicate_named_capturing_groups_are_only_available_when_targeting_0_or_later
- internal/diagnostics/diagnostics_generated.go:5 diagnostics.Unterminated_string_literal
- internal/diagnostics/diagnostics_generated.go:575 diagnostics.An_identifier_or_keyword_cannot_immediately_follow_a_numeric_literal
- internal/diagnostics/diagnostics_generated.go:577 diagnostics.A_bigint_literal_cannot_use_exponential_notation
- internal/diagnostics/diagnostics_generated.go:579 diagnostics.A_bigint_literal_must_be_an_integer
- internal/diagnostics/diagnostics_generated.go:611 diagnostics.Did_you_mean_0
- ... 62 more

### map (11)

- internal/collections/set.go:5 collections.Set.M
- internal/scanner/regexp.go:34 scanner.charCodeToRegExpFlag
- internal/scanner/regexp.go:45 scanner.regExpFlagToFirstAvailableLanguageVersion
- internal/scanner/regexp.go:78 scanner.regExpParser.groupSpecifiers
- internal/scanner/scanner.go:124 scanner.textToToken
- internal/scanner/scanner.go:203 scanner.Scanner.hexDigitCache
- internal/scanner/scanner.go:203 scanner.Scanner.hexNumberCache
- internal/scanner/scanner.go:203 scanner.Scanner.numberCache
- internal/scanner/scanner.go:36 scanner.textToKeyword
- internal/scanner/unicodeproperties.go:139 scanner.valuesOfNonBinaryUnicodeProperties
- internal/scanner/unicodeproperties.go:7 scanner.nonBinaryUnicodeProperties

### slice (7)

- internal/core/core.go:641 core.levenshteinBuffers.current
- internal/core/core.go:641 core.levenshteinBuffers.previous
- internal/json/json.go:12 json.allowInvalid
- internal/scanner/regexp.go:78 scanner.regExpParser.decimalEscapes
- internal/scanner/regexp.go:78 scanner.regExpParser.groupNameReferences
- internal/scanner/regexp.go:78 scanner.regExpParser.namedCapturingGroups
- internal/scanner/scanner.go:192 scanner.ScannerState.commentDirectives

### slice-expr (81)

- internal/core/core.go:654 core.levenshteinWithMax
- internal/core/core.go:654 core.levenshteinWithMax
- internal/core/core.go:655 core.levenshteinWithMax
- internal/core/core.go:655 core.levenshteinWithMax
- internal/core/scripttarget_stringer_generated.go:43 core.ScriptTarget.String
- internal/core/scripttarget_stringer_generated.go:46 core.ScriptTarget.String
- internal/jsnum/string.go:126 jsnum.tryParseInt
- internal/jsnum/string.go:126 jsnum.tryParseInt
- internal/jsnum/string.go:246 jsnum.cutAny
- internal/jsnum/string.go:247 jsnum.cutAny
- internal/jsnum/string.go:249 jsnum.cutAny
- internal/scanner/regexp.go:1014 scanner.regExpParser.scanWordCharacters
- internal/scanner/regexp.go:1025 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1031 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1047 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1073 scanner.regExpParser.scanDigits
- internal/scanner/regexp.go:169 scanner.regExpParser.scanDisjunction
- internal/scanner/regexp.go:379 scanner.regExpParser.scanPatternModifiers
- internal/scanner/regexp.go:610 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:660 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:691 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:701 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:707 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:858 scanner.regExpParser.scanClassSetCharacter
- internal/scanner/scanner.go:1003 scanner.Scanner.processCommentDirective
- ... 56 more

### append (11)

- internal/json/json.go:18 json.Marshal
- internal/scanner/regexp.go:166 scanner.regExpParser.scanDisjunction
- internal/scanner/regexp.go:444 scanner.regExpParser.scanDecimalEscape
- internal/scanner/regexp.go:507 scanner.regExpParser.scanGroupName
- internal/scanner/scanner.go:1010 scanner.Scanner.processCommentDirective
- internal/scanner/scanner.go:1650 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:1661 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:1667 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:1668 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:1675 scanner.Scanner.scanTemplateAndSetTokenValue
- internal/scanner/scanner.go:1680 scanner.Scanner.scanTemplateAndSetTokenValue

### string-conv (32)

- internal/core/core.go:593 core.getSpellingSuggestion
- internal/core/core.go:619 core.getSpellingSuggestion
- internal/jsnum/string.go:37 jsnum.Number.String
- internal/scanner/regexp.go:1045 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1057 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1064 scanner.regExpParser.scanExpectedChar
- internal/scanner/regexp.go:308 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:319 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:364 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:472 scanner.regExpParser.scanCharacterEscape
- internal/scanner/regexp.go:480 scanner.regExpParser.scanCharacterEscape
- internal/scanner/regexp.go:483 scanner.regExpParser.scanCharacterEscape
- internal/scanner/regexp.go:688 scanner.regExpParser.scanClassSetExpression
- internal/scanner/regexp.go:745 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:749 scanner.regExpParser.scanClassSetSubExpression
- internal/scanner/regexp.go:849 scanner.regExpParser.scanClassSetCharacter
- internal/scanner/regexp.go:863 scanner.regExpParser.scanClassSetCharacter
- internal/scanner/regexp.go:865 scanner.regExpParser.scanClassSetCharacter
- internal/scanner/regexp.go:891 scanner.regExpParser.scanClassAtom
- internal/scanner/regexp.go:975 scanner.regExpParser.scanCharacterClassEscape
- internal/scanner/scanner.go:1494 scanner.Scanner.ScanJSDocToken
- internal/scanner/scanner.go:1729 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:1741 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:1780 scanner.Scanner.scanEscapeSequence
- internal/scanner/scanner.go:1793 scanner.Scanner.scanEscapeSequence
- ... 7 more

### embedding (1)

- internal/scanner/scanner.go:203 scanner.Scanner.ScannerState

### method (109)

- internal/collections/set.go:16 collections.Set.Has
- internal/collections/set.go:24 collections.Set.Add
- internal/collections/set.go:42 collections.Set.Keys
- internal/core/scripttarget_stringer_generated.go:40 core.ScriptTarget.String
- internal/jsnum/jsnum.go:26 jsnum.Number.IsNaN
- internal/jsnum/jsnum.go:34 jsnum.Number.IsInf
- internal/jsnum/string.go:17 jsnum.Number.String
- internal/scanner/regexp.go:1005 scanner.regExpParser.scanWordCharacters
- internal/scanner/regexp.go:1017 scanner.regExpParser.scanSourceCharacter
- internal/scanner/regexp.go:1060 scanner.regExpParser.scanExpectedChar
- internal/scanner/regexp.go:1068 scanner.regExpParser.scanDigits
- internal/scanner/regexp.go:1076 scanner.regExpParser.run
- internal/scanner/regexp.go:109 scanner.regExpParser.pos
- internal/scanner/regexp.go:117 scanner.regExpParser.incPos
- internal/scanner/regexp.go:121 scanner.regExpParser.char
- internal/scanner/regexp.go:125 scanner.regExpParser.charAt
- internal/scanner/regexp.go:129 scanner.regExpParser.error
- internal/scanner/regexp.go:133 scanner.regExpParser.text
- internal/scanner/regexp.go:156 scanner.regExpParser.scanDisjunction
- internal/scanner/regexp.go:224 scanner.regExpParser.scanAlternative
- internal/scanner/regexp.go:377 scanner.regExpParser.scanPatternModifiers
- internal/scanner/regexp.go:406 scanner.regExpParser.scanAtomEscape
- internal/scanner/regexp.go:434 scanner.regExpParser.scanDecimalEscape
- internal/scanner/regexp.go:460 scanner.regExpParser.scanCharacterEscape
- internal/scanner/regexp.go:500 scanner.regExpParser.scanGroupName
- ... 84 more

### stdlib-call (147)

- internal/core/core.go:595 core.getSpellingSuggestion (math.Floor)
- internal/core/core.go:596 core.getSpellingSuggestion (sync.Pool.Get)
- internal/core/core.go:597 core.getSpellingSuggestion (sync.Pool.Put)
- internal/core/core.go:616 core.getSpellingSuggestion (strings.EqualFold)
- internal/core/core.go:654 core.levenshteinWithMax (slices.Grow)
- internal/core/core.go:655 core.levenshteinWithMax (slices.Grow)
- internal/core/core.go:666 core.levenshteinWithMax (math.Ceil)
- internal/core/core.go:667 core.levenshteinWithMax (math.Floor)
- internal/core/core.go:675 core.levenshteinWithMax (unicode.ToLower)
- internal/core/core.go:675 core.levenshteinWithMax (unicode.ToLower)
- internal/core/core.go:683 core.levenshteinWithMax (math.Min)
- internal/core/core.go:683 core.levenshteinWithMax (math.Min)
- internal/core/core.go:686 core.levenshteinWithMax (math.Min)
- internal/core/scripttarget_stringer_generated.go:48 core.ScriptTarget.String (strconv.FormatInt)
- internal/debug/debug.go:56 debug.assertSlow (fmt.Sprint)
- internal/jsnum/jsnum.go:23 jsnum.NaN (math.NaN)
- internal/jsnum/jsnum.go:27 jsnum.Number.IsNaN (math.IsNaN)
- internal/jsnum/jsnum.go:31 jsnum.Inf (math.Inf)
- internal/jsnum/jsnum.go:35 jsnum.Number.IsInf (math.IsInf)
- internal/jsnum/pseudobigint.go:46 jsnum.ParsePseudoBigInt (strings.TrimSuffix)
- internal/jsnum/pseudobigint.go:55 jsnum.ParsePseudoBigInt (strings.TrimLeft)
- internal/jsnum/pseudobigint.go:61 jsnum.ParsePseudoBigInt (math/big.Int.SetString)
- internal/jsnum/pseudobigint.go:63 jsnum.ParsePseudoBigInt (fmt.Sprintf)
- internal/jsnum/pseudobigint.go:65 jsnum.ParsePseudoBigInt (math/big.Int.String)
- internal/jsnum/string.go:115 jsnum.isStrWhiteSpace (unicode.Is)
- ... 122 more

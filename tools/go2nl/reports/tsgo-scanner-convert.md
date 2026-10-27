# go2nl conversion report

Upstream: https://github.com/microsoft/typescript-go at 89d5d5b2849a0db0957065889ca58536fa6d2e4a

359 declarations converted, 154 not converted, 0 excluded by the config, 0 replaced by stubs.

**335 of the 359 converted declarations are dependency-closed**: they and everything they use converted, so only these can compile.

Functions and methods: 178 reachable, 40 converted, **16 dependency-closed**.

| Blocked by | Declarations |
| --- | ---: |
| embedding | 55 |
| variadic | 23 |
| stdlib-call | 21 |
| generic | 17 |
| float | 6 |
| func-value | 5 |
| multi-return | 5 |
| range-string | 5 |
| stdlib-type | 5 |
| string-conv | 3 |
| nil | 2 |
| type | 2 |
| address-of | 1 |
| goto-label | 1 |
| mutable-global | 1 |
| pointer-alias | 1 |
| pointer-field | 1 |

## Not converted

- collections.Set (internal/collections/set.go:5): generic: generic type
- collections.Set.Has (internal/collections/set.go:16): generic: generic function
- collections.Set.Add (internal/collections/set.go:24): generic: generic function
- collections.Set.Keys (internal/collections/set.go:42): generic: generic function
- collections.NewSetFromItems (internal/collections/set.go:138): generic: generic function
- core.IfElse (internal/core/core.go:402): generic: generic function
- core.GetSpellingSuggestion (internal/core/core.go:584): generic: generic function
- core.getSpellingSuggestion (internal/core/core.go:592): generic: generic function
- core.GetSpellingSuggestionForStrings (internal/core/core.go:637): generic: generic type iter.Seq[string]
- core.levenshteinBuffers (internal/core/core.go:641): float: float64 (stage 0 has no floats)
- core.levenshteinBuffersPool (internal/core/core.go:646): mutable-global: package variable levenshteinBuffersPool is written after initialisation (next-lang has no mutable globals)
- core.levenshteinWithMax (internal/core/core.go:652): float: float64 (stage 0 has no floats)
- core.Identity (internal/core/core.go:704): generic: generic function
- core.ConcatenateSeq (internal/core/core.go:737): generic: generic function
- core.ScriptTarget.String (internal/core/scripttarget_stringer_generated.go:48): stdlib-call: strconv.FormatInt has no shim yet
- debug.Assert (internal/debug/debug.go:45): variadic: variadic function
- debug.assertSlow (internal/debug/debug.go:52): variadic: variadic function
- jsnum.Number (internal/jsnum/jsnum.go:20): float: float64 (stage 0 has no floats)
- jsnum.NaN (internal/jsnum/jsnum.go:23): stdlib-call: math.NaN has no shim yet
- jsnum.Number.IsNaN (internal/jsnum/jsnum.go:27): stdlib-call: math.IsNaN has no shim yet
- jsnum.Inf (internal/jsnum/jsnum.go:31): stdlib-call: math.Inf has no shim yet
- jsnum.Number.IsInf (internal/jsnum/jsnum.go:35): stdlib-call: math.IsInf has no shim yet
- jsnum.ParsePseudoBigInt (internal/jsnum/pseudobigint.go:46): stdlib-call: strings.TrimSuffix has no shim yet
- jsnum.Number.String (internal/jsnum/string.go:22): float: float constant 0
- jsnum.FromString (internal/jsnum/string.go:55): stdlib-call: strings.TrimFunc has no shim yet
- jsnum.isStrWhiteSpace (internal/jsnum/string.go:115): stdlib-call: unicode.Is has no shim yet
- jsnum.tryParseInt (internal/jsnum/string.go:120): type: no zero value for github.com/microsoft/typescript-go/internal/jsnum.Number
- jsnum.parseFloatString (internal/jsnum/string.go:173): float: float64 (stage 0 has no floats)
- jsnum.cutAny (internal/jsnum/string.go:245): stdlib-call: strings.IndexAny has no shim yet
- jsnum.trimLeadingZeros (internal/jsnum/string.go:257): stdlib-call: strings.TrimLeft has no shim yet
- jsnum.trimTrailingZeros (internal/jsnum/string.go:267): stdlib-call: strings.TrimRight has no shim yet
- jsnum.stringToFloat64 (internal/jsnum/string.go:275): float: float64 (stage 0 has no floats)
- jsnum.isAllDigits (internal/jsnum/string.go:287): range-string: range over a string (decodes UTF-8 runes)
- jsnum.isAllBinaryDigits (internal/jsnum/string.go:296): range-string: range over a string (decodes UTF-8 runes)
- jsnum.isAllOctalDigits (internal/jsnum/string.go:305): range-string: range over a string (decodes UTF-8 runes)
- jsnum.isAllHexDigits (internal/jsnum/string.go:314): range-string: range over a string (decodes UTF-8 runes)
- json.allowInvalid (internal/json/json.go:12): stdlib-type: standard-library type encoding/json/internal/jsonopts.Options
- json.Marshal (internal/json/json.go:14): variadic: variadic function
- scanner.Scanner.checkRegularExpressionFlagAvailability (internal/scanner/regexp.go:53): variadic: call of variadic errorAt
- scanner.regExpParser (internal/scanner/regexp.go:78): pointer-field: field scanner has pointer type *github.com/microsoft/typescript-go/internal/scanner.Scanner (an object graph needs pools and ids)
- scanner.regExpParser.pos (internal/scanner/regexp.go:110): embedding: promoted field pos
- scanner.regExpParser.incPos (internal/scanner/regexp.go:118): embedding: promoted field pos
- scanner.regExpParser.error (internal/scanner/regexp.go:129): variadic: variadic function
- scanner.compareDecimalStrings (internal/scanner/regexp.go:138): stdlib-call: strings.TrimLeft has no shim yet
- scanner.regExpParser.scanDisjunction (internal/scanner/regexp.go:156): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.regExpParser.scanAlternative (internal/scanner/regexp.go:263): variadic: call of variadic error
- scanner.regExpParser.scanPatternModifiers (internal/scanner/regexp.go:379): multi-return: several results from utf8.DecodeRuneInString(p.text()[p.pos():])
- scanner.regExpParser.scanAtomEscape (internal/scanner/regexp.go:407): variadic: call of variadic Assert
- scanner.regExpParser.scanDecimalEscape (internal/scanner/regexp.go:435): variadic: call of variadic Assert
- scanner.regExpParser.scanCharacterEscape (internal/scanner/regexp.go:461): variadic: call of variadic Assert
- scanner.regExpParser.scanGroupName (internal/scanner/regexp.go:501): variadic: call of variadic Assert
- scanner.regExpParser.scanClassRanges (internal/scanner/regexp.go:540): variadic: call of variadic Assert
- scanner.regExpParser.scanClassSetExpression (internal/scanner/regexp.go:595): variadic: call of variadic Assert
- scanner.regExpParser.scanClassSetSubExpression (internal/scanner/regexp.go:732): variadic: call of variadic error
- scanner.regExpParser.scanClassSetOperand (internal/scanner/regexp.go:803): goto-label: fallthrough
- scanner.regExpParser.scanClassStringDisjunctionContents (internal/scanner/regexp.go:811): variadic: call of variadic Assert
- scanner.regExpParser.scanClassSetCharacter (internal/scanner/regexp.go:849): string-conv: conversion string(innerCh)
- scanner.regExpParser.scanClassAtom (internal/scanner/regexp.go:891): string-conv: conversion string(ch)
- scanner.regExpParser.scanCharacterClassEscape (internal/scanner/regexp.go:908): variadic: call of variadic Assert
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyName (internal/scanner/regexp.go:986): stdlib-call: maps.Keys has no shim yet
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyValue (internal/scanner/regexp.go:990): pointer-alias: pointer copied from valuesOfNonBinaryUnicodeProperties[propertyName]: two Go names for one value
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyNameOrValue (internal/scanner/regexp.go:998): variadic: call of variadic ConcatenateSeq
- scanner.regExpParser.scanSourceCharacter (internal/scanner/regexp.go:1025): multi-return: several results from utf8.DecodeRuneInString(p.text()[p.pos():])
- scanner.regExpParser.scanExpectedChar (internal/scanner/regexp.go:1064): variadic: call of variadic error
- scanner.regExpParser.scanDigits (internal/scanner/regexp.go:1073): embedding: promoted field tokenValue
- scanner.regExpParser.run (internal/scanner/regexp.go:1085): variadic: call of variadic error
- scanner.ErrorCallback (internal/scanner/scanner.go:34): func-value: function type func(diagnostic *github.com/microsoft/typescript-go/internal/diagnostics.Message, start int, length int, args ...any)
- scanner.textToToken (internal/scanner/scanner.go:124): func-value: call of a function value func() map[string]ast.Kind { 	m := map[string]ast.Kind{ 	...
- scanner.Scanner (internal/scanner/scanner.go:203): type: no zero value for github.com/microsoft/typescript-go/internal/scanner.ErrorCallback
- scanner.NewScanner (internal/scanner/scanner.go:226): address-of: address of s
- scanner.cleared (internal/scanner/scanner.go:239): generic: generic function
- scanner.Scanner.Token (internal/scanner/scanner.go:249): embedding: promoted field token
- scanner.Scanner.TokenFlags (internal/scanner/scanner.go:253): embedding: promoted field tokenFlags
- scanner.Scanner.TokenFullStart (internal/scanner/scanner.go:257): embedding: promoted field fullStartPos
- scanner.Scanner.TokenStart (internal/scanner/scanner.go:261): embedding: promoted field tokenStart
- scanner.Scanner.TokenEnd (internal/scanner/scanner.go:265): embedding: promoted field pos
- scanner.Scanner.TokenText (internal/scanner/scanner.go:269): embedding: promoted field tokenStart
- scanner.Scanner.TokenValue (internal/scanner/scanner.go:273): embedding: promoted field tokenValue
- scanner.Scanner.TokenRange (internal/scanner/scanner.go:277): embedding: promoted field tokenStart
- scanner.Scanner.CommentDirectives (internal/scanner/scanner.go:281): embedding: promoted field commentDirectives
- scanner.Scanner.ResetPos (internal/scanner/scanner.go:296): embedding: promoted field pos
- scanner.Scanner.ResetTokenState (internal/scanner/scanner.go:303): embedding: promoted field token
- scanner.Scanner.SetSkipJSDocLeadingAsterisks (internal/scanner/scanner.go:310): embedding: promoted field skipJSDocLeadingAsterisks
- scanner.Scanner.HasUnicodeEscape (internal/scanner/scanner.go:321): embedding: promoted field tokenFlags
- scanner.Scanner.HasExtendedUnicodeEscape (internal/scanner/scanner.go:325): embedding: promoted field tokenFlags
- scanner.Scanner.HasPrecedingLineBreak (internal/scanner/scanner.go:329): embedding: promoted field tokenFlags
- scanner.Scanner.HasPrecedingJSDocComment (internal/scanner/scanner.go:333): embedding: promoted field tokenFlags
- scanner.Scanner.HasPrecedingJSDocLeadingAsterisks (internal/scanner/scanner.go:337): embedding: promoted field tokenFlags
- scanner.Scanner.HasPrecedingJSDocWithDeprecatedTag (internal/scanner/scanner.go:341): embedding: promoted field tokenFlags
- scanner.Scanner.HasPrecedingJSDocWithSeeOrLink (internal/scanner/scanner.go:345): embedding: promoted field tokenFlags
- scanner.Scanner.scanJSDocCommentForTags (internal/scanner/scanner.go:357): embedding: promoted field tokenFlags
- scanner.hasJSDocTag (internal/scanner/scanner.go:372): variadic: variadic function
- scanner.Scanner.error (internal/scanner/scanner.go:414): variadic: call of variadic errorAt
- scanner.Scanner.errorAt (internal/scanner/scanner.go:417): variadic: variadic function
- scanner.Scanner.char (internal/scanner/scanner.go:427): embedding: promoted field pos
- scanner.Scanner.charAt (internal/scanner/scanner.go:435): embedding: promoted field pos
- scanner.Scanner.charAndSize (internal/scanner/scanner.go:445): embedding: promoted field pos
- scanner.Scanner.scanASCIIWhile (internal/scanner/scanner.go:456): func-value: function type func(byte) bool
- scanner.Scanner.Scan (internal/scanner/scanner.go:470): embedding: promoted field fullStartPos
- scanner.Scanner.processCommentDirective (internal/scanner/scanner.go:1010): embedding: promoted field commentDirectives
- scanner.Scanner.ReScanLessThanToken (internal/scanner/scanner.go:1014): embedding: promoted field token
- scanner.Scanner.ReScanGreaterThanToken (internal/scanner/scanner.go:1022): embedding: promoted field token
- scanner.Scanner.reScanGreaterThanTokenInner (internal/scanner/scanner.go:1029): embedding: promoted field pos
- scanner.Scanner.ReScanTemplateToken (internal/scanner/scanner.go:1053): embedding: promoted field pos
- scanner.Scanner.ReScanAsteriskEqualsToken (internal/scanner/scanner.go:1059): embedding: promoted field token
- scanner.Scanner.ReScanSlashToken (internal/scanner/scanner.go:1067): variadic: variadic function
- scanner.Scanner.ReScanJsxToken (internal/scanner/scanner.go:1226): embedding: promoted field pos
- scanner.Scanner.ReScanHashToken (internal/scanner/scanner.go:1233): embedding: promoted field token
- scanner.Scanner.ReScanQuestionToken (internal/scanner/scanner.go:1241): embedding: promoted field token
- scanner.Scanner.ScanJsxTokenEx (internal/scanner/scanner.go:1254): embedding: promoted field fullStartPos
- scanner.Scanner.ScanJsxIdentifier (internal/scanner/scanner.go:1322): embedding: promoted field token
- scanner.Scanner.ScanJsxAttributeValue (internal/scanner/scanner.go:1349): embedding: promoted field fullStartPos
- scanner.Scanner.ReScanJsxAttributeValue (internal/scanner/scanner.go:1368): embedding: promoted field pos
- scanner.Scanner.ScanJSDocCommentTextToken (internal/scanner/scanner.go:1375): embedding: promoted field fullStartPos
- scanner.Scanner.CanFollowJSDocAt (internal/scanner/scanner.go:1411): embedding: promoted field pos
- scanner.Scanner.ScanJSDocToken (internal/scanner/scanner.go:1419): embedding: promoted field fullStartPos
- scanner.Scanner.scanIdentifier (internal/scanner/scanner.go:1528): embedding: promoted field pos
- scanner.Scanner.scanIdentifierParts (internal/scanner/scanner.go:1562): stdlib-type: standard-library type strings.Builder
- scanner.Scanner.scanString (internal/scanner/scanner.go:1589): embedding: promoted field tokenFlags
- scanner.Scanner.scanTemplateAndSetTokenValue (internal/scanner/scanner.go:1640): embedding: promoted field pos
- scanner.Scanner.scanEscapeSequence (internal/scanner/scanner.go:1691): embedding: promoted field pos
- scanner.Scanner.scanUnicodeEscape (internal/scanner/scanner.go:1856): embedding: promoted field pos
- scanner.Scanner.scanLowSurrogateEscape (internal/scanner/scanner.go:1916): embedding: promoted field pos
- scanner.Scanner.peekUnicodeEscape (internal/scanner/scanner.go:1934): embedding: promoted field pos
- scanner.Scanner.scanNumber (internal/scanner/scanner.go:1945): embedding: promoted field pos
- scanner.Scanner.scanNumberFragment (internal/scanner/scanner.go:2045): embedding: promoted field pos
- scanner.Scanner.scanDigits (internal/scanner/scanner.go:2091): embedding: promoted field pos
- scanner.Scanner.scanHexDigits (internal/scanner/scanner.go:2104): embedding: promoted field pos
- scanner.Scanner.scanBinaryOrOctalDigits (internal/scanner/scanner.go:2151): stdlib-type: standard-library type strings.Builder
- scanner.Scanner.scanBigIntSuffix (internal/scanner/scanner.go:2184): embedding: promoted field tokenValue
- scanner.Scanner.scanInvalidCharacter (internal/scanner/scanner.go:2209): variadic: call of variadic errorAt
- scanner.IsValidIdentifier (internal/scanner/scanner.go:2228): range-string: range over a string (decodes UTF-8 runes)
- scanner.tokenToText (internal/scanner/scanner.go:2255): func-value: call of a function value func() [ast.KindCount]string { 	var result [ast.KindCount...
- scanner.SkipTrivia (internal/scanner/scanner.go:2308): nil: nil
- scanner.SkipTriviaEx (internal/scanner/scanner.go:2315): nil: comparison with nil
- scanner.isConflictMarkerTrivia (internal/scanner/scanner.go:2424): multi-return: several results from utf8.DecodeLastRuneInString(text[:pos-2])
- scanner.scanConflictMarkerTrivia (internal/scanner/scanner.go:2444): func-value: function type func(diag *github.com/microsoft/typescript-go/internal/diagnostics.Message, pos int, length int, args ...any)
- scanner.scanShebangTrivia (internal/scanner/scanner.go:2488): multi-return: several results from utf8.DecodeRuneInString(text[pos:])
- scanner.binaryUnicodeProperties (internal/scanner/unicodeproperties.go:18): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.binaryUnicodePropertiesOfStrings (internal/scanner/unicodeproperties.go:55): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.scriptValues (internal/scanner/unicodeproperties.go:62): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.valuesOfNonBinaryUnicodeProperties (internal/scanner/unicodeproperties.go:139): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.IsIdentifierText (internal/scanner/utilities.go:130): multi-return: several results from utf8.DecodeRuneInString(name)
- stringutil.IsUnicodeIdentifierStart (internal/stringutil/identifier.go:9): stdlib-call: unicode.Is has no shim yet
- stringutil.IsUnicodeIdentifierPart (internal/stringutil/identifier.go:16): stdlib-call: unicode.Is has no shim yet
- stringutil.unicodeESNextIdentifierStart (internal/stringutil/identifier_parts_generated.go:12): stdlib-type: standard-library type unicode.RangeTable
- stringutil.unicodeESNextIdentifierPart (internal/stringutil/identifier_parts_generated.go:644): stdlib-type: standard-library type unicode.RangeTable
- stringutil.IsHighSurrogate (internal/stringutil/util.go:281): stdlib-call: unicode/utf16.IsSurrogate has no shim yet
- stringutil.IsLowSurrogate (internal/stringutil/util.go:285): stdlib-call: unicode/utf16.IsSurrogate has no shim yet
- stringutil.IsSurrogate (internal/stringutil/util.go:289): stdlib-call: unicode/utf16.IsSurrogate has no shim yet
- stringutil.SurrogatePairToCodePoint (internal/stringutil/util.go:293): stdlib-call: unicode/utf16.DecodeRune has no shim yet
- stringutil.CodePointToSurrogatePair (internal/stringutil/util.go:297): stdlib-call: unicode/utf16.EncodeRune has no shim yet
- stringutil.EncodeJSStringRune (internal/stringutil/util.go:325): string-conv: conversion string([]byte{ 			surrogateUTF8Lead, 			byte(utf8ContMark...
- stringutil.DecodeJSStringRune (internal/stringutil/util.go:341): stdlib-call: unicode/utf8.DecodeRuneInString has no shim yet

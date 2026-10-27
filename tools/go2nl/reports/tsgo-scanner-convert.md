# go2nl conversion report

Upstream: https://github.com/microsoft/typescript-go at 89d5d5b2849a0db0957065889ca58536fa6d2e4a

460 declarations converted, 43 not converted, 0 excluded by the config, 0 replaced by stubs.

**421 of the 460 converted declarations are dependency-closed**: they and everything they use converted, so only these can compile.

Functions and methods: 178 reachable, 146 converted, **98 dependency-closed**.

| Blocked by | Declarations |
| --- | ---: |
| stdlib-call | 19 |
| generic | 8 |
| float | 6 |
| nil | 2 |
| pointer-alias | 2 |
| stdlib-type | 2 |
| map | 1 |
| mutable-global | 1 |
| pointer-field | 1 |
| range-map | 1 |
| type | 1 |

## Not converted

- collections.Set (internal/collections/set.go:5): generic: generic type
- core.GetSpellingSuggestionForStrings (internal/core/core.go:637): generic: generic type iter.Seq[string]
- core.levenshteinBuffers (internal/core/core.go:641): float: float64 (stage 0 has no floats)
- core.levenshteinBuffersPool (internal/core/core.go:646): mutable-global: package variable levenshteinBuffersPool is written after initialisation (next-lang has no mutable globals)
- core.levenshteinWithMax (internal/core/core.go:652): float: float64 (stage 0 has no floats)
- jsnum.Number (internal/jsnum/jsnum.go:20): float: float64 (stage 0 has no floats)
- jsnum.NaN (internal/jsnum/jsnum.go:23): stdlib-call: math.NaN has no shim yet
- jsnum.Number.IsNaN (internal/jsnum/jsnum.go:27): stdlib-call: math.IsNaN has no shim yet
- jsnum.Inf (internal/jsnum/jsnum.go:31): stdlib-call: math.Inf has no shim yet
- jsnum.Number.IsInf (internal/jsnum/jsnum.go:35): stdlib-call: math.IsInf has no shim yet
- jsnum.ParsePseudoBigInt (internal/jsnum/pseudobigint.go:55): stdlib-call: strings.TrimLeft has no shim yet
- jsnum.Number.String (internal/jsnum/string.go:22): float: float constant 0
- jsnum.FromString (internal/jsnum/string.go:55): stdlib-call: strings.TrimFunc has no shim yet
- jsnum.isStrWhiteSpace (internal/jsnum/string.go:115): stdlib-call: unicode.Is of a table that isn't a package variable
- jsnum.tryParseInt (internal/jsnum/string.go:120): type: no zero value for github.com/microsoft/typescript-go/internal/jsnum.Number
- jsnum.parseFloatString (internal/jsnum/string.go:173): float: float64 (stage 0 has no floats)
- jsnum.cutAny (internal/jsnum/string.go:245): stdlib-call: strings.IndexAny has no shim yet
- jsnum.trimLeadingZeros (internal/jsnum/string.go:257): stdlib-call: strings.TrimLeft has no shim yet
- jsnum.trimTrailingZeros (internal/jsnum/string.go:267): stdlib-call: strings.TrimRight has no shim yet
- jsnum.stringToFloat64 (internal/jsnum/string.go:275): float: float64 (stage 0 has no floats)
- json.allowInvalid (internal/json/json.go:12): stdlib-type: standard-library type encoding/json/internal/jsonopts.Options
- json.Marshal (internal/json/json.go:14): stdlib-type: standard-library type encoding/json/internal/jsonopts.Options
- scanner.Scanner.checkRegularExpressionFlagAvailability (internal/scanner/regexp.go:53): stdlib-call: strings.ToLower has no shim yet
- scanner.regExpParser (internal/scanner/regexp.go:78): pointer-field: field scanner has pointer type *github.com/microsoft/typescript-go/internal/scanner.Scanner (an object graph needs pools and ids)
- scanner.compareDecimalStrings (internal/scanner/regexp.go:138): stdlib-call: strings.TrimLeft has no shim yet
- scanner.regExpParser.scanDisjunction (internal/scanner/regexp.go:156): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.regExpParser.scanAlternative (internal/scanner/regexp.go:280): stdlib-call: strings.ToLower has no shim yet
- scanner.regExpParser.scanGroupName (internal/scanner/regexp.go:516): stdlib-call: strings.ToLower has no shim yet
- scanner.regExpParser.scanCharacterClassEscape (internal/scanner/regexp.go:942): pointer-alias: pointer copied from valuesOfNonBinaryUnicodeProperties[propertyName]: two Go names for one value
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyName (internal/scanner/regexp.go:986): stdlib-call: maps.Keys has no shim yet
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyValue (internal/scanner/regexp.go:990): pointer-alias: pointer copied from valuesOfNonBinaryUnicodeProperties[propertyName]: two Go names for one value
- scanner.regExpParser.getSpellingSuggestionForUnicodePropertyNameOrValue (internal/scanner/regexp.go:999): stdlib-call: maps.Keys has no shim yet
- scanner.regExpParser.scanSourceCharacter (internal/scanner/regexp.go:1037): stdlib-call: unicode/utf16.RuneLen has no shim yet
- scanner.regExpParser.run (internal/scanner/regexp.go:1087): stdlib-call: maps.Keys has no shim yet
- scanner.textToToken (internal/scanner/scanner.go:125): map: non-empty map literal inside a function
- scanner.Scanner.scanHexDigits (internal/scanner/scanner.go:2143): stdlib-call: strings.ReplaceAll has no shim yet
- scanner.tokenToText (internal/scanner/scanner.go:2257): range-map: range over a map (Go's order is random)
- scanner.SkipTrivia (internal/scanner/scanner.go:2308): nil: nil
- scanner.SkipTriviaEx (internal/scanner/scanner.go:2315): nil: comparison with nil
- scanner.binaryUnicodeProperties (internal/scanner/unicodeproperties.go:18): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.binaryUnicodePropertiesOfStrings (internal/scanner/unicodeproperties.go:55): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.scriptValues (internal/scanner/unicodeproperties.go:62): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- scanner.valuesOfNonBinaryUnicodeProperties (internal/scanner/unicodeproperties.go:139): generic: generic type github.com/microsoft/typescript-go/internal/collections.Set[string]
- core.ConcatenateSeq[core_ConcatenateSeq__string] (internal/core/core.go:737): generic: generic type iter.Seq[string]

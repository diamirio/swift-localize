// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Maps cross-platform format placeholders used in the source Google Sheet into
/// the Apple-flavored format specifiers expected by `NSLocalizedString`/`String(format:)`.
///
/// Conversions (in order):
/// - `%s`      → `%@`        (untyped string placeholder)
/// - `%<N>s`   → `%<N>$@`    (positional string placeholder, e.g. `%2s` → `%2$@`)
///
/// Other specifiers (`%d`, `%f`, `%@`, `%<N>$d`, etc.) pass through unchanged.
public enum PlaceholderMapper {

    /// Returns `value` with sheet-style placeholders remapped to Apple-style.
    public static func mapped(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)

        var iterator = value.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let c = pending { pending = nil; return c }
            return iterator.next()
        }

        while let char = nextChar() {
            guard char == "%" else {
                output.append(char)
                continue
            }

            // Collect any digits after '%'
            var digits = ""
            var lookahead = iterator.next()
            while let d = lookahead, d.isASCII, d.isNumber {
                digits.append(d)
                lookahead = iterator.next()
            }

            // Handle `%s`         → `%@`
            // Handle `%<N>s`      → `%<N>$@`
            // Handle `%<N>$s`     → `%<N>$@`  (also normalize already-positional `s`)
            if let next = lookahead {
                if next == "s" {
                    if digits.isEmpty {
                        output.append("%@")
                    } else {
                        output.append("%")
                        output.append(digits)
                        output.append("$@")
                    }
                    continue
                }
                if next == "$" {
                    // Possibly `%<N>$s` → `%<N>$@`
                    if !digits.isEmpty, let after = iterator.next() {
                        if after == "s" {
                            output.append("%")
                            output.append(digits)
                            output.append("$@")
                            continue
                        } else {
                            // Not an `s` specifier — emit verbatim.
                            output.append("%")
                            output.append(digits)
                            output.append("$")
                            output.append(after)
                            continue
                        }
                    }
                }

                // Not a remapped form — emit collected pieces verbatim.
                output.append("%")
                output.append(digits)
                output.append(next)
            } else {
                // Stream ended after digits with no specifier byte.
                output.append("%")
                output.append(digits)
            }
        }

        return output
    }
}

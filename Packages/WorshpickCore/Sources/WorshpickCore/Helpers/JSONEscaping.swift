import Foundation

extension String {
    /// Rewrites every non-ASCII character of a JSON text as a `\uXXXX` escape. The JSON value stays the same.
    public var jsonWithNonASCIIEscaped: String {
        var escapedJSON = ""
        for scalar in unicodeScalars {
            if scalar.isASCII {
                escapedJSON.unicodeScalars.append(scalar)
            } else {
                for codeUnit in String(scalar).utf16 {
                    escapedJSON += String(format: "\\u%04x", codeUnit)
                }
            }
        }
        return escapedJSON
    }
}

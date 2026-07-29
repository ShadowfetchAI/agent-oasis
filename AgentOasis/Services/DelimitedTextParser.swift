import Foundation

enum DelimitedTextParser {
    static func parse(_ text: String, delimiter: Character? = nil) -> [[String: String]] {
        let inferred = delimiter ?? (text.prefix(1_000).contains("\t") ? "\t" : ",")
        let rows = parseRows(text, delimiter: inferred)
        guard let headers = rows.first, !headers.isEmpty else { return [] }
        return rows.dropFirst().compactMap { values in
            guard values.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                return nil
            }
            return Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = index < values.count
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                return (key, value)
            })
        }
    }

    private static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)

            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append("\"")
                    index = text.index(after: nextIndex)
                    continue
                }
                isQuoted.toggle()
            } else if character == delimiter, !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r", nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = text.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                continue
            } else {
                field.append(character)
            }
            index = nextIndex
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

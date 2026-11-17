import Foundation

/// Built at run time because the invitation and moment vocabularies are editable in Settings.
public enum ClaudeSchemas {
    public static func songAnalysisSchema(invitations: [String], moments: [String]) -> String {
        let nullableInteger: [String: Any] = ["type": ["integer", "null"], "minimum": 1]
        let passageSchema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["book", "chapter", "verseStart", "verseEnd", "chapterEnd", "kind"],
            "properties": [
                "book": ["type": "string"],
                "chapter": ["type": "integer", "minimum": 1],
                "verseStart": nullableInteger,
                "verseEnd": nullableInteger,
                "chapterEnd": nullableInteger,
                "kind": ["type": "string", "enum": PassageKind.allCases.map(\.rawValue)],
            ],
        ]
        return json([
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "artist", "language", "lyrics", "summary", "keywords", "invitations", "themes", "moments", "energy", "passages"],
            "properties": [
                "title": ["type": "string", "minLength": 1],
                "artist": ["type": "string"],
                "language": ["type": "string", "enum": SongLanguage.allCases.map(\.rawValue)],
                "lyrics": ["type": "string"],
                "summary": ["type": "string"],
                "keywords": stringArray(minimum: 10, maximum: 20),
                "invitations": enumArray(invitations, minimum: 1, maximum: 3),
                "themes": stringArray(minimum: 2, maximum: 5),
                "moments": enumArray(moments, minimum: 1, maximum: 2),
                "energy": ["type": "string", "enum": Energy.allCases.map(\.rawValue)],
                "passages": ["type": "array", "items": passageSchema],
            ],
        ])
    }

    public static let ocrSchema = json([
        "type": "object",
        "additionalProperties": false,
        "required": ["blocks"],
        "properties": [
            "blocks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["frameIndex", "text"],
                    "properties": ["frameIndex": ["type": "integer", "minimum": 0], "text": ["type": "string"]],
                ],
            ],
        ],
    ])

    public static let suggestionSchema = json([
        "type": "object",
        "additionalProperties": false,
        "required": ["slots"],
        "properties": [
            "slots": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["slotIndex", "songId", "reason", "alternativeSongIds"],
                    "properties": [
                        "slotIndex": ["type": "integer", "minimum": 0],
                        "songId": ["type": "string"],
                        "reason": ["type": "string"],
                        "alternativeSongIds": ["type": "array", "items": ["type": "string"], "maxItems": 2],
                    ],
                ],
            ],
        ],
    ])

    public static let connectionTestSchema = json([
        "type": "object",
        "additionalProperties": false,
        "required": ["ok"],
        "properties": ["ok": ["type": "boolean"]],
    ])

    private static func stringArray(minimum: Int, maximum: Int) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "minItems": minimum, "maxItems": maximum]
    }

    private static func enumArray(_ values: [String], minimum: Int, maximum: Int) -> [String: Any] {
        ["type": "array", "items": ["type": "string", "enum": values], "minItems": minimum, "maxItems": maximum]
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

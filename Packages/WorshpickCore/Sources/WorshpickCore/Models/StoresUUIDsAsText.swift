import GRDB

/// Raw SQL in the stores compares ids with `uuidString`, so UUIDs must be stored as text, not GRDB's default blob.
public protocol StoresUUIDsAsText: EncodableRecord {}

extension StoresUUIDsAsText {
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
}

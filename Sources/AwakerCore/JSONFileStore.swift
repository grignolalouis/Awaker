import Foundation

/// Reads and writes Codable values as JSON files in one folder (Application Support by default).
public struct JSONFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static var applicationSupport: JSONFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONFileStore(directory: base.appendingPathComponent("Awaker", isDirectory: true))
    }

    public func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save<Value: Encodable>(_ value: Value, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

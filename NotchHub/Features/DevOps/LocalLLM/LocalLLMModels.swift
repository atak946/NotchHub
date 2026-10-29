import Foundation

enum LocalLLMServerKind: String, CaseIterable, Identifiable, Sendable {
    case lmStudio
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lmStudio: "LM Studio"
        case .ollama: "Ollama"
        }
    }

    static let defaultLMStudioPort = 1234
    static let defaultOllamaPort = 11434
}

/// Reachability and model information of one local server.
struct LocalLLMServerStatus: Equatable, Sendable {
    enum Reachability: Equatable, Sendable {
        case unknown
        case up
        case down
    }

    var reachability: Reachability = .unknown
    /// Models currently loaded in memory (Ollama `/api/ps`, LM Studio `/v1/models`).
    var loadedModels: [String] = []
    /// Models installed on disk (Ollama `/api/tags` only).
    var installedModelCount: Int?

    var isUp: Bool { reachability == .up }
}

/// Pure decoders for the local LLM server responses.
enum LocalLLMResponseParser {
    enum ParseError: Error, Equatable {
        case unexpectedShape
    }

    /// LM Studio (OpenAI compatible) `GET /v1/models` → `{"data":[{"id":"…"}]}`.
    static func lmStudioModels(_ data: Data) throws -> [String] {
        let response = try decode(OpenAIModelList.self, from: data)
        return response.data.map(\.id).filter { !$0.isEmpty }
    }

    /// Ollama `GET /api/tags` and `GET /api/ps` → `{"models":[{"name":"…"}]}`.
    static func ollamaModels(_ data: Data) throws -> [String] {
        let response = try decode(OllamaModelList.self, from: data)
        return response.models.compactMap { $0.name ?? $0.model }.filter { !$0.isEmpty }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ParseError.unexpectedShape
        }
    }

    private struct OpenAIModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private struct OllamaModelList: Decodable {
        struct Model: Decodable {
            let name: String?
            let model: String?
        }

        let models: [Model]
    }
}

/// Minimal HTTP GET used by the LLM monitor, injectable for tests.
protocol LocalLLMHTTPFetching: Sendable {
    /// Returns the body and status code.
    func get(_ url: URL) async throws -> (Data, Int)
}

struct URLSessionLocalLLMFetcher: LocalLLMHTTPFetching {
    static let timeout: TimeInterval = 3

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

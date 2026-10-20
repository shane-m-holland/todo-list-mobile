import Foundation
import Yams

/// Reads `components.examples.<name>.value` from `contract/openapi.yaml` as JSON, so tests use the
/// exact payloads the contract documents. Contract edits that break the client fail here.
enum ContractExamples {
    nonisolated(unsafe) private static let examples: [String: Any] = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() } // up to the repo root
        url.appendPathComponent("contract/openapi.yaml")
        guard
            let text = try? String(contentsOf: url, encoding: .utf8),
            let spec = try? Yams.load(yaml: text) as? [String: Any],
            let components = spec["components"] as? [String: Any],
            let examples = components["examples"] as? [String: Any]
        else { fatalError("Could not read components.examples from \(url.path)") }
        return examples
    }()

    static func json(_ name: String) -> Data {
        guard let example = examples[name] as? [String: Any], let value = example["value"] else {
            fatalError("No example '\(name)' in the contract")
        }
        return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    /// The example decoded as a dictionary, for assertions on individual values.
    static func object(_ name: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: json(name)) as! [String: Any]
    }
}

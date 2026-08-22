import Foundation
import GMCCDaemonKit

/// CLARIFY_ASK — insert a question while the summary is building (optionally pre-answered as bot_inferred for confident yeet-type detections).
enum ClarifyAskHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyAskRequest.self, from: line)
        return try okResult(.clarifyAsk, head, try store.clarifyAsk(request))
    }
}

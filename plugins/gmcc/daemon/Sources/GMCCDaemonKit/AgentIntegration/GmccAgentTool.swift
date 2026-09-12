import Foundation
import FoundationModels

public enum GmccAgentToolFamily: String, Sendable, CaseIterable {
    ///
    case dope
    ///
    case kbite
    ///
    case diagram
    ///
    case cde
    ///
    case system
}

@available(GmccAgentOS 1.0, *)
public protocol GmccAgentTool: Tool {
    var family: GmccAgentToolFamily { get }
}

@available(GmccAgentOS 1.0, *)
public protocol GmDopeAgentTool: GmccAgentTool {}

@available(GmccAgentOS 1.0, *)
extension GmDopeAgentTool {
    public var family: GmccAgentToolFamily { .dope }
}

@available(GmccAgentOS 1.0, *)
public protocol GmKbiteAgentTool: GmccAgentTool {}

@available(GmccAgentOS 1.0, *)
extension GmKbiteAgentTool {
    public var family: GmccAgentToolFamily { .kbite }
}

@available(GmccAgentOS 1.0, *)
public protocol GmDiagramAgentTool: GmccAgentTool {}

@available(GmccAgentOS 1.0, *)
extension GmDiagramAgentTool {
    public var family: GmccAgentToolFamily { .diagram }
}

@available(GmccAgentOS 1.0, *)
public protocol GmCdeAgentTool: GmccAgentTool {}

@available(GmccAgentOS 1.0, *)
extension GmCdeAgentTool {
    public var family: GmccAgentToolFamily { .cde }
}

@available(GmccAgentOS 1.0, *)
public protocol GmSystemAgentTool: GmccAgentTool {}

@available(GmccAgentOS 1.0, *)
extension GmSystemAgentTool {
    public var family: GmccAgentToolFamily { .system }
}

import Foundation
import Testing
@testable import aTerm

// Alias for protocol type to avoid reserved word
extension AgentDefinition {
    var `protocol`: AgentProtocol { protocolType }
}

// MARK: - TermConfig Tests

struct TermConfigTests {
    @Test
    func parsesProfileSection() {
        let content = """
        [profile]
        name = "work"
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.profileName == "work")
    }
    
    @Test
    func parsesAISection() {
        let content = """
        [ai]
        provider = "anthropic"
        model = "claude-sonnet-4-5"
        classifier_model = "claude-haiku-4-5"
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.aiProvider == "anthropic")
        #expect(config.aiModel == "claude-sonnet-4-5")
        #expect(config.classifierModel == "claude-haiku-4-5")
    }
    
    @Test
    func parsesMCPSection() {
        let content = """
        [mcp]
        servers = ["filesystem", "git"]
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.mcpServers == ["filesystem", "git"])
    }
    
    @Test
    func parsesAgentsSection() {
        let content = """
        [agents]
        default = "claude-code"
        auto_start = true
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.defaultAgent == "claude-code")
        #expect(config.agentAutoStart == true)
    }
    
    @Test
    func parsesFullConfig() {
        let content = """
        [profile]
        name = "work"
        
        [ai]
        provider = "anthropic"
        model = "claude-sonnet-4-5"
        classifier_model = "claude-haiku-4-5"
        
        [mcp]
        servers = ["filesystem", "git"]
        
        [agents]
        default = "claude-code"
        auto_start = false
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.profileName == "work")
        #expect(config.aiProvider == "anthropic")
        #expect(config.aiModel == "claude-sonnet-4-5")
        #expect(config.classifierModel == "claude-haiku-4-5")
        #expect(config.mcpServers == ["filesystem", "git"])
        #expect(config.defaultAgent == "claude-code")
        #expect(config.agentAutoStart == false)
    }
    
    @Test
    func handlesEmptyContent() {
        let content = ""
        
        let config = TermConfig.parse(content)
        
        #expect(config.profileName == nil)
        #expect(config.aiProvider == nil)
        #expect(config.mcpServers == [])
    }
    
    @Test
    func handlesCommentsAndEmptyLines() {
        let content = """
        # This is a comment
        [profile]
        name = "work"
        
        # Another comment
        [ai]
        provider = "openai"
        """
        
        let config = TermConfig.parse(content)
        
        #expect(config.profileName == "work")
        #expect(config.aiProvider == "openai")
    }
    
    @Test
    func parsesLoadFromDirectory() throws {
        let content = """
        [profile]
        name = "test"
        """
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let configURL = tempDir.appendingPathComponent(".termconfig")
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        
        let config = TermConfig.load(from: tempDir)
        
        #expect(config != nil)
        #expect(config?.profileName == "test")
    }
    
    @Test
    func loadReturnsNilForMissingFile() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Don't create the directory or file
        
        let config = TermConfig.load(from: tempDir)
        
        #expect(config == nil)
    }
}

// MARK: - Agent Definition Tests

struct AgentDefinitionTests {
    @Test
    func builtinAgentsExist() {
        let agents = BuiltinAgents.all
        
        #expect(!agents.isEmpty)
        
        let claude = agents.first { $0.id == "claude-code" }
        #expect(claude != nil)
        #expect(claude?.command == "claude")
        #expect(claude?.authEnvVar == "ANTHROPIC_API_KEY")
    }
    
    @Test
    func agentDefinitionProperties() {
        let agent = AgentDefinition(
            id: "test-agent",
            name: "Test Agent",
            command: "test-agent",
            args: ["--arg1", "--arg2"],
            authEnvVar: "TEST_API_KEY",
            installCheck: "which test-agent",
            installHint: "npm install -g test-agent",
            protocolType: .interactiveCLI,
            isBuiltin: false
        )
        
        #expect(agent.id == "test-agent")
        #expect(agent.name == "Test Agent")
        #expect(agent.command == "test-agent")
        #expect(agent.args == ["--arg1", "--arg2"])
        #expect(agent.authEnvVar == "TEST_API_KEY")
        #expect(agent.installCheck == "which test-agent")
        #expect(agent.installHint == "npm install -g test-agent")
        #expect(agent.protocolType == .interactiveCLI)
        #expect(agent.isBuiltin == false)
    }
    
    @Test
    func agentProtocolEquality() {
        #expect(AgentProtocol.interactiveCLI == AgentProtocol.interactiveCLI)
    }
}

// MARK: - MCP Definition Tests

struct MCPDefinitionTests {
    @Test
    func builtinMCPServersExist() {
        let servers = BuiltinMCPServers.all
        
        #expect(!servers.isEmpty)
        
        let filesystem = servers.first { $0.id == "filesystem" }
        #expect(filesystem != nil)
        #expect(filesystem?.transport == .stdio)
        #expect(filesystem?.autoStart == true)
    }
    
    @Test
    func mcpServerDefinitionProperties() {
        let server = MCPServerDefinition(
            id: "test-server",
            name: "Test Server",
            transport: .sse,
            command: "",
            args: [],
            endpoint: "http://localhost:3000",
            autoStart: false,
            scope: .global,
            isBuiltin: false
        )
        
        #expect(server.id == "test-server")
        #expect(server.name == "Test Server")
        #expect(server.transport == .sse)
        #expect(server.endpoint == "http://localhost:3000")
        #expect(server.autoStart == false)
        #expect(server.scope == .global)
        #expect(server.isBuiltin == false)
    }
    
    @Test
    func mcpTransportEquality() {
        #expect(MCPTransport.stdio == MCPTransport.stdio)
        #expect(MCPTransport.sse == MCPTransport.sse)
        #expect(MCPTransport.stdio != MCPTransport.sse)
    }
    
    @Test
    func mcpScopeEquality() {
        #expect(MCPScope.global == MCPScope.global)
        #expect(MCPScope.perProject == MCPScope.perProject)
        #expect(MCPScope.global != MCPScope.perProject)
    }
}

// MARK: - Profile Tests

struct ProfileTests {
    @Test
    func profileCreation() {
        let appearance = TerminalAppearance.default
        let profile = Profile(id: UUID(), name: "Test Profile", appearance: appearance)
        
        #expect(profile.name == "Test Profile")
        #expect(profile.appearance.themeID == appearance.themeID)
    }
    
    @Test
    func terminalAppearanceDefault() {
        let appearance = TerminalAppearance.default
        
        #expect(appearance.themeID == "custom-default")
        #expect(appearance.fontSize == 13)
        #expect(appearance.lineHeight == 1.18)
        #expect(appearance.letterSpacing == 0)
        #expect(appearance.opacity == 0.96)
        #expect(appearance.blur == 0.45)
        #expect(appearance.cursorStyle == .bar)
        #expect(appearance.cursorBlink == false)
        #expect(appearance.scrollbackSize == 10000)
    }
    
    @Test
    func cursorStyleEquality() {
        #expect(CursorStyle.block == CursorStyle.block)
        #expect(CursorStyle.bar == CursorStyle.bar)
        #expect(CursorStyle.underline == CursorStyle.underline)
        #expect(CursorStyle.block != CursorStyle.bar)
    }
}



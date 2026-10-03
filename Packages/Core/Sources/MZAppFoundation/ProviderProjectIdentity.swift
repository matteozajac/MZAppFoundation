/// Optional dashboard labels supplied by the app's bootstrap; never inferred from an SDK key.
public struct ProviderProjectIdentity: Equatable, Codable, Sendable {
    public let name: String?
    public let projectID: String?
    public let appID: String?
    public let organization: String?

    public init(name: String? = nil, projectID: String? = nil, appID: String? = nil, organization: String? = nil) {
        self.name = name; self.projectID = projectID; self.appID = appID; self.organization = organization
    }

    public var details: [ProviderDetail] {
        var result = [ProviderDetail("projectName", label: "Project name", value: name ?? "Not supplied by app"),
                      ProviderDetail("projectID", label: "Project ID", value: projectID ?? "Not supplied by app")]
        if let appID { result.append(.init("appID", label: "App ID", value: appID)) }
        if let organization { result.append(.init("organization", label: "Organization", value: organization)) }
        return result
    }
}

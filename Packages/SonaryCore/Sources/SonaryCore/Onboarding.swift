public struct OnboardingStep: Sendable, Equatable {
    public let permission: SonaryPermission
    public let moduleIDs: [String]

    public init(permission: SonaryPermission, moduleIDs: [String]) {
        self.permission = permission
        self.moduleIDs = moduleIDs
    }
}

/// One step per permission that at least one module needs, in `SonaryPermission.allCases` order.
@MainActor
public func onboardingSteps(for modules: [any SonaryModule]) -> [OnboardingStep] {
    SonaryPermission.allCases.compactMap { permission in
        let ids = modules.filter { $0.requiredPermissions.contains(permission) }.map(\.id)
        return ids.isEmpty ? nil : OnboardingStep(permission: permission, moduleIDs: ids)
    }
}
